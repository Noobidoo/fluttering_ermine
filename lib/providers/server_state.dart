import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';

class ServerState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  ServerState(this._service);

  List<RevoltServer> _servers = [];
  List<RevoltChannel> _allChannels = [];
  RevoltServer? _selectedServer;
  RevoltChannel? _selectedChannel;
  bool _showDMs = false;
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};

  // ── Unread tracking ────────────────────────────────────────────────────────
  final Map<String, String> _channelUnreads = {};
  final Map<String, List<String>> _channelMentions = {};
  final Map<String, String> _latestMessageIds = {};
  /// Tracks which channels had entries in the server's `channel_unreads` array.
  /// Channels absent from this set were intentionally omitted (fully-read).
  final Set<String> _seenInChannelUnreads = {};

  // ── Members ────────────────────────────────────────────────────────────────
  final Map<String, List<RevoltMember>> _membersByServer = {};
  bool _loadingMembers = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  List<RevoltServer> get servers => _servers;
  RevoltServer? get selectedServer => _selectedServer;
  RevoltChannel? get selectedChannel => _selectedChannel;
  bool get showDMs => _showDMs;

  List<RevoltChannel> get selectedServerChannels {
    if (_selectedServer == null) return [];
    return _allChannels
        .where((c) => c.serverId == _selectedServer!.id)
        .toList();
  }

  List<RevoltChannel> get dmChannels => _allChannels
      .where((c) =>
          c.type == ChannelType.directMessage ||
          c.type == ChannelType.group ||
          c.type == ChannelType.savedMessages)
      .toList();

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void subscribeToEvents() {
    _wsSub?.cancel();
    _wsSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'Ready':
        _onReady(event);
        break;
      case 'Message':
        _onMessage(event);
        break;
      case 'ChannelAck':
        _onChannelAck(event);
        break;
      default:
        break;
    }
  }

  void _onReady(Map<String, dynamic> event) {
    final servers = (event['servers'] as List<dynamic>?) ?? [];
    _servers = servers
        .map((s) => RevoltServer.fromJson(s as Map<String, dynamic>))
        .toList();

    final channels = (event['channels'] as List<dynamic>?) ?? [];
    _allChannels = channels
        .map((c) => RevoltChannel.fromJson(c as Map<String, dynamic>))
        .toList();

    final unreads = (event['channel_unreads'] as List<dynamic>?) ?? [];
    _channelUnreads.clear();
    _channelMentions.clear();
    _seenInChannelUnreads.clear();
    for (final u in unreads) {
      final data = u as Map<String, dynamic>;
      final channelId = data['_id'] as String;
      _seenInChannelUnreads.add(channelId);
      final lastId = data['last_id'] as String?;
      if (lastId != null) _channelUnreads[channelId] = lastId;
      final mentions = (data['mentions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [];
      if (mentions.isNotEmpty) _channelMentions[channelId] = mentions;
    }

    if (_servers.isNotEmpty && _selectedServer == null && !_showDMs) {
      _selectedServer = _servers.first;
      fetchMembers();
    }
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> event) {
    final channelId = event['channel'] as String?;
    final messageId = event['_id'] as String?;
    if (channelId != null && messageId != null) {
      _latestMessageIds[channelId] = messageId;
      notifyListeners();
    }
  }

  void _onChannelAck(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final messageId = event['message_id'] as String?;
    if (channelId != null && messageId != null) {
      _channelUnreads[channelId] = messageId;
      _channelMentions.remove(channelId);
      notifyListeners();
    }
  }

  void selectServer(RevoltServer server) {
    _selectedServer = server;
    _selectedChannel = null;
    _showDMs = false;
    _fetchServerChannels(server);
    fetchMembers();
    notifyListeners();
  }

  void selectDMs() {
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = true;
    notifyListeners();
  }

  void selectChannel(RevoltChannel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  void selectVoiceChannel(RevoltChannel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  // ── Members ────────────────────────────────────────────────────────────────

  List<RevoltMember>? get currentServerMembers {
    if (_selectedServer == null) return null;
    return _membersByServer[_selectedServer!.id];
  }

  bool get isLoadingMembers => _loadingMembers;

  Future<void> fetchMembers() async {
    final server = _selectedServer;
    if (server == null) return;
    if (_membersByServer.containsKey(server.id)) return;
    _loadingMembers = true;
    notifyListeners();
    try {
      final (members, _) = await _service.fetchServerMembers(server.id);
      _membersByServer[server.id] = members;
    } catch (e) {
      debugPrint('[fetchMembers] ${server.id} failed: $e');
    } finally {
      _loadingMembers = false;
      notifyListeners();
    }
  }

  /// Finds a cached member by user ID in the given server.
  RevoltMember? memberInServer(String serverId, String userId) {
    return _membersByServer[serverId]
        ?.where((m) => m.userId == userId)
        .firstOrNull;
  }

  // ── Unread queries ─────────────────────────────────────────────────────────

  /// Whether [channelId] has messages newer than the user's last read position.
  bool isChannelUnread(String channelId) {
    final unread = _channelUnreads[channelId];
    final latest = _latestMessageIds[channelId];
    if (latest != null) return unread != latest;
    final channel = _allChannels.cast<RevoltChannel?>().firstWhere(
        (c) => c?.id == channelId,
        orElse: () => null);
    if (channel == null || channel.lastMessageId == null) return false;
    if (!_seenInChannelUnreads.contains(channelId)) return false;
    return unread != channel.lastMessageId;
  }

  /// Number of unread @mentions in [channelId].
  int mentionCountFor(String channelId) =>
      _channelMentions[channelId]?.length ?? 0;

  /// Number of channels in [serverId] that have unread messages.
  int serverUnreadCount(String serverId) {
    int count = 0;
    for (final channel in _allChannels) {
      if (channel.serverId == serverId && isChannelUnread(channel.id)) {
        count++;
      }
    }
    return count;
  }

  /// Latest known message ID for [channelId] (from WS), or null.
  String? latestMessageId(String channelId) => _latestMessageIds[channelId];

  /// Mark [channelId] as read up to [messageId].
  void markChannelRead(String channelId, String messageId) {
    _channelUnreads[channelId] = messageId;
    _channelMentions.remove(channelId);
    notifyListeners();
  }

  // ── Invites ───────────────────────────────────────────────────────────────

  Future<String> createInvite(String channelId) =>
      _service.createInvite(channelId);

  Future<void> joinInvite(String code) => _service.joinInvite(code);

  Future<void> _fetchServerChannels(RevoltServer server) async {
    notifyListeners();
    try {
      final channels = await _service.fetchChannels(server.channelIds);
      _allChannels = [
        ..._allChannels.where((c) => c.serverId != server.id),
        ...channels,
      ];
    } catch (e) {
      debugPrint('[fetchServerChannels] ${server.id} failed: $e');
      _channelErrors[server.id] = e.toString().replaceAll('Exception: ', '');
    } finally {
      _loadingChannels.remove(server.id);
      notifyListeners();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    _servers = [];
    _allChannels = [];
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = false;
    _channelErrors.clear();
    _loadingChannels.clear();
    _channelUnreads.clear();
    _channelMentions.clear();
    _latestMessageIds.clear();
    _seenInChannelUnreads.clear();
    _membersByServer.clear();
    _loadingMembers = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}

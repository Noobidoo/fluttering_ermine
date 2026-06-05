import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';

class ServerState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  /// Called when fetchMembers receives user data that should be cached.
  void Function(List<RevoltUser> users)? onUsersFetched;

  /// Called when a member's server profile changes (ServerMemberUpdate).
  /// Passes raw data (fields that changed) and clear list so the receiver
  /// can merge with any existing profile.
  void Function(String userId, String serverId, Map<String, dynamic>? data,
      List<String> clear)? onServerProfileUpdated;

  ServerState(this._service);

  List<RevoltServer> _servers = [];
  List<RevoltChannel> _allChannels = [];
  RevoltServer? _selectedServer;
  RevoltChannel? _selectedChannel;
  bool _showDMs = false;
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};

  // -- Unread tracking --------------------------------------------------------
  final Map<String, String> _channelUnreads = {};
  final Map<String, List<String>> _channelMentions = {};
  final Map<String, String> _latestMessageIds = {};

  // -- Members ----------------------------------------------------------------
  final Map<String, List<String>> _memberIdsByServer = {};
  bool _loadingMembers = false;

  // -- Getters ---------------------------------------------------------------

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

  // -- WebSocket -------------------------------------------------------------

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
      case 'ServerMemberUpdate':
        _onServerMemberUpdate(event);
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
    for (final u in unreads) {
      final data = u as Map<String, dynamic>;
      final channelId = data['_id'] as String;
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
      _memberIdsByServer.clear();
      fetchMembers(force: true);
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
    fetchMembers(force: true);
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

  // -- Members ----------------------------------------------------------------

  /// Returns the list of user IDs for the selected server's members, or null.
  List<String>? get currentServerMemberIds {
    if (_selectedServer == null) return null;
    return _memberIdsByServer[_selectedServer!.id];
  }

  bool get isLoadingMembers => _loadingMembers;

  Future<void> fetchMembers({bool force = false}) async {
    final server = _selectedServer;
    if (server == null) return;
    if (!force && _memberIdsByServer.containsKey(server.id)) return;
    _loadingMembers = true;
    notifyListeners();
    try {
      final (memberProfiles, users) =
          await _service.fetchServerMembers(server.id);
      _memberIdsByServer[server.id] =
          memberProfiles.map((m) => m.userId).toList();

      // Attach server profiles to each user
      final profileByUserId = {
        for (final m in memberProfiles) m.userId: m,
      };
      final updatedUsers = users.map((u) {
        final p = profileByUserId[u.id];
        if (p == null) return u;
        return u.copyWithServerProfile(
          server.id,
          ServerProfile(
            nickname: p.nickname,
            roles: p.roles,
            avatar: p.avatar,
          ),
        );
      }).toList();

      onUsersFetched?.call(updatedUsers);
    } catch (e) {
      debugPrint('[fetchMembers] ${server.id} failed: $e');
    } finally {
      _loadingMembers = false;
      notifyListeners();
    }
  }

  void _onServerMemberUpdate(Map<String, dynamic> event) {
    debugPrint(
        '[ServerMemberUpdate] raw: ${String.fromCharCodes(utf8.encode(event.toString()))}');
    final idMap = event['id'];
    if (idMap is! Map) return;
    final serverId = idMap['server'] as String?;
    final userId = idMap['user'] as String?;
    if (serverId == null || userId == null) return;
    final data = event['data'] as Map<String, dynamic>?;
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    // Keep the member list consistent
    if (!_memberIdsByServer.containsKey(serverId)) return;
    if (!_memberIdsByServer[serverId]!.contains(userId)) return;

    onServerProfileUpdated?.call(userId, serverId, data, clear);
    notifyListeners();
  }

  /// Returns whether [userId] is a member of [serverId].
  bool isMember(String serverId, String userId) =>
      _memberIdsByServer[serverId]?.contains(userId) ?? false;

  // -- Unread queries ---------------------------------------------------------

  /// Whether [channelId] has messages newer than the user's last read position.
  bool isChannelUnread(String channelId) {
    final unread = _channelUnreads[channelId];
    final latest = _latestMessageIds[channelId];
    if (latest != null) return unread != latest;
    if (unread == null) return false;
    final channel = _allChannels.cast<RevoltChannel?>().firstWhere(
        (c) => c?.id == channelId,
        orElse: () => null);
    if (channel == null || channel.lastMessageId == null) return false;
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

  // -- Invites ---------------------------------------------------------------

  Future<String> createInvite(String channelId) =>
      _service.createInvite(channelId);

  Future<List<RevoltInvite>> fetchInvites(String serverId) =>
      _service.fetchInvites(serverId);

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

  // -- Lifecycle -------------------------------------------------------------

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
    _memberIdsByServer.clear();
    _loadingMembers = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}

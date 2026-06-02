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

  void selectServer(RevoltServer server) {
    _selectedServer = server;
    _selectedChannel = null;
    _showDMs = false;
    _fetchServerChannels(server);
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
    return unread != channel.lastMessageId;
  }

  /// Number of unread @mentions in [channelId].
  int mentionCountFor(String channelId) =>
      _channelMentions[channelId]?.length ?? 0;

  /// Mark [channelId] as read up to [messageId].
  void markChannelRead(String channelId, String messageId) {
    _channelUnreads[channelId] = messageId;
    _channelMentions.remove(channelId);
    notifyListeners();
  }

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
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}

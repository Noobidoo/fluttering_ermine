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
  // channelId -> list of user IDs currently in that voice channel
  final Map<String, List<String>> _voiceChannelMembers = {};
  // userId -> is_publishing (true = mic active / not muted)
  final Map<String, bool> _voicePublishing = {};

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

  List<String> voiceParticipantsFor(String channelId) =>
      List.unmodifiable(_voiceChannelMembers[channelId] ?? []);

  /// Returns null if state unknown, true if mic active, false if muted.
  bool? voicePublishingFor(String userId) => _voicePublishing[userId];

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
      case 'ServerMemberUpdate':
        _onMemberUpdate(event);
        break;
      case 'VoiceChannelJoin':
        _onVoiceChannelJoin(event);
        break;
      case 'VoiceChannelLeave':
        _onVoiceChannelLeave(event);
        break;
      case 'VoiceChannelMove':
        _onVoiceChannelMove(event);
        break;
      case 'UserVoiceStateUpdate':
        _onUserVoiceStateUpdate(event);
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

    _voiceChannelMembers.clear();
    _voicePublishing.clear();
    final voiceStates = (event['voice_states'] as List<dynamic>?) ?? [];
    for (final vs in voiceStates) {
      final map = vs as Map<String, dynamic>;
      final channelId = map['id'] as String?;
      if (channelId == null) continue;
      final participants = (map['participants'] as List<dynamic>?) ?? [];
      for (final p in participants) {
        final pm = p as Map<String, dynamic>;
        final userId = pm['id'] as String?;
        final isPublishing = pm['is_publishing'] as bool?;
        if (userId == null) continue;
        _voiceChannelMembers.putIfAbsent(channelId, () => []);
        if (!_voiceChannelMembers[channelId]!.contains(userId)) {
          _voiceChannelMembers[channelId]!.add(userId);
        }
        if (isPublishing != null) _voicePublishing[userId] = isPublishing;
      }
    }
    debugPrint('[ServerState] voiceChannelMembers after Ready: $_voiceChannelMembers');

    if (_servers.isNotEmpty && _selectedServer == null && !_showDMs) {
      _selectedServer = _servers.first;
    }
    notifyListeners();
  }

  void _onVoiceChannelJoin(Map<String, dynamic> event) {
    // { id: channelId, state: { id: userId, ... } }
    final channelId = event['id'] as String?;
    final state = event['state'] as Map<String, dynamic>?;
    final userId = state?['id'] as String?;
    debugPrint('[ServerState] VoiceChannelJoin channel=$channelId user=$userId');
    if (channelId == null || userId == null) return;
    _voiceChannelMembers.putIfAbsent(channelId, () => []);
    if (!_voiceChannelMembers[channelId]!.contains(userId)) {
      _voiceChannelMembers[channelId]!.add(userId);
    }
    notifyListeners();
  }

  void _onVoiceChannelLeave(Map<String, dynamic> event) {
    // { id: channelId, user: userId }
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    debugPrint('[ServerState] VoiceChannelLeave channel=$channelId user=$userId raw=$event');
    if (channelId == null || userId == null) return;
    _voiceChannelMembers[channelId]?.remove(userId);
    _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);
    _voicePublishing.remove(userId);
    notifyListeners();
  }

  void _onVoiceChannelMove(Map<String, dynamic> event) {
    // { user: userId, from: channelId, to: channelId, state: ... }
    final userId = event['user'] as String?;
    final from = event['from'] as String?;
    final to = event['to'] as String?;
    debugPrint('[ServerState] VoiceChannelMove user=$userId from=$from to=$to');
    if (userId == null) return;
    if (from != null) {
      _voiceChannelMembers[from]?.remove(userId);
      _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);
    }
    if (to != null) {
      _voiceChannelMembers.putIfAbsent(to, () => []);
      if (!_voiceChannelMembers[to]!.contains(userId)) {
        _voiceChannelMembers[to]!.add(userId);
      }
    }
    notifyListeners();
  }

  void _onUserVoiceStateUpdate(Map<String, dynamic> event) {
    // { id: userId, channel_id: channelId, data: { is_publishing: bool } }
    final userId = event['id'] as String?;
    final data = event['data'] as Map<String, dynamic>?;
    if (userId == null || data == null) return;
    final isPublishing = data['is_publishing'] as bool?;
    if (isPublishing != null) {
      _voicePublishing[userId] = isPublishing;
    }
    notifyListeners();
  }

  void _onMemberUpdate(Map<String, dynamic> event) {
    debugPrint('[ServerState] ServerMemberUpdate raw: $event');
    final id = event['id'] as Map<String, dynamic>?;
    final userId = id?['user'] as String?;
    if (userId == null) {
      debugPrint('[ServerState] ServerMemberUpdate: no userId, skipping');
      return;
    }

    // Remove user from any existing voice channel
    _voiceChannelMembers.forEach((ch, list) => list.remove(userId));
    _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);

    // Check if cleared
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];
    if (clear.contains('VoiceChannel')) {
      notifyListeners();
      return;
    }

    // Add to new channel if present
    final data = event['data'] as Map<String, dynamic>?;
    final newChannel = data?['voice_channel'] as String?;
    if (newChannel != null) {
      _voiceChannelMembers.putIfAbsent(newChannel, () => []).add(userId);
    }
    debugPrint('[ServerState] voiceChannelMembers after update: $_voiceChannelMembers');
    notifyListeners();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

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
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}

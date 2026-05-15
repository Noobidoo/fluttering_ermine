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
    if (event['type'] == 'Ready') _onReady(event);
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

    if (_servers.isNotEmpty && _selectedServer == null && !_showDMs) {
      _selectedServer = _servers.first;
    }
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

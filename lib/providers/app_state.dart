import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';

const _defaultWsUrl = 'wss://ws.revolt.chat';

const _tokenKey = 'revolt_session_token';
const _apiBaseKey = 'revolt_api_base';
const _wsUrlKey = 'revolt_ws_url';
const _autumnBaseKey = 'revolt_autumn_base';

class AppState extends ChangeNotifier  with DiagnosticableTreeMixin{
  final RevoltService _service = RevoltService();
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  bool _isLoggedIn = false;
  bool _isLoading = true; // true until init() completes
  String? _error;

  RevoltUser? _currentUser;
  List<RevoltServer> _servers = [];
  List<RevoltChannel> _allChannels = [];
  final Map<String, RevoltUser> _userCache = {};
  final Map<String, List<RevoltMessage>> _messages = {};
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};

  RevoltServer? _selectedServer;
  RevoltChannel? _selectedChannel;
  bool _showDMs = false;

  // ── Voice state ───────────────────────────────────────────────────────────
  Room? _voiceRoom;
  late EventsListener<RoomEvent> _voiceRoomListener;
  RevoltChannel? _activeVoiceChannel;
  bool _isInVoice = false;
  bool _isMuted = false;
  bool _isJoiningVoice = false;
  String? _voiceError;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get serverUrl => _service.apiBase;
  String get apiBase => _service.apiBase;
  String get autumnBase => _service.autumnBase;
  RevoltUser? get currentUser => _currentUser;
  List<RevoltServer> get servers => _servers;
  RevoltServer? get selectedServer => _selectedServer;
  RevoltChannel? get selectedChannel => _selectedChannel;
  bool get showDMs => _showDMs;

  // Voice
  RevoltChannel? get activeVoiceChannel => _activeVoiceChannel;
  bool get isInVoice => _isInVoice;
  bool get isMuted => _isMuted;
  bool get isJoiningVoice => _isJoiningVoice;
  String? get voiceError => _voiceError;

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

  List<RevoltMessage> get currentMessages {
    if (_selectedChannel == null) return [];
    return List.unmodifiable(_messages[_selectedChannel!.id] ?? []);
  }

  bool get isLoadingMessages =>
      _selectedChannel != null &&
      _loadingChannels.contains(_selectedChannel!.id);

  String? get currentChannelError =>
      _selectedChannel != null ? _channelErrors[_selectedChannel!.id] : null;

  RevoltUser? getUser(String id) => _userCache[id];

  // ── Init / Auth ───────────────────────────────────────────────────────────

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedApi = prefs.getString(_apiBaseKey);
      final savedWs = prefs.getString(_wsUrlKey);
      final savedAutumn = prefs.getString(_autumnBaseKey);
      if (savedApi != null && savedWs != null) {
        _service.setServerUrl(savedApi, savedWs);
      }
      if (savedAutumn != null) {
        _service.setAutumnUrl(savedAutumn);
      }
      final token = prefs.getString(_tokenKey);
      if (token == null) return;
      _service.setToken(token);
      // Refresh node config to get current voice node name
      try {
        final config = await _service.fetchNodeConfig();
        final features = config['features'] as Map<String, dynamic>? ?? {};
        final livekit = features['livekit'] as Map<String, dynamic>? ?? {};
        final nodes = livekit['nodes'] as List<dynamic>? ?? [];
        final voiceNode = nodes.isNotEmpty
            ? (nodes.first as Map<String, dynamic>)['name'] as String?
            : null;
        _service.setVoiceNode(voiceNode);
      } catch (_) {} // non-fatal: voice just won't work if this fails
      _currentUser = await _service.fetchSelf();
      _userCache[_currentUser!.id] = _currentUser!;
      _connectWebSocket();
      _isLoggedIn = true;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setServerUrl(String userInput) async {
    final (apiBase, config) = await _service.discoverApiUrl(userInput);
    final wsUrl = config['ws'] as String? ?? _defaultWsUrl;
    final features = config['features'] as Map<String, dynamic>? ?? {};
    final autumnUrl = features['autumn'] as Map<String, dynamic>? ?? {};
    final autumnBase = autumnUrl['url'] as String? ?? 'https://autumn.revolt.chat';
    final livekit = features['livekit'] as Map<String, dynamic>? ?? {};
    final nodes = livekit['nodes'] as List<dynamic>? ?? [];
    final voiceNode = nodes.isNotEmpty
        ? (nodes.first as Map<String, dynamic>)['name'] as String?
        : null;
    _service.setServerUrl(apiBase, wsUrl);
    _service.setAutumnUrl(autumnBase);
    _service.setVoiceNode(voiceNode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseKey, apiBase);
    await prefs.setString(_wsUrlKey, wsUrl);
    await prefs.setString(_autumnBaseKey, autumnBase);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.login(email, password);
      final resultType = result['result'] as String?;
      if (resultType == 'MFA') {
        throw Exception(
            'Account has MFA/2FA enabled. Please use an app-password or disable MFA temporarily.');
      }
      if (resultType == 'Disabled') {
        throw Exception('This account has been disabled.');
      }
      final token = result['token'] as String;
      _service.setToken(token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      _currentUser = await _service.fetchSelf();
      _userCache[_currentUser!.id] = _currentUser!;
      _connectWebSocket();
      _isLoggedIn = true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    try {
      await _service.logout();
    } catch (_) {}
    _wsSub?.cancel();
    await _voiceRoom?.disconnect();
    await _voiceRoomListener.dispose();
    await _voiceRoom?.disconnect();
    _service.disconnect();

    _voiceRoom = null;
    _activeVoiceChannel = null;
    _isInVoice = false;
    _isLoggedIn = false;
    _currentUser = null;
    _servers = [];
    _allChannels = [];
    _messages.clear();
    _userCache.clear();
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = false;
    await prefs.remove(_apiBaseKey);
    await prefs.remove(_wsUrlKey);
    await prefs.remove(_autumnBaseKey);
    _service.setServerUrl('https://api.revolt.chat', _defaultWsUrl);
    _service.setAutumnUrl('https://autumn.revolt.chat');
    notifyListeners();
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void _connectWebSocket() {
    _service.connectWebSocket();
    _wsSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type'] as String?) {
      case 'Ready':
        _onReady(event);
      case 'Message':
        _onMessage(event);
      case 'MessageUpdate':
        _onMessageUpdate(event);
      case 'MessageDelete':
        _onMessageDelete(event);
    }
  }

  void _onReady(Map<String, dynamic> event) {
    final users = (event['users'] as List<dynamic>?) ?? [];
    for (final u in users) {
      final user = RevoltUser.fromJson(u as Map<String, dynamic>);
      _userCache[user.id] = user;
    }

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

  void _onMessage(Map<String, dynamic> event) {
    final msg = RevoltMessage.fromJson(event);
    final list = _messages.putIfAbsent(msg.channelId, () => []);
    if (list.any((m) => m.id == msg.id)) return; // already added optimistically
    list.insert(0, msg);
    _ensureUserCached(msg.authorId);
    notifyListeners();
  }

  void _onMessageUpdate(Map<String, dynamic> event) {
    final id = event['id'] as String;
    final channelId = event['channel'] as String;
    final list = _messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final old = list[idx];
    list[idx] = RevoltMessage(
      id: old.id,
      channelId: old.channelId,
      authorId: old.authorId,
      content: data['content'] as String? ?? old.content,
      timestamp: old.timestamp,
      edited: data['edited'] as String? ?? old.edited,
      attachments: old.attachments,
    );
    notifyListeners();
  }

  void _onMessageDelete(Map<String, dynamic> event) {
    final id = event['id'] as String;
    final channelId = event['channel'] as String;
    _messages[channelId]?.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  void _ensureUserCached(String userId) {
    if (userId.isEmpty || _userCache.containsKey(userId)) return;
    _service.fetchUser(userId).then((user) {
      _userCache[user.id] = user;
      notifyListeners();
    }).catchError((_) {});
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void selectServer(RevoltServer server) {
    _selectedServer = server;
    _selectedChannel = null;
    _showDMs = false;
    _fetchServerChannels(server);
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

  void selectDMs() {
    _selectedServer = null;
    _selectedChannel = null;
    _showDMs = true;
    notifyListeners();
  }

  Future<void> selectChannel(RevoltChannel channel) async {
    _selectedChannel = channel;
    notifyListeners();
    if (!_messages.containsKey(channel.id)) {
      await _loadMessages(channel.id);
    }
  }

  void selectVoiceChannel(RevoltChannel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  Future<void> retryLoadMessages() async {
    if (_selectedChannel == null) return;
    final id = _selectedChannel!.id;
    _messages.remove(id);
    _channelErrors.remove(id);
    notifyListeners();
    await _loadMessages(id);
  }

  Future<void> _loadMessages(String channelId) async {
    _loadingChannels.add(channelId);
    _channelErrors.remove(channelId);
    notifyListeners();
    try {
      final msgs = await _service.fetchMessages(channelId);
      _messages[channelId] = msgs;
      for (final m in msgs) {
        _ensureUserCached(m.authorId);
      }
    } catch (e) {
      debugPrint('[loadMessages] $channelId failed: $e');
      _channelErrors[channelId] = e.toString().replaceAll('Exception: ', '');
    } finally {
      _loadingChannels.remove(channelId);
      notifyListeners();
    }
  }

  // ── Voice actions ──────────────────────────────────────────────────────────

  Future<void> joinVoiceChannel(RevoltChannel channel) async {
    if (_isJoiningVoice) return;
    // Leave current room if in one
    if (_voiceRoom != null) await leaveVoiceChannel();
    _isJoiningVoice = true;
    _voiceError = null;
    notifyListeners();
    try {
      final data = await _service.joinVoiceChannel(channel.id);
      var url = data['url'] as String;
      final token = data['token'] as String;
      // LiveKit requires a WebSocket URL; normalize https:// → wss://
      if (url.startsWith('https://')) {
        url = 'wss://${url.substring(8)}';
      } else if (url.startsWith('http://')) {
        url = 'ws://${url.substring(7)}';
      }
      final room = Room();
      _voiceRoomListener  = room.createListener();
      _voiceRoomListener 
        ..on<RoomConnectedEvent>((e) {
          debugPrint('[voice] connected to room ${room.name}');
          _voiceError = null;
          _isInVoice = true;
          _voiceRoom = e.room;
          _activeVoiceChannel = channel;
          notifyListeners();
        })
        ..on<RoomDisconnectedEvent>((e) {
          debugPrint('[voice] disconnected from room ${room.name}');
          _voiceRoom = null;
          _activeVoiceChannel = null;
          _isInVoice = false;
          _isMuted = false;
          _voiceError = 'Disconnected from voice';
          notifyListeners();
        })
        ..on<RoomReconnectingEvent>((e) {
          debugPrint('[voice] reconnecting to room ${room.name}...');
          _voiceError = 'Reconnecting...';
          _isJoiningVoice = true;
          notifyListeners();
        })
        ..on<RoomReconnectedEvent>((e) {
          debugPrint('[voice] reconnected to room ${room.name}');
          _voiceError = null;
          _isInVoice = true;
          _isJoiningVoice = false;
          notifyListeners();
        });

      // Attempt connection with a timeout to handle cases where the WS connection hangs indefinitely
      await room.connect(url, token).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('Voice connection timed out'),
      );
      _isMuted = false;

        await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      debugPrint('[voice] join failed: $e');
      _voiceError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isJoiningVoice = false;
      notifyListeners();
    }
  }

  Future<void> leaveVoiceChannel() async {
    await _voiceRoom?.disconnect();
    await _voiceRoomListener.dispose();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (_voiceRoom == null) return;
    _isMuted = !_isMuted;
    await _voiceRoom!.localParticipant?.setMicrophoneEnabled(!_isMuted);
    notifyListeners();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> sendMessage(String content) async {
    if (_selectedChannel == null || content.trim().isEmpty) return;
    final msg = await _service.sendMessage(_selectedChannel!.id, content.trim());
    final list = _messages.putIfAbsent(msg.channelId, () => []);
    if (!list.any((m) => m.id == msg.id)) {
      list.insert(0, msg);
      _ensureUserCached(msg.authorId);
      notifyListeners();
    }
  }

  String channelDisplayName(RevoltChannel channel) {
    if (channel.name != null) return channel.name!;
    if (channel.type == ChannelType.savedMessages) return 'Saved Messages';
    if (channel.type == ChannelType.directMessage) {
      final otherId = channel.recipientIds?.firstWhere(
        (id) => id != _currentUser?.id,
        orElse: () => '',
      );
      if (otherId != null && otherId.isNotEmpty) {
        return _userCache[otherId]?.displayUsername ?? 'Direct Message';
      } 
    }
    return 'Unknown Channel';
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _voiceRoomListener.dispose();  // add this
    _voiceRoom?.disconnect();
    _service.dispose();
    super.dispose();
  }
}

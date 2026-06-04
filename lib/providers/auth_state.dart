import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';
import '../services/voice_event_service.dart';
import 'messaging_state.dart';
import 'server_state.dart';
import 'voice_state.dart';

const _defaultWsUrl = 'wss://ws.revolt.chat';
const _tokenKey = 'revolt_session_token';
const _apiBaseKey = 'revolt_api_base';
const _wsUrlKey = 'revolt_ws_url';
const _autumnBaseKey = 'revolt_autumn_base';

class AuthState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  final ServerState _serverState;
  final MessagingState _messagingState;
  final VoiceState _voiceState;
  final VoiceEventService _voiceEventService;

  AuthState(
    this._service,
    this._serverState,
    this._messagingState,
    this._voiceState,
    this._voiceEventService,
  );

  bool _isLoggedIn = false;
  bool _isLoading = true;
  String? _error;
  RevoltUser? _currentUser;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get serverUrl => _service.apiBase;
  String get apiBase => _service.apiBase;
  String get autumnBase => _service.autumnBase;
  RevoltUser? get currentUser => _currentUser;

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
      try {
        final config = await _service.fetchNodeConfig();
        final features = config['features'] as Map<String, dynamic>? ?? {};
        final livekit = features['livekit'] as Map<String, dynamic>? ?? {};
        final nodes = livekit['nodes'] as List<dynamic>? ?? [];
        final voiceNode = nodes.isNotEmpty
            ? (nodes.first as Map<String, dynamic>)['name'] as String?
            : null;
        _service.setVoiceNode(voiceNode);
      } catch (_) {}
      _currentUser = await _service.fetchSelf();
      _messagingState.setCurrentUserId(_currentUser!.id);
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
    final autumnBase =
        autumnUrl['url'] as String? ?? 'https://autumn.revolt.chat';
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
      _messagingState.setCurrentUserId(_currentUser!.id);
      _connectWebSocket();
      _isLoggedIn = true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateDisplayName(String name) async {
    await _service.updateProfile(displayName: name.isEmpty ? '' : name);
    _currentUser = await _service.fetchSelf();
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    try {
      await _service.logout();
    } catch (_) {}
    await _voiceState.clear();
    _serverState.clear();
    _messagingState.clear();
    _service.disconnect();
    _isLoggedIn = false;
    _currentUser = null;
    await prefs.remove(_apiBaseKey);
    await prefs.remove(_wsUrlKey);
    await prefs.remove(_autumnBaseKey);
    _service.setServerUrl('https://api.revolt.chat', _defaultWsUrl);
    _service.setAutumnUrl('https://autumn.revolt.chat');
    notifyListeners();
  }

  // ── Profile updates ───────────────────────────────────────────────────────

  void _syncCurrentUser() {
    if (_currentUser != null) {
      _messagingState.cacheUser(_currentUser!);
    }
  }

  Future<void> updateStatus({String? presence, String? statusText}) async {
    _currentUser = await _service.updateProfile(
        presence: presence, statusText: statusText);
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateBio(String bio) async {
    _currentUser = await _service.updateProfile(profileContent: bio);
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateAvatar(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadAvatar(bytes, filename);
    await _service.updateProfile(avatar: fileId);
    _currentUser = await _service.fetchSelf();
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateBanner(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadBackground(bytes, filename);
    await _service.updateProfile(background: fileId);
    _currentUser = await _service.fetchSelf();
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateServerProfile(
    String serverId, {
    String? nickname,
    String? avatar,
  }) async {
    await _service.updateServerMember(serverId, nickname: nickname, avatar: avatar);
    _currentUser = await _service.fetchSelf();
    _syncCurrentUser();
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _connectWebSocket() {
    _service.connectWebSocket();
    _serverState.subscribeToEvents();
    _messagingState.subscribeToEvents();
    _voiceEventService.subscribeToWebSocketEvents();
    _voiceState.subscribeToVoiceEvents();
    _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['type'] != 'UserUpdate') return;
    final id = event['id'] as String?;
    if (id == null || id != _currentUser?.id) return;
    // Evict old avatar from Flutter image cache before re-fetching
    if (_currentUser != null) {
      final oldUrl = _currentUser!.avatarUrlFor(_service.autumnBase, _service.apiBase);
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    // Our own profile changed — re-fetch to get latest avatar/display name
    _service.fetchSelf().then((user) {
      _currentUser = user;
      _syncCurrentUser();
      notifyListeners();
    }).catchError((_) {});
  }
}

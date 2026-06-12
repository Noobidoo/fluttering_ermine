import 'dart:async';
import 'dart:convert';

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

  // -- Getters ---------------------------------------------------------------

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get serverUrl => _service.apiBase;
  String get apiBase => _service.apiBase;
  String get autumnBase => _service.autumnBase;
  RevoltUser? get currentUser => _currentUser;

  // -- Init / Auth -----------------------------------------------------------

  Future<void> init() async {
    try {
      final asyncPrefs = SharedPreferencesAsync();
      final savedApi = await asyncPrefs.getString(_apiBaseKey);
      final savedWs = await asyncPrefs.getString(_wsUrlKey);
      final savedAutumn = await asyncPrefs.getString(_autumnBaseKey);
      if (savedApi != null && savedWs != null) {
        _service.setServerUrl(savedApi, savedWs);
      }
      if (savedAutumn != null) {
        _service.setAutumnUrl(savedAutumn);
      }
      final token = await asyncPrefs.getString(_tokenKey);
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
      final asyncPrefs = SharedPreferencesAsync();
      await asyncPrefs.remove(_tokenKey);
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
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString(_apiBaseKey, apiBase);
    await asyncPrefs.setString(_wsUrlKey, wsUrl);
    await asyncPrefs.setString(_autumnBaseKey, autumnBase);
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
      final asyncPrefs = SharedPreferencesAsync();
      await asyncPrefs.setString(_tokenKey, token);
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
    _currentUser = _currentUser?.copyWith(displayName: name.isEmpty ? '' : name);
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> logout() async {
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.remove(_tokenKey);
    try {
      await _service.logout();
    } catch (_) {}
    await _voiceState.clear();
    _serverState.clear();
    _messagingState.clear();
    _service.disconnect();
    _isLoggedIn = false;
    _currentUser = null;
    await asyncPrefs.remove(_apiBaseKey);
    await asyncPrefs.remove(_wsUrlKey);
    await asyncPrefs.remove(_autumnBaseKey);
    _service.setServerUrl('https://api.revolt.chat', _defaultWsUrl);
    _service.setAutumnUrl('https://autumn.revolt.chat');
    notifyListeners();
  }

  // -- Profile updates -------------------------------------------------------

  void _syncCurrentUser() {
    if (_currentUser != null) {
      _messagingState.cacheUser(_currentUser!);
    }
  }

  Future<void> updateStatus({String? presence, String? statusText}) async {
    await _service.updateProfile(presence: presence, statusText: statusText);
    _currentUser = _currentUser?.copyWith(
      presence: presence != null ? parsePresence(presence) : null,
      statusText: statusText,
    );
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateBio(String bio) async {
    await _service.updateProfile(profileContent: bio);
    _currentUser = _currentUser?.copyWith(profileContent: bio);
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateAvatar(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadAvatar(bytes, filename);
    await _service.updateProfile(avatar: fileId);
    final oldUrl = _currentUser?.resolveAvatarUrl(null, _service.autumnBase, _service.apiBase);
    _currentUser = _currentUser?.copyWith(
      avatar: RevoltFile(id: fileId, tag: 'avatars', filename: filename),
    );
    if (oldUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateBanner(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadBackground(bytes, filename);
    await _service.updateProfile(background: fileId);
    final oldUrl = _currentUser?.bannerUrlFor(_service.autumnBase);
    _currentUser = _currentUser?.copyWith(
      banner: RevoltFile(id: fileId, tag: 'backgrounds', filename: filename),
    );
    if (oldUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    _syncCurrentUser();
    notifyListeners();
  }

  Future<void> updateServerProfile(
    String serverId, {
    String? nickname,
    String? avatar,
  }) async {
    final userId = _currentUser?.id;
    if (userId == null) return;
    final remove = <String>[];
    String? effectiveNickname = nickname;
    if (nickname == '') {
      remove.add('Nickname');
      effectiveNickname = null;
    }
    await _service.updateServerMember(serverId, userId,
        nickname: effectiveNickname, avatar: avatar, remove: remove);
    notifyListeners();
  }

  StreamSubscription<Map<String, dynamic>>? _eventSub;

  // -- Internal --------------------------------------------------------------

  void _connectWebSocket() {
    _service.connectWebSocket();
    _serverState.subscribeToEvents();
    _messagingState.subscribeToEvents();
    _voiceEventService.subscribeToWebSocketEvents();
    _voiceState.subscribeToVoiceEvents();
    _eventSub?.cancel();
    _eventSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (event['type'] == 'Disconnected') {
      debugPrint('[Auth] WebSocket disconnected, reconnecting in 3s...');
      Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      return;
    }
    if (event['type'] != 'UserUpdate') return;
    debugPrint('[Auth/UserUpdate] raw: ${String.fromCharCodes(utf8.encode(event.toString()))}');
    final id = event['id'] as String?;
    if (id == null || id != _currentUser?.id) return;
    final data = (event['data'] as Map?)?.cast<String, dynamic>();
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    if (_currentUser == null) return;
    final cached = _currentUser!;

    RevoltFile? parseFile(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        try {
          return RevoltFile.fromJson(Map<String, dynamic>.from(value));
        } catch (_) {
          return null;
        }
      }
      if (value is String) {
        return RevoltFile(id: value, tag: 'avatars', filename: '');
      }
      return null;
    }

    // Evict old avatar if avatar changed or cleared
    if (data != null && (data.containsKey('avatar') || clear.contains('avatar'))) {
      final oldUrl = cached.resolveAvatarUrl(null, _service.autumnBase, _service.apiBase);
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }

    final user = RevoltUser(
      id: cached.id,
      username: data?['username'] as String? ?? cached.username,
      discriminator: (data?['discriminator'] as String? ?? cached.discriminator),
      displayName: data?['display_name'] as String? ?? cached.displayName,
      avatar: clear.contains('avatar')
          ? null
          : data?.containsKey('avatar') == true
              ? parseFile(data!['avatar'])
              : cached.avatar,
      banner: clear.contains('banner')
          ? null
          : data?.containsKey('banner') == true
              ? parseFile(data!['banner'])
              : cached.banner,
      presence: clear.contains('status')
          ? UserPresence.invisible
          : data?['status'] is Map && (data!['status'] as Map).containsKey('presence')
              ? parsePresence((data['status'] as Map)['presence'] as String?)
              : cached.presence,
      statusText: clear.contains('status')
          ? null
          : data?['status'] is Map
              ? (data!['status'] as Map)['text'] as String? ?? cached.statusText
              : cached.statusText,
      profileContent: clear.contains('profile')
          ? null
          : data?['profile'] is Map
              ? (data!['profile'] as Map)['content'] as String? ?? cached.profileContent
              : cached.profileContent,
      serverProfiles: cached.serverProfiles,
    );
    _currentUser = user;
    _syncCurrentUser();
    notifyListeners();
  }
}

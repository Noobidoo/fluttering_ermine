import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/models.dart';
import '../../../services/revolt_service.dart';
import '../../../services/voice_event_service.dart';
import '../../core/providers/service_providers.dart';

const _defaultWsUrl = 'wss://ws.revolt.chat';
const _tokenKey = 'revolt_session_token';
const _apiBaseKey = 'revolt_api_base';
const _wsUrlKey = 'revolt_ws_url';
const _autumnBaseKey = 'revolt_autumn_base';

@immutable
class LoginStateData {
  final bool isLoggedIn;
  final RevoltUser? currentUser;
  final String apiBase;
  final String autumnBase;

  const LoginStateData({
    this.isLoggedIn = false,
    this.currentUser,
    this.apiBase = 'https://api.revolt.chat',
    this.autumnBase = 'https://autumn.revolt.chat',
  });

  LoginStateData copyWith({
    bool? isLoggedIn,
    Object? currentUser = _omit,
    String? apiBase,
    String? autumnBase,
  }) => LoginStateData(
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    currentUser: currentUser == _omit ? this.currentUser : currentUser as RevoltUser?,
    apiBase: apiBase ?? this.apiBase,
    autumnBase: autumnBase ?? this.autumnBase,
  );

  static const _omit = Object();
}

class LoginNotifier extends AsyncNotifier<LoginStateData> {
  late RevoltService _service;
  late VoiceEventService _voiceEventService;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  @override
  Future<LoginStateData> build() async {
    _service = ref.watch(revoltServiceProvider);
    _voiceEventService = ref.watch(voiceEventServiceProvider);

    ref.onDispose(() {
      _eventSub?.cancel();
    });

    return _autoLogin();
  }

  Future<LoginStateData> _autoLogin() async {
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
      if (token == null) {
        return LoginStateData(apiBase: _service.apiBase, autumnBase: _service.autumnBase);
      }
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
      final user = await _service.fetchSelf();
      _connectWebSocket();
      return LoginStateData(
        isLoggedIn: true,
        currentUser: user,
        apiBase: _service.apiBase,
        autumnBase: _service.autumnBase,
      );
    } catch (_) {
      final asyncPrefs = SharedPreferencesAsync();
      await asyncPrefs.remove(_tokenKey);
      return LoginStateData(apiBase: _service.apiBase, autumnBase: _service.autumnBase);
    }
  }

  void _connectWebSocket() {
    _service.connectWebSocket();
    _voiceEventService.subscribeToWebSocketEvents();
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
    if (id == null || id != state.requireValue.currentUser?.id) return;
    final data = (event['data'] as Map?)?.cast<String, dynamic>();
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    final cached = state.requireValue.currentUser;
    if (cached == null) return;

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
    state = AsyncData(state.requireValue.copyWith(currentUser: user));
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
    state = AsyncData(
      (state.value ?? const LoginStateData()).copyWith(
        apiBase: _service.apiBase,
        autumnBase: _service.autumnBase,
      ),
    );
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString(_apiBaseKey, apiBase);
    await asyncPrefs.setString(_wsUrlKey, wsUrl);
    await asyncPrefs.setString(_autumnBaseKey, autumnBase);
  }

  Future<void> login(String email, String password) async {
    final result = await _service.login(email, password);
    final resultType = result['result'] as String?;
    if (resultType == 'MFA') {
      throw Exception(
        'Account has MFA/2FA enabled. Please use an app-password or disable MFA temporarily.',
      );
    }
    if (resultType == 'Disabled') {
      throw Exception('This account has been disabled.');
    }
    final token = result['token'] as String;
    _service.setToken(token);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString(_tokenKey, token);
    final user = await _service.fetchSelf();
    _connectWebSocket();
    state = AsyncData(
      (state.value ?? const LoginStateData()).copyWith(
        isLoggedIn: true,
        currentUser: user,
        apiBase: _service.apiBase,
        autumnBase: _service.autumnBase,
      ),
    );
  }

  Future<void> logout() async {
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.remove(_tokenKey);
    try {
      await _service.logout();
    } catch (_) {}
    _service.disconnect();
    _eventSub?.cancel();
    _eventSub = null;
    await asyncPrefs.remove(_apiBaseKey);
    await asyncPrefs.remove(_wsUrlKey);
    await asyncPrefs.remove(_autumnBaseKey);
    _service.setServerUrl('https://api.revolt.chat', _defaultWsUrl);
    _service.setAutumnUrl('https://autumn.revolt.chat');
    state = AsyncData(
      const LoginStateData(
        apiBase: 'https://api.revolt.chat',
        autumnBase: 'https://autumn.revolt.chat',
      ),
    );
  }

  Future<void> updateDisplayName(String name) async {
    await _service.updateProfile(displayName: name.isEmpty ? '' : name);
    final current = state.requireValue;
    final updated = current.currentUser?.copyWith(displayName: name.isEmpty ? '' : name);
    state = AsyncData(current.copyWith(currentUser: updated));
  }

  Future<void> updateStatus({String? presence, String? statusText}) async {
    await _service.updateProfile(presence: presence, statusText: statusText);
    final current = state.requireValue;
    final updated = current.currentUser?.copyWith(
      presence: presence != null ? parsePresence(presence) : null,
      statusText: statusText,
    );
    state = AsyncData(current.copyWith(currentUser: updated));
  }

  Future<void> updateBio(String bio) async {
    await _service.updateProfile(profileContent: bio);
    final current = state.requireValue;
    final updated = current.currentUser?.copyWith(profileContent: bio);
    state = AsyncData(current.copyWith(currentUser: updated));
  }

  Future<void> updateAvatar(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadAvatar(bytes, filename);
    await _service.updateProfile(avatar: fileId);
    final current = state.requireValue;
    final oldUrl = current.currentUser?.resolveAvatarUrl(
      null,
      _service.autumnBase,
      _service.apiBase,
    );
    final updated = current.currentUser?.copyWith(
      avatar: RevoltFile(id: fileId, tag: 'avatars', filename: filename),
    );
    if (oldUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    state = AsyncData(current.copyWith(currentUser: updated));
  }

  Future<void> updateBanner(Uint8List bytes, String filename) async {
    final fileId = await _service.uploadBackground(bytes, filename);
    await _service.updateProfile(background: fileId);
    final current = state.requireValue;
    final oldUrl = current.currentUser?.bannerUrlFor(_service.autumnBase);
    final updated = current.currentUser?.copyWith(
      banner: RevoltFile(id: fileId, tag: 'backgrounds', filename: filename),
    );
    if (oldUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    state = AsyncData(current.copyWith(currentUser: updated));
  }

  Future<void> updateServerProfile(String serverId, {String? nickname, String? avatar}) async {
    final userId = state.requireValue.currentUser?.id;
    if (userId == null) return;
    final remove = <String>[];
    String? effectiveNickname = nickname;
    if (nickname == '') {
      remove.add('Nickname');
      effectiveNickname = null;
    }
    await _service.updateServerMember(
      serverId,
      userId,
      nickname: effectiveNickname,
      avatar: avatar,
      remove: remove,
    );
  }
}

final loginStateProvider = AsyncNotifierProvider<LoginNotifier, LoginStateData>(LoginNotifier.new);

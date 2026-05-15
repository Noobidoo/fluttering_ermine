import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';
import 'server_state.dart';

class MessagingState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  final ServerState _serverState;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  String? _currentUserId;
  RevoltChannel? _prevSelectedChannel;

  final Map<String, RevoltUser> _userCache = {};
  final Map<String, List<RevoltMessage>> _messages = {};
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};

  MessagingState(this._service, this._serverState) {
    _serverState.addListener(_onServerStateChanged);
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  List<RevoltMessage> get currentMessages {
    final channel = _serverState.selectedChannel;
    if (channel == null) return const [];
    return List.unmodifiable(_messages[channel.id] ?? []);
  }

  bool get isLoadingMessages {
    final channel = _serverState.selectedChannel;
    return channel != null && _loadingChannels.contains(channel.id);
  }

  String? get currentChannelError {
    final channel = _serverState.selectedChannel;
    return channel != null ? _channelErrors[channel.id] : null;
  }

  RevoltUser? getUser(String id) => _userCache[id];

  // ── Channel display ───────────────────────────────────────────────────────

  void setCurrentUserId(String? id) => _currentUserId = id;

  String channelDisplayName(RevoltChannel channel) {
    if (channel.name != null) return channel.name!;
    if (channel.type == ChannelType.savedMessages) return 'Saved Messages';
    if (channel.type == ChannelType.directMessage) {
      final otherId = channel.recipientIds?.firstWhere(
        (id) => id != _currentUserId,
        orElse: () => '',
      );
      if (otherId != null && otherId.isNotEmpty) {
        return _userCache[otherId]?.displayUsername ?? 'Direct Message';
      }
    }
    return 'Unknown Channel';
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void subscribeToEvents() {
    _wsSub?.cancel();
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
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> event) {
    final msg = RevoltMessage.fromJson(event);
    final list = _messages.putIfAbsent(msg.channelId, () => []);
    if (list.any((m) => m.id == msg.id)) return;
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

  // ── Reacts to ServerState channel changes ─────────────────────────────────

  void _onServerStateChanged() {
    final channel = _serverState.selectedChannel;
    if (channel?.id == _prevSelectedChannel?.id) return;
    _prevSelectedChannel = channel;
    notifyListeners(); // so currentMessages / isLoadingMessages update immediately
    if (channel != null && !_messages.containsKey(channel.id)) {
      _loadMessages(channel.id);
    }
  }

  void _ensureUserCached(String userId) {
    if (userId.isEmpty || _userCache.containsKey(userId)) return;
    _service.fetchUser(userId).then((user) {
      _userCache[user.id] = user;
      notifyListeners();
    }).catchError((_) {});
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> sendMessage(String content) async {
    final channel = _serverState.selectedChannel;
    if (channel == null || content.trim().isEmpty) return;
    final msg = await _service.sendMessage(channel.id, content.trim());
    final list = _messages.putIfAbsent(msg.channelId, () => []);
    if (!list.any((m) => m.id == msg.id)) {
      list.insert(0, msg);
      _ensureUserCached(msg.authorId);
      notifyListeners();
    }
  }

  Future<void> retryLoadMessages() async {
    final channel = _serverState.selectedChannel;
    if (channel == null) return;
    _messages.remove(channel.id);
    _channelErrors.remove(channel.id);
    notifyListeners();
    await _loadMessages(channel.id);
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

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    _messages.clear();
    _userCache.clear();
    _channelErrors.clear();
    _loadingChannels.clear();
    _currentUserId = null;
    _prevSelectedChannel = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _serverState.removeListener(_onServerStateChanged);
    _wsSub?.cancel();
    super.dispose();
  }
}

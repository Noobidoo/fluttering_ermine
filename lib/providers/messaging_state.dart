import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';
import 'server_state.dart';

class MessagingState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  /// Exposed so widgets can call low-level service operations (e.g. upload).
  RevoltService get service => _service;
  final ServerState _serverState;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  String? _currentUserId;
  RevoltChannel? _prevSelectedChannel;

  final Map<String, RevoltUser> _userCache = {};
  final Map<String, List<RevoltMessage>> _messages = {};
  final Map<String, String> _channelErrors = {};
  final Set<String> _loadingChannels = {};
  // Reply compose state
  RevoltMessage? _replyTarget;
  // Typing state: channelId -> set of user IDs currently typing
  final Map<String, Set<String>> _typingUsers = {};
  // Debounce: last time we sent BeginTyping per channel
  final Map<String, DateTime> _lastTypingSent = {};

  MessagingState(this._service, this._serverState) {
    _serverState.addListener(_onServerStateChanged);
  }

  // -- Getters ---------------------------------------------------------------

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

  List<RevoltUser> get cachedUsers => _userCache.values.toList();

  RevoltMessage? get replyTarget => _replyTarget;

  /// Returns the set of user IDs currently typing in [channelId].
  Set<String> typingUsersFor(String channelId) =>
      Set.unmodifiable(_typingUsers[channelId] ?? {});

  /// Looks up a cached message by ID within a channel.
  RevoltMessage? getMessageById(String channelId, String messageId) {
    final list = _messages[channelId];
    if (list == null) return null;
    for (final m in list) {
      if (m.id == messageId) return m;
    }
    return null;
  }

  // -- Channel display -------------------------------------------------------

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

  // -- WebSocket -------------------------------------------------------------

  void subscribeToEvents() {
    _wsSub?.cancel();
    _wsSub = _service.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> event) {
    switch (event['type'] as String?) {
      case 'Ready':
        _onReady(event);
        break;
      case 'Message':
        _onMessage(event);
        break;
      case 'MessageUpdate':
        _onMessageUpdate(event);
        break;
      case 'MessageDelete':
        _onMessageDelete(event);
        break;
      case 'ChannelStartTyping':
        _onTypingStart(event);
        break;
      case 'ChannelStopTyping':
        _onTypingStop(event);
        break;
      case 'MessageReact':
        _onMessageReact(event);
        break;
      case 'MessageUnreact':
        _onMessageUnreact(event);
        break;
      case 'MessageRemoveReaction':
        _onMessageRemoveReaction(event);
        break;
      case 'UserUpdate':
        _onUserUpdate(event);
        break;
      // Voice events handled by ServerState - ignore here.
      case 'VoiceChannelJoin':
      case 'VoiceChannelLeave':
      case 'VoiceChannelMove':
      case 'UserVoiceStateUpdate':
      case 'ServerMemberUpdate':
        break;
      default:
        // Debug print unhandled events, but only in debug mode to avoid spamming release logs
        debugPrint('Unhandled WS event: ${event['type']}');
        break;
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
    // Auto-ack if already viewing this channel
    final current = _serverState.selectedChannel;
    if (current?.id == msg.channelId) {
      _serverState.markChannelRead(msg.channelId, msg.id);
      _service.ackMessage(msg.channelId, msg.id).catchError((Object e) {
        debugPrint('[ack] channel=${msg.channelId} failed: $e');
      });
    }
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

  // -- Reacts to ServerState channel changes ---------------------------------

  void _onServerStateChanged() {
    final channel = _serverState.selectedChannel;
    if (channel?.id == _prevSelectedChannel?.id) return;
    _prevSelectedChannel = channel;
    notifyListeners(); // so currentMessages / isLoadingMessages update immediately
    if (channel != null && !_messages.containsKey(channel.id)) {
      _loadMessages(channel.id);
    }
    if (channel != null && channel.lastMessageId != null) {
      _ackChannel(channel);
    }
  }

  void _ackChannel(RevoltChannel channel) {
    final lastId = _serverState.latestMessageId(channel.id) ??
        channel.lastMessageId;
    if (lastId == null) return;
    _service.ackMessage(channel.id, lastId).catchError((Object e) {
      debugPrint('[ack] channel=${channel.id} failed: $e');
    });
    _serverState.markChannelRead(channel.id, lastId);
  }

  void _ensureUserCached(String userId) {
    if (userId.isEmpty || _userCache.containsKey(userId)) return;
    _service.fetchUser(userId).then((user) {
      _userCache[user.id] = user;
      notifyListeners();
    }).catchError((_) {});
  }

  void _onMessageReact(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final userId = event['user_id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null || messageId == null ||
        userId == null || emojiId == null) {
      return;
    }
    final list = _messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = msg.reactions.map(
        (k, v) => MapEntry(k, List<String>.from(v)));
    newReactions.putIfAbsent(emojiId, () => []);
    if (!newReactions[emojiId]!.contains(userId)) {
      newReactions[emojiId]!.add(userId);
    }
    list[idx] = msg.copyWith(reactions: newReactions);
    notifyListeners();
  }

  void _onMessageUnreact(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final userId = event['user_id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null || messageId == null ||
        userId == null || emojiId == null) {
      return;
    }
    final list = _messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = msg.reactions.map(
        (k, v) => MapEntry(k, List<String>.from(v)));
    newReactions[emojiId]?.remove(userId);
    if (newReactions[emojiId]?.isEmpty == true) {
      newReactions.remove(emojiId);
    }
    list[idx] = msg.copyWith(reactions: newReactions);
    notifyListeners();
  }

  void _onMessageRemoveReaction(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null || messageId == null || emojiId == null) return;
    final list = _messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = Map<String, List<String>>.from(msg.reactions)
      ..remove(emojiId);
    list[idx] = msg.copyWith(reactions: newReactions);
    notifyListeners();
  }

  void _onTypingStart(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    if (channelId == null || userId == null) return;
    if (userId == _currentUserId) return;
    _typingUsers.putIfAbsent(channelId, () => {}).add(userId);
    _ensureUserCached(userId);
    notifyListeners();
  }

  void _onTypingStop(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    if (channelId == null || userId == null) return;
    _typingUsers[channelId]?.remove(userId);
    if (_typingUsers[channelId]?.isEmpty == true) {
      _typingUsers.remove(channelId);
    }
    notifyListeners();
  }

  void _onUserUpdate(Map<String, dynamic> event) {
    final userId = event['id'] as String?;
    if (userId == null) return;
    final cached = _userCache[userId];
    final data = (event['data'] as Map?)?.cast<String, dynamic>();
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    if (cached != null && data != null && data.isNotEmpty) {
      // Evict old avatar if avatar changed or cleared
      if (data.containsKey('avatar') || clear.contains('avatar')) {
        final oldUrl = cached.avatarUrlFor(_service.autumnBase, _service.apiBase);
        PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
      }

      _userCache[userId] = RevoltUser(
        id: cached.id,
        username: data['username'] as String? ?? cached.username,
        discriminator: (data['discriminator'] as String? ?? cached.discriminator),
        displayName: data['display_name'] as String? ?? cached.displayName,
        avatar: clear.contains('avatar')
            ? null
            : data['avatar'] != null
                ? RevoltFile.fromJson(Map<String, dynamic>.from(data['avatar'] as Map))
                : data.containsKey('avatar')
                    ? null
                    : cached.avatar,
        banner: clear.contains('banner')
            ? null
            : data['banner'] != null
                ? RevoltFile.fromJson(Map<String, dynamic>.from(data['banner'] as Map))
                : data.containsKey('banner')
                    ? null
                    : cached.banner,
        presence: clear.contains('status')
            ? UserPresence.invisible
            : data['status'] is Map && (data['status'] as Map).containsKey('presence')
                ? parsePresence((data['status'] as Map)['presence'] as String?)
                : cached.presence,
        statusText: clear.contains('status')
            ? null
            : data['status'] is Map
                ? (data['status'] as Map)['text'] as String? ?? cached.statusText
                : cached.statusText,
        profileContent: clear.contains('profile')
            ? null
            : data['profile'] is Map
                ? (data['profile'] as Map)['content'] as String? ?? cached.profileContent
                : cached.profileContent,
      );
      notifyListeners();
      return;
    }

    // Fallback: re-fetch from API for uncached or no-data events
    if (cached != null) {
      final oldUrl = cached.avatarUrlFor(_service.autumnBase, _service.apiBase);
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    _service.fetchUser(userId).then((user) {
      _userCache[user.id] = user;
      notifyListeners();
    }).catchError((_) {});
  }

  void cacheUser(RevoltUser user) {
    _userCache[user.id] = user;
    notifyListeners();
  }

  void ensureUsersCached(List<String> userIds) {
    for (final id in userIds) {
      _ensureUserCached(id);
    }
  }

  // -- Reply compose ---------------------------------------------------------

  void setReplyTarget(RevoltMessage msg) {
    _replyTarget = msg;
    notifyListeners();
  }

  void clearReplyTarget() {
    if (_replyTarget == null) return;
    _replyTarget = null;
    notifyListeners();
  }

  // -- Typing indicator ------------------------------------------------------

  /// Sends a BeginTyping pulse at most once every 2.5 seconds.
  void sendTypingIndicator() {
    final channel = _serverState.selectedChannel;
    if (channel == null) return;
    final now = DateTime.now();
    final last = _lastTypingSent[channel.id];
    if (last != null && now.difference(last).inMilliseconds < 2500) return;
    _lastTypingSent[channel.id] = now;
    _service.sendTyping(channel.id);
  }

  // -- Actions ---------------------------------------------------------------

  Future<void> sendMessage(String content,
      {List<String> attachmentIds = const []}) async {
    final channel = _serverState.selectedChannel;
    if (channel == null || (content.trim().isEmpty && attachmentIds.isEmpty)) {
      return;
    }
    final replyId = _replyTarget?.id;
    _replyTarget = null;
    notifyListeners();
    final msg = await _service.sendMessage(
      channel.id,
      content.trim(),
      replyToId: replyId,
      attachmentIds: attachmentIds,
    );
    final list = _messages.putIfAbsent(msg.channelId, () => []);
    if (!list.any((m) => m.id == msg.id)) {
      list.insert(0, msg);
      _ensureUserCached(msg.authorId);
      notifyListeners();
    }
  }

  Future<void> addReaction(
      String channelId, String messageId, String emoji) async {
    await _service.addReaction(channelId, messageId, emoji);
    // WS MessageReact will update local state
  }

  Future<void> removeReaction(
      String channelId, String messageId, String emoji) async {
    await _service.removeReaction(channelId, messageId, emoji);
    // WS MessageUnreact will update local state
  }

  Future<void> editMessage(
      String channelId, String messageId, String content) async {
    await _service.editMessage(channelId, messageId, content);
    // WS MessageUpdate will update local state
  }

  Future<void> deleteMessage(String channelId, String messageId) async {
    await _service.deleteMessage(channelId, messageId);
    // WS MessageDelete will update local state
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

  // -- Lifecycle -------------------------------------------------------------

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    _messages.clear();
    _userCache.clear();
    _channelErrors.clear();
    _loadingChannels.clear();
    _replyTarget = null;
    _typingUsers.clear();
    _lastTypingSent.clear();
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

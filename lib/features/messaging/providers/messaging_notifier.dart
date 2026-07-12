import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/models.dart';
import '../../../services/revolt_service.dart';
import '../../core/providers/service_providers.dart';
import '../../servers/providers/current_user_id_provider.dart';
import '../../servers/providers/server_notifier.dart';

@immutable
class MessagingStateData {
  final Map<String, RevoltUser> userCache;
  final Map<String, List<RevoltMessage>> messages;
  final Map<String, String> channelErrors;
  final Set<String> loadingChannels;
  final RevoltMessage? replyTarget;
  final Map<String, Set<String>> typingUsers;

  const MessagingStateData({
    this.userCache = const {},
    this.messages = const {},
    this.channelErrors = const {},
    this.loadingChannels = const {},
    this.replyTarget,
    this.typingUsers = const {},
  });

  MessagingStateData copyWith({
    Map<String, RevoltUser>? userCache,
    Map<String, List<RevoltMessage>>? messages,
    Map<String, String>? channelErrors,
    Set<String>? loadingChannels,
    Object? replyTarget = _omit,
    Map<String, Set<String>>? typingUsers,
  }) => MessagingStateData(
    userCache: userCache ?? this.userCache,
    messages: messages ?? this.messages,
    channelErrors: channelErrors ?? this.channelErrors,
    loadingChannels: loadingChannels ?? this.loadingChannels,
    replyTarget: replyTarget == _omit
        ? this.replyTarget
        : replyTarget as RevoltMessage?,
    typingUsers: typingUsers ?? this.typingUsers,
  );

  static const _omit = Object();
}

class MessagingNotifier extends Notifier<MessagingStateData> {
  late RevoltService _service;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  String? _prevSelectedChannelId;
  final Map<String, DateTime> _lastTypingSent = {};

  @override
  MessagingStateData build() {
    _service = ref.watch(revoltServiceProvider);

    ref.listen(serverStateProvider, (prev, next) {
      final prevId = prev?.asData?.value.selectedChannel?.id;
      final nextId = next.asData?.value.selectedChannel?.id;
      if (prevId != nextId) {
        _onSelectedChannelChanged(next.asData?.value.selectedChannel);
      }
    });

    ref.onDispose(() {
      _wsSub?.cancel();
    });

    _subscribeToEvents();

    return const MessagingStateData();
  }

  void _subscribeToEvents() {
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
      default:
        debugPrint('[Messaging] Unhandled WS event: ${event['type']}');
        break;
    }
  }

  void _onReady(Map<String, dynamic> event) {
    final users = (event['users'] as List<dynamic>?) ?? [];
    final cache = Map<String, RevoltUser>.from(state.userCache);
    for (final u in users) {
      final user = RevoltUser.fromJson(u as Map<String, dynamic>);
      cache[user.id] = user;
    }
    state = state.copyWith(userCache: cache);
  }

  void _onMessage(Map<String, dynamic> event) {
    final msg = RevoltMessage.fromJson(event);
    final list = List<RevoltMessage>.from(state.messages[msg.channelId] ?? []);
    if (list.any((m) => m.id == msg.id)) return;
    list.insert(0, msg);
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[msg.channelId] = list;
    _ensureUserCached(msg.authorId);
    final channel = ref.read(serverStateProvider).asData?.value.selectedChannel;
    if (channel?.id == msg.channelId) {
      ref
          .read(serverStateProvider.notifier)
          .markChannelRead(msg.channelId, msg.id);
      _service.ackMessage(msg.channelId, msg.id).catchError((Object e) {
        debugPrint('[ack] channel=${msg.channelId} failed: $e');
      });
    }
    state = state.copyWith(messages: messages);
  }

  void _onMessageUpdate(Map<String, dynamic> event) {
    final id = event['id'] as String;
    final channelId = event['channel'] as String;
    final list = state.messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final data = event['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final old = list[idx];
    final updated = list.toList()
      ..[idx] = RevoltMessage(
        id: old.id,
        channelId: old.channelId,
        authorId: old.authorId,
        content: data['content'] as String? ?? old.content,
        timestamp: old.timestamp,
        edited: data['edited'] as String? ?? old.edited,
        attachments: old.attachments,
      );
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[channelId] = updated;
    state = state.copyWith(messages: messages);
  }

  void _onMessageDelete(Map<String, dynamic> event) {
    final id = event['id'] as String;
    final channelId = event['channel'] as String;
    final list = state.messages[channelId];
    if (list == null) return;
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[channelId] = list.where((m) => m.id != id).toList();
    state = state.copyWith(messages: messages);
  }

  void _onMessageReact(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final userId = event['user_id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null ||
        messageId == null ||
        userId == null ||
        emojiId == null) {
      return;
    }
    final list = state.messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = msg.reactions.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    );
    newReactions.putIfAbsent(emojiId, () => []);
    if (!newReactions[emojiId]!.contains(userId)) {
      newReactions[emojiId]!.add(userId);
    }
    final updated = list.toList()
      ..[idx] = msg.copyWith(reactions: newReactions);
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[channelId] = updated;
    state = state.copyWith(messages: messages);
  }

  void _onMessageUnreact(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final userId = event['user_id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null ||
        messageId == null ||
        userId == null ||
        emojiId == null) {
      return;
    }
    final list = state.messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = msg.reactions.map(
      (k, v) => MapEntry(k, List<String>.from(v)),
    );
    newReactions[emojiId]?.remove(userId);
    if (newReactions[emojiId]?.isEmpty == true) {
      newReactions.remove(emojiId);
    }
    final updated = list.toList()
      ..[idx] = msg.copyWith(reactions: newReactions);
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[channelId] = updated;
    state = state.copyWith(messages: messages);
  }

  void _onMessageRemoveReaction(Map<String, dynamic> event) {
    final channelId = event['channel_id'] as String?;
    final messageId = event['id'] as String?;
    final emojiId = event['emoji_id'] as String?;
    if (channelId == null || messageId == null || emojiId == null) return;
    final list = state.messages[channelId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final msg = list[idx];
    final newReactions = Map<String, List<String>>.from(msg.reactions)
      ..remove(emojiId);
    final updated = list.toList()
      ..[idx] = msg.copyWith(reactions: newReactions);
    final messages = Map<String, List<RevoltMessage>>.from(state.messages);
    messages[channelId] = updated;
    state = state.copyWith(messages: messages);
  }

  void _onTypingStart(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    final currentUserId = ref.read(currentUserIdProvider);
    if (channelId == null || userId == null) return;
    if (userId == currentUserId) return;
    final typingUsers = Map<String, Set<String>>.from(state.typingUsers);
    typingUsers.putIfAbsent(channelId, () => {}).add(userId);
    _ensureUserCached(userId);
    state = state.copyWith(typingUsers: typingUsers);
  }

  void _onTypingStop(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    if (channelId == null || userId == null) return;
    final typingUsers = Map<String, Set<String>>.from(state.typingUsers);
    typingUsers[channelId]?.remove(userId);
    if (typingUsers[channelId]?.isEmpty == true) {
      typingUsers.remove(channelId);
    }
    state = state.copyWith(typingUsers: typingUsers);
  }

  RevoltFile? _parseFile(dynamic value) {
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

  void _onUserUpdate(Map<String, dynamic> event) {
    debugPrint('[Messaging/UserUpdate] raw event: ${event.toString()}');
    final userId = event['id'] as String?;
    if (userId == null) return;
    final cached = state.userCache[userId];
    final data = (event['data'] as Map?)?.cast<String, dynamic>();
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];

    if (cached != null && (data != null || clear.isNotEmpty)) {
      if (data?.containsKey('avatar') == true || clear.contains('avatar')) {
        final oldUrl = cached.resolveAvatarUrl(
          null,
          _service.autumnBase,
          _service.apiBase,
        );
        PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
      }

      try {
        final cache = Map<String, RevoltUser>.from(state.userCache);
        cache[userId] = RevoltUser(
          id: cached.id,
          username: data?['username'] as String? ?? cached.username,
          discriminator:
              (data?['discriminator'] as String? ?? cached.discriminator),
          displayName: data?['display_name'] as String? ?? cached.displayName,
          avatar: clear.contains('avatar')
              ? null
              : data?.containsKey('avatar') == true
              ? _parseFile(data!['avatar'])
              : cached.avatar,
          banner: clear.contains('banner')
              ? null
              : data?.containsKey('banner') == true
              ? _parseFile(data!['banner'])
              : cached.banner,
          presence: clear.contains('status')
              ? UserPresence.invisible
              : data?['status'] is Map &&
                    (data!['status'] as Map).containsKey('presence')
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
              ? (data!['profile'] as Map)['content'] as String? ??
                    cached.profileContent
              : cached.profileContent,
          serverProfiles: cached.serverProfiles,
        );
        state = state.copyWith(userCache: cache);
      } catch (_) {}
      return;
    }

    if (cached != null) return;

    _service
        .fetchUser(userId)
        .then((user) {
          final cache = Map<String, RevoltUser>.from(state.userCache);
          cache[user.id] = user;
          state = state.copyWith(userCache: cache);
        })
        .catchError((_) {});
  }

  void updateServerProfile(
    String userId,
    String serverId,
    Map<String, dynamic>? data,
    List<String> clear,
  ) {
    final cached = state.userCache[userId];
    if (cached == null) return;
    final existing = cached.serverProfiles[serverId] ?? ServerProfile();
    final profile = existing.copyWith(
      nickname: clear.contains('Nickname')
          ? null
          : (data?['nickname'] as String?),
      roles: clear.contains('Roles')
          ? []
          : data?['roles'] != null
          ? (data!['roles'] as List<dynamic>).cast<String>()
          : null,
      avatar: clear.contains('Avatar')
          ? null
          : data?.containsKey('avatar') == true
          ? _parseFile(data!['avatar'])
          : null,
      clearNickname: clear.contains('Nickname'),
      clearAvatar: clear.contains('Avatar'),
      clearRoles: clear.contains('Roles'),
    );
    final cache = Map<String, RevoltUser>.from(state.userCache);
    cache[userId] = cached.copyWithServerProfile(serverId, profile);
    state = state.copyWith(userCache: cache);
  }

  void _onSelectedChannelChanged(RevoltChannel? channel) {
    if (channel?.id == _prevSelectedChannelId) return;
    _prevSelectedChannelId = channel?.id;
    if (channel != null && !state.messages.containsKey(channel.id)) {
      _loadMessages(channel.id);
    }
    if (channel != null && channel.lastMessageId != null) {
      _ackChannel(channel);
    }
  }

  void _ackChannel(RevoltChannel channel) {
    final serverState = ref.read(serverStateProvider).asData?.value;
    final lastId =
        serverState?.latestMessageId(channel.id) ?? channel.lastMessageId;
    if (lastId == null) return;
    _service.ackMessage(channel.id, lastId).catchError((Object e) {
      debugPrint('[ack] channel=${channel.id} failed: $e');
    });
    ref.read(serverStateProvider.notifier).markChannelRead(channel.id, lastId);
  }

  void _ensureUserCached(String userId) {
    if (userId.isEmpty || state.userCache.containsKey(userId)) return;
    _service
        .fetchUser(userId)
        .then((user) {
          final cache = Map<String, RevoltUser>.from(state.userCache);
          cache[user.id] = user;
          state = state.copyWith(userCache: cache);
        })
        .catchError((_) {});
  }

  String channelDisplayName(RevoltChannel channel) {
    if (channel.name != null) return channel.name!;
    if (channel.type == ChannelType.savedMessages) return 'Saved Messages';
    if (channel.type == ChannelType.directMessage) {
      final currentUserId = ref.read(currentUserIdProvider);
      final otherId = channel.recipientIds?.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );
      if (otherId != null && otherId.isNotEmpty) {
        return state.userCache[otherId]?.resolveDisplayName(null) ??
            'Direct Message';
      }
    }
    return 'Unknown Channel';
  }

  void cacheUser(RevoltUser user) {
    final cache = Map<String, RevoltUser>.from(state.userCache);
    cache[user.id] = user;
    state = state.copyWith(userCache: cache);
  }

  void cacheUsers(List<RevoltUser> users) {
    final cache = Map<String, RevoltUser>.from(state.userCache);
    for (final u in users) {
      cache[u.id] = u;
    }
    state = state.copyWith(userCache: cache);
  }

  void ensureUsersCached(List<String> userIds) {
    for (final id in userIds) {
      _ensureUserCached(id);
    }
  }

  void setReplyTarget(RevoltMessage msg) {
    state = state.copyWith(replyTarget: msg);
  }

  void clearReplyTarget() {
    if (state.replyTarget == null) return;
    state = state.copyWith(replyTarget: null);
  }

  void sendTypingIndicator() {
    final channel = ref.read(serverStateProvider).asData?.value.selectedChannel;
    if (channel == null) return;
    final now = DateTime.now();
    final last = _lastTypingSent[channel.id];
    if (last != null && now.difference(last).inMilliseconds < 2500) return;
    _lastTypingSent[channel.id] = now;
    _service.sendTyping(channel.id);
  }

  Future<void> sendMessage(
    String content, {
    List<String> attachmentIds = const [],
  }) async {
    final channel = ref.read(serverStateProvider).asData?.value.selectedChannel;
    if (channel == null || (content.trim().isEmpty && attachmentIds.isEmpty)) {
      return;
    }
    final replyId = state.replyTarget?.id;
    state = state.copyWith(replyTarget: null);
    final msg = await _service.sendMessage(
      channel.id,
      content.trim(),
      replyToId: replyId,
      attachmentIds: attachmentIds,
    );
    final list = List<RevoltMessage>.from(state.messages[msg.channelId] ?? []);
    if (!list.any((m) => m.id == msg.id)) {
      list.insert(0, msg);
      _ensureUserCached(msg.authorId);
      final messages = Map<String, List<RevoltMessage>>.from(state.messages);
      messages[msg.channelId] = list;
      state = state.copyWith(messages: messages);
    }
  }

  Future<void> addReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    await _service.addReaction(channelId, messageId, emoji);
  }

  Future<void> removeReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    await _service.removeReaction(channelId, messageId, emoji);
  }

  Future<void> editMessage(
    String channelId,
    String messageId,
    String content,
  ) async {
    await _service.editMessage(channelId, messageId, content);
  }

  Future<void> deleteMessage(String channelId, String messageId) async {
    await _service.deleteMessage(channelId, messageId);
  }

  Future<void> retryLoadMessages() async {
    final channel = ref.read(serverStateProvider).asData?.value.selectedChannel;
    if (channel == null) return;
    final messages = Map<String, List<RevoltMessage>>.from(state.messages)
      ..remove(channel.id);
    final channelErrors = Map<String, String>.from(state.channelErrors)
      ..remove(channel.id);
    state = state.copyWith(messages: messages, channelErrors: channelErrors);
    await _loadMessages(channel.id);
  }

  Future<void> _loadMessages(String channelId) async {
    final loadingChannels = Set<String>.from(state.loadingChannels)
      ..add(channelId);
    final channelErrors = Map<String, String>.from(state.channelErrors)
      ..remove(channelId);
    state = state.copyWith(
      loadingChannels: loadingChannels,
      channelErrors: channelErrors,
    );
    try {
      final msgs = await _service.fetchMessages(channelId);
      final messages = Map<String, List<RevoltMessage>>.from(state.messages);
      messages[channelId] = msgs;
      state = state.copyWith(messages: messages);
      for (final m in msgs) {
        _ensureUserCached(m.authorId);
      }
    } catch (e) {
      debugPrint('[loadMessages] $channelId failed: $e');
      state = state.copyWith(
        channelErrors: {
          ...state.channelErrors,
          channelId: e.toString().replaceAll('Exception: ', ''),
        },
      );
    } finally {
      final done = Set<String>.from(state.loadingChannels)..remove(channelId);
      state = state.copyWith(loadingChannels: done);
    }
  }

  void clear() {
    _wsSub?.cancel();
    _wsSub = null;
    _lastTypingSent.clear();
    _prevSelectedChannelId = null;
    state = const MessagingStateData();
  }
}

final messagingStateProvider =
    NotifierProvider<MessagingNotifier, MessagingStateData>(
      MessagingNotifier.new,
    );

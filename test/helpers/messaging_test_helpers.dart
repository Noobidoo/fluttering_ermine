// Shared helpers for Phase 1 MessagingState unit tests.
//
// Import this file from each focused test file to avoid duplicating
// the fake service and common builder functions.

import 'dart:async';
import 'dart:typed_data';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/services/revolt_service.dart';

// ── Fake RevoltService ────────────────────────────────────────────────────────

class FakeRevoltService extends RevoltService {
  final _ctrl =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);

  final List<String> typingCalls = [];
  final List<({String channelId, String messageId, String content})>
      editCalls = [];
  final List<({String channelId, String messageId})> deleteCalls = [];
  final List<({String channelId, String messageId, String emoji})>
      addReactionCalls = [];
  final List<({String channelId, String messageId, String emoji})>
      removeReactionCalls = [];
  final List<({String channelId, String content, String? replyToId})>
      sendMessageCalls = [];

  final Map<String, RevoltUser> _userStubs = {};
  RevoltMessage? sendMessageResult;

  @override
  Stream<Map<String, dynamic>> get events => _ctrl.stream;

  @override
  void connectWebSocket() {}

  @override
  String get apiBase => 'https://api.example.test';

  @override
  String get autumnBase => 'https://autumn.example.test';

  /// Inject a raw WS event into all subscribed providers.
  void push(Map<String, dynamic> event) => _ctrl.add(event);

  void stubUser(RevoltUser user) => _userStubs[user.id] = user;

  @override
  Future<RevoltUser> fetchUser(String userId) async =>
      _userStubs[userId] ??
      RevoltUser(id: userId, username: 'stub', discriminator: '0000');

  /// Never completes — prevents _loadMessages from overwriting WS-pushed messages.
  @override
  Future<List<RevoltMessage>> fetchMessages(String channelId,
          {int limit = 50}) =>
      Completer<List<RevoltMessage>>().future;

  @override
  void sendTyping(String channelId) => typingCalls.add(channelId);

  @override
  Future<RevoltMessage> sendMessage(
    String channelId,
    String content, {
    String? replyToId,
    List<String> attachmentIds = const [],
  }) async {
    sendMessageCalls.add(
        (channelId: channelId, content: content, replyToId: replyToId));
    return sendMessageResult ??
        RevoltMessage(
          id: 'stub-msg',
          channelId: channelId,
          authorId: 'stub-author',
          content: content,
          timestamp: '2024-01-01T00:00:00.000Z',
        );
  }

  @override
  Future<void> editMessage(
      String channelId, String messageId, String content) async {
    editCalls
        .add((channelId: channelId, messageId: messageId, content: content));
  }

  @override
  Future<void> deleteMessage(String channelId, String messageId) async {
    deleteCalls.add((channelId: channelId, messageId: messageId));
  }

  @override
  Future<void> addReaction(
      String channelId, String messageId, String emoji) async {
    addReactionCalls
        .add((channelId: channelId, messageId: messageId, emoji: emoji));
  }

  @override
  Future<void> removeReaction(
      String channelId, String messageId, String emoji) async {
    removeReactionCalls
        .add((channelId: channelId, messageId: messageId, emoji: emoji));
  }

  @override
  Future<String> uploadAttachment(Uint8List bytes, String filename) async =>
      'stub-file-id';

  void close() => _ctrl.close();
}

// ── Builder helpers ───────────────────────────────────────────────────────────

/// WS payload for a new Message event (mirrors RevoltMessage.fromJson fields).
Map<String, dynamic> msgEvent({
  String id = 'msg1',
  String channel = 'chan1',
  String author = 'u1',
  String content = 'Hello',
  List<String>? replies,
  Map<String, List<String>>? reactions,
}) =>
    {
      'type': 'Message',
      '_id': id,
      'channel': channel,
      'author': author,
      'content': content,
      'timestamp': '2024-01-01T00:00:00.000Z',
      if (replies != null) 'replies': replies,
      if (reactions != null)
        'reactions': {
          for (final e in reactions.entries) e.key: e.value,
        },
    };

/// Minimal text channel for selecting in ServerState.
RevoltChannel textChan(String id) => RevoltChannel(
      id: id,
      type: ChannelType.textChannel,
      name: 'test',
    );

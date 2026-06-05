// Shared helpers for Phase 1 MessagingState unit tests.
//
// Import this file from each focused test file to avoid duplicating
// the fake service and common builder functions.

import 'dart:async';
import 'dart:typed_data';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/services/revolt_service.dart';

// -- Fake RevoltService --------------------------------------------------------

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

  /// Never completes ΓÇö prevents _loadMessages from overwriting WS-pushed messages.
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

  final Map<String, RevoltChannel> _channelStubs = {};

  void stubChannel(RevoltChannel channel) =>
      _channelStubs[channel.id] = channel;

  @override
  Future<List<RevoltChannel>> fetchChannels(List<String> channelIds) async =>
      channelIds.map((id) => _channelStubs[id]!).toList();

  // -- Ack / Unread ----------------------------------------------------------

  final List<String> ackCalls = [];

  @override
  Future<void> ackMessage(String channelId, String messageId) async {
    ackCalls.add(channelId);
  }

  // -- Members ---------------------------------------------------------------

  final Map<String, List<({String userId, String? nickname, List<String> roles, RevoltFile? avatar})>> _memberStubs = {};
  bool fetchMembersThrows = false;

  void stubMembers(String serverId, List<({String userId, String? nickname, List<String> roles, RevoltFile? avatar})> members) {
    _memberStubs[serverId] = members;
  }

  @override
  Future<(List<({String userId, String? nickname, List<String> roles, RevoltFile? avatar})>, List<RevoltUser>)> fetchServerMembers(
      String serverId) async {
    if (fetchMembersThrows) throw Exception('fetch failed');
    final members = _memberStubs[serverId] ?? [];
    return (members, List<RevoltUser>.empty());
  }

  // -- Invites ---------------------------------------------------------------

  final List<String> createInviteCalls = [];
  final List<String> joinInviteCalls = [];
  String createInviteResult = 'test-code';
  List<RevoltInvite> fetchInvitesResult = const [];
  final List<String> fetchInvitesCalls = [];

  @override
  Future<String> createInvite(String channelId) async {
    createInviteCalls.add(channelId);
    return createInviteResult;
  }

  @override
  Future<List<RevoltInvite>> fetchInvites(String serverId) async {
    fetchInvitesCalls.add(serverId);
    return fetchInvitesResult;
  }

  @override
  Future<void> joinInvite(String code) async {
    joinInviteCalls.add(code);
  }

  // -- Profile updates (Phase 3) ---------------------------------------------

  final List<({
    String? displayName,
    String? presence,
    String? statusText,
    String? profileContent,
    String? avatar,
    String? background,
  })> updateProfileCalls = [];

  RevoltUser? _currentUserStub;

  void stubCurrentUser(RevoltUser user) => _currentUserStub = user;

  @override
  Future<RevoltUser> fetchSelf() async =>
      _currentUserStub ??
      RevoltUser(id: 'self', username: 'self', discriminator: '0000');

  @override
  Future<RevoltUser> updateProfile({
    String? displayName,
    String? presence,
    String? statusText,
    String? profileContent,
    String? avatar,
    String? background,
  }) async {
    updateProfileCalls.add((
      displayName: displayName,
      presence: presence,
      statusText: statusText,
      profileContent: profileContent,
      avatar: avatar,
      background: background,
    ));
    return _currentUserStub ??
        RevoltUser(id: 'self', username: 'self', discriminator: '0000');
  }

  // -- Server member updates --------------------------------------------------

  final List<({String serverId, String userId, String? nickname, String? avatar, List<String> remove})>
      updateServerMemberCalls = [];

  @override
  Future<void> updateServerMember(
    String serverId,
    String userId, {
    String? nickname,
    String? avatar,
    List<String> remove = const [],
  }) async {
    updateServerMemberCalls.add((
      serverId: serverId,
      userId: userId,
      nickname: nickname,
      avatar: avatar,
      remove: remove,
    ));
  }

  // -- File uploads -----------------------------------------------------------

  final List<({Uint8List bytes, String filename})> uploadAvatarCalls = [];
  final List<({Uint8List bytes, String filename})> uploadBackgroundCalls = [];
  String uploadResult = 'stub-file-id';

  @override
  Future<String> uploadAvatar(Uint8List bytes, String filename) async {
    uploadAvatarCalls.add((bytes: bytes, filename: filename));
    return uploadResult;
  }

  @override
  Future<String> uploadBackground(Uint8List bytes, String filename) async {
    uploadBackgroundCalls.add((bytes: bytes, filename: filename));
    return uploadResult;
  }

  void close() => _ctrl.close();
}

// -- Builder helpers ------------------------------------------------------------

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
      'replies': ?replies,
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

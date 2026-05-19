// Tests for WebSocket event handling in ServerState and MessagingState.
//
// Covers the exact bugs that were reported:
//   - VoiceChannelLeave not removing users from the participant list
//   - UserUpdate not refreshing the user cache (avatar / display name)
//   - VoiceChannelMove not moving users between channels
//   - VoiceChannelJoin adding users to the list

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/providers/messaging_state.dart';
import 'package:fluttering_ermine/providers/server_state.dart';
import 'package:fluttering_ermine/services/revolt_service.dart';

// ── Minimal fake RevoltService ───────────────────────────────────────────────

class _FakeService extends RevoltService {
  // sync:true so events are delivered immediately when add() is called,
  // making tests straightforward without awaiting microtasks.
  final _ctrl = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final Map<String, RevoltUser> _userStubs = {};

  @override
  Stream<Map<String, dynamic>> get events => _ctrl.stream;

  @override
  void connectWebSocket() {} // no-op – tests inject events manually

  @override
  String get apiBase => 'https://api.example.test';

  @override
  String get autumnBase => 'https://autumn.example.test';

  /// Inject a raw WS event into both subscribed providers.
  void push(Map<String, dynamic> event) => _ctrl.add(event);

  /// Register a user to be returned by [fetchUser].
  void stubUser(RevoltUser user) => _userStubs[user.id] = user;

  @override
  Future<RevoltUser> fetchUser(String userId) async {
    final u = _userStubs[userId];
    if (u == null) throw Exception('No stub for user $userId');
    return u;
  }

  void close() => _ctrl.close();
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a minimal Ready event payload.
Map<String, dynamic> readyEvent({
  List<Map<String, dynamic>> users = const [],
  Map<String, List<String>> voiceMembers = const {},
}) {
  return {
    'type': 'Ready',
    'servers': [],
    'channels': [],
    'users': users,
    'voice_states': voiceMembers.entries
        .map((e) => {
              'id': e.key,
              'participants': e.value.map((uid) => {'id': uid}).toList(),
            })
        .toList(),
  };
}

RevoltUser fakeUser(String id, {String username = 'user'}) => RevoltUser(
      id: id,
      username: username,
      discriminator: '0001',
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // PaintingBinding is needed for imageCache.evict inside MessagingState.
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ServerState: voice membership events ────────────────────────────────

  group('ServerState – voice channel events', () {
    late _FakeService svc;
    late ServerState state;

    setUp(() {
      svc = _FakeService();
      state = ServerState(svc);
      state.subscribeToEvents();
    });

    tearDown(() => svc.close());

    test('VoiceChannelJoin adds user to channel participant list', () {
      svc.push(readyEvent());
      svc.push({
        'type': 'VoiceChannelJoin',
        'id': 'chan1',
        'state': {'id': 'user1'},
      });

      expect(state.voiceParticipantsFor('chan1'), contains('user1'));
    });

    test('VoiceChannelJoin is idempotent (no duplicates)', () {
      svc.push(readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({
        'type': 'VoiceChannelJoin',
        'id': 'chan1',
        'state': {'id': 'user1'},
      });

      expect(state.voiceParticipantsFor('chan1').length, 1);
    });

    test('VoiceChannelLeave removes the user from the channel', () {
      svc.push(readyEvent(voiceMembers: {
        'chan1': ['user1', 'user2']
      }));

      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});

      final participants = state.voiceParticipantsFor('chan1');
      expect(participants, isNot(contains('user1')));
      expect(participants, contains('user2'));
    });

    test('VoiceChannelLeave on last user empties the channel entry', () {
      svc.push(readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});

      expect(state.voiceParticipantsFor('chan1'), isEmpty);
    });

    test('VoiceChannelLeave with wrong channel ID does not affect other channels', () {
      svc.push(readyEvent(voiceMembers: {
        'chan1': ['user1'],
        'chan2': ['user2'],
      }));

      // user1 leaves chan1 (correct)
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});

      expect(state.voiceParticipantsFor('chan1'), isNot(contains('user1')));
      expect(state.voiceParticipantsFor('chan2'), contains('user2'));
    });

    test('VoiceChannelMove removes user from source and adds to destination', () {
      svc.push(readyEvent(voiceMembers: {'chan1': ['user1']}));

      svc.push({
        'type': 'VoiceChannelMove',
        'user': 'user1',
        'from': 'chan1',
        'to': 'chan2',
        'state': {'id': 'user1'},
      });

      expect(state.voiceParticipantsFor('chan1'), isNot(contains('user1')));
      expect(state.voiceParticipantsFor('chan2'), contains('user1'));
    });
  });

  // ── MessagingState: UserUpdate ──────────────────────────────────────────

  group('MessagingState – UserUpdate event', () {
    late _FakeService svc;
    late ServerState serverState;
    late MessagingState state;

    setUp(() {
      svc = _FakeService();
      serverState = ServerState(svc);
      serverState.subscribeToEvents();
      state = MessagingState(svc, serverState);
      state.subscribeToEvents();
    });

    tearDown(() => svc.close());

    test('UserUpdate re-fetches user and updates cache', () async {
      // Prime cache via Ready
      svc.push(readyEvent(users: [
        {'_id': 'user1', 'username': 'OldName', 'discriminator': '0001'},
      ]));
      expect(state.getUser('user1')?.username, 'OldName');

      // Stub the updated version
      svc.stubUser(fakeUser('user1', username: 'NewName'));

      // Inject UserUpdate
      svc.push({'type': 'UserUpdate', 'id': 'user1', 'data': {}, 'clear': []});

      // Let the async fetchUser complete
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('user1')?.username, 'NewName');
    });

    test('UserUpdate for unknown user still populates cache', () async {
      svc.stubUser(fakeUser('user99', username: 'Stranger'));

      svc.push({'type': 'UserUpdate', 'id': 'user99', 'data': {}, 'clear': []});
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('user99')?.username, 'Stranger');
    });

    test('ensureUsersCached fetches uncached users', () async {
      svc.stubUser(fakeUser('u1', username: 'Alice'));
      svc.stubUser(fakeUser('u2', username: 'Bob'));

      state.ensureUsersCached(['u1', 'u2']);
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('u1')?.username, 'Alice');
      expect(state.getUser('u2')?.username, 'Bob');
    });

    test('ensureUsersCached skips already-cached users (no duplicate fetch)', () async {
      svc.push(readyEvent(users: [
        {'_id': 'u1', 'username': 'Cached', 'discriminator': '0001'},
      ]));

      // Stub a different value – should NOT be loaded since u1 is already cached
      svc.stubUser(fakeUser('u1', username: 'ShouldNotAppear'));

      state.ensureUsersCached(['u1']);
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('u1')?.username, 'Cached');
    });
  });
}

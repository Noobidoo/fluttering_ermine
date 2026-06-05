// Tests for WebSocket event handling in MessagingState.
//
// Voice channel membership events (VoiceChannelJoin/Leave/Move) are tested in
// voice_state_test.dart since VoiceState now owns that data.
// Covers:
//   - UserUpdate refreshing the user cache (avatar / display name)
//   - UserUpdate for unknown users, ensureUsersCached

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/providers/messaging_state.dart';
import 'package:fluttering_ermine/providers/server_state.dart';

import '../helpers/messaging_test_helpers.dart';

// -- Helpers ------------------------------------------------------------------

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

// -- Tests --------------------------------------------------------------------

void main() {
  // PaintingBinding is needed for imageCache.evict inside MessagingState.
  TestWidgetsFlutterBinding.ensureInitialized();

  // -- MessagingState: UserUpdate ------------------------------------------

  group('MessagingState – UserUpdate event', () {
    late FakeRevoltService svc;
    late ServerState serverState;
    late MessagingState state;

    setUp(() {
      svc = FakeRevoltService();
      serverState = ServerState(svc);
      serverState.subscribeToEvents();
      state = MessagingState(svc, serverState);
      state.subscribeToEvents();
    });

    tearDown(() => svc.close());

    test('UserUpdate with empty data preserves cached bio', () async {
      // Prime cache via Ready (user without bio, as API delivers)
      svc.push(readyEvent(users: [
        {'_id': 'user1', 'username': 'user1', 'discriminator': '0001'},
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(state.getUser('user1')?.profileContent, isNull);

      // Simulate AuthState.cacheUser after saving a bio
      state.cacheUser(RevoltUser(
        id: 'user1', username: 'user1', discriminator: '0001',
        profileContent: 'My bio',
      ));
      expect(state.getUser('user1')?.profileContent, 'My bio');

      // Inject UserUpdate with empty data (as server sends for bio changes)
      svc.push({'type': 'UserUpdate', 'id': 'user1', 'data': {}, 'clear': []});
      await Future<void>.delayed(Duration.zero);

      // Bio should be preserved (not overwritten by fetchUser)
      expect(state.getUser('user1')?.profileContent, 'My bio');
    });

    test('UserUpdate merges non-empty data into cached user', () async {
      // Prime cache via Ready
      svc.push(readyEvent(users: [
        {'_id': 'user1', 'username': 'OldName', 'discriminator': '0001'},
      ]));
      expect(state.getUser('user1')?.username, 'OldName');

      // Inject UserUpdate with data
      svc.push({'type': 'UserUpdate', 'id': 'user1', 'data': {'display_name': 'NewDisplay'}, 'clear': []});

      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('user1')?.displayName, 'NewDisplay');
      expect(state.getUser('user1')?.username, 'OldName'); // unchanged
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

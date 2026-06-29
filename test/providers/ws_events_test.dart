import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/features/messaging/providers/messaging_providers.dart';
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';
import 'package:fluttering_ermine/models/models.dart';

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

  // -- MessagingNotifier: UserUpdate ------------------------------------------

  group('MessagingNotifier – UserUpdate event', () {
    late FakeRevoltService svc;
    late ProviderContainer container;

    setUp(() async {
      svc = FakeRevoltService();
      container = ProviderContainer(overrides: [
        revoltServiceProvider.overrideWithValue(svc),
      ]);
      container.read(serverStateProvider.notifier);
      container.read(messagingStateProvider);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() {
      svc.close();
      container.dispose();
    });

    MessagingNotifier notifier() => container.read(messagingStateProvider.notifier);
    MessagingStateData state() => container.read(messagingStateProvider);

    test('UserUpdate with empty data preserves cached bio', () async {
      // Prime cache via Ready (user without bio, as API delivers)
      svc.push(readyEvent(users: [
        {'_id': 'user1', 'username': 'user1', 'discriminator': '0001'},
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(state().userCache['user1']?.profileContent, isNull);

      // Simulate LoginNotifier.cacheUser after saving a bio
      notifier().cacheUser(RevoltUser(
        id: 'user1', username: 'user1', discriminator: '0001',
        profileContent: 'My bio',
      ));
      expect(state().userCache['user1']?.profileContent, 'My bio');

      // Inject UserUpdate with empty data (as server sends for bio changes)
      svc.push({'type': 'UserUpdate', 'id': 'user1', 'data': {}, 'clear': []});
      await Future<void>.delayed(Duration.zero);

      // Bio should be preserved (not overwritten by fetchUser)
      expect(state().userCache['user1']?.profileContent, 'My bio');
    });

    test('UserUpdate merges non-empty data into cached user', () async {
      // Prime cache via Ready
      svc.push(readyEvent(users: [
        {'_id': 'user1', 'username': 'OldName', 'discriminator': '0001'},
      ]));
      expect(state().userCache['user1']?.username, 'OldName');

      // Inject UserUpdate with data
      svc.push({'type': 'UserUpdate', 'id': 'user1', 'data': {'display_name': 'NewDisplay'}, 'clear': []});

      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['user1']?.displayName, 'NewDisplay');
      expect(state().userCache['user1']?.username, 'OldName'); // unchanged
    });

    test('UserUpdate for unknown user still populates cache', () async {
      svc.stubUser(fakeUser('user99', username: 'Stranger'));

      svc.push({'type': 'UserUpdate', 'id': 'user99', 'data': {}, 'clear': []});
      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['user99']?.username, 'Stranger');
    });

    test('ensureUsersCached fetches uncached users', () async {
      svc.stubUser(fakeUser('u1', username: 'Alice'));
      svc.stubUser(fakeUser('u2', username: 'Bob'));

      notifier().ensureUsersCached(['u1', 'u2']);
      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['u1']?.username, 'Alice');
      expect(state().userCache['u2']?.username, 'Bob');
    });

    test('ensureUsersCached skips already-cached users (no duplicate fetch)', () async {
      svc.push(readyEvent(users: [
        {'_id': 'u1', 'username': 'Cached', 'discriminator': '0001'},
      ]));

      // Stub a different value – should NOT be loaded since u1 is already cached
      svc.stubUser(fakeUser('u1', username: 'ShouldNotAppear'));

      notifier().ensureUsersCached(['u1']);
      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['u1']?.username, 'Cached');
    });
  });
}

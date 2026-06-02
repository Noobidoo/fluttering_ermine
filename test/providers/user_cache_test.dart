// Tests for user caching used by mention autocomplete.
//
// The mention filter logic lives in `_MessageInputState._updateMentionState`
// (chat_panel.dart).  This file validates the data source — `cachedUsers`
// and `getUser` — that the autocomplete popup consumes.

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/providers/messaging_state.dart';
import 'package:fluttering_ermine/providers/server_state.dart';

import '../helpers/messaging_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('Mention autocomplete — user cache', () {
    test('Ready event populates user cache', () {
      svc.push({
        'type': 'Ready',
        'servers': [],
        'channels': [],
        'users': [
          {
            '_id': 'u1',
            'username': 'alice',
            'discriminator': '0001',
          },
          {
            '_id': 'u2',
            'username': 'bob',
            'discriminator': '0002',
          },
        ],
      });

      expect(state.cachedUsers, hasLength(2));
      expect(state.getUser('u1')?.username, 'alice');
      expect(state.getUser('u2')?.username, 'bob');
    });

    test('getUser returns null for unknown ID', () {
      expect(state.getUser('nonexistent'), isNull);
    });

    test('getUser returns cached user from Message event', () async {
      svc.push(msgEvent(
        id: 'msg1',
        channel: 'chan1',
        author: 'u1',
        content: 'Hi',
      ));

      // _ensureUserCached uses .then() — let microtask resolve
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('u1'), isNotNull);
      expect(state.getUser('u1')?.username, 'stub');
    });

    test('cachedUsers includes users from Ready and Message events', () async {
      svc.push({
        'type': 'Ready',
        'servers': [],
        'channels': [],
        'users': [
          {
            '_id': 'u1',
            'username': 'alice',
            'discriminator': '0001',
          },
        ],
      });

      svc.push(msgEvent(
        id: 'msg1',
        channel: 'chan1',
        author: 'u2',
        content: 'Hello',
      ));

      // _ensureUserCached uses .then() — let microtask resolve
      await Future<void>.delayed(Duration.zero);

      expect(state.getUser('u1')?.username, 'alice');
      expect(state.getUser('u2'), isNotNull);
    });
  });
}

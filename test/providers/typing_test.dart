// Tests for TypingStart / TypingStop WS events and sendTypingIndicator debounce.

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

  // ── TypingStart / TypingStop WS events ────────────────────────────────────

  group('TypingStart / TypingStop WS events', () {
    const currentUser = 'current-user';
    const otherUser = 'other-user';
    const chan = 'chan1';

    setUp(() => state.setCurrentUserId(currentUser));

    test('TypingStart adds user to channel typing set', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': otherUser});

      expect(state.typingUsersFor(chan), contains(otherUser));
    });

    test('TypingStart ignores current user ID', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': currentUser});

      expect(state.typingUsersFor(chan), isEmpty);
    });

    test('multiple users can type simultaneously', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': 'u1'});
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': 'u2'});

      expect(state.typingUsersFor(chan), containsAll(['u1', 'u2']));
    });

    test('TypingStop removes user from typing set', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': otherUser});
      svc.push({'type': 'TypingStop', 'channel': chan, 'id': otherUser});

      expect(state.typingUsersFor(chan), isEmpty);
    });

    test('TypingStop for last user empties the channel entry', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': 'u1'});
      svc.push({'type': 'TypingStop', 'channel': chan, 'id': 'u1'});

      expect(state.typingUsersFor(chan), isEmpty);
    });

    test('TypingStop for one of two users leaves the other', () {
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': 'u1'});
      svc.push({'type': 'TypingStart', 'channel': chan, 'id': 'u2'});
      svc.push({'type': 'TypingStop', 'channel': chan, 'id': 'u1'});

      expect(state.typingUsersFor(chan), isNot(contains('u1')));
      expect(state.typingUsersFor(chan), contains('u2'));
    });

    test('TypingStop is no-op for unknown channel (no throw)', () {
      svc.push({'type': 'TypingStop', 'channel': 'ghost', 'id': 'u1'});
    });
  });

  // ── sendTypingIndicator debounce ──────────────────────────────────────────

  group('sendTypingIndicator debounce', () {
    setUp(() => serverState.selectChannel(textChan('chan1')));

    test('first call sends BeginTyping for selected channel', () {
      state.sendTypingIndicator();

      expect(svc.typingCalls, hasLength(1));
      expect(svc.typingCalls.first, 'chan1');
    });

    test('second immediate call within 2.5 s is debounced', () {
      state.sendTypingIndicator();
      state.sendTypingIndicator();

      expect(svc.typingCalls, hasLength(1));
    });

    test('no channel selected: nothing sent', () {
      final emptyServerState = ServerState(svc);
      final freshState = MessagingState(svc, emptyServerState);
      freshState.subscribeToEvents();

      freshState.sendTypingIndicator();

      expect(svc.typingCalls, isEmpty);
      freshState.dispose();
    });
  });
}

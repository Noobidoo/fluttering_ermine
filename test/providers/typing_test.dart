// Tests for ChannelStartTyping / ChannelStopTyping WS events and sendTypingIndicator debounce.

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

  // -- ChannelStartTyping / ChannelStopTyping WS events ---------------------

  group('ChannelStartTyping / ChannelStopTyping WS events', () {
    const currentUser = 'current-user';
    const otherUser = 'other-user';
    const chan = 'chan1';

    setUp(() => state.setCurrentUserId(currentUser));

    test('ChannelStartTyping adds user to channel typing set', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': otherUser});

      expect(state.typingUsersFor(chan), contains(otherUser));
    });

    test('ChannelStartTyping ignores current user ID', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': currentUser});

      expect(state.typingUsersFor(chan), isEmpty);
    });

    test('multiple users can type simultaneously', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u2'});

      expect(state.typingUsersFor(chan), containsAll(['u1', 'u2']));
    });

    test('ChannelStopTyping removes user from typing set', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': otherUser});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': otherUser});

      expect(state.typingUsersFor(chan), isNot(contains(otherUser)));
    });

    test('ChannelStopTyping for last user empties the channel entry', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': 'u1'});

      expect(state.typingUsersFor(chan), isEmpty);
    });

    test('ChannelStopTyping for one of two users leaves the other', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u2'});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': 'u1'});

      expect(state.typingUsersFor(chan), contains('u2'));
      expect(state.typingUsersFor(chan), isNot(contains('u1')));
    });

    test('ChannelStopTyping is no-op for unknown channel (no throw)', () {
      svc.push({'type': 'ChannelStopTyping', 'id': 'ghost', 'user': 'u1'});

      expect(state.typingUsersFor('ghost'), isEmpty);
    });
  });

  // -- sendTypingIndicator debounce ------------------------------------------

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

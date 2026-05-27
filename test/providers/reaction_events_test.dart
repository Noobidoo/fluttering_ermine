// Tests for MessageReact / MessageUnreact / MessageRemoveReaction WS events.

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

  // ── MessageReact ──────────────────────────────────────────────────────────

  group('MessageReact WS event', () {
    const emoji = '\u{1F44D}';

    setUp(() => svc.push(msgEvent(id: 'msg1', channel: 'chan1')));

    test('adds userId to reaction for a new emoji', () {
      svc.push({
        'type': 'MessageReact',
        'channel_id': 'chan1',
        'id': 'msg1',
        'user_id': 'u1',
        'emoji_id': emoji,
      });

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions[emoji],
          contains('u1'));
    });

    test('adds second user to existing emoji key', () {
      svc.push({
        'type': 'MessageReact',
        'channel_id': 'chan1',
        'id': 'msg1',
        'user_id': 'u1',
        'emoji_id': emoji,
      });
      svc.push({
        'type': 'MessageReact',
        'channel_id': 'chan1',
        'id': 'msg1',
        'user_id': 'u2',
        'emoji_id': emoji,
      });

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions[emoji],
          containsAll(['u1', 'u2']));
    });

    test('duplicate react from same user is idempotent', () {
      for (var i = 0; i < 3; i++) {
        svc.push({
          'type': 'MessageReact',
          'channel_id': 'chan1',
          'id': 'msg1',
          'user_id': 'u1',
          'emoji_id': emoji,
        });
      }

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions[emoji]?.length, 1);
    });

    test('no-op for unknown message ID (no throw)', () {
      svc.push({
        'type': 'MessageReact',
        'channel_id': 'chan1',
        'id': 'ghost',
        'user_id': 'u1',
        'emoji_id': emoji,
      });
    });
  });

  // ── MessageUnreact ────────────────────────────────────────────────────────

  group('MessageUnreact WS event', () {
    const emoji = '\u{1F44D}';

    setUp(() {
      svc.push(msgEvent(
          id: 'msg1',
          channel: 'chan1',
          reactions: {emoji: ['u1', 'u2']}));
    });

    test('removes userId from reaction', () {
      svc.push({
        'type': 'MessageUnreact',
        'channel_id': 'chan1',
        'id': 'msg1',
        'user_id': 'u1',
        'emoji_id': emoji,
      });

      final reactors =
          state.getMessageById('chan1', 'msg1')?.reactions[emoji];
      expect(reactors, isNot(contains('u1')));
      expect(reactors, contains('u2'));
    });

    test('removes emoji key entirely when last user unreacts', () {
      for (final uid in ['u1', 'u2']) {
        svc.push({
          'type': 'MessageUnreact',
          'channel_id': 'chan1',
          'id': 'msg1',
          'user_id': uid,
          'emoji_id': emoji,
        });
      }

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions.containsKey(emoji),
          isFalse);
    });

    test('no-op for unknown emoji key (no throw, original unchanged)', () {
      svc.push({
        'type': 'MessageUnreact',
        'channel_id': 'chan1',
        'id': 'msg1',
        'user_id': 'u1',
        'emoji_id': '\u2764',
      });

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions[emoji],
          hasLength(2));
    });
  });

  // ── MessageRemoveReaction ─────────────────────────────────────────────────

  group('MessageRemoveReaction WS event', () {
    const emoji = '\u{1F44D}';

    setUp(() {
      svc.push(msgEvent(
          id: 'msg1',
          channel: 'chan1',
          reactions: {
            emoji: ['u1', 'u2', 'u3'],
            '\u2764': ['u4'],
          }));
    });

    test('removes entire emoji entry regardless of reactor count', () {
      svc.push({
        'type': 'MessageRemoveReaction',
        'channel_id': 'chan1',
        'id': 'msg1',
        'emoji_id': emoji,
      });

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions.containsKey(emoji),
          isFalse);
    });

    test('leaves other emoji entries untouched', () {
      svc.push({
        'type': 'MessageRemoveReaction',
        'channel_id': 'chan1',
        'id': 'msg1',
        'emoji_id': emoji,
      });

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions.containsKey('\u2764'),
          isTrue);
    });
  });
}

// Tests for Message / MessageUpdate / MessageDelete WS events.

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

  // Push WS messages THEN select channel — _onServerStateChanged sees
  // _messages already has the key → skips _loadMessages → currentMessages works.
  void selectAfterPush(String channelId) =>
      serverState.selectChannel(textChan(channelId));

  // ── Message ───────────────────────────────────────────────────────────────

  group('Message WS event', () {
    test('new message is prepended to channel list', () {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1', content: 'Hi'));
      selectAfterPush('chan1');

      expect(state.currentMessages, hasLength(1));
      expect(state.currentMessages.first.id, 'msg1');
      expect(state.currentMessages.first.content, 'Hi');
    });

    test('message with replies field is stored', () {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1', replies: ['orig']));

      expect(state.getMessageById('chan1', 'msg1')?.replies, contains('orig'));
    });

    test('message with reactions field is stored', () {
      svc.push(msgEvent(
          id: 'msg1',
          channel: 'chan1',
          reactions: {'\u{1F44D}': ['u1']}));

      expect(
          state.getMessageById('chan1', 'msg1')?.reactions['\u{1F44D}'],
          contains('u1'));
    });

    test('duplicate message ID is ignored', () {
      svc.push(msgEvent(id: 'msg1', content: 'First'));
      svc.push(msgEvent(id: 'msg1', content: 'Duplicate'));
      selectAfterPush('chan1');

      expect(state.currentMessages, hasLength(1));
      expect(state.currentMessages.first.content, 'First');
    });

    test('messages from different channels are stored separately', () {
      svc.push(msgEvent(id: 'a', channel: 'chan1'));
      svc.push(msgEvent(id: 'b', channel: 'chan2'));

      expect(state.getMessageById('chan1', 'a'), isNotNull);
      expect(state.getMessageById('chan2', 'b'), isNotNull);
      expect(state.getMessageById('chan1', 'b'), isNull);
      expect(state.getMessageById('chan2', 'a'), isNull);
    });
  });

  // ── MessageUpdate ─────────────────────────────────────────────────────────

  group('MessageUpdate WS event', () {
    setUp(() => svc.push(msgEvent(id: 'msg1', channel: 'chan1')));

    test('updates content in-place', () {
      svc.push({
        'type': 'MessageUpdate',
        'id': 'msg1',
        'channel': 'chan1',
        'data': {
          'content': 'Edited',
          'edited': '2024-06-01T00:00:00.000Z',
        },
      });

      final msg = state.getMessageById('chan1', 'msg1');
      expect(msg?.content, 'Edited');
      expect(msg?.edited, '2024-06-01T00:00:00.000Z');
    });

    test('no-op for unknown channel', () {
      svc.push({
        'type': 'MessageUpdate',
        'id': 'msg1',
        'channel': 'unknown-chan',
        'data': {'content': 'Should not appear'},
      });

      expect(state.getMessageById('chan1', 'msg1')?.content, 'Hello');
    });

    test('no-op for unknown message ID in known channel', () {
      svc.push({
        'type': 'MessageUpdate',
        'id': 'unknown-msg',
        'channel': 'chan1',
        'data': {'content': 'Should not appear'},
      });

      expect(state.getMessageById('chan1', 'msg1')?.content, 'Hello');
    });
  });

  // ── MessageDelete ─────────────────────────────────────────────────────────

  group('MessageDelete WS event', () {
    setUp(() {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1'));
      svc.push(msgEvent(id: 'msg2', channel: 'chan1'));
    });

    test('removes target message from list', () {
      svc.push({'type': 'MessageDelete', 'id': 'msg1', 'channel': 'chan1'});

      expect(state.getMessageById('chan1', 'msg1'), isNull);
      expect(state.getMessageById('chan1', 'msg2'), isNotNull);
    });

    test('no-op for unknown message ID', () {
      svc.push({'type': 'MessageDelete', 'id': 'ghost', 'channel': 'chan1'});

      expect(state.getMessageById('chan1', 'msg1'), isNotNull);
      expect(state.getMessageById('chan1', 'msg2'), isNotNull);
    });

    test('no-op for unknown channel', () {
      svc.push(
          {'type': 'MessageDelete', 'id': 'msg1', 'channel': 'ghost-chan'});

      expect(state.getMessageById('chan1', 'msg1'), isNotNull);
    });
  });
}

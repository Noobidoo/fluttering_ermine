// Tests for MessagingState service delegation methods.

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

  // ── Service delegation ────────────────────────────────────────────────────

  group('Service delegation', () {
    test('editMessage delegates to service with correct args', () async {
      await state.editMessage('chan1', 'msg1', 'new content');

      expect(svc.editCalls, hasLength(1));
      expect(svc.editCalls.first.channelId, 'chan1');
      expect(svc.editCalls.first.messageId, 'msg1');
      expect(svc.editCalls.first.content, 'new content');
    });

    test('deleteMessage delegates to service with correct args', () async {
      await state.deleteMessage('chan1', 'msg1');

      expect(svc.deleteCalls, hasLength(1));
      expect(svc.deleteCalls.first.channelId, 'chan1');
      expect(svc.deleteCalls.first.messageId, 'msg1');
    });

    test('addReaction delegates to service with correct args', () async {
      await state.addReaction('chan1', 'msg1', '\u{1F44D}');

      expect(svc.addReactionCalls, hasLength(1));
      expect(svc.addReactionCalls.first.channelId, 'chan1');
      expect(svc.addReactionCalls.first.messageId, 'msg1');
      expect(svc.addReactionCalls.first.emoji, '\u{1F44D}');
    });

    test('removeReaction delegates to service with correct args', () async {
      await state.removeReaction('chan1', 'msg1', '\u{1F44D}');

      expect(svc.removeReactionCalls, hasLength(1));
      expect(svc.removeReactionCalls.first.channelId, 'chan1');
      expect(svc.removeReactionCalls.first.messageId, 'msg1');
      expect(svc.removeReactionCalls.first.emoji, '\u{1F44D}');
    });

    test('sendMessage passes replyToId and clears reply target', () async {
      serverState.selectChannel(textChan('chan1'));
      svc.push(msgEvent(id: 'orig', channel: 'chan1'));
      state.setReplyTarget(state.getMessageById('chan1', 'orig')!);

      await state.sendMessage('reply text');

      expect(svc.sendMessageCalls, hasLength(1));
      expect(svc.sendMessageCalls.first.replyToId, 'orig');
      expect(svc.sendMessageCalls.first.content, 'reply text');
      expect(state.replyTarget, isNull);
    });
  });
}

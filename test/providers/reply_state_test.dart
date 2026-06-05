// Tests for reply compose state (setReplyTarget / clearReplyTarget).

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
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

  // -- Reply compose state ---------------------------------------------------

  group('Reply compose state', () {
    late RevoltMessage target;

    setUp(() {
      svc.push(msgEvent(id: 'orig', channel: 'chan1', content: 'Original'));
      target = state.getMessageById('chan1', 'orig')!;
    });

    test('setReplyTarget stores the message', () {
      state.setReplyTarget(target);
      expect(state.replyTarget?.id, 'orig');
    });

    test('setReplyTarget notifies listeners', () {
      var notified = false;
      state.addListener(() => notified = true);
      state.setReplyTarget(target);
      expect(notified, isTrue);
    });

    test('clearReplyTarget clears the reply target', () {
      state.setReplyTarget(target);
      state.clearReplyTarget();
      expect(state.replyTarget, isNull);
    });

    test('clearReplyTarget notifies listeners', () {
      state.setReplyTarget(target);
      var notified = false;
      state.addListener(() => notified = true);
      state.clearReplyTarget();
      expect(notified, isTrue);
    });

    test('clearReplyTarget is no-op when already null (no notification)', () {
      var notifyCount = 0;
      state.addListener(() => notifyCount++);
      state.clearReplyTarget();
      expect(notifyCount, 0);
    });
  });
}

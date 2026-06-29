import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/features/messaging/providers/messaging_providers.dart';
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';

import '../helpers/messaging_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // -- Service delegation ----------------------------------------------------

  group('Service delegation', () {
    test('editMessage delegates to service with correct args', () async {
      await notifier().editMessage('chan1', 'msg1', 'new content');

      expect(svc.editCalls, hasLength(1));
      expect(svc.editCalls.first.channelId, 'chan1');
      expect(svc.editCalls.first.messageId, 'msg1');
      expect(svc.editCalls.first.content, 'new content');
    });

    test('deleteMessage delegates to service with correct args', () async {
      await notifier().deleteMessage('chan1', 'msg1');

      expect(svc.deleteCalls, hasLength(1));
      expect(svc.deleteCalls.first.channelId, 'chan1');
      expect(svc.deleteCalls.first.messageId, 'msg1');
    });

    test('addReaction delegates to service with correct args', () async {
      await notifier().addReaction('chan1', 'msg1', '\u{1F44D}');

      expect(svc.addReactionCalls, hasLength(1));
      expect(svc.addReactionCalls.first.channelId, 'chan1');
      expect(svc.addReactionCalls.first.messageId, 'msg1');
      expect(svc.addReactionCalls.first.emoji, '\u{1F44D}');
    });

    test('removeReaction delegates to service with correct args', () async {
      await notifier().removeReaction('chan1', 'msg1', '\u{1F44D}');

      expect(svc.removeReactionCalls, hasLength(1));
      expect(svc.removeReactionCalls.first.channelId, 'chan1');
      expect(svc.removeReactionCalls.first.messageId, 'msg1');
      expect(svc.removeReactionCalls.first.emoji, '\u{1F44D}');
    });

    test('sendMessage passes replyToId and clears reply target', () async {
      container.read(serverStateProvider.notifier).selectChannel(textChan('chan1'));
      svc.push(msgEvent(id: 'orig', channel: 'chan1'));
      notifier().setReplyTarget(state().messages['chan1']!.first);

      await notifier().sendMessage('reply text');

      expect(svc.sendMessageCalls, hasLength(1));
      expect(svc.sendMessageCalls.first.replyToId, 'orig');
      expect(svc.sendMessageCalls.first.content, 'reply text');
      expect(state().replyTarget, isNull);
    });
  });
}

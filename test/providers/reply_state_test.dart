import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/features/messaging/providers/messaging_providers.dart';
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';
import 'package:fluttering_ermine/models/models.dart';

import '../helpers/messaging_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRevoltService svc;
  late ProviderContainer container;

  setUp(() async {
    svc = FakeRevoltService();
    container = ProviderContainer(
      overrides: [revoltServiceProvider.overrideWithValue(svc)],
    );
    container.read(serverStateProvider.notifier);
    container.read(messagingStateProvider);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    svc.close();
    container.dispose();
  });

  MessagingNotifier notifier() =>
      container.read(messagingStateProvider.notifier);
  MessagingStateData state() => container.read(messagingStateProvider);

  // -- Reply compose state ---------------------------------------------------

  group('Reply compose state', () {
    late RevoltMessage target;

    setUp(() {
      svc.push(msgEvent(id: 'orig', channel: 'chan1', content: 'Original'));
      target = state().messages['chan1']!.firstWhere((m) => m.id == 'orig');
    });

    test('setReplyTarget stores the message', () {
      notifier().setReplyTarget(target);
      expect(state().replyTarget?.id, 'orig');
    });

    test('clearReplyTarget clears the reply target', () {
      notifier().setReplyTarget(target);
      notifier().clearReplyTarget();
      expect(state().replyTarget, isNull);
    });

    test('clearReplyTarget is no-op when already null (no state change)', () {
      notifier().clearReplyTarget();
      expect(state().replyTarget, isNull);
    });
  });
}

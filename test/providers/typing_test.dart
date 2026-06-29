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
      currentUserIdProvider.overrideWithValue('current-user'),
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

  // -- ChannelStartTyping / ChannelStopTyping WS events ---------------------

  group('ChannelStartTyping / ChannelStopTyping WS events', () {
    const currentUser = 'current-user';
    const otherUser = 'other-user';
    const chan = 'chan1';

    test('ChannelStartTyping adds user to channel typing set', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': otherUser});

      expect(state().typingUsers[chan], contains(otherUser));
    });

    test('ChannelStartTyping ignores current user ID', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': currentUser});

      expect(state().typingUsers[chan] ?? <String>{}, isEmpty);
    });

    test('multiple users can type simultaneously', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u2'});

      expect(state().typingUsers[chan], containsAll(['u1', 'u2']));
    });

    test('ChannelStopTyping removes user from typing set', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': otherUser});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': otherUser});

      expect(state().typingUsers[chan] ?? <String>{}, isNot(contains(otherUser)));
    });

    test('ChannelStopTyping for last user empties the channel entry', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': 'u1'});

      expect(state().typingUsers[chan] ?? <String>{}, isEmpty);
    });

    test('ChannelStopTyping for one of two users leaves the other', () {
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u1'});
      svc.push({'type': 'ChannelStartTyping', 'id': chan, 'user': 'u2'});
      svc.push({'type': 'ChannelStopTyping', 'id': chan, 'user': 'u1'});

      expect(state().typingUsers[chan], contains('u2'));
      expect(state().typingUsers[chan], isNot(contains('u1')));
    });

    test('ChannelStopTyping is no-op for unknown channel (no throw)', () {
      svc.push({'type': 'ChannelStopTyping', 'id': 'ghost', 'user': 'u1'});

      expect(state().typingUsers['ghost'] ?? <String>{}, isEmpty);
    });
  });

  // -- sendTypingIndicator debounce ------------------------------------------

  group('sendTypingIndicator debounce', () {
    setUp(() => container.read(serverStateProvider.notifier).selectChannel(textChan('chan1')));

    test('first call sends BeginTyping for selected channel', () {
      notifier().sendTypingIndicator();

      expect(svc.typingCalls, hasLength(1));
      expect(svc.typingCalls.first, 'chan1');
    });

    test('second immediate call within 2.5 s is debounced', () {
      notifier().sendTypingIndicator();
      notifier().sendTypingIndicator();

      expect(svc.typingCalls, hasLength(1));
    });

    test('no channel selected: nothing sent', () {
      // Create a fresh container without selecting a channel
      final freshContainer = ProviderContainer(overrides: [
        revoltServiceProvider.overrideWithValue(svc),
      ]);
      freshContainer.read(serverStateProvider.notifier);
      freshContainer.read(messagingStateProvider);
      final freshNotifier = freshContainer.read(messagingStateProvider.notifier);

      freshNotifier.sendTypingIndicator();

      expect(svc.typingCalls, isEmpty);
      freshContainer.dispose();
    });
  });
}

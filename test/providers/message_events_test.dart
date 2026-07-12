import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/features/messaging/providers/messaging_notifier.dart';
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';

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
    // Trigger both notifiers' build() to subscribe to service events
    container.read(serverStateProvider.notifier);
    container.read(messagingStateProvider);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    svc.close();
    container.dispose();
  });

  // Push WS messages THEN select channel - _onServerStateChanged sees
  // _messages already has the key → skips _loadMessages → currentMessages works.
  void selectAfterPush(String channelId) => container
      .read(serverStateProvider.notifier)
      .selectChannel(textChan(channelId));

  MessagingStateData state() => container.read(messagingStateProvider);

  // -- Message ---------------------------------------------------------------

  group('Message WS event', () {
    test('new message is prepended to channel list', () {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1', content: 'Hi'));
      selectAfterPush('chan1');

      expect(state().messages['chan1']?.length, 1);
      expect(state().messages['chan1']!.first.id, 'msg1');
      expect(state().messages['chan1']!.first.content, 'Hi');
    });

    test('message with replies field is stored', () {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1', replies: ['orig']));
      // GetMessageById requires messages to be in the map for that channel
      expect(
        state().messages['chan1']?.firstWhere((m) => m.id == 'msg1').replies,
        contains('orig'),
      );
    });

    test('message with reactions field is stored', () {
      svc.push(
        msgEvent(
          id: 'msg1',
          channel: 'chan1',
          reactions: {
            '\u{1F44D}': ['u1'],
          },
        ),
      );

      expect(
        state().messages['chan1']
            ?.firstWhere((m) => m.id == 'msg1')
            .reactions['\u{1F44D}'],
        contains('u1'),
      );
    });

    test('duplicate message ID is ignored', () {
      svc.push(msgEvent(id: 'msg1', content: 'First'));
      svc.push(msgEvent(id: 'msg1', content: 'Duplicate'));
      selectAfterPush('chan1');

      expect(state().messages['chan1']?.length, 1);
      expect(state().messages['chan1']!.first.content, 'First');
    });

    test('messages from different channels are stored separately', () {
      svc.push(msgEvent(id: 'a', channel: 'chan1'));
      svc.push(msgEvent(id: 'b', channel: 'chan2'));

      expect(state().messages['chan1']?.any((m) => m.id == 'a'), isTrue);
      expect(state().messages['chan2']?.any((m) => m.id == 'b'), isTrue);
      expect(state().messages['chan1']?.any((m) => m.id == 'b'), isFalse);
      expect(state().messages['chan2']?.any((m) => m.id == 'a'), isFalse);
    });
  });

  // -- MessageUpdate ---------------------------------------------------------

  group('MessageUpdate WS event', () {
    setUp(() => svc.push(msgEvent(id: 'msg1', channel: 'chan1')));

    test('updates content in-place', () {
      svc.push({
        'type': 'MessageUpdate',
        'id': 'msg1',
        'channel': 'chan1',
        'data': {'content': 'Edited', 'edited': '2024-06-01T00:00:00.000Z'},
      });

      final msg = state().messages['chan1']?.firstWhere((m) => m.id == 'msg1');
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

      expect(
        state().messages['chan1']?.firstWhere((m) => m.id == 'msg1').content,
        'Hello',
      );
    });

    test('no-op for unknown message ID in known channel', () {
      svc.push({
        'type': 'MessageUpdate',
        'id': 'unknown-msg',
        'channel': 'chan1',
        'data': {'content': 'Should not appear'},
      });

      expect(
        state().messages['chan1']?.firstWhere((m) => m.id == 'msg1').content,
        'Hello',
      );
    });
  });

  // -- MessageDelete ---------------------------------------------------------

  group('MessageDelete WS event', () {
    setUp(() {
      svc.push(msgEvent(id: 'msg1', channel: 'chan1'));
      svc.push(msgEvent(id: 'msg2', channel: 'chan1'));
    });

    test('removes target message from list', () {
      svc.push({'type': 'MessageDelete', 'id': 'msg1', 'channel': 'chan1'});

      expect(state().messages['chan1']?.any((m) => m.id == 'msg1'), isFalse);
      expect(state().messages['chan1']?.any((m) => m.id == 'msg2'), isTrue);
    });

    test('no-op for unknown message ID', () {
      svc.push({'type': 'MessageDelete', 'id': 'ghost', 'channel': 'chan1'});

      expect(state().messages['chan1']?.any((m) => m.id == 'msg1'), isTrue);
      expect(state().messages['chan1']?.any((m) => m.id == 'msg2'), isTrue);
    });

    test('no-op for unknown channel', () {
      svc.push({
        'type': 'MessageDelete',
        'id': 'msg1',
        'channel': 'ghost-chan',
      });

      expect(state().messages['chan1']?.any((m) => m.id == 'msg1'), isTrue);
    });
  });
}

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

  MessagingStateData state() => container.read(messagingStateProvider);

  group('Mention autocomplete - user cache', () {
    test('Ready event populates user cache', () {
      svc.push({
        'type': 'Ready',
        'servers': [],
        'channels': [],
        'users': [
          {'_id': 'u1', 'username': 'alice', 'discriminator': '0001'},
          {'_id': 'u2', 'username': 'bob', 'discriminator': '0002'},
        ],
      });

      expect(state().userCache, hasLength(2));
      expect(state().userCache['u1']?.username, 'alice');
      expect(state().userCache['u2']?.username, 'bob');
    });

    test('getUser returns null for unknown ID', () {
      expect(state().userCache['nonexistent'], isNull);
    });

    test('getUser returns cached user from Message event', () async {
      svc.push(
        msgEvent(id: 'msg1', channel: 'chan1', author: 'u1', content: 'Hi'),
      );

      // _ensureUserCached uses .then() - let microtask resolve
      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['u1'], isNotNull);
      expect(state().userCache['u1']?.username, 'stub');
    });

    test('cachedUsers includes users from Ready and Message events', () async {
      svc.push({
        'type': 'Ready',
        'servers': [],
        'channels': [],
        'users': [
          {'_id': 'u1', 'username': 'alice', 'discriminator': '0001'},
        ],
      });

      svc.push(
        msgEvent(id: 'msg1', channel: 'chan1', author: 'u2', content: 'Hello'),
      );

      // _ensureUserCached uses .then() - let microtask resolve
      await Future<void>.delayed(Duration.zero);

      expect(state().userCache['u1']?.username, 'alice');
      expect(state().userCache['u2'], isNotNull);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluttering_ermine/features/auth/providers/login_notifier.dart';
import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/models/models.dart';

import '../helpers/messaging_test_helpers.dart';
import '../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('LoginNotifier – profile updates', () {
    late FakeRevoltService svc;
    late MockVoiceEventService voiceEvent;
    late ProviderContainer container;

    setUp(() async {
      svc = FakeRevoltService();
      voiceEvent = MockVoiceEventService();
      container = ProviderContainer(overrides: [
        revoltServiceProvider.overrideWithValue(svc),
        voiceEventServiceProvider.overrideWithValue(voiceEvent),
      ]);
    });

    tearDown(() {
      svc.close();
      container.dispose();
    });

    Future<void> initWithUser(RevoltUser user) async {
      svc.stubCurrentUser(user);
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
        'revolt_session_token': 'test-token',
      });
      await container.read(loginStateProvider.future);
    }

    // -- updateDisplayName --------------------------------------------------

    test('updateDisplayName preserves bio and updates displayName locally', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        displayName: 'OldName',
        profileContent: 'My bio',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateDisplayName('NewDisplay');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.displayName, 'NewDisplay');
      expect(container.read(loginStateProvider).requireValue.currentUser?.displayName, 'NewDisplay');
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    // -- updateStatus --------------------------------------------------------

    test('updateStatus delegates presence and statusText to service and preserves bio', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        presence: UserPresence.online,
        profileContent: 'My bio',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateStatus(presence: 'Idle', statusText: 'busy');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.presence, 'Idle');
      expect(svc.updateProfileCalls.first.statusText, 'busy');
      expect(container.read(loginStateProvider).requireValue.currentUser?.presence, UserPresence.idle);
      expect(container.read(loginStateProvider).requireValue.currentUser?.statusText, 'busy');
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    test('updateStatus can omit statusText and preserve bio', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        presence: UserPresence.online,
        profileContent: 'My bio',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateStatus(presence: 'Focus');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.presence, 'Focus');
      expect(svc.updateProfileCalls.first.statusText, isNull);
      expect(container.read(loginStateProvider).requireValue.currentUser?.presence, UserPresence.focus);
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    // -- updateBio ----------------------------------------------------------

    test('updateBio delegates profileContent to service and caches bio locally', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateBio('My bio');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.profileContent, 'My bio');
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    // -- updateAvatar -------------------------------------------------------

    test('updateAvatar uploads file, patches avatar locally, preserves bio', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        profileContent: 'My bio',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await notifier.updateAvatar(bytes, 'avatar.png');

      expect(svc.uploadAvatarCalls, hasLength(1));
      expect(svc.uploadAvatarCalls.first.filename, 'avatar.png');
      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.avatar, 'stub-file-id');
      expect(container.read(loginStateProvider).requireValue.currentUser?.avatar?.id, 'stub-file-id');
      expect(container.read(loginStateProvider).requireValue.currentUser?.avatar?.tag, 'avatars');
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    // -- updateBanner -------------------------------------------------------

    test('updateBanner uploads file, patches background locally, preserves bio', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        profileContent: 'My bio',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      final bytes = Uint8List.fromList([4, 5, 6]);
      await notifier.updateBanner(bytes, 'banner.png');

      expect(svc.uploadBackgroundCalls, hasLength(1));
      expect(svc.uploadBackgroundCalls.first.filename, 'banner.png');
      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.background, 'stub-file-id');
      expect(container.read(loginStateProvider).requireValue.currentUser?.banner?.id, 'stub-file-id');
      expect(container.read(loginStateProvider).requireValue.currentUser?.banner?.tag, 'backgrounds');
      expect(container.read(loginStateProvider).requireValue.currentUser?.profileContent, 'My bio');
    });

    // -- updateServerProfile ------------------------------------------------

    test('updateServerProfile delegates nickname to service', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateServerProfile('srv1', nickname: 'ServerNick');

      expect(svc.updateServerMemberCalls, hasLength(1));
      expect(svc.updateServerMemberCalls.first.serverId, 'srv1');
      expect(svc.updateServerMemberCalls.first.userId, 'self');
      expect(svc.updateServerMemberCalls.first.nickname, 'ServerNick');
      expect(svc.updateServerMemberCalls.first.avatar, isNull);
    });

    test('updateServerProfile delegates avatar to service', () async {
      await initWithUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      final notifier = container.read(loginStateProvider.notifier);
      await notifier.updateServerProfile('srv1', avatar: 'file-id');

      expect(svc.updateServerMemberCalls, hasLength(1));
      expect(svc.updateServerMemberCalls.first.serverId, 'srv1');
      expect(svc.updateServerMemberCalls.first.userId, 'self');
      expect(svc.updateServerMemberCalls.first.avatar, 'file-id');
      expect(svc.updateServerMemberCalls.first.nickname, isNull);
    });
  });
}

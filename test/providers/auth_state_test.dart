import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/providers/auth_state.dart';
import 'package:fluttering_ermine/providers/messaging_state.dart';
import 'package:fluttering_ermine/providers/server_state.dart';
import 'package:fluttering_ermine/providers/voice_state.dart';
import 'package:fluttering_ermine/services/voice_event_service.dart';

import '../helpers/messaging_test_helpers.dart';
import '../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthState – profile updates', () {
    late FakeRevoltService svc;
    late MockVoiceEventService voiceEvent;
    late ServerState serverState;
    late MessagingState messagingState;
    late VoiceState voiceState;
    late AuthState authState;

    setUp(() {
      svc = FakeRevoltService();
      voiceEvent = MockVoiceEventService();
      serverState = ServerState(svc);
      messagingState = MessagingState(svc, serverState);
      voiceState = VoiceState(svc, voiceEvent);
      authState = AuthState(
        svc,
        serverState,
        messagingState,
        voiceState,
        voiceEvent,
      );
    });

    tearDown(() => svc.close());

    // -- updateDisplayName --------------------------------------------------

    test('updateDisplayName delegates to service and uses response directly', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        displayName: 'NewDisplay',
      ));

      await authState.updateDisplayName('NewDisplay');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.displayName, 'NewDisplay');
      expect(authState.currentUser?.displayName, 'NewDisplay');
    });

    // -- updateStatus --------------------------------------------------------

    test('updateStatus delegates presence and statusText to service', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        presence: UserPresence.idle,
        statusText: 'busy',
      ));

      await authState.updateStatus(presence: 'Idle', statusText: 'busy');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.presence, 'Idle');
      expect(svc.updateProfileCalls.first.statusText, 'busy');
      expect(authState.currentUser?.presence, UserPresence.idle);
      expect(authState.currentUser?.statusText, 'busy');
    });

    test('updateStatus can omit statusText', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
        presence: UserPresence.focus,
      ));

      await authState.updateStatus(presence: 'Focus');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.presence, 'Focus');
      expect(svc.updateProfileCalls.first.statusText, isNull);
    });

    // -- updateBio ----------------------------------------------------------

    test('updateBio delegates profileContent to service and caches bio locally', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      // Simulate a pre-existing currentUser (same flow as init() after login)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('revolt_session_token', 'test-token');
      await authState.init();

      await authState.updateBio('My bio');

      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.profileContent, 'My bio');
      expect(authState.currentUser?.profileContent, 'My bio');
    });

    // -- updateAvatar -------------------------------------------------------

    test('updateAvatar uploads file then patches avatar', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      final bytes = Uint8List.fromList([1, 2, 3]);
      await authState.updateAvatar(bytes, 'avatar.png');

      // Should upload first
      expect(svc.uploadAvatarCalls, hasLength(1));
      expect(svc.uploadAvatarCalls.first.filename, 'avatar.png');
      // Then patch with returned file ID
      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.avatar, 'stub-file-id');
    });

    // -- updateBanner -------------------------------------------------------

    test('updateBanner uploads file then patches background', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      final bytes = Uint8List.fromList([4, 5, 6]);
      await authState.updateBanner(bytes, 'banner.png');

      expect(svc.uploadBackgroundCalls, hasLength(1));
      expect(svc.uploadBackgroundCalls.first.filename, 'banner.png');
      expect(svc.updateProfileCalls, hasLength(1));
      expect(svc.updateProfileCalls.first.background, 'stub-file-id');
    });

    // -- updateServerProfile ------------------------------------------------

    test('updateServerProfile delegates nickname to service', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      await authState.updateServerProfile('srv1', nickname: 'ServerNick');

      expect(svc.updateServerMemberCalls, hasLength(1));
      expect(svc.updateServerMemberCalls.first.serverId, 'srv1');
      expect(svc.updateServerMemberCalls.first.nickname, 'ServerNick');
      expect(svc.updateServerMemberCalls.first.avatar, isNull);
    });

    test('updateServerProfile delegates avatar to service', () async {
      svc.stubCurrentUser(RevoltUser(
        id: 'self',
        username: 'self',
        discriminator: '0000',
      ));

      await authState.updateServerProfile('srv1', avatar: 'file-id');

      expect(svc.updateServerMemberCalls, hasLength(1));
      expect(svc.updateServerMemberCalls.first.serverId, 'srv1');
      expect(svc.updateServerMemberCalls.first.avatar, 'file-id');
      expect(svc.updateServerMemberCalls.first.nickname, isNull);
    });
  });
}

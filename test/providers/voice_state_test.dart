// Unit tests for VoiceState: initial state, leaveVoiceChannel no-op, and
// WS-driven voice channel membership events.
//
// LiveKit disconnect paths (RoomDisconnectedEvent, ParticipantDisconnectedEvent)
// call _removeParticipant internally; those require a real LiveKit Room and
// are not unit-tested here.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluttering_ermine/providers/voice_state.dart';
import 'package:fluttering_ermine/services/voice_event_service.dart';

import '../helpers/messaging_test_helpers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _readyEvent({
  Map<String, List<String>> voiceMembers = const {},
  Set<String> publishingUsers = const {},
}) {
  final voiceStates = voiceMembers.entries.map((e) {
    final participants = e.value.map((uid) {
      if (publishingUsers.contains(uid)) {
        return <String, dynamic>{'id': uid, 'is_publishing': true};
      }
      return <String, dynamic>{'id': uid};
    }).toList();
    return <String, dynamic>{'id': e.key, 'participants': participants};
  }).toList();
  return {
    'type': 'Ready',
    'servers': <dynamic>[],
    'channels': <dynamic>[],
    'users': <dynamic>[],
    'voice_states': voiceStates,
  };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // VoiceState._loadSettings uses SharedPreferences — use in-memory store.
    SharedPreferences.setMockInitialValues({});
  });

  late FakeRevoltService svc;
  late VoiceEventService voiceEventService;
  late VoiceState voiceState;

  setUp(() {
    svc = FakeRevoltService();
    voiceEventService = VoiceEventService(svc);
    voiceState = VoiceState(svc, voiceEventService);
    voiceEventService.subscribeToWebSocketEvents();
    voiceState.subscribeToVoiceEvents();
  });

  tearDown(() => svc.close());

  // ── Initial state ─────────────────────────────────────────────────────────

  group('VoiceState – initial state', () {
    test('not in voice at startup', () {
      expect(voiceState.isInVoice, isFalse);
      expect(voiceState.isJoiningVoice, isFalse);
      expect(voiceState.activeVoiceChannel, isNull);
      expect(voiceState.isMuted, isFalse);
      expect(voiceState.voiceError, isNull);
    });

    test('default values for screen share and settings getters', () {
      expect(voiceState.isScreenSharing, isFalse);
      expect(voiceState.isScreenShareSubscribed('any'), isFalse);
      expect(voiceState.voicePublishingFor('any'), isNull);
      expect(voiceState.outputVolume, 1.0);
      expect(voiceState.noiseSuppression, isTrue);
      expect(voiceState.echoCancellation, isTrue);
      expect(voiceState.autoGainControl, isTrue);
    });

    test('voiceParticipants is empty when not connected to a room', () {
      expect(voiceState.voiceParticipants, isEmpty);
    });

    test('remoteVideoStreams is empty when not connected to a room', () {
      expect(voiceState.remoteVideoStreams, isEmpty);
    });
  });

  // ── VoiceParticipant model ──────────────────────────────────────────────────

  group('VoiceParticipant', () {
    test('displayName returns name when set', () {
      final p = VoiceParticipant(
        identity: 'u1',
        name: 'Alice',
        isLocal: false,
        isMuted: false,
      );
      expect(p.displayName, 'Alice');
    });

    test('displayName falls back to identity when name is empty', () {
      final p = VoiceParticipant(
        identity: 'u1',
        name: '',
        isLocal: false,
        isMuted: false,
      );
      expect(p.displayName, 'u1');
    });

    test('displayName falls back to identity when name is null', () {
      final p = VoiceParticipant(
        identity: 'u1',
        isLocal: false,
        isMuted: false,
      );
      expect(p.displayName, 'u1');
    });
  });

  // ── leaveVoiceChannel when not connected ──────────────────────────────────

  group('VoiceState – leaveVoiceChannel when not connected', () {
    test('completes without throwing when no room is active', () async {
      await voiceState.leaveVoiceChannel(); // no room active → all awaits are no-ops
    });

    test('isInVoice and activeVoiceChannel remain false/null after spurious leave', () async {
      await voiceState.leaveVoiceChannel();

      expect(voiceState.isInVoice, isFalse);
      expect(voiceState.activeVoiceChannel, isNull);
    });
  });

  // ── toggleMute without LiveKit Room ───────────────────────────────────────

  group('VoiceState – toggleMute without Room', () {
    test('toggleMute is no-op when no Room is connected', () async {
      await voiceState.toggleMute();
      expect(voiceState.isMuted, isFalse);
    });
  });

  // ── clear / dispose ───────────────────────────────────────────────────────

  group('VoiceState – lifecycle', () {
    test('clear resets state without throwing when no Room is active', () async {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      expect(voiceState.voiceParticipantsFor('chan1'), isNotEmpty);

      await voiceState.clear();

      expect(voiceState.isInVoice, isFalse);
      expect(voiceState.activeVoiceChannel, isNull);
      expect(voiceState.isMuted, isFalse);
      expect(voiceState.isJoiningVoice, isFalse);
      expect(voiceState.isScreenSharing, isFalse);
      expect(voiceState.voiceError, isNull);
      // channel membership is preserved by clear (only clears subs + LiveKit state)
    });

    test('dispose does not throw', () {
      expect(() => voiceState.dispose(), returnsNormally);
    });
  });

  // ── WS voice channel membership ───────────────────────────────────────────

  group('VoiceState – voice channel events', () {
    test('Ready seeds voice membership from voice_states', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      expect(voiceState.voiceParticipantsFor('chan1'), contains('user1'));
    });

    test('Ready seeds publishing state from voice_states', () {
      svc.push(_readyEvent(
        voiceMembers: {'chan1': ['u1', 'u2']},
        publishingUsers: {'u1'},
      ));
      expect(voiceState.voicePublishingFor('u1'), isTrue);
      expect(voiceState.voicePublishingFor('u2'), isNull);
    });

    test('VoiceChannelJoin adds user to channel participant list', () {
      svc.push(_readyEvent());
      svc.push({'type': 'VoiceChannelJoin', 'id': 'chan1', 'state': {'id': 'user1'}});
      expect(voiceState.voiceParticipantsFor('chan1'), contains('user1'));
    });

    test('VoiceChannelJoin is idempotent (no duplicates)', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelJoin', 'id': 'chan1', 'state': {'id': 'user1'}});
      expect(voiceState.voiceParticipantsFor('chan1').length, 1);
    });

    test('VoiceChannelLeave removes the user from the channel', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1', 'user2']}));
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});
      expect(voiceState.voiceParticipantsFor('chan1'), isNot(contains('user1')));
      expect(voiceState.voiceParticipantsFor('chan1'), contains('user2'));
    });

    test('VoiceChannelLeave on last user empties the channel entry', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});
      expect(voiceState.voiceParticipantsFor('chan1'), isEmpty);
    });

    test('VoiceChannelLeave does not affect other channels', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1'], 'chan2': ['user2']}));
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});
      expect(voiceState.voiceParticipantsFor('chan2'), contains('user2'));
    });

    test('VoiceChannelLeave for unknown user is a no-op', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user2']}));
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'user1'});
      expect(voiceState.voiceParticipantsFor('chan1'), contains('user2'));
    });

    test('ServerMemberUpdate with VoiceChannel clear removes user from all channels and clears publishing', () {
      svc.push(_readyEvent(
        voiceMembers: {'a': ['u1', 'u2'], 'b': ['u1']},
        publishingUsers: {'u1'},
      ));
      expect(voiceState.voicePublishingFor('u1'), isTrue);
      svc.push({
        'type': 'ServerMemberUpdate',
        'id': {'server': 's1', 'user': 'u1'},
        'clear': ['VoiceChannel'],
      });
      expect(voiceState.voiceParticipantsFor('a'), ['u2']);
      expect(voiceState.voiceParticipantsFor('b'), isEmpty);
      expect(voiceState.voicePublishingFor('u1'), isNull);
    });

    test('VoiceChannelMove removes from source and adds to destination', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelMove', 'user': 'user1', 'from': 'chan1', 'to': 'chan2'});
      expect(voiceState.voiceParticipantsFor('chan1'), isNot(contains('user1')));
      expect(voiceState.voiceParticipantsFor('chan2'), contains('user1'));
    });

    test('VoiceChannelMove with null from only adds to destination', () {
      svc.push(_readyEvent(voiceMembers: {'chan2': []}));
      svc.push({'type': 'VoiceChannelMove', 'user': 'user1', 'from': null, 'to': 'chan2'});
      expect(voiceState.voiceParticipantsFor('chan2'), contains('user1'));
    });

    test('VoiceChannelMove with null to only removes from source', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelMove', 'user': 'user1', 'from': 'chan1', 'to': null});
      expect(voiceState.voiceParticipantsFor('chan1'), isEmpty);
    });

    test('VoiceChannelLeave notifies listeners', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      var notified = false;
      voiceState.addListener(() => notified = true);
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'u1'});
      expect(notified, isTrue);
    });

    test('UserVoiceStateUpdate updates publishing state', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      svc.push({
        'type': 'UserVoiceStateUpdate',
        'id': 'u1',
        'data': {'is_publishing': true},
      });
      expect(voiceState.voicePublishingFor('u1'), isTrue);
    });

    test('UserVoiceStateUpdate sets false when user stops publishing', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      svc.push({
        'type': 'UserVoiceStateUpdate',
        'id': 'u1',
        'data': {'is_publishing': true},
      });
      svc.push({
        'type': 'UserVoiceStateUpdate',
        'id': 'u1',
        'data': {'is_publishing': false},
      });
      expect(voiceState.voicePublishingFor('u1'), isFalse);
    });

    test('UserVoiceStateUpdate notifies listeners', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      var notified = false;
      voiceState.addListener(() => notified = true);
      svc.push({
        'type': 'UserVoiceStateUpdate',
        'id': 'u1',
        'data': {'is_publishing': true},
      });
      expect(notified, isTrue);
    });
  });

  // ── Settings ───────────────────────────────────────────────────────────────

  group('VoiceState – settings', () {
    test('setOutputVolume updates volume and notifies', () async {
      var notified = false;
      voiceState.addListener(() => notified = true);
      await voiceState.setOutputVolume(0.5);
      expect(voiceState.outputVolume, 0.5);
      expect(notified, isTrue);
    });

    test('setOutputVolume clamps to 0.0 – 1.0', () async {
      await voiceState.setOutputVolume(-1.0);
      expect(voiceState.outputVolume, 0.0);
      await voiceState.setOutputVolume(2.0);
      expect(voiceState.outputVolume, 1.0);
    });

    test('setNoiseSuppression updates setting and notifies', () async {
      var notified = false;
      voiceState.addListener(() => notified = true);
      await voiceState.setNoiseSuppression(false);
      expect(voiceState.noiseSuppression, isFalse);
      expect(notified, isTrue);
    });

    test('setEchoCancellation updates setting and notifies', () async {
      var notified = false;
      voiceState.addListener(() => notified = true);
      await voiceState.setEchoCancellation(false);
      expect(voiceState.echoCancellation, isFalse);
      expect(notified, isTrue);
    });

    test('setAutoGainControl updates setting and notifies', () async {
      var notified = false;
      voiceState.addListener(() => notified = true);
      await voiceState.setAutoGainControl(false);
      expect(voiceState.autoGainControl, isFalse);
      expect(notified, isTrue);
    });
  });
}

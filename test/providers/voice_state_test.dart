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
}) =>
    {
      'type': 'Ready',
      'servers': [],
      'channels': [],
      'users': [],
      'voice_states': voiceMembers.entries
          .map((e) => {
                'id': e.key,
                'participants': e.value.map((uid) => {'id': uid}).toList(),
              })
          .toList(),
    };

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

    test('voiceParticipants is empty when not connected to a room', () {
      expect(voiceState.voiceParticipants, isEmpty);
    });

    test('remoteVideoStreams is empty when not connected to a room', () {
      expect(voiceState.remoteVideoStreams, isEmpty);
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
  // ── WS voice channel membership ────────────────────────────────────────────────────

  group('VoiceState – voice channel events', () {
    test('Ready seeds voice membership from voice_states', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      expect(voiceState.voiceParticipantsFor('chan1'), contains('user1'));
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

    test('VoiceChannelMove removes from source and adds to destination', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['user1']}));
      svc.push({'type': 'VoiceChannelMove', 'user': 'user1', 'from': 'chan1', 'to': 'chan2'});
      expect(voiceState.voiceParticipantsFor('chan1'), isNot(contains('user1')));
      expect(voiceState.voiceParticipantsFor('chan2'), contains('user1'));
    });

    test('VoiceChannelLeave notifies listeners', () {
      svc.push(_readyEvent(voiceMembers: {'chan1': ['u1']}));
      var notified = false;
      voiceState.addListener(() => notified = true);
      svc.push({'type': 'VoiceChannelLeave', 'id': 'chan1', 'user': 'u1'});
      expect(notified, isTrue);
    });
  });
}

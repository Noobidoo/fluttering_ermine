// Unit tests for VoiceState and the integration gap between VoiceState and
// ServerState that causes participant list staleness bugs.
//
// Bug 1 — Local user ghost:
//   leaveVoiceChannel() resets VoiceState but never touches
//   ServerState._voiceChannelMembers. If the server doesn't echo a
//   VoiceChannelLeave WS event back to the departing client (it doesn't),
//   the local user's entry stays in the sidebar forever.
//
// Bug 2 — Remote participant ghost:
//   ParticipantDisconnectedEvent fires → VoiceState.notifyListeners() →
//   widget rebuilds → sidebar reads server.voiceParticipantsFor() which
//   still has the user because no WS VoiceChannelLeave has arrived yet
//   (network cut, abrupt drop, server lag).
//
// Tests marked [FAILS] assert the desired/fixed behaviour and will fail
// with the current code until the bugs are resolved.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluttering_ermine/providers/server_state.dart';
import 'package:fluttering_ermine/providers/voice_state.dart';

import '../helpers/messaging_test_helpers.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

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
  late ServerState serverState;
  late VoiceState voiceState;

  setUp(() {
    svc = FakeRevoltService();
    serverState = ServerState(svc);
    serverState.subscribeToEvents();
    voiceState = VoiceState(svc);
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

  // ── BUG 1: Local user ghost in ServerState sidebar ────────────────────────
  //
  // When the local client calls leaveVoiceChannel(), the server sends a
  // VoiceChannelLeave to all *remaining* participants — not back to the
  // departing client itself.  VoiceState has no reference to ServerState, so
  // it cannot clear _voiceChannelMembers.  The sidebar entry never disappears.
  //
  // Fix options:
  //   • Pass ServerState (or a callback) into VoiceState and call it on leave.
  //   • Have the service send a synthetic VoiceChannelLeave on the local stream.
  //
  // [FAILS] — flip the expectation once the bug is fixed.

  group('BUG 1 – local user ghost after leaveVoiceChannel', () {
    test('[FAILS] local user is removed from ServerState participant list on leave', () async {
      // Add local user to ServerState via WS Ready (simulates being in a call).
      svc.push(_readyEvent(voiceMembers: {'chan1': ['localUser']}));
      expect(serverState.voiceParticipantsFor('chan1'), contains('localUser'));

      // Local user disconnects.  VoiceState resets but ServerState is untouched.
      await voiceState.leaveVoiceChannel();

      // DESIRED — currently fails because no mechanism clears the entry:
      expect(serverState.voiceParticipantsFor('chan1'),
          isNot(contains('localUser')));
    });
  });

  // ── BUG 2: Remote participant ghost — client is in the room ───────────────
  //
  // The sidebar always reads from ServerState.voiceParticipantsFor(), which is
  // updated only by WS VoiceChannelLeave events.  When a remote participant
  // drops (network cut, abrupt quit), LiveKit fires ParticipantDisconnectedEvent
  // and VoiceState.notifyListeners() is called — but ServerState is never
  // updated.  The sidebar rebuilds and still shows the ghost because
  // voiceParticipantsFor() returns stale data.
  //
  // Partial fix available: on ParticipantDisconnectedEvent, remove the
  // participant's identity from ServerState._voiceChannelMembers (requires
  // VoiceState → ServerState coupling, or a shared event bus).
  //
  // [FAILS] — flip the expectation once the bug is fixed.

  group('BUG 2 – remote participant ghost (client in room, no WS event)', () {
    test('[FAILS] participant is removed from ServerState when LiveKit fires ParticipantDisconnectedEvent without a WS event', () {
      // Remote participant is in the channel per the last WS Ready snapshot.
      svc.push(_readyEvent(voiceMembers: {'chan1': ['remoteUser']}));

      // In production: LiveKit fires ParticipantDisconnectedEvent here.
      // VoiceState.notifyListeners() is called, but no WS VoiceChannelLeave
      // arrives (abrupt network drop / server lag).
      // With the fix, this expectation should pass:
      expect(serverState.voiceParticipantsFor('chan1'),
          isNot(contains('remoteUser')));
    });
  });

}

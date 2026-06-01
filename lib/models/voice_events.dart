// Domain events for voice channel state changes.
// These events unify WebSocket and LiveKit event sources into a clean interface.
import 'package:livekit_client/livekit_client.dart';

// ── Voice Channel Membership Events ──────────────────────────────────────────

/// A user joined a voice channel.
class VoiceChannelJoinEvent {
  final String channelId;
  final String userId;

  const VoiceChannelJoinEvent({
    required this.channelId,
    required this.userId,
  });
}

/// A user left a voice channel.
class VoiceChannelLeaveEvent {
  /// Null channelId signals removal from all channels.
  final String? channelId;
  final String userId;

  const VoiceChannelLeaveEvent({
    this.channelId,
    required this.userId,
  });
}

/// A user moved from one voice channel to another.
class VoiceChannelMoveEvent {
  final String userId;
  final String? fromChannelId;
  final String? toChannelId;

  const VoiceChannelMoveEvent({
    required this.userId,
    this.fromChannelId,
    this.toChannelId,
  });
}

/// Voice channel membership was cleared (e.g., on Ready event).
class VoiceChannelMembershipResetEvent {
  final Map<String, List<String>> channelMembers;
  final Map<String, bool> publishingState;

  const VoiceChannelMembershipResetEvent({
    required this.channelMembers,
    required this.publishingState,
  });
}

// ── Voice Publishing State ───────────────────────────────────────────────────

/// A user's publishing state changed (muted/unmuted).
class VoicePublishingStateChangeEvent {
  final String userId;
  final bool isPublishing;

  const VoicePublishingStateChangeEvent({
    required this.userId,
    required this.isPublishing,
  });
}

// ── Room Connection Events ───────────────────────────────────────────────────

/// LiveKit room connection state.
enum RoomConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Room connection state changed.
class RoomConnectionStateChangeEvent {
  final RoomConnectionState state;
  final Room? room;
  final String? channelId;
  final String? errorMessage;
  final DisconnectReason? disconnectReason;

  const RoomConnectionStateChangeEvent({
    required this.state,
    this.room,
    this.channelId,
    this.errorMessage,
    this.disconnectReason,
  });
}

// ── Participant Events ───────────────────────────────────────────────────────

/// A participant connected to the room.
class VoiceParticipantConnectedEvent {
  final String participantId;
  final String? participantName;

  const VoiceParticipantConnectedEvent({
    required this.participantId,
    this.participantName,
  });
}

/// A participant disconnected from the room.
class VoiceParticipantDisconnectedEvent {
  final String participantId;
  final String channelId;

  const VoiceParticipantDisconnectedEvent({
    required this.participantId,
    required this.channelId,
  });
}

// ── Track Events ─────────────────────────────────────────────────────────────

/// A track was subscribed.
class VoiceTrackSubscribedEvent {
  final String participantId;
  final Track track;
  final TrackSource source;

  const VoiceTrackSubscribedEvent({
    required this.participantId,
    required this.track,
    required this.source,
  });
}

/// A track was unsubscribed.
class VoiceTrackUnsubscribedEvent {
  final String participantId;

  const VoiceTrackUnsubscribedEvent({
    required this.participantId,
  });
}

// ── Speaking State ───────────────────────────────────────────────────────────

/// Active speakers changed.
class VoiceActiveSpeakersChangedEvent {
  final List<String> activeSpeakers;

  const VoiceActiveSpeakersChangedEvent({
    required this.activeSpeakers,
  });
}

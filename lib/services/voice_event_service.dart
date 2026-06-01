import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'revolt_service.dart';

/// Service that unifies WebSocket voice events and LiveKit room events
/// into typed domain event streams.
///
/// This service acts as an event router and translator, subscribing to both
/// RevoltService WebSocket events and LiveKit Room events, then emitting
/// clean domain events that state providers can consume.
class VoiceEventService {
  final RevoltService _revoltService;

  VoiceEventService(this._revoltService);

  StreamSubscription<Map<String, dynamic>>? _wsSub;

  // Event stream controllers (sync: true so events are delivered immediately,
  // which makes unit tests predictable without requiring Future.delayed waits)
  final _membershipController = StreamController<dynamic>.broadcast(sync: true);
  final _publishingController = StreamController<VoicePublishingStateChangeEvent>.broadcast(sync: true);

  // Public event streams
  /// Emits VoiceChannelJoinEvent, VoiceChannelLeaveEvent, VoiceChannelMoveEvent,
  /// and VoiceChannelMembershipResetEvent.
  Stream<dynamic> get membershipEvents => _membershipController.stream;

  /// Emits VoicePublishingStateChangeEvent when a user mutes/unmutes.
  Stream<VoicePublishingStateChangeEvent> get publishingEvents => _publishingController.stream;

  // ── Initialization ────────────────────────────────────────────────────────

  /// Subscribe to WebSocket events from RevoltService.
  void subscribeToWebSocketEvents() {
    _wsSub?.cancel();
    _wsSub = _revoltService.events.listen(_handleWebSocketEvent);
  }

  // ── WebSocket Event Handling ──────────────────────────────────────────────

  void _handleWebSocketEvent(Map<String, dynamic> event) {
    switch (event['type'] as String?) {
      case 'Ready':
        _handleWsReady(event);
      case 'VoiceChannelJoin':
        _handleWsVoiceChannelJoin(event);
      case 'VoiceChannelLeave':
        _handleWsVoiceChannelLeave(event);
      case 'VoiceChannelMove':
        _handleWsVoiceChannelMove(event);
      case 'UserVoiceStateUpdate':
        _handleWsUserVoiceStateUpdate(event);
      case 'ServerMemberUpdate':
        _handleWsMemberUpdate(event);
    }
  }

  void _handleWsReady(Map<String, dynamic> event) {
    final channelMembers = <String, List<String>>{};
    final publishingState = <String, bool>{};

    final voiceStates = (event['voice_states'] as List<dynamic>?) ?? [];
    for (final vs in voiceStates) {
      final map = vs as Map<String, dynamic>;
      final channelId = map['id'] as String?;
      if (channelId == null) continue;

      final participants = (map['participants'] as List<dynamic>?) ?? [];
      for (final p in participants) {
        final pm = p as Map<String, dynamic>;
        final userId = pm['id'] as String?;
        final isPublishing = pm['is_publishing'] as bool?;
        if (userId == null) continue;

        channelMembers.putIfAbsent(channelId, () => []);
        if (!channelMembers[channelId]!.contains(userId)) {
          channelMembers[channelId]!.add(userId);
        }

        if (isPublishing != null) {
          publishingState[userId] = isPublishing;
        }
      }
    }

    debugPrint('[VoiceEventService] Ready: channelMembers=$channelMembers');
    _membershipController.add(VoiceChannelMembershipResetEvent(
      channelMembers: channelMembers,
      publishingState: publishingState,
    ));
  }

  void _handleWsVoiceChannelJoin(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final state = event['state'] as Map<String, dynamic>?;
    final userId = state?['id'] as String?;

    debugPrint('[VoiceEventService] VoiceChannelJoin channel=$channelId user=$userId');

    if (channelId != null && userId != null) {
      _membershipController.add(VoiceChannelJoinEvent(
        channelId: channelId,
        userId: userId,
      ));
    }
  }

  void _handleWsVoiceChannelLeave(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;

    debugPrint('[VoiceEventService] VoiceChannelLeave channel=$channelId user=$userId');

    if (channelId != null && userId != null) {
      _membershipController.add(VoiceChannelLeaveEvent(
        channelId: channelId,
        userId: userId,
      ));
    }
  }

  void _handleWsVoiceChannelMove(Map<String, dynamic> event) {
    final userId = event['user'] as String?;
    final from = event['from'] as String?;
    final to = event['to'] as String?;

    debugPrint('[VoiceEventService] VoiceChannelMove user=$userId from=$from to=$to');

    if (userId != null) {
      _membershipController.add(VoiceChannelMoveEvent(
        userId: userId,
        fromChannelId: from,
        toChannelId: to,
      ));
    }
  }

  void _handleWsUserVoiceStateUpdate(Map<String, dynamic> event) {
    final userId = event['id'] as String?;
    final data = event['data'] as Map<String, dynamic>?;
    if (userId == null || data == null) return;

    final isPublishing = data['is_publishing'] as bool?;
    if (isPublishing != null) {
      _publishingController.add(VoicePublishingStateChangeEvent(
        userId: userId,
        isPublishing: isPublishing,
      ));
    }
  }

  void _handleWsMemberUpdate(Map<String, dynamic> event) {
    final id = event['id'] as Map<String, dynamic>?;
    final userId = id?['user'] as String?;
    if (userId == null) return;

    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];
    if (clear.contains('VoiceChannel')) {
      // User left all voice channels - emit leave events for cleanup
      // States should remove this user from all channels
      debugPrint('[VoiceEventService] ServerMemberUpdate: user $userId cleared from voice');
      // Emit a special leave event with null channelId to signal "remove from all"
      _membershipController.add(VoiceChannelLeaveEvent(
        channelId: null, // null signals "remove from all channels"
        userId: userId,
      ));
      return;
    }

    final data = event['data'] as Map<String, dynamic>?;
    final newChannel = data?['voice_channel'] as String?;
    if (newChannel != null) {
      _membershipController.add(VoiceChannelJoinEvent(
        channelId: newChannel,
        userId: userId,
      ));
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _wsSub?.cancel();
    await _membershipController.close();
    await _publishingController.close();
  }
}

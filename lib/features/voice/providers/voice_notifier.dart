import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/models.dart' hide Permission;
import '../../../services/revolt_service.dart';
import '../../../services/voice_event_service.dart';
import '../../core/providers/service_providers.dart';
import '../../servers/providers/current_user_id_provider.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// -----------------------------------------------------------------------------
// Helper classes
// -----------------------------------------------------------------------------

class RemoteVideoStream {
  final VideoTrack track;
  final String participantIdentity;
  final TrackSource source;
  const RemoteVideoStream({
    required this.track,
    required this.participantIdentity,
    required this.source,
  });
}

class VoiceParticipant {
  final String identity;
  final String? name;
  final bool isLocal;
  final bool isMuted;
  final bool isSpeaking;
  final bool isScreenSharing;
  const VoiceParticipant({
    required this.identity,
    this.name,
    required this.isLocal,
    required this.isMuted,
    this.isSpeaking = false,
    this.isScreenSharing = false,
  });

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    return identity;
  }
}

// -----------------------------------------------------------------------------
// Pure data state (immutable)
// -----------------------------------------------------------------------------

@immutable
class VoiceStateData {
  final RevoltChannel? activeVoiceChannel;
  final bool isInVoice;
  final bool isMuted;
  final bool isJoiningVoice;
  final bool isScreenSharing;
  final bool isCameraEnabled;
  final String? voiceError;
  final Map<String, List<String>> voiceChannelMembers;
  final Map<String, bool> voicePublishing;
  final double outputVolume;
  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;
  final String? selectedAudioInputId;
  final Map<String, double> participantVolumes;
  final bool deepFilterEnabled;
  final bool deepFilterIsApmAttached;
  final Set<String> subscribedScreenShares;
  final List<VoiceParticipant> voiceParticipants;
  final List<RemoteVideoStream> remoteVideoStreams;
  final LocalVideoTrack? localCameraTrack;
  final int leaveCalledAmount;

  const VoiceStateData({

    this.activeVoiceChannel,
    this.isInVoice = false,
    this.isMuted = false,
    this.isJoiningVoice = false,
    this.isScreenSharing = false,
    this.isCameraEnabled = false,
    this.voiceError,
    this.voiceChannelMembers = const {},
    this.voicePublishing = const {},
    this.outputVolume = 1.0,
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.selectedAudioInputId,
    this.participantVolumes = const {},
    this.deepFilterEnabled = true,
    this.deepFilterIsApmAttached = false,
    this.subscribedScreenShares = const {},
    this.voiceParticipants = const [],
    this.remoteVideoStreams = const [],
    this.localCameraTrack,
    this.leaveCalledAmount = 0,
  });

  // -- Query methods (only state fields) ------------------------------------

  bool isScreenShareSubscribed(String identity) => subscribedScreenShares.contains(identity);

  List<String> voiceParticipantsFor(String channelId) =>
      List.unmodifiable(voiceChannelMembers[channelId] ?? []);

  bool? voicePublishingFor(String userId) => voicePublishing[userId];

  double getParticipantVolume(String identity, {TrackSource? source}) {
    if (source != null) {
      return participantVolumes['$identity:${source.name}'] ?? 1.0;
    }
    return participantVolumes[identity] ?? 1.0;
  }

  // -- copyWith ----------------------------------------------------------------

  static const _omit = Object();

  VoiceStateData copyWith({
    Object? activeVoiceChannel = _omit,
    bool? isInVoice,
    bool? isMuted,
    bool? isJoiningVoice,
    bool? isScreenSharing,
    bool? isCameraEnabled,
    Object? voiceError = _omit,
    Map<String, List<String>>? voiceChannelMembers,
    Map<String, bool>? voicePublishing,
    double? outputVolume,
    bool? noiseSuppression,
    bool? echoCancellation,
    bool? autoGainControl,
    Object? selectedAudioInputId = _omit,
    Map<String, double>? participantVolumes,
    bool? deepFilterEnabled,
    bool? deepFilterIsApmAttached,
    Set<String>? subscribedScreenShares,
    List<VoiceParticipant>? voiceParticipants,
    List<RemoteVideoStream>? remoteVideoStreams,
    Object? localCameraTrack = _omit,
    int? leaveCalledAmount,
  }) => VoiceStateData(
    activeVoiceChannel: activeVoiceChannel == _omit
        ? this.activeVoiceChannel
        : activeVoiceChannel as RevoltChannel?,
    isInVoice: isInVoice ?? this.isInVoice,
    isMuted: isMuted ?? this.isMuted,
    isJoiningVoice: isJoiningVoice ?? this.isJoiningVoice,
    isScreenSharing: isScreenSharing ?? this.isScreenSharing,
    isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
    voiceError: voiceError == _omit ? this.voiceError : voiceError as String?,
    voiceChannelMembers: voiceChannelMembers ?? this.voiceChannelMembers,
    voicePublishing: voicePublishing ?? this.voicePublishing,
    outputVolume: outputVolume ?? this.outputVolume,
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    autoGainControl: autoGainControl ?? this.autoGainControl,
    selectedAudioInputId: selectedAudioInputId == _omit
        ? this.selectedAudioInputId
        : selectedAudioInputId as String?,
    participantVolumes: participantVolumes ?? this.participantVolumes,
    deepFilterEnabled: deepFilterEnabled ?? this.deepFilterEnabled,
    deepFilterIsApmAttached: deepFilterIsApmAttached ?? this.deepFilterIsApmAttached,
    subscribedScreenShares: subscribedScreenShares ?? this.subscribedScreenShares,
    voiceParticipants: voiceParticipants ?? this.voiceParticipants,
    remoteVideoStreams: remoteVideoStreams ?? this.remoteVideoStreams,
    localCameraTrack: localCameraTrack == _omit
        ? this.localCameraTrack
        : localCameraTrack as LocalVideoTrack?,
    leaveCalledAmount: leaveCalledAmount ?? this.leaveCalledAmount,
  );
}

// -----------------------------------------------------------------------------
// Notifier
// -----------------------------------------------------------------------------

class VoiceNotifier extends Notifier<VoiceStateData> {
  late RevoltService _service;
  late VoiceEventService _voiceEventService;

  StreamSubscription<dynamic>? _membershipSub;
  StreamSubscription<VoicePublishingStateChangeEvent>? _publishingSub;

  Room? _voiceRoom;
  EventsListener<RoomEvent>? _voiceRoomListener;
  // ignore: unused_field
  LocalVideoTrack? _screenShareTrack;
  final _liveKitDeepFilter = LiveKitDeepFilter();

  // -- Static helpers --------------------------------------------------------

  static bool get deepFilterSupported => LiveKitDeepFilter.isSupported;
  static bool get deepFilterIsRealLibrary => LiveKitDeepFilter.isRealLibrary;

  // -- build() ---------------------------------------------------------------

  @override
  VoiceStateData build() {
    _service = ref.watch(revoltServiceProvider);
    _voiceEventService = ref.watch(voiceEventServiceProvider);

    // Rule 3: Pull, Don't Push
    ref.watch(currentUserIdProvider);

    subscribeToVoiceEvents();
    _asyncLoadSettings();

    ref.onDispose(_dispose);

    return VoiceStateData();
  }

  // -- Device queries (no state dependency) --------------------------------

  Future<List<MediaDevice>> getAudioInputDevices() async {
    try {
      return await Hardware.instance.audioInputs();
    } catch (e) {
      debugPrint('[voice] enumerateDevices failed: $e');
      return [];
    }
  }

  Future<List<MediaDevice>> getVideoInputDevices() async {
    try {
      return await Hardware.instance.videoInputs();
    } catch (e) {
      debugPrint('[voice] enumerate video devices failed: $e');
      return [];
    }
  }

  // -- Internal helpers for recomputing Room-derived lists -------------------

  List<VoiceParticipant> _computeVoiceParticipants() {
    final room = _voiceRoom;
    if (room == null) return const [];
    final result = <VoiceParticipant>[];
    final local = room.localParticipant;
    if (local != null) {
      result.add(
        VoiceParticipant(
          identity: local.identity,
          name: local.name,
          isLocal: true,
          isMuted: state.isMuted,
          isSpeaking: local.isSpeaking,
          isScreenSharing: state.isScreenSharing,
        ),
      );
    }
    for (final p in room.remoteParticipants.values) {
      final audioMuted = p.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .every((pub) => pub.muted);
      final hasScreenShare = p.trackPublications.values.any((pub) => pub.isScreenShare);
      result.add(
        VoiceParticipant(
          identity: p.identity,
          name: p.name,
          isLocal: false,
          isMuted: audioMuted,
          isSpeaking: p.isSpeaking,
          isScreenSharing: hasScreenShare,
        ),
      );
    }
    return result;
  }

  List<RemoteVideoStream> _computeRemoteVideoStreams() {
    final room = _voiceRoom;
    if (room == null) return const [];
    final streams = <RemoteVideoStream>[];
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        if (pub.track is VideoTrack &&
            (pub.source == TrackSource.camera || pub.source == TrackSource.screenShareVideo)) {
          streams.add(
            RemoteVideoStream(
              track: pub.track as VideoTrack,
              participantIdentity: p.identity,
              source: pub.source,
            ),
          );
        }
      }
    }
    return streams;
  }

  LocalVideoTrack? _computeLocalCameraTrack() {
    if (_voiceRoom == null) return null;
    final lp = _voiceRoom!.localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      if (pub.source == TrackSource.camera) {
        return pub.track;
      }
    }
    return null;
  }

  VoiceStateData _withRoomValues(VoiceStateData data) {
    if (_voiceRoom == null) return data;
    return data.copyWith(
      voiceParticipants: _computeVoiceParticipants(),
      remoteVideoStreams: _computeRemoteVideoStreams(),
      localCameraTrack: _computeLocalCameraTrack(),
    );
  }

  bool _shouldSubscribeTrack(RemoteTrackPublication publication) =>
      !publication.isScreenShare || state.isScreenShareSubscribed(publication.participant.identity);

  // -- Voice Event Subscription (via VoiceEventService) --------------------

  void subscribeToVoiceEvents() {
    _membershipSub?.cancel();
    _publishingSub?.cancel();
    _membershipSub = _voiceEventService.membershipEvents.listen(_handleMembershipEvent);
    _publishingSub = _voiceEventService.publishingEvents.listen(_handlePublishingEvent);
  }

  void _handleMembershipEvent(dynamic event) {
    if (event is VoiceChannelMembershipResetEvent) {
      state = state.copyWith(
        voiceChannelMembers: Map<String, List<String>>.from(event.channelMembers),
        voicePublishing: Map<String, bool>.from(event.publishingState),
      );
      debugPrint('[VoiceState] VoiceChannelMembershipReset: ${state.voiceChannelMembers}');
    } else if (event is VoiceChannelJoinEvent) {
      debugPrint('[VoiceState] VoiceChannelJoin channel=${event.channelId} user=${event.userId}');
      final newMembers = Map<String, List<String>>.from(state.voiceChannelMembers);
      newMembers.putIfAbsent(event.channelId, () => []);
      if (!newMembers[event.channelId]!.contains(event.userId)) {
        newMembers[event.channelId] = [...newMembers[event.channelId]!, event.userId];
      }
      state = state.copyWith(voiceChannelMembers: newMembers);
    } else if (event is VoiceChannelLeaveEvent) {
      debugPrint('[VoiceState] VoiceChannelLeave channel=${event.channelId} user=${event.userId}');
      final newMembers = Map<String, List<String>>.from(state.voiceChannelMembers);
      final newPublishing = Map<String, bool>.from(state.voicePublishing)..remove(event.userId);
      if (event.channelId == null) {
        for (final list in newMembers.values) {
          list.remove(event.userId);
        }
        newMembers.removeWhere((_, list) => list.isEmpty);
      } else {
        newMembers[event.channelId]?.remove(event.userId);
        newMembers.removeWhere((_, list) => list.isEmpty);
      }
      state = state.copyWith(voiceChannelMembers: newMembers, voicePublishing: newPublishing);
    } else if (event is VoiceChannelMoveEvent) {
      debugPrint(
        '[VoiceState] VoiceChannelMove user=${event.userId} from=${event.fromChannelId} to=${event.toChannelId}',
      );
      final newMembers = Map<String, List<String>>.from(state.voiceChannelMembers);
      if (event.fromChannelId != null) {
        newMembers[event.fromChannelId]?.remove(event.userId);
        newMembers.removeWhere((_, list) => list.isEmpty);
      }
      if (event.toChannelId != null) {
        newMembers.putIfAbsent(event.toChannelId!, () => []);
        if (!newMembers[event.toChannelId]!.contains(event.userId)) {
          newMembers[event.toChannelId!] = [...newMembers[event.toChannelId!]!, event.userId];
        }
      }
      state = state.copyWith(voiceChannelMembers: newMembers);
    }
  }

  void _handlePublishingEvent(VoicePublishingStateChangeEvent event) {
    state = state.copyWith(
      voicePublishing: {...state.voicePublishing, event.userId: event.isPublishing},
    );
  }

  /// Returns updated channel members map with [userId] removed from [channelId].
  Map<String, List<String>> _removeParticipantFrom(
    Map<String, List<String>> members,
    String channelId,
    String userId,
  ) {
    final newMembers = Map<String, List<String>>.from(members);
    newMembers[channelId]?.remove(userId);
    newMembers.removeWhere((_, list) => list.isEmpty);
    return newMembers;
  }

  // -- Actions ---------------------------------------------------------------

  Future<void> joinVoiceChannel(RevoltChannel channel) async {
    if (state.isJoiningVoice) return;

    if (!defaultTargetPlatform.name.toLowerCase().contains('linux') &&
        !defaultTargetPlatform.name.toLowerCase().contains('windows')) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        state = state.copyWith(voiceError: 'Microphone permission denied');
        return;
      }
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        state = state.copyWith(voiceError: 'Camera permission denied');
        return;
      }
    }

    if (_voiceRoom != null) await leaveVoiceChannel();
    state = state.copyWith(isJoiningVoice: true, voiceError: null);

    try {
      final data = await _service.joinVoiceChannel(channel.id);
      var url = data['url'] as String;
      final token = data['token'] as String;
      debugPrint('[voice:debug] LiveKit URL  : $url');
      debugPrint('[voice:debug] LiveKit token: $token');
      if (url.startsWith('https://')) {
        url = 'wss://${url.substring(8)}';
      } else if (url.startsWith('http://')) {
        url = 'ws://${url.substring(7)}';
      }

      final room = Room();
      _voiceRoomListener = room.createListener();
      _voiceRoomListener!
        ..on<RoomConnectedEvent>((e) {
          debugPrint('[voice:event] RoomConnectedEvent room=${room.name}');
          debugPrint(
            '[voice:event] Channel ${channel.id} has ${e.room.remoteParticipants.length + (e.room.localParticipant != null ? 1 : 0)} participants',
          );
          debugPrint('[voice:event] _voiceRoom assigned');
          _voiceRoom = e.room;
          final newMembers = Map<String, List<String>>.from(state.voiceChannelMembers);
          newMembers.putIfAbsent(channel.id, () => []);
          for (final p in e.room.remoteParticipants.values) {
            if (!newMembers[channel.id]!.contains(p.identity)) {
              newMembers[channel.id] = [...newMembers[channel.id]!, p.identity];
            }
          }
          state = _withRoomValues(
            state.copyWith(
              isInVoice: true,
              isJoiningVoice: false,
              activeVoiceChannel: channel,
              voiceError: null,
              voiceChannelMembers: newMembers,
            ),
          );
          debugPrint('[voice:event] RoomConnectedEvent handler complete');
        })
        ..on<RoomDisconnectedEvent>((e) {
          debugPrint(
            '[voice:event] RoomDisconnectedEvent channel=${channel.id} reason=${e.reason}',
          );
          final localId = room.localParticipant?.identity;
          final base = state.copyWith(
            isInVoice: false,
            isJoiningVoice: false,
            isMuted: false,
            isScreenSharing: false,
          );
          _voiceRoom = null;
          final cleared = base.copyWith(
            activeVoiceChannel: null,
            voiceParticipants: const [],
            remoteVideoStreams: const [],
          );
          if (localId != null) {
            final members = _removeParticipantFrom(
              cleared.voiceChannelMembers,
              channel.id,
              localId,
            );
            state = cleared.copyWith(voiceChannelMembers: members);
          } else {
            state = cleared;
          }
          _screenShareTrack = null;
          switch (e.reason) {
            case DisconnectReason.clientInitiated:
              state = state.copyWith(voiceError: null);
              break;
            case DisconnectReason.participantRemoved:
              state = state.copyWith(voiceError: 'Disconnected by server');
              break;
            case DisconnectReason.joinFailure:
            case DisconnectReason.signalingConnectionFailure:
              state = state.copyWith(voiceError: 'Network error');
              break;
            case DisconnectReason.reconnectAttemptsExceeded:
              state = state.copyWith(voiceError: 'Network error, reconnect attempts exceeded');
              break;
            case DisconnectReason.duplicateIdentity:
              state = state.copyWith(voiceError: 'Logged in elsewhere');
              break;
            case DisconnectReason.unknown:
            default:
              state = state.copyWith(voiceError: 'Disconnected from voice');
          }
        })
        ..on<RoomReconnectingEvent>((e) {
          debugPrint('[voice:event] RoomReconnectingEvent room=${room.name}');
          state = state.copyWith(voiceError: 'Reconnecting...', isJoiningVoice: true);
        })
        ..on<RoomReconnectedEvent>((e) {
          debugPrint('[voice:event] RoomReconnectedEvent room=${room.name}');
          state = _withRoomValues(
            state.copyWith(voiceError: null, isInVoice: true, isJoiningVoice: false),
          );
        })
        ..on<TrackSubscribedEvent>((e) {
          debugPrint(
            '[voice:event] TrackSubscribedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}',
          );
          if (e.track is RemoteAudioTrack && e.publication.source == TrackSource.screenShareAudio) {
            e.track.events.listen((trackEvent) {
              if (trackEvent is AudioReceiverStatsEvent) {
                final s = trackEvent.stats;
                debugPrint(
                  '[voice:rx] screen audio | '
                  '${trackEvent.currentBitrate.toStringAsFixed(1)} kbps | '
                  'jitter=${s.jitter?.toStringAsFixed(4) ?? '-'} | '
                  'lost=${s.packetsLost ?? '-'} | '
                  'concealed=${s.concealedSamples ?? '-'} '
                  '(${s.concealmentEvents ?? '-'} events) | '
                  'audioEnergy=${s.totalAudioEnergy?.toStringAsFixed(4) ?? '-'} | '
                  'track.enabled=${e.track.mediaStreamTrack.enabled}',
                );
              }
            });
          }
          if (e.track is RemoteAudioTrack && e.publication.kind == TrackType.AUDIO) {
            final storedVolume =
                state.participantVolumes['${e.participant.identity}:${e.publication.source.name}'];
            if (storedVolume != null) {
              unawaited(NativeAudioManagement.setVolume(storedVolume, e.track.mediaStreamTrack));
            }
          }
          state = _withRoomValues(state);
        })
        ..on<TrackUnsubscribedEvent>((e) {
          debugPrint(
            '[voice:event] TrackUnsubscribedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}',
          );
          state = _withRoomValues(state);
        })
        ..on<TrackPublishedEvent>((e) {
          final willSubscribe = _shouldSubscribeTrack(e.publication);
          if (willSubscribe) e.publication.subscribe();
          state = _withRoomValues(state);
        })
        ..on<TrackUnpublishedEvent>((e) {
          debugPrint(
            '[voice:event] TrackUnpublishedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}',
          );
          state = _withRoomValues(state);
        })
        ..on<TrackMutedEvent>((e) {
          debugPrint(
            '[voice:event] TrackMutedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}',
          );
          state = _withRoomValues(state);
        })
        ..on<TrackUnmutedEvent>((e) {
          debugPrint(
            '[voice:event] TrackUnmutedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}',
          );
          state = _withRoomValues(state);
        })
        ..on<TrackSubscriptionExceptionEvent>((e) {
          debugPrint(
            '[voice:event] TrackSubscriptionExceptionEvent participant=${e.participant?.identity} sid=${e.sid} reason=${e.reason}',
          );
          state = _withRoomValues(state);
        })
        ..on<ParticipantConnectedEvent>((e) {
          debugPrint('[voice:event] ParticipantConnectedEvent id=${e.participant.identity}');
          final newMembers = Map<String, List<String>>.from(state.voiceChannelMembers);
          newMembers.putIfAbsent(channel.id, () => []);
          if (!newMembers[channel.id]!.contains(e.participant.identity)) {
            newMembers[channel.id] = [...newMembers[channel.id]!, e.participant.identity];
          }
          state = _withRoomValues(state.copyWith(voiceChannelMembers: newMembers));
        })
        ..on<ParticipantDisconnectedEvent>((e) {
          debugPrint(
            '[voice:event] ParticipantDisconnectedEvent id=${e.participant.identity} remaining=${_voiceRoom?.remoteParticipants.length}',
          );
          final newMembers = _removeParticipantFrom(
            state.voiceChannelMembers,
            channel.id,
            e.participant.identity,
          );
          state = _withRoomValues(state.copyWith(voiceChannelMembers: newMembers));
        })
        ..on<ActiveSpeakersChangedEvent>((_) {
          state = _withRoomValues(state);
        });

      await room.connect(url, token, connectOptions: const ConnectOptions(autoSubscribe: false));

      state = state.copyWith(isMuted: false);
      final lp = room.localParticipant;
      if (lp == null) {
        debugPrint('[voice] localParticipant is null after connect');
        throw Exception('Failed to get local participant');
      }
      debugPrint('[voice] localParticipant identity=${lp.identity}');

      await setSelectedAudioInput(await _getSelectedAudioInputId());

      if (state.deepFilterEnabled) {
        await _liveKitDeepFilter.enable(enabled: true);
        state = state.copyWith(deepFilterIsApmAttached: _liveKitDeepFilter.isProcessing);
      }

      try {
        await lp.setMicrophoneEnabled(
          true,
          audioCaptureOptions: AudioCaptureOptions(
            deviceId: state.selectedAudioInputId,
            noiseSuppression: state.noiseSuppression,
            echoCancellation: state.echoCancellation,
            autoGainControl: state.autoGainControl,
            processor: _liveKitDeepFilter.processor,
          ),
        );
        debugPrint('[voice] mic enabled, published tracks: ${lp.trackPublications.length}');
      } catch (micErr) {
        debugPrint('[voice] mic enable failed: $micErr');
        state = state.copyWith(voiceError: 'Failed to access microphone');
      }

      _subscribeInitialTracks();
      await _applyOutputVolume();
      await _applyParticipantVolumes();
    } catch (e) {
      debugPrint('[voice] join failed: $e');
      state = state.copyWith(voiceError: e.toString().replaceAll('Exception: ', ''));
    } finally {
      state = state.copyWith(isJoiningVoice: false);
    }
  }

  Future<void> leaveVoiceChannel() async {
    debugPrint('[voice:leave] leaveVoiceChannel called, room=${_voiceRoom?.name}');
    state = state.copyWith(leaveCalledAmount: state.leaveCalledAmount + 1);
    debugPrint('[voice:leave] _leaveCalledAmount=${state.leaveCalledAmount}');

    if (state.isScreenSharing && _voiceRoom?.localParticipant != null) {
      try {
        await _voiceRoom!.localParticipant!.setScreenShareEnabled(false);
      } catch (_) {}
    }

    await _liveKitDeepFilter.disable();
    state = state.copyWith(deepFilterIsApmAttached: false);

    try {
      await _voiceRoom?.disconnect();
      debugPrint('[voice:leave] disconnect() returned');
    } catch (e) {
      debugPrint('[voice:leave] disconnect failed: $e');
    }
    await _voiceRoomListener?.dispose();
    _voiceRoomListener = null;
    _voiceRoom = null;
    _screenShareTrack = null;
    state = state.copyWith(
      activeVoiceChannel: null,
      isInVoice: false,
      isJoiningVoice: false,
      isMuted: false,
      isScreenSharing: false,
      isCameraEnabled: false,
      voiceError: null,
      voiceParticipants: const [],
      remoteVideoStreams: const [],
      leaveCalledAmount: 0,
    );
  }

  Future<void> toggleScreenShareSubscription(String identity) async {
    final newSet = Set<String>.from(state.subscribedScreenShares);
    if (newSet.contains(identity)) {
      newSet.remove(identity);
      _unsubscribeScreenShare(identity);
    } else {
      newSet.add(identity);
      _subscribeScreenShare(identity);
    }
    state = _withRoomValues(state.copyWith(subscribedScreenShares: newSet));
  }

  void _subscribeScreenShare(String identity) {
    if (_voiceRoom == null) return;
    final p = _voiceRoom!.remoteParticipants[identity];
    if (p == null) return;
    for (final pub in p.trackPublications.values) {
      if (pub.isScreenShare) pub.subscribe();
    }
  }

  void _unsubscribeScreenShare(String identity) {
    if (_voiceRoom == null) return;
    final p = _voiceRoom!.remoteParticipants[identity];
    if (p == null) return;
    for (final pub in p.trackPublications.values) {
      if (pub.isScreenShare) pub.unsubscribe();
    }
  }

  void _subscribeInitialTracks() {
    if (_voiceRoom == null) {
      debugPrint('[voice:subscribe] _subscribeInitialTracks: room is null');
      return;
    }
    debugPrint(
      '[voice:subscribe] _subscribeInitialTracks: ${_voiceRoom!.remoteParticipants.length} remote participants',
    );
    for (final p in _voiceRoom!.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        if (_shouldSubscribeTrack(pub)) pub.subscribe();
      }
    }
  }

  Future<void> toggleMute() async {
    if (_voiceRoom == null) return;
    final newMuted = !state.isMuted;
    state = state.copyWith(isMuted: newMuted);
    await _voiceRoom!.localParticipant?.setMicrophoneEnabled(!newMuted);
  }

  Future<void> toggleCamera() async {
    if (_voiceRoom == null) return;
    final newEnabled = !state.isCameraEnabled;
    final lp = _voiceRoom!.localParticipant;
    if (lp != null) {
      try {
        await lp.setCameraEnabled(newEnabled);
      } catch (e) {
        debugPrint('[voice] camera toggle failed: $e');
        state = state.copyWith(isCameraEnabled: !newEnabled, voiceError: 'Failed to toggle camera');
        return;
      }
    }
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_camera_enabled', newEnabled);
    state = state.copyWith(isCameraEnabled: newEnabled);
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (_voiceRoom == null || state.isCameraEnabled == enabled) return;
    final lp = _voiceRoom!.localParticipant;
    if (lp != null) {
      try {
        await lp.setCameraEnabled(enabled);
      } catch (e) {
        debugPrint('[voice] camera set failed: $e');
        state = state.copyWith(isCameraEnabled: !enabled, voiceError: 'Failed to set camera');
        return;
      }
    }
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_camera_enabled', enabled);
    state = state.copyWith(isCameraEnabled: enabled);
  }

  Future<void> startDesktopScreenShare(String sourceId) async {
    if (_voiceRoom?.localParticipant == null) return;
    try {
      final tracks = await LocalVideoTrack.createScreenShareTracksWithAudio(
        ScreenShareCaptureOptions(sourceId: sourceId, captureScreenAudio: true, maxFrameRate: 15.0),
      );
      _screenShareTrack = null;
      final publishFutures = <Future>[];
      for (final track in tracks) {
        if (track is LocalVideoTrack) {
          _screenShareTrack = track;
          publishFutures.add(_voiceRoom!.localParticipant!.publishVideoTrack(track));
        } else if (track is LocalAudioTrack) {
          track.events.listen((event) {
            if (event is AudioSenderStatsEvent) {
              final level = event.stats.audioSourceStats?.audioLevel ?? 0.0;
              debugPrint(
                '[voice] screen audio: '
                '${event.currentBitrate.toStringAsFixed(1)} kbps, '
                'level=${level.toStringAsFixed(3)}',
              );
            }
          });
          publishFutures.add(
            _voiceRoom!.localParticipant!.publishAudioTrack(
              track,
              publishOptions: const AudioPublishOptions(
                encoding: AudioEncoding.presetMusic,
                dtx: false,
              ),
            ),
          );
        }
      }
      await Future.wait(publishFutures);
      state = _withRoomValues(state.copyWith(isScreenSharing: true));
    } catch (e) {
      debugPrint('[voice] screen share failed: $e');
      _screenShareTrack = null;
      state = state.copyWith(voiceError: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> stopScreenShare() async {
    if (_voiceRoom?.localParticipant == null) return;
    try {
      await _voiceRoom!.localParticipant!.setScreenShareEnabled(false);
      _screenShareTrack = null;
      state = _withRoomValues(state.copyWith(isScreenSharing: false));
    } catch (e) {
      debugPrint('[voice] stop screen share failed: $e');
      state = state.copyWith(voiceError: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> toggleScreenShare() async {
    if (_voiceRoom?.localParticipant == null) return;
    final newSharing = !state.isScreenSharing;
    try {
      await _voiceRoom!.localParticipant!.setScreenShareEnabled(
        newSharing,
        screenShareCaptureOptions: newSharing
            ? const ScreenShareCaptureOptions(captureScreenAudio: true)
            : null,
      );
      state = _withRoomValues(state.copyWith(isScreenSharing: newSharing));
    } catch (e) {
      debugPrint('[voice] screen share failed: $e');
      state = state.copyWith(
        isScreenSharing: !newSharing,
        voiceError: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> clear() async {
    await _liveKitDeepFilter.disable();
    await _voiceRoom?.disconnect();
    await _voiceRoomListener?.dispose();
    _voiceRoomListener = null;
    _voiceRoom = null;
    _screenShareTrack = null;
    state = state.copyWith(
      activeVoiceChannel: null,
      isInVoice: false,
      isMuted: false,
      isJoiningVoice: false,
      isScreenSharing: false,
      voiceError: null,
      subscribedScreenShares: {},
      voiceParticipants: const [],
      remoteVideoStreams: const [],
    );
  }

  // -- Settings --------------------------------------------------------------

  Future<void> _asyncLoadSettings() async {
    final asyncPrefs = SharedPreferencesAsync();
    final outputVolume = await asyncPrefs.getDouble('voice_output_volume') ?? 1.0;
    final noiseSuppression = await asyncPrefs.getBool('voice_noise_suppression') ?? true;
    final echoCancellation = await asyncPrefs.getBool('voice_echo_cancellation') ?? true;
    final autoGainControl = await asyncPrefs.getBool('voice_auto_gain_control') ?? true;
    final deepFilterEnabled = await asyncPrefs.getBool('voice_deep_filter_enabled') ?? true;
    final selectedAudioInputId = await asyncPrefs.getString('voice_selected_audio_input_id');
    final isCameraEnabled = await asyncPrefs.getBool('voice_camera_enabled') ?? false;
    final volumesJson = await asyncPrefs.getString('voice_participant_volumes');
    Map<String, double> participantVolumes = const {};
    if (volumesJson != null) {
      try {
        final decoded = jsonDecode(volumesJson) as Map<String, dynamic>;
        participantVolumes = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
      } catch (_) {}
    }
    state = state.copyWith(
      outputVolume: outputVolume,
      noiseSuppression: noiseSuppression,
      echoCancellation: echoCancellation,
      autoGainControl: autoGainControl,
      deepFilterEnabled: deepFilterEnabled,
      selectedAudioInputId: selectedAudioInputId,
      isCameraEnabled: isCameraEnabled,
      participantVolumes: participantVolumes,
    );
  }

  Future<void> _saveParticipantVolumes() async {
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString('voice_participant_volumes', jsonEncode(state.participantVolumes));
  }

  Future<String?> _getSelectedAudioInputId() async {
    try {
      final devices = await Hardware.instance.audioInputs();
      return devices
          .firstWhere(
            (d) =>
                state.selectedAudioInputId != null &&
                state.selectedAudioInputId!.isNotEmpty &&
                d.deviceId == state.selectedAudioInputId,
            orElse: () => devices.isNotEmpty
                ? devices.first
                : throw Exception('No audio input devices found'),
          )
          .deviceId;
    } catch (e) {
      debugPrint('[voice] Failed to enumerate devices: $e');
    }
    return null;
  }

  Future<void> setOutputVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(outputVolume: clamped);
    await _applyOutputVolume();
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setDouble('voice_output_volume', clamped);
  }

  Future<void> setNoiseSuppression(bool value) async {
    state = state.copyWith(noiseSuppression: value);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_noise_suppression', value);
  }

  Future<void> setEchoCancellation(bool value) async {
    state = state.copyWith(echoCancellation: value);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_echo_cancellation', value);
  }

  Future<void> setAutoGainControl(bool value) async {
    state = state.copyWith(autoGainControl: value);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_auto_gain_control', value);
  }

  Future<void> setSelectedAudioInput(String? deviceId) async {
    if (state.selectedAudioInputId == deviceId) return;
    state = state.copyWith(selectedAudioInputId: deviceId);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString('voice_selected_audio_input_id', deviceId ?? '');
  }

  Future<void> selectAudioInput(String? deviceId) async {
    if (state.selectedAudioInputId == deviceId) return;
    state = state.copyWith(selectedAudioInputId: deviceId);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString('voice_selected_audio_input_id', deviceId ?? '');
    if (_voiceRoom != null && state.isInVoice) {
      final lp = _voiceRoom!.localParticipant;
      if (lp != null) {
        await lp.setMicrophoneEnabled(false);
        await lp.setMicrophoneEnabled(
          true,
          audioCaptureOptions: AudioCaptureOptions(
            deviceId: deviceId,
            noiseSuppression: state.noiseSuppression,
            echoCancellation: state.echoCancellation,
            autoGainControl: state.autoGainControl,
            processor: _liveKitDeepFilter.processor,
          ),
        );
      }
    }
  }

  Future<void> setDeepFilterEnabled(bool value) async {
    state = state.copyWith(deepFilterEnabled: value);
    final asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setBool('voice_deep_filter_enabled', value);
    if (value && _voiceRoom != null && state.isInVoice && !_liveKitDeepFilter.isEnabled) {
      await _liveKitDeepFilter.enable(enabled: true);
      final audioTrack = _voiceRoom!.localParticipant?.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .firstOrNull
          ?.track;
      if (audioTrack is LocalAudioTrack) {
        await _liveKitDeepFilter.attachToTrack(audioTrack);
      }
    } else {
      _liveKitDeepFilter.setEnabled(value);
    }
    state = state.copyWith(deepFilterIsApmAttached: _liveKitDeepFilter.isProcessing);
  }

  Future<void> setParticipantVolume(String identity, double volume, {TrackSource? source}) async {
    final clamped = volume.clamp(0.0, 2.0);
    final key = source != null ? '$identity:${source.name}' : identity;
    final newVolumes = Map<String, double>.from(state.participantVolumes);
    newVolumes[key] = clamped;
    state = state.copyWith(participantVolumes: newVolumes);
    await _saveParticipantVolumes();
    if (_voiceRoom != null && state.isInVoice) {
      final participant = _voiceRoom!.remoteParticipants[identity];
      if (participant != null) {
        for (final pub in participant.trackPublications.values) {
          if (pub.kind == TrackType.AUDIO && (source == null || pub.source == source)) {
            final track = pub.track;
            if (track is RemoteAudioTrack) {
              await NativeAudioManagement.setVolume(clamped, track.mediaStreamTrack);
            }
          }
        }
      }
    }
  }

  Future<void> _applyParticipantVolumes() async {
    if (_voiceRoom == null || !state.isInVoice) return;
    for (final entry in state.participantVolumes.entries) {
      final parts = entry.key.split(':');
      final identity = parts[0];
      final source = parts.length > 1
          ? TrackSource.values.where((s) => s.name == parts[1]).firstOrNull
          : null;
      final participant = _voiceRoom!.remoteParticipants[identity];
      if (participant != null) {
        for (final pub in participant.trackPublications.values) {
          if (pub.kind == TrackType.AUDIO && (source == null || pub.source == source)) {
            final track = pub.track;
            if (track is RemoteAudioTrack) {
              await NativeAudioManagement.setVolume(entry.value, track.mediaStreamTrack);
            }
          }
        }
      }
    }
  }

  Future<void> _applyOutputVolume() async {
    if (_voiceRoom == null || !state.isInVoice) return;
    for (final participant in _voiceRoom!.remoteParticipants.values) {
      for (final pub in participant.trackPublications.values) {
        if (pub.kind == TrackType.AUDIO) {
          final track = pub.track;
          if (track is RemoteAudioTrack) {
            await NativeAudioManagement.setVolume(state.outputVolume, track.mediaStreamTrack);
          }
        }
      }
    }
  }

  // -- Lifecycle -------------------------------------------------------------

  void _dispose() {
    _membershipSub?.cancel();
    _publishingSub?.cancel();
    _voiceRoom?.disconnect();
    _voiceRoomListener?.dispose();
    unawaited(_liveKitDeepFilter.disable());
  }
}

final voiceStateProvider = NotifierProvider<VoiceNotifier, VoiceStateData>(VoiceNotifier.new);

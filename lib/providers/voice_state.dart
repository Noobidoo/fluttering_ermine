import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';
import '../services/voice_event_service.dart';
import '../services/volume_helper.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

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

class VoiceState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;
  final VoiceEventService _voiceEventService;

  VoiceState(this._service, this._voiceEventService) {
    _loadSettings();
  }

  StreamSubscription<dynamic>? _membershipSub;
  StreamSubscription<VoicePublishingStateChangeEvent>? _publishingSub;

  Room? _voiceRoom;
  EventsListener<RoomEvent>? _voiceRoomListener;
  RevoltChannel? _activeVoiceChannel;
  bool _isInVoice = false;
  bool _isMuted = false;
  bool _isJoiningVoice = false;
  bool _isScreenSharing = false;
  // ignore: unused_field
  LocalVideoTrack? _screenShareTrack;
  String? _voiceError;

  // -- Voice channel membership (WS-sourced + LiveKit instant updates) -------
  final Map<String, List<String>> _voiceChannelMembers = {};
  final Map<String, bool> _voicePublishing = {};

  // -- Voice settings --------------------------------------------------------

  double _outputVolume = 1.0;
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _autoGainControl = true;
  String? _defaultAudioInputId;

  // -- DeepFilterNet noise suppression ---------------------------------------
  DeepFilterProcessor? _deepFilterProcessor;
  bool _deepFilterEnabled = true;

  // -- Per-participant screen share subscriptions -----------------------------
  final Set<String> _subscribedScreenShares = {};

  // -- Development/debugging only: expose LiveKit internals for diagnostics and testing --
  int _leaveCalledAmount = 0;

  // -- Getters ---------------------------------------------------------------

  RevoltChannel? get activeVoiceChannel => _activeVoiceChannel;
  bool get isInVoice => _isInVoice;
  bool get isMuted => _isMuted;
  bool get isJoiningVoice => _isJoiningVoice;
  bool get isScreenSharing => _isScreenSharing;
  String? get voiceError => _voiceError;
  double get outputVolume => _outputVolume;
  bool get noiseSuppression => _noiseSuppression;
  bool get echoCancellation => _echoCancellation;
  bool get autoGainControl => _autoGainControl;
  bool get deepFilterEnabled => _deepFilterEnabled;
  static bool get deepFilterSupported => DeepFilterProcessor.isSupported;
  static bool get deepFilterIsRealLibrary => DeepFilterProcessor.isRealLibrary;
  static bool get deepFilterIsApmAttached => DeepFilterProcessor.isApmAttached;

  // Returns true if the given participant's screen share is currently subscribed.
  bool isScreenShareSubscribed(String identity) => _subscribedScreenShares.contains(identity);

  // Returns true if the track should be auto-subscribed based on its source and the participant's identity.
  bool _shouldSubscribeTrack(RemoteTrackPublication publication) =>
      !publication.isScreenShare || isScreenShareSubscribed(publication.participant.identity);

  // Returns the list of userIds currently in the given voice channel, or null if the channel is not active.
  List<String> voiceParticipantsFor(String channelId) =>
      List.unmodifiable(_voiceChannelMembers[channelId] ?? []);

  /// Returns null if state unknown, true if mic active, false if muted.
  bool? voicePublishingFor(String userId) => _voicePublishing[userId];

  // Returns a list of active remote video streams in the current voice room.
  List<RemoteVideoStream> get remoteVideoStreams {
    if (_voiceRoom == null) return const [];
    final streams = <RemoteVideoStream>[];
    for (final p in _voiceRoom!.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        if (pub.track is VideoTrack &&
            (pub.source == TrackSource.camera ||
                pub.source == TrackSource.screenShareVideo)) {
          streams.add(RemoteVideoStream(
            track: pub.track as VideoTrack,
            participantIdentity: p.identity,
            source: pub.source,
          ));
        }
      }
    }
    return streams;
  }

  List<VoiceParticipant> get voiceParticipants {
    if (_voiceRoom == null) return const [];
    final result = <VoiceParticipant>[];
    final local = _voiceRoom!.localParticipant;
    if (local != null) {
      result.add(VoiceParticipant(
        identity: local.identity,
        name: local.name,
        isLocal: true,
        isMuted: _isMuted,
        isSpeaking: local.isSpeaking,
        isScreenSharing: _isScreenSharing,
      ));
    }
    for (final p in _voiceRoom!.remoteParticipants.values) {
      final audioMuted = p.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .every((pub) => pub.muted);
      final hasScreenShare = p.trackPublications.values.any((pub) => pub.isScreenShare);
      result.add(VoiceParticipant(
        identity: p.identity,
        name: p.name,
        isLocal: false,
        isMuted: audioMuted,
        isSpeaking: p.isSpeaking,
        isScreenSharing: hasScreenShare,
      ));
    }
    return result;
  }

  // -- Voice Event Subscription (via VoiceEventService) --------------------

  void subscribeToVoiceEvents() {
    _membershipSub?.cancel();
    _publishingSub?.cancel();
    _membershipSub = _voiceEventService.membershipEvents.listen(_handleMembershipEvent);
    _publishingSub = _voiceEventService.publishingEvents.listen(_handlePublishingEvent);
  }

  void _handleMembershipEvent(dynamic event) {
    if (event is VoiceChannelMembershipResetEvent) {
      _voiceChannelMembers
        ..clear()
        ..addAll(event.channelMembers);
      _voicePublishing
        ..clear()
        ..addAll(event.publishingState);
      debugPrint('[VoiceState] VoiceChannelMembershipReset: $_voiceChannelMembers');
      notifyListeners();
    } else if (event is VoiceChannelJoinEvent) {
      debugPrint('[VoiceState] VoiceChannelJoin channel=${event.channelId} user=${event.userId}');
      _voiceChannelMembers.putIfAbsent(event.channelId, () => []);
      if (!_voiceChannelMembers[event.channelId]!.contains(event.userId)) {
        _voiceChannelMembers[event.channelId]!.add(event.userId);
      }
      notifyListeners();
    } else if (event is VoiceChannelLeaveEvent) {
      debugPrint('[VoiceState] VoiceChannelLeave channel=${event.channelId} user=${event.userId}');
      if (event.channelId == null) {
        // null channelId signals removal from all channels
        for (final list in _voiceChannelMembers.values) {
          list.remove(event.userId);
        }
        _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);
      } else {
        _removeParticipant(event.channelId!, event.userId);
      }
      _voicePublishing.remove(event.userId);
      notifyListeners();
    } else if (event is VoiceChannelMoveEvent) {
      debugPrint('[VoiceState] VoiceChannelMove user=${event.userId} from=${event.fromChannelId} to=${event.toChannelId}');
      if (event.fromChannelId != null) {
        _removeParticipant(event.fromChannelId!, event.userId);
      }
      if (event.toChannelId != null) {
        _voiceChannelMembers.putIfAbsent(event.toChannelId!, () => []);
        if (!_voiceChannelMembers[event.toChannelId]!.contains(event.userId)) {
          _voiceChannelMembers[event.toChannelId]!.add(event.userId);
        }
      }
      notifyListeners();
    }
  }

  void _handlePublishingEvent(VoicePublishingStateChangeEvent event) {
    _voicePublishing[event.userId] = event.isPublishing;
    notifyListeners();
  }

  /// Removes [userId] from [channelId]'s participant list.
  /// Called by both WS leave events and LiveKit disconnect events.
  void _removeParticipant(String channelId, String userId) {
    _voiceChannelMembers[channelId]?.remove(userId);
    _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);
  }

  // -- Actions ---------------------------------------------------------------

  Future<void> joinVoiceChannel(RevoltChannel channel) async {
    if (_isJoiningVoice) return;

    // permission_handler has no Linux implementation; the OS handles mic
    // access natively (PipeWire/PulseAudio prompts when the stream opens).
    if (!defaultTargetPlatform.name.toLowerCase().contains('linux')) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        _voiceError = 'Microphone permission denied';
        notifyListeners();
        return;
      }
    }

    if (_voiceRoom != null) await leaveVoiceChannel();
    _isJoiningVoice = true;
    _voiceError = null;
    notifyListeners();
    try {
      final data = await _service.joinVoiceChannel(channel.id);
      var url = data['url'] as String;
      final token = data['token'] as String;
      // DEBUG: copy these into https://meet.livekit.io to join as a browser observer
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
          debugPrint('[voice:event] Channel ${channel.id} has ${e.room.remoteParticipants.length + (e.room.localParticipant != null ? 1 : 0)} participants');
          debugPrint('[voice:event] _voiceRoom assigned');
          _voiceError = null;
          _isInVoice = true;
          _isJoiningVoice = false;
          _voiceRoom = e.room;
          _activeVoiceChannel = channel;
          notifyListeners();
          debugPrint('[voice:event] RoomConnectedEvent handler complete');
        })
        ..on<RoomDisconnectedEvent>((e) {
          debugPrint('[voice:event] RoomDisconnectedEvent channel=${channel.id} reason=${e.reason}');
          final localId = room.localParticipant?.identity;
          if (localId != null) _removeParticipant(channel.id, localId);
          _voiceRoom = null;
          _activeVoiceChannel = null;
          _isInVoice = false;
          _isJoiningVoice = false;
          _isMuted = false;
          _isScreenSharing = false;
          _screenShareTrack = null;
          switch (e.reason) {
            case DisconnectReason.clientInitiated:
              _voiceError = null;
              break;
            case DisconnectReason.participantRemoved:
              _voiceError = 'Disconnected by server';
              break;
            case DisconnectReason.joinFailure:
            case DisconnectReason.signalingConnectionFailure:
              _voiceError = 'Network error';
              break;
            case DisconnectReason.reconnectAttemptsExceeded:
              _voiceError = 'Network error, reconnect attempts exceeded';
              break;
            case DisconnectReason.duplicateIdentity:
              _voiceError = 'Logged in elsewhere';
              break;
            case DisconnectReason.unknown:
            default:
              _voiceError = 'Disconnected from voice';
          }
          notifyListeners();
        })
        ..on<RoomReconnectingEvent>((e) {
          debugPrint('[voice:event] RoomReconnectingEvent room=${room.name}');
          _voiceError = 'Reconnecting...';
           _isJoiningVoice = true;
          notifyListeners();
        })
        ..on<RoomReconnectedEvent>((e) {
          debugPrint('[voice:event] RoomReconnectedEvent room=${room.name}');
          _voiceError = null;
          _isInVoice = true;
          _isJoiningVoice = false;
          notifyListeners();
        })
        ..on<TrackSubscribedEvent>((e) {
          debugPrint('[voice:event] TrackSubscribedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}');
          if (e.track is RemoteAudioTrack &&
              e.publication.source == TrackSource.screenShareAudio) {
            e.track.events.listen((trackEvent) {
              if (trackEvent is AudioReceiverStatsEvent) {
                final s = trackEvent.stats;
                debugPrint('[voice:rx] screen audio | '
                    '${trackEvent.currentBitrate.toStringAsFixed(1)} kbps | '
                    'jitter=${s.jitter?.toStringAsFixed(4) ?? '-'} | '
                    'lost=${s.packetsLost ?? '-'} | '
                    'concealed=${s.concealedSamples ?? '-'} '
                    '(${s.concealmentEvents ?? '-'} events) | '
                    'audioEnergy=${s.totalAudioEnergy?.toStringAsFixed(4) ?? '-'} | '
                    'track.enabled=${e.track.mediaStreamTrack.enabled}');
              }
            });
          }
          notifyListeners();
        })
        ..on<TrackUnsubscribedEvent>((e) {
          debugPrint('[voice:event] TrackUnsubscribedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}');
          notifyListeners();
        })
        ..on<TrackPublishedEvent>((e) {
          final willSubscribe = _shouldSubscribeTrack(e.publication);
          if (willSubscribe) {
            e.publication.subscribe();
          }
          notifyListeners();
        })
        ..on<TrackUnpublishedEvent>((e) {
          debugPrint('[voice:event] TrackUnpublishedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}');
          notifyListeners();
        })
        ..on<TrackMutedEvent>((e) {
          debugPrint('[voice:event] TrackMutedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}');
          notifyListeners();
        })
        ..on<TrackUnmutedEvent>((e) {
          debugPrint('[voice:event] TrackUnmutedEvent participant=${e.participant.identity} kind=${e.publication.kind} source=${e.publication.source}');
          notifyListeners();
        })
        ..on<TrackSubscriptionExceptionEvent>((e) {
          debugPrint('[voice:event] TrackSubscriptionExceptionEvent participant=${e.participant?.identity} sid=${e.sid} reason=${e.reason}');
          notifyListeners();
        })
        ..on<ParticipantConnectedEvent>((e) { debugPrint('[voice:event] ParticipantConnectedEvent id=${e.participant.identity}'); notifyListeners(); })
        ..on<ParticipantDisconnectedEvent>((e) {
            debugPrint('[voice:event] ParticipantDisconnectedEvent id=${e.participant.identity} remaining=${_voiceRoom?.remoteParticipants.length}');
            _removeParticipant(channel.id, e.participant.identity);
            notifyListeners();
          })
        ..on<ActiveSpeakersChangedEvent>((_) => notifyListeners());

      await room.connect(url, token, connectOptions: const ConnectOptions(autoSubscribe: false));
      _isMuted = false;
      final lp = room.localParticipant;
      if (lp == null) {
        debugPrint('[voice] localParticipant is null after connect');
        throw Exception('Failed to get local participant');
      }
      debugPrint('[voice] localParticipant identity=${lp.identity}');
      // Enumerate devices first to get the default mic deviceId
      // TODO: remove deviceId workaround once flutter-webrtc#2071 is resolved
      _defaultAudioInputId = await _getDefaultAudioInputId();
      // Enable mic before subscribing to ensure ADM is fully initialized before
      // remote audio sinks are wired up.
      try {
         await lp.setMicrophoneEnabled(
           true,
           audioCaptureOptions: AudioCaptureOptions(
                   deviceId: _defaultAudioInputId,
                   noiseSuppression: _noiseSuppression,
                   echoCancellation: _echoCancellation,
                   autoGainControl: _autoGainControl,
                 ),
         );
         debugPrint('[voice] mic enabled, published tracks: ${lp.trackPublications.length}');
       } catch (micErr) {
         debugPrint('[voice] mic enable failed: $micErr');
         _voiceError = 'Failed to access microphone';
      }
      _subscribeInitialTracks();
      // Apply stored output volume to any already-connected remote participants
      _applyOutputVolume();
      // Attach DeepFilterNet neural noise suppression
      if (_deepFilterEnabled) {
        await _attachDeepFilter();
      }
    } catch (e) {
      debugPrint('[voice] join failed: $e');
      _voiceError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isJoiningVoice = false;
      notifyListeners();
    }
  }

  Future<void> leaveVoiceChannel() async {
    debugPrint('[voice:leave] leaveVoiceChannel called, room=${_voiceRoom?.name}');
    _leaveCalledAmount++;
    debugPrint('[voice:leave] _leaveCalledAmount=$_leaveCalledAmount');
    // Stop screen share BEFORE disconnecting so the loopback capturer is
    // cleanly shut down before the peer connection tears down the AudioSendStream.
    if (_isScreenSharing && _voiceRoom?.localParticipant != null) {
      try {
        await _voiceRoom!.localParticipant!.setScreenShareEnabled(false);
      } catch (_) {}
      _isScreenSharing = false;
      _screenShareTrack = null;
    }
    // Detach DeepFilterNet processor before tearing down the connection
    await _detachDeepFilter();

    try {
      await _voiceRoom?.disconnect();
      debugPrint('[voice:leave] disconnect() returned');
    } catch (e) {
      debugPrint('[voice:leave] disconnect failed: $e');
    }
    await _voiceRoomListener?.dispose();
    _voiceRoomListener = null;
    _voiceRoom = null;
    _activeVoiceChannel = null;
    _isInVoice = false;
    _isJoiningVoice = false;
    _isMuted = false;
    _isScreenSharing = false;
    _screenShareTrack = null;
    _voiceError = null;
    _leaveCalledAmount = 0;
    notifyListeners();
  }

  /// Subscribes or unsubscribes from [identity]'s screen share.
  void toggleScreenShareSubscription(String identity) {
    if (_subscribedScreenShares.contains(identity)) {
      _subscribedScreenShares.remove(identity);
      _unsubscribeScreenShare(identity);
    } else {
      _subscribedScreenShares.add(identity);
      _subscribeScreenShare(identity);
    }
    notifyListeners();
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
    debugPrint('[voice:subscribe] _subscribeInitialTracks: ${_voiceRoom!.remoteParticipants.length} remote participants');
    for (final p in _voiceRoom!.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        final shouldSub = _shouldSubscribeTrack(pub);
        if (shouldSub) {
          pub.subscribe();
        }
      }
    }
  }

  Future<void> toggleMute() async {
    if (_voiceRoom == null) return;
    _isMuted = !_isMuted;
    await _voiceRoom!.localParticipant?.setMicrophoneEnabled(!_isMuted);
    notifyListeners();
  }

  Future<void> startDesktopScreenShare(String sourceId) async {
    if (_voiceRoom?.localParticipant == null) return;
    try {
      final tracks = await LocalVideoTrack.createScreenShareTracksWithAudio(
        ScreenShareCaptureOptions(
          sourceId: sourceId,
          captureScreenAudio: true,
          maxFrameRate: 15.0,
        ),
      );
      _screenShareTrack = null;
      final publishFutures = <Future>[];
      for (final track in tracks) {
        if (track is LocalVideoTrack) {
          _screenShareTrack = track;
          publishFutures.add(
            _voiceRoom!.localParticipant!.publishVideoTrack(track),
          );
        } else if (track is LocalAudioTrack) {
          track.events.listen((event) {
            if (event is AudioSenderStatsEvent) {
              final level = event.stats.audioSourceStats?.audioLevel ?? 0.0;
              debugPrint('[voice] screen audio: '
                  '${event.currentBitrate.toStringAsFixed(1)} kbps, '
                  'level=${level.toStringAsFixed(3)}');
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
      _isScreenSharing = true;
    } catch (e) {
      debugPrint('[voice] screen share failed: $e');
      _screenShareTrack = null;
      _voiceError = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    if (_voiceRoom?.localParticipant == null) return;
    try {
      await _voiceRoom!.localParticipant!.setScreenShareEnabled(false);
      _screenShareTrack = null;
      _isScreenSharing = false;
    } catch (e) {
      debugPrint('[voice] stop screen share failed: $e');
      _voiceError = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  /// Used for non-desktop platforms (mobile/web) where no source picker is needed.
  Future<void> toggleScreenShare() async {
    if (_voiceRoom?.localParticipant == null) return;
    _isScreenSharing = !_isScreenSharing;
    try {
      await _voiceRoom!.localParticipant!.setScreenShareEnabled(
        _isScreenSharing,
        screenShareCaptureOptions: _isScreenSharing
            ? const ScreenShareCaptureOptions(captureScreenAudio: true)
            : null,
      );
    } catch (e) {
      debugPrint('[voice] screen share failed: $e');
      _isScreenSharing = !_isScreenSharing;
      _voiceError = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  Future<void> clear() async {
    await _detachDeepFilter();
    await _voiceRoom?.disconnect();
    await _voiceRoomListener?.dispose();
    _voiceRoomListener = null;
    _voiceRoom = null;
    _activeVoiceChannel = null;
    _isInVoice = false;
    _isMuted = false;
    _isJoiningVoice = false;
    _isScreenSharing = false;
    _screenShareTrack = null;
    _voiceError = null;
    _subscribedScreenShares.clear();
    notifyListeners();
  }

  // -- Settings ------------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _outputVolume = prefs.getDouble('voice_output_volume') ?? 1.0;
    _noiseSuppression = prefs.getBool('voice_noise_suppression') ?? true;
    _echoCancellation = prefs.getBool('voice_echo_cancellation') ?? true;
    _autoGainControl = prefs.getBool('voice_auto_gain_control') ?? true;
    _deepFilterEnabled = prefs.getBool('voice_deep_filter_enabled') ?? true;
    notifyListeners();
  }

  void _applyOutputVolume() {
    applyLiveKitVolume(_outputVolume);
  }

  Future<String?> _getDefaultAudioInputId() async {
    try {
      final devices = await rtc.navigator.mediaDevices.enumerateDevices();
      for (final d in devices) {
        if (d.kind == 'audioinput') return d.deviceId;
      }
    } catch (e) {
      debugPrint('[voice] Failed to enumerate devices: $e');
    }

    return null;
  }

  Future<void> setOutputVolume(double volume) async {
    _outputVolume = volume.clamp(0.0, 1.0);
    _applyOutputVolume();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voice_output_volume', volume);
    notifyListeners();
  }

  Future<void> setNoiseSuppression(bool value) async {
    _noiseSuppression = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_noise_suppression', value);
    notifyListeners();
  }

  Future<void> setEchoCancellation(bool value) async {
    _echoCancellation = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_echo_cancellation', value);
    notifyListeners();
  }

  Future<void> setAutoGainControl(bool value) async {
    _autoGainControl = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_auto_gain_control', value);
    notifyListeners();
  }

  Future<void> setDeepFilterEnabled(bool value) async {
    _deepFilterEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_deep_filter_enabled', value);
    if (_deepFilterProcessor != null) {
      // APM hook is already attached — toggle instantly via the atomic flag
      _deepFilterProcessor!.setEnabled(value);
    } else if (_voiceRoom != null && _isInVoice && value) {
      // Not yet attached (e.g. was disabled on join) — attach now
      await _attachDeepFilter();
    }
    notifyListeners();
  }

  Future<void> _attachDeepFilter() async {
    debugPrint('[voice:df] _attachDeepFilter enter');
    if (_deepFilterProcessor != null) {
      debugPrint('[voice:df] _attachDeepFilter: already attached, skipping');
      return;
    }
    debugPrint('[voice:df] _attachDeepFilter: isSupported=${DeepFilterProcessor.isSupported}');
    if (!DeepFilterProcessor.isSupported) return;
    try {
      final audioPub = _voiceRoom?.localParticipant?.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .firstOrNull;
      debugPrint('[voice:df] _attachDeepFilter: audioPub=$audioPub isAudioTrack=${audioPub?.track is LocalAudioTrack}');
      if (audioPub?.track is LocalAudioTrack) {
        debugPrint('[voice:df] _attachDeepFilter: about to create DeepFilterProcessor');
        _deepFilterProcessor = DeepFilterProcessor(enabled: true);
        debugPrint('[voice:df] _attachDeepFilter: processor created, about to setProcessor');
        await (audioPub!.track as LocalAudioTrack)
            .setProcessor(_deepFilterProcessor!);
        // setProcessor on an already-published track does not call onPublish,
        // so the processor's _published flag stays false and setApmEnabled is
        // never invoked. Call onPublish explicitly to activate processing.
        if (!_deepFilterProcessor!.isProcessing && _voiceRoom != null) {
          await _deepFilterProcessor!.onPublish(_voiceRoom!);
        }
        debugPrint('[voice:df] _attachDeepFilter: processor attached to track');
      } else {
        debugPrint('[voice:df] _attachDeepFilter: no audio track found');
      }
    } catch (e, st) {
      debugPrint('[voice:df] _attachDeepFilter: FAILED: $e');
      debugPrint('[voice:df] _attachDeepFilter: stack: $st');
    }
    debugPrint('[voice:df] _attachDeepFilter: exit');
  }

  Future<void> _detachDeepFilter() async {
    if (_deepFilterProcessor == null) return;
    try {
      final audioPub = _voiceRoom?.localParticipant?.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .firstOrNull;
      if (audioPub?.track is LocalAudioTrack) {
        await (audioPub!.track as LocalAudioTrack).setProcessor(null);
      }
    } catch (e) {
      debugPrint('[voice] DeepFilterNet detach failed: $e');
    }
    await _deepFilterProcessor?.destroy();
    _deepFilterProcessor = null;
    debugPrint('[voice] DeepFilterNet processor detached');
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    _publishingSub?.cancel();
    _voiceRoom?.disconnect();
    _voiceRoomListener?.dispose();
    _subscribedScreenShares.clear();
    _detachDeepFilter();
    super.dispose();
  }
}

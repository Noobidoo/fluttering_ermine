import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/revolt_service.dart';
import '../services/volume_helper.dart';

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
  const VoiceParticipant({
    required this.identity,
    this.name,
    required this.isLocal,
    required this.isMuted,
    this.isSpeaking = false,
  });

  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    return identity;
  }
}

class VoiceState extends ChangeNotifier with DiagnosticableTreeMixin {
  final RevoltService _service;

  VoiceState(this._service) {
    _loadSettings();
  }

  StreamSubscription<Map<String, dynamic>>? _wsSub;

  Room? _voiceRoom;
  EventsListener<RoomEvent>? _voiceRoomListener;
  RevoltChannel? _activeVoiceChannel;
  bool _isInVoice = false;
  bool _isMuted = false;
  bool _isJoiningVoice = false;
  bool _isScreenSharing = false;
  LocalVideoTrack? _screenShareTrack;
  bool _leavingIntentionally = false;
  String? _voiceError;

  // -- Voice channel membership (WS-sourced + LiveKit instant updates) -------
  final Map<String, List<String>> _voiceChannelMembers = {};
  final Map<String, bool> _voicePublishing = {};

  // -- Voice settings --------------------------------------------------------

  double _outputVolume = 1.0;
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _autoGainControl = true;

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

  List<String> voiceParticipantsFor(String channelId) =>
      List.unmodifiable(_voiceChannelMembers[channelId] ?? []);

  /// Returns null if state unknown, true if mic active, false if muted.
  bool? voicePublishingFor(String userId) => _voicePublishing[userId];

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
      ));
    }
    for (final p in _voiceRoom!.remoteParticipants.values) {
      final audioMuted = p.trackPublications.values
          .where((pub) => pub.kind == TrackType.AUDIO)
          .every((pub) => pub.muted);
      result.add(VoiceParticipant(
        identity: p.identity,
        name: p.name,
        isLocal: false,
        isMuted: audioMuted,
        isSpeaking: p.isSpeaking,
      ));
    }
    return result;
  }

  // -- WebSocket ------------------------------------------------------------

  void subscribeToEvents() {
    _wsSub?.cancel();
    _wsSub = _service.events.listen(_handleWsEvent);
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    switch (event['type'] as String?) {
      case 'Ready':
        _onWsReady(event);
      case 'VoiceChannelJoin':
        _onVoiceChannelJoin(event);
      case 'VoiceChannelLeave':
        _onVoiceChannelLeave(event);
      case 'VoiceChannelMove':
        _onVoiceChannelMove(event);
      case 'UserVoiceStateUpdate':
        _onUserVoiceStateUpdate(event);
      case 'ServerMemberUpdate':
        _onMemberUpdate(event);
    }
  }

  void _onWsReady(Map<String, dynamic> event) {
    _voiceChannelMembers.clear();
    _voicePublishing.clear();
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
        _voiceChannelMembers.putIfAbsent(channelId, () => []);
        if (!_voiceChannelMembers[channelId]!.contains(userId)) {
          _voiceChannelMembers[channelId]!.add(userId);
        }
        if (isPublishing != null) _voicePublishing[userId] = isPublishing;
      }
    }
    debugPrint('[VoiceState] voiceChannelMembers after Ready: $_voiceChannelMembers');
    notifyListeners();
  }

  void _onVoiceChannelJoin(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final state = event['state'] as Map<String, dynamic>?;
    final userId = state?['id'] as String?;
    debugPrint('[VoiceState] VoiceChannelJoin channel=$channelId user=$userId');
    if (channelId == null || userId == null) return;
    _voiceChannelMembers.putIfAbsent(channelId, () => []);
    if (!_voiceChannelMembers[channelId]!.contains(userId)) {
      _voiceChannelMembers[channelId]!.add(userId);
    }
    notifyListeners();
  }

  void _onVoiceChannelLeave(Map<String, dynamic> event) {
    final channelId = event['id'] as String?;
    final userId = event['user'] as String?;
    debugPrint('[VoiceState] VoiceChannelLeave channel=$channelId user=$userId');
    if (channelId == null || userId == null) return;
    _removeParticipant(channelId, userId);
    _voicePublishing.remove(userId);
    notifyListeners();
  }

  void _onVoiceChannelMove(Map<String, dynamic> event) {
    final userId = event['user'] as String?;
    final from = event['from'] as String?;
    final to = event['to'] as String?;
    debugPrint('[VoiceState] VoiceChannelMove user=$userId from=$from to=$to');
    if (userId == null) return;
    if (from != null) _removeParticipant(from, userId);
    if (to != null) {
      _voiceChannelMembers.putIfAbsent(to, () => []);
      if (!_voiceChannelMembers[to]!.contains(userId)) {
        _voiceChannelMembers[to]!.add(userId);
      }
    }
    notifyListeners();
  }

  void _onUserVoiceStateUpdate(Map<String, dynamic> event) {
    final userId = event['id'] as String?;
    final data = event['data'] as Map<String, dynamic>?;
    if (userId == null || data == null) return;
    final isPublishing = data['is_publishing'] as bool?;
    if (isPublishing != null) _voicePublishing[userId] = isPublishing;
    notifyListeners();
  }

  void _onMemberUpdate(Map<String, dynamic> event) {
    final id = event['id'] as Map<String, dynamic>?;
    final userId = id?['user'] as String?;
    if (userId == null) return;
    _voiceChannelMembers.forEach((_, list) => list.remove(userId));
    _voiceChannelMembers.removeWhere((_, list) => list.isEmpty);
    final clear = (event['clear'] as List<dynamic>?)?.cast<String>() ?? [];
    if (clear.contains('VoiceChannel')) {
      notifyListeners();
      return;
    }
    final data = event['data'] as Map<String, dynamic>?;
    final newChannel = data?['voice_channel'] as String?;
    if (newChannel != null) {
      _voiceChannelMembers.putIfAbsent(newChannel, () => []).add(userId);
    }
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
    _leavingIntentionally = false;
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
        ..on<TrackUnsubscribedEvent>((_) { debugPrint('[voice:event] TrackUnsubscribedEvent'); notifyListeners(); })
        ..on<ParticipantConnectedEvent>((e) { debugPrint('[voice:event] ParticipantConnectedEvent id=${e.participant.identity}'); notifyListeners(); })
        ..on<ParticipantDisconnectedEvent>((e) {
            debugPrint('[voice:event] ParticipantDisconnectedEvent id=${e.participant.identity} remaining=${_voiceRoom?.remoteParticipants.length}');
            _removeParticipant(channel.id, e.participant.identity);
            notifyListeners();
          })
        ..on<ActiveSpeakersChangedEvent>((_) => notifyListeners());

      await room.connect(url, token);
      debugPrint('[voice] room.connect() returned, isInVoice=$_isInVoice');
      _isMuted = false;
      final lp = room.localParticipant;
      if (lp == null) {
        debugPrint('[voice] localParticipant is null after connect');
        throw Exception('Failed to get local participant');
      }
      debugPrint('[voice] localParticipant identity=${lp.identity}, enabling mic...');
      // try {
      //   await lp.setMicrophoneEnabled(
      //     true,
      //     audioCaptureOptions: AudioCaptureOptions(
      //             noiseSuppression: _noiseSuppression,
      //             echoCancellation: _echoCancellation,
      //             autoGainControl: _autoGainControl,
      //           ),
      //   );
      //   debugPrint('[voice] mic enabled, published tracks: ${lp.trackPublications.length}');
      // } catch (micErr) {
      //   debugPrint('[voice] mic enable failed: $micErr');
      // }
      // Apply stored output volume to any already-connected remote participants
      //_applyOutputVolume();
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
    await _voiceRoom?.disconnect();
    debugPrint('[voice:leave] disconnect() returned');
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
      for (final track in tracks) {
        if (track is LocalVideoTrack) {
          _screenShareTrack = track;
          await _voiceRoom!.localParticipant!.publishVideoTrack(track);
        } else if (track is LocalAudioTrack) {
          await _voiceRoom!.localParticipant!.publishAudioTrack(
            track,
            publishOptions: const AudioPublishOptions(
              encoding: AudioEncoding.presetMusicHighQualityStereo,
              dtx: false,
            ),
          );
          // Log audio bitrate every stats cycle to diagnose quality issues.
          track.events.listen((event) {
            if (event is AudioSenderStatsEvent) {
              final level = event.stats.audioSourceStats?.audioLevel ?? 0.0;
              debugPrint('[voice] screen audio: '
                  '${event.currentBitrate.toStringAsFixed(1)} kbps, '
                  'level=${level.toStringAsFixed(3)}');
            }
          });
        }
      }
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
    notifyListeners();
  }

  // -- Settings ------------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _outputVolume = prefs.getDouble('voice_output_volume') ?? 1.0;
    _noiseSuppression = prefs.getBool('voice_noise_suppression') ?? true;
    _echoCancellation = prefs.getBool('voice_echo_cancellation') ?? true;
    _autoGainControl = prefs.getBool('voice_auto_gain_control') ?? true;
    notifyListeners();
  }

  void _applyOutputVolume() {
    applyLiveKitVolume(_outputVolume);
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

  @override
  void dispose() {
    _wsSub?.cancel();
    _voiceRoom?.disconnect();
    _voiceRoomListener?.dispose();
    super.dispose();
  }
}

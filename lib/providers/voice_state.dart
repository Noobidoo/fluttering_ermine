import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
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

  Room? _voiceRoom;
  EventsListener<RoomEvent>? _voiceRoomListener;
  RevoltChannel? _activeVoiceChannel;
  bool _isInVoice = false;
  bool _isMuted = false;
  bool _isJoiningVoice = false;
  bool _isScreenSharing = false;
  bool _leavingIntentionally = false;
  String? _voiceError;

  // ── Voice settings ────────────────────────────────────────────────────────

  double _outputVolume = 1.0;
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _autoGainControl = true;

  // ── Getters ───────────────────────────────────────────────────────────────

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

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> joinVoiceChannel(RevoltChannel channel) async {
    if (_isJoiningVoice) return;
    if (_voiceRoom != null) await leaveVoiceChannel();
    _leavingIntentionally = false;
    _isJoiningVoice = true;
    _voiceError = null;
    notifyListeners();
    try {
      final data = await _service.joinVoiceChannel(channel.id);
      var url = data['url'] as String;
      final token = data['token'] as String;
      if (url.startsWith('https://')) {
        url = 'wss://${url.substring(8)}';
      } else if (url.startsWith('http://')) {
        url = 'ws://${url.substring(7)}';
      }
      final room = Room();
      _voiceRoomListener = room.createListener();
      _voiceRoomListener!
        ..on<RoomConnectedEvent>((e) {
          debugPrint('[voice] connected to room ${room.name}');
          _voiceError = null;
          _isInVoice = true;
          _isJoiningVoice = false;
          _voiceRoom = e.room;
          _activeVoiceChannel = channel;
          notifyListeners();
        })
        ..on<RoomDisconnectedEvent>((e) {
          debugPrint('[voice] disconnected from room ${_voiceRoom?.name}');
          _voiceRoom = null;
          _activeVoiceChannel = null;
          _isInVoice = false;
          _isJoiningVoice = false;
          _isMuted = false;
          _isScreenSharing = false;
          if (!_leavingIntentionally) {
            _voiceError = 'Disconnected from voice';
          } else {
            _voiceError = null;
          }
          notifyListeners();
        })
        ..on<RoomReconnectingEvent>((e) {
          debugPrint('[voice] reconnecting to room ${room.name}...');
          _voiceError = 'Reconnecting...';
          _isJoiningVoice = true;
          notifyListeners();
        })
        ..on<RoomReconnectedEvent>((e) {
          debugPrint('[voice] reconnected to room ${room.name}');
          _voiceError = null;
          _isInVoice = true;
          _isJoiningVoice = false;
          notifyListeners();
        })
        ..on<TrackSubscribedEvent>((_) => notifyListeners())
        ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
        ..on<ParticipantConnectedEvent>((_) => notifyListeners())
        ..on<ParticipantDisconnectedEvent>((_) => notifyListeners())
        ..on<ActiveSpeakersChangedEvent>((_) => notifyListeners());

      await room.connect(url, token);
      _isMuted = false;
      await room.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: AudioCaptureOptions(
          noiseSuppression: _noiseSuppression,
          echoCancellation: _echoCancellation,
          autoGainControl: _autoGainControl,
        ),
      );
      // Apply stored output volume to any already-connected remote participants
      _applyOutputVolume();
    } catch (e) {
      debugPrint('[voice] join failed: $e');
      _voiceError = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isJoiningVoice = false;
      notifyListeners();
    }
  }

  Future<void> leaveVoiceChannel() async {
    _leavingIntentionally = true;
    await _voiceRoom?.disconnect(); // fires RoomDisconnectedEvent → resets state + notifyListeners
    await _voiceRoomListener?.dispose();
    _voiceRoomListener = null;
    // _leavingIntentionally stays true until next joinVoiceChannel
  }

  Future<void> toggleMute() async {
    if (_voiceRoom == null) return;
    _isMuted = !_isMuted;
    await _voiceRoom!.localParticipant?.setMicrophoneEnabled(!_isMuted);
    notifyListeners();
  }

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
    _voiceError = null;
    notifyListeners();
  }

  // ── Settings ────────────────────────────────────────────────────────────

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
    _voiceRoom?.disconnect();
    _voiceRoomListener?.dispose();
    super.dispose();
  }
}

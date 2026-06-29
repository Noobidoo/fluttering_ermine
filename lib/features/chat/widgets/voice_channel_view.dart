import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../models/revolt_channel.dart';
import '../../voice/providers/voice_notifier.dart';

class VoiceTabBar extends StatelessWidget {
  final bool showVoice;
  final ValueChanged<bool> onToggle;

  const VoiceTabBar({super.key, required this.showVoice, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    const active = Color(0xFF7F5AF0);
    const inactive = Color(0xFF2A2A30);
    const textActive = Colors.white;
    const textInactive = Colors.white38;

    return Container(
      height: 36,
      color: const Color(0xFF16161A),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(true),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: showVoice ? active : inactive, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 14,
                      color: showVoice ? active : textInactive,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Voice',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: showVoice ? textActive : textInactive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(false),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: !showVoice ? active : inactive, width: 2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag, size: 14, color: !showVoice ? active : textInactive),
                    const SizedBox(width: 6),
                    Text(
                      'Chat',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: !showVoice ? textActive : textInactive,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceChannelView extends ConsumerWidget {
  final RevoltChannel channel;

  const VoiceChannelView(this.channel, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceStateProvider);
    final isActive = voice.activeVoiceChannel?.id == channel.id;
    final streams = isActive ? voice.remoteVideoStreams : <RemoteVideoStream>[];
    final localCameraTrack = isActive ? voice.localCameraTrack : null;

    Widget controls;
    if (isActive) {
      controls = Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => ref.read(voiceStateProvider.notifier).toggleMute(),
            icon: Icon(voice.isMuted ? Icons.mic_off : Icons.mic),
            label: Text(voice.isMuted ? 'Unmute' : 'Mute'),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isMuted ? Colors.redAccent : const Color(0xFF2CB67D),
            ),
          ),
          FilledButton.icon(
            onPressed: () => ref.read(voiceStateProvider.notifier).toggleCamera(),
            icon: Icon(voice.isCameraEnabled ? Icons.videocam_off : Icons.videocam),
            label: Text(voice.isCameraEnabled ? 'Camera Off' : 'Camera On'),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isCameraEnabled ? Colors.redAccent : const Color(0xFF2CB67D),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final notifier = ref.read(voiceStateProvider.notifier);
              if (voice.isScreenSharing) {
                notifier.stopScreenShare();
                return;
              }
              if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
                final dynamic source = await showDialog(
                  context: context,
                  builder: (context) => ScreenSelectDialog(),
                );
                if (source == null) return;
                notifier.startDesktopScreenShare(source.id as String);
              } else {
                notifier.toggleScreenShare();
              }
            },
            icon: Icon(voice.isScreenSharing ? Icons.stop_screen_share : Icons.screen_share),
            label: Text(voice.isScreenSharing ? 'Stop Sharing' : 'Share Screen'),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isScreenSharing
                  ? Colors.orangeAccent
                  : const Color(0xFF7F5AF0),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => ref.read(voiceStateProvider.notifier).leaveVoiceChannel(),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
          ),
        ],
      );
    } else if (voice.isJoiningVoice) {
      controls = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Connecting…', style: TextStyle(color: Colors.white38)),
        ],
      );
    } else {
      controls = FilledButton.icon(
        onPressed: () => ref.read(voiceStateProvider.notifier).joinVoiceChannel(channel),
        icon: const Icon(Icons.call),
        label: const Text('Join Voice'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2CB67D),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
      );
    }

    return Column(
      children: [
        if (streams.isNotEmpty)
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  _VideoGrid(streams: streams),
                  if (localCameraTrack != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SizedBox(
                        width: 160,
                        height: 90,
                        child: _LocalVideoTile(track: localCameraTrack),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? Icons.graphic_eq : Icons.volume_up_rounded,
                  size: 72,
                  color: isActive ? const Color(0xFF2CB67D) : Colors.white12,
                ),
                const SizedBox(height: 16),
                Text(
                  isActive ? 'You are in this channel' : 'Voice Channel',
                  style: TextStyle(
                    fontSize: 18,
                    color: isActive ? const Color(0xFF2CB67D) : Colors.white38,
                  ),
                ),
                const SizedBox(height: 24),
                if (voice.voiceError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      voice.voiceError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                controls,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final List<RemoteVideoStream> streams;
  const _VideoGrid({required this.streams});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = streams.length <= 1
        ? 1
        : streams.length <= 4
        ? 2
        : 3;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: streams.length,
      itemBuilder: (_, i) => _RemoteVideoTile(stream: streams[i]),
    );
  }
}

class _LocalVideoTile extends StatelessWidget {
  final LocalVideoTrack track;
  const _LocalVideoTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoTrackRenderer(track),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'You (mirrored)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteVideoTile extends ConsumerWidget {
  final RemoteVideoStream stream;
  const _RemoteVideoTile({required this.stream});

  void _showVolumeMenu(BuildContext context, WidgetRef ref) {
    final voice = ref.read(voiceStateProvider);
    final notifier = ref.read(voiceStateProvider.notifier);
    final identity = stream.participantIdentity;
    final audioSource = stream.source == TrackSource.screenShareVideo
        ? TrackSource.screenShareAudio
        : TrackSource.microphone;
    final currentVolume = voice.getParticipantVolume(identity, source: audioSource);
    double tempVolume = currentVolume;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      stream.source == TrackSource.screenShareVideo
                          ? Icons.screen_share
                          : Icons.videocam,
                      size: 18,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        identity,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Volume Level',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.volume_down_rounded, size: 18, color: Colors.white38),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        ),
                        child: Slider(
                          value: tempVolume,
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          onChanged: (v) {
                            setDialogState(() => tempVolume = v);
                            notifier.setParticipantVolume(identity, v, source: audioSource);
                          },
                          activeColor: const Color(0xFF7F5AF0),
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded, size: 18, color: Colors.white38),
                  ],
                ),
                Center(
                  child: Text(
                    '${(tempVolume * 100).round()}%',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setDialogState(() => tempVolume = 1.0);
                      notifier.setParticipantVolume(identity, 1.0, source: audioSource);
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset to 100%'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isScreen = stream.source == TrackSource.screenShareVideo;
    return GestureDetector(
      onSecondaryTapDown: (_) => _showVolumeMenu(context, ref),
      onLongPress: () => _showVolumeMenu(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoTrackRenderer(stream.track),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isScreen ? Icons.screen_share : Icons.videocam,
                      size: 14,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        stream.participantIdentity,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

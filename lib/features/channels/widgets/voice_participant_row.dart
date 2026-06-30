import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../voice/providers/voice_notifier.dart';

class VoiceParticipantRow extends ConsumerWidget {
  final String identity;
  final String displayName;
  final bool isLocal;
  final bool? isMuted;
  final bool isSpeaking;
  final bool isScreenSharing;
  final String? avatarUrl;

  const VoiceParticipantRow({
    super.key,
    required this.identity,
    required this.displayName,
    required this.isLocal,
    this.isMuted,
    this.isSpeaking = false,
    this.isScreenSharing = false,
    this.avatarUrl,
  });

  void _showVolumeMenu(BuildContext context, WidgetRef ref) {
    final voice = ref.read(voiceStateProvider);
    final notifier = ref.read(voiceStateProvider.notifier);
    final currentVolume = voice.getParticipantVolume(
      identity,
      source: TrackSource.microphone,
    );
    double tempVolume = currentVolume;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayName,
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
                  'Microphone Level',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.volume_down_rounded,
                      size: 18,
                      color: Colors.white38,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(ctx).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: tempVolume,
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          onChanged: (v) {
                            setDialogState(() => tempVolume = v);
                            notifier.setParticipantVolume(
                              identity,
                              v,
                              source: TrackSource.microphone,
                            );
                          },
                          activeColor: const Color(0xFF7F5AF0),
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.volume_up_rounded,
                      size: 18,
                      color: Colors.white38,
                    ),
                  ],
                ),
                Center(
                  child: Text(
                    '${(tempVolume * 100).round()}%',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setDialogState(() => tempVolume = 1.0);
                        notifier.setParticipantVolume(
                          identity,
                          1.0,
                          source: TrackSource.microphone,
                        );
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Reset'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                      ),
                    ),
                    if (isMuted != null)
                      TextButton.icon(
                        onPressed: () {
                          notifier.setParticipantVolume(
                            identity,
                            isMuted! ? tempVolume.clamp(0.01, 2.0) : 0.0,
                            source: TrackSource.microphone,
                          );
                          Navigator.pop(ctx);
                        },
                        icon: Icon(
                          isMuted == true ? Icons.mic : Icons.mic_off,
                          size: 14,
                        ),
                        label: Text(isMuted == true ? 'Unmute' : 'Mute'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white60,
                        ),
                      ),
                  ],
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
    final notifier = ref.read(voiceStateProvider.notifier);
    final voiceData = ref.read(voiceStateProvider);
    const speakingColor = Color(0xFF2CB67D);
    return GestureDetector(
      onSecondaryTapDown: (_) => _showVolumeMenu(context, ref),
      onLongPress: () => _showVolumeMenu(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSpeaking ? speakingColor : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSpeaking
                    ? [
                        BoxShadow(
                          color: speakingColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: 10,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl!)
                    : null,
                backgroundColor: const Color(0xFF7F5AF0),
                onBackgroundImageError: avatarUrl != null ? (_, _) {} : null,
                child: avatarUrl == null
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              isMuted == true ? Icons.mic_off : Icons.mic,
              size: 11,
              color: isMuted == true ? Colors.redAccent : speakingColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '$displayName${isLocal ? ' (you)' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: isSpeaking ? Colors.white70 : Colors.white54,
                  fontWeight: isSpeaking ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isLocal && isScreenSharing)
              GestureDetector(
                onTap: () => notifier.toggleScreenShareSubscription(identity),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: voiceData.isScreenShareSubscribed(identity)
                        ? const Color(0xFF7F5AF0)
                        : const Color(0xFF2A2A30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: voiceData.isScreenShareSubscribed(identity)
                          ? const Color(0xFF7F5AF0)
                          : const Color(0xFF3A3A42),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        voiceData.isScreenShareSubscribed(identity)
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 10,
                        color: voiceData.isScreenShareSubscribed(identity)
                            ? Colors.white
                            : Colors.white54,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        voiceData.isScreenShareSubscribed(identity)
                            ? 'Hide'
                            : 'Watch',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: voiceData.isScreenShareSubscribed(identity)
                              ? Colors.white
                              : Colors.white54,
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

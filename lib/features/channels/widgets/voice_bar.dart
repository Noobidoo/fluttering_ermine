import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../messaging/providers/messaging_notifier.dart';
import '../../voice/providers/voice_notifier.dart';
import 'deep_filter_status.dart';

class VoiceBar extends ConsumerWidget {
  const VoiceBar({super.key});

  Color _deepFilterColor(VoiceStateData voice) {
    if (!voice.deepFilterEnabled) return Colors.white38;
    if (!VoiceNotifier.deepFilterIsRealLibrary) return Colors.orange;
    if (!voice.deepFilterIsApmAttached) return Colors.amber;
    return const Color(0xFF2CB67D);
  }

  String _deepFilterTooltip(VoiceStateData voice) {
    if (!voice.deepFilterEnabled) return 'Neural noise suppression: off';
    if (!VoiceNotifier.deepFilterIsRealLibrary) {
      return 'Neural noise suppression: stub (library not loaded)';
    }
    if (!voice.deepFilterIsApmAttached) {
      return 'Neural noise suppression: initializing…';
    }
    return 'Neural noise suppression: active';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceStateProvider);
    final messagingNotifier = ref.read(messagingStateProvider.notifier);
    final notifier = ref.read(voiceStateProvider.notifier);
    final channelName = voice.activeVoiceChannel != null
        ? messagingNotifier.channelDisplayName(voice.activeVoiceChannel!)
        : 'Connecting…';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1A3A2A),
      child: voice.isJoiningVoice
          ? const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Connecting to voice…', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, size: 16, color: Color(0xFF2CB67D)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Voice Connected',
                            style: TextStyle(
                              color: Color(0xFF2CB67D),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            channelName,
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (VoiceNotifier.deepFilterSupported) ...[
                      Tooltip(
                        message: _deepFilterTooltip(voice),
                        child: IconButton(
                          icon: Icon(
                            voice.deepFilterEnabled ? Icons.noise_aware : Icons.noise_control_off,
                            size: 18,
                            color: _deepFilterColor(voice),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => notifier.setDeepFilterEnabled(!voice.deepFilterEnabled),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      icon: Icon(
                        voice.isMuted ? Icons.mic_off : Icons.mic,
                        size: 18,
                        color: voice.isMuted ? Colors.redAccent : Colors.white70,
                      ),
                      tooltip: voice.isMuted ? 'Unmute' : 'Mute',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => notifier.toggleMute(),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.call_end, size: 18, color: Colors.redAccent),
                      tooltip: 'Leave voice',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => notifier.leaveVoiceChannel(),
                    ),
                  ],
                ),
                if (VoiceNotifier.deepFilterSupported) const DeepFilterStatus(),
              ],
            ),
    );
  }
}

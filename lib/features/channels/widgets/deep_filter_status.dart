import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/providers/voice_notifier.dart';

class DeepFilterStatus extends ConsumerWidget {
  const DeepFilterStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceStateProvider);
    final isReal = VoiceNotifier.deepFilterIsRealLibrary;
    final isActive = voice.deepFilterIsApmAttached;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            isReal ? Icons.check_circle_outline : Icons.error_outline,
            size: 11,
            color: isReal ? const Color(0xFF2CB67D) : Colors.orange,
          ),
          const SizedBox(width: 3),
          Text(
            isReal ? 'DeepFilter' : 'DeepFilter (stub)',
            style: TextStyle(
              fontSize: 10,
              color: isReal ? Colors.white38 : Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isActive ? Icons.graphic_eq : Icons.mic_off,
            size: 11,
            color: isActive ? const Color(0xFF2CB67D) : Colors.white38,
          ),
          const SizedBox(width: 3),
          Text(
            isActive
                ? 'APM active'
                : voice.deepFilterEnabled
                ? 'APM inactive'
                : 'disabled',
            style: TextStyle(
              fontSize: 10,
              color: isActive ? const Color(0xFF2CB67D) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

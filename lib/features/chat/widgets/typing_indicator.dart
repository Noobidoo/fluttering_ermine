import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../messaging/providers/messaging_notifier.dart';
import '../providers/chat_selectors.dart';

class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userIds = ref.watch(typingUserIdsProvider);
    if (userIds.isEmpty) return const SizedBox.shrink();

    final messaging = ref.read(messagingStateProvider);

    String text;
    if (userIds.length == 1) {
      final uid = userIds.first;
      final name = messaging.userCache[uid]?.resolveDisplayName(null) ?? uid;
      text = '$name is typing…';
    } else if (userIds.length == 2) {
      final it = userIds.iterator;
      it.moveNext();
      final a =
          messaging.userCache[it.current]?.resolveDisplayName(null) ??
          it.current;
      it.moveNext();
      final b =
          messaging.userCache[it.current]?.resolveDisplayName(null) ??
          it.current;
      text = '$a and $b are typing…';
    } else {
      text = 'Several people are typing…';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 16, 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white54,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

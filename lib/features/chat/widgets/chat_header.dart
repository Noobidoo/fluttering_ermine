import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/revolt_channel.dart';
import '../../messaging/providers/messaging_notifier.dart';

class ChatHeader extends ConsumerWidget {
  final RevoltChannel channel;
  final List<Widget> actions;

  const ChatHeader(this.channel, {super.key, this.actions = const []});

  IconData _icon() => switch (channel.type) {
    ChannelType.textChannel when channel.isVoice => Icons.volume_up_rounded,
    ChannelType.textChannel => Icons.tag,
    ChannelType.directMessage => Icons.person_rounded,
    ChannelType.group => Icons.group_rounded,
    ChannelType.savedMessages => Icons.bookmark_rounded,
    _ => Icons.chat_bubble_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.read(messagingStateProvider.notifier).channelDisplayName(channel);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF16161A),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Row(
        children: [
          Icon(_icon(), size: 20, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (channel.description != null && channel.description!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: Colors.white24),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      channel.description!,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[const SizedBox(width: 8), ...actions],
        ],
      ),
    );
  }
}

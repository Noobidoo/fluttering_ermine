import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/revolt_channel.dart';
import '../../servers/providers/server_notifier.dart';
import '../../messaging/providers/messaging_notifier.dart';
import '../providers/chat_selectors.dart';
import 'message_bubble.dart';

class MessageList extends ConsumerWidget {
  final RevoltChannel channel;
  final ScrollController ctrl;

  const MessageList(this.channel, this.ctrl, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(currentMessagesProvider);
    final loading = ref.watch(isLoadingMessagesProvider);
    final error = ref.watch(currentChannelErrorProvider);
    final messaging = ref.watch(messagingStateProvider);

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.read(messagingStateProvider.notifier).retryLoadMessages(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
              ),
            ],
          ),
        ),
      );
    }

    if (messages.isEmpty) {
      return const Center(
        child: Text('No messages yet', style: TextStyle(color: Colors.white38)),
      );
    }

    final serverState = ref.read(serverStateProvider).asData?.value;
    final serverId = serverState?.selectedServer?.id;

    return ListView.builder(
      controller: ctrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final prev = i + 1 < messages.length ? messages[i + 1] : null;
        final grouped = prev != null && prev.authorId == msg.authorId;
        return MessageBubble(
          message: msg,
          author: messaging.userCache[msg.authorId],
          grouped: grouped,
          serverId: serverId,
        );
      },
    );
  }
}

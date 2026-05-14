import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import 'message_bubble.dart';

class ChatPanel extends StatelessWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const ChatPanel(
      {required this.msgCtrl, required this.scrollCtrl, super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channel = state.selectedChannel;

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 72, color: Colors.white12),
            SizedBox(height: 16),
            Text('Select a channel',
                style: TextStyle(color: Colors.white38, fontSize: 18)),
            SizedBox(height: 4),
            Text('Pick a channel from the left to start chatting.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _ChatHeader(channel),
        if (channel.isVoice)
          Expanded(child: _VoiceChannelView(channel))
        else ...[
          Expanded(child: _MessageList(channel, scrollCtrl)),
          _MessageInput(msgCtrl: msgCtrl),
        ],
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final RevoltChannel channel;
  const _ChatHeader(this.channel);

  IconData _icon() => switch (channel.type) {
        ChannelType.textChannel when channel.isVoice => Icons.volume_up_rounded,
        ChannelType.textChannel => Icons.tag,
        ChannelType.directMessage => Icons.person_rounded,
        ChannelType.group => Icons.group_rounded,
        ChannelType.savedMessages => Icons.bookmark_rounded,
        _ => Icons.chat_bubble_outline,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

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
          Text(
            state.channelDisplayName(channel),
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (channel.description != null &&
              channel.description!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.description!,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceChannelView extends StatelessWidget {
  final RevoltChannel channel;
  const _VoiceChannelView(this.channel);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isActive = state.activeVoiceChannel?.id == channel.id;

    Widget controls;
    if (isActive) {
      controls = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: () => context.read<AppState>().toggleMute(),
            icon: Icon(state.isMuted ? Icons.mic_off : Icons.mic),
            label: Text(state.isMuted ? 'Unmute' : 'Mute'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  state.isMuted ? Colors.redAccent : const Color(0xFF2CB67D),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => context.read<AppState>().leaveVoiceChannel(),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Leave',
                style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ],
      );
    } else if (state.isJoiningVoice) {
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
        onPressed: () => context.read<AppState>().joinVoiceChannel(channel),
        icon: const Icon(Icons.call),
        label: const Text('Join Voice'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2CB67D),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
      );
    }

    return Center(
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
          if (state.voiceError != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                state.voiceError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],
          controls,
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final RevoltChannel channel;
  final ScrollController ctrl;
  const _MessageList(this.channel, this.ctrl);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final messages = state.currentMessages;

    if (state.isLoadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.currentChannelError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                state.currentChannelError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.read<AppState>().retryLoadMessages(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0)),
              ),
            ],
          ),
        ),
      );
    }

    if (messages.isEmpty) {
      return const Center(
          child: Text('No messages yet',
              style: TextStyle(color: Colors.white38)));
    }

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
          author: state.getUser(msg.authorId),
          grouped: grouped,
        );
      },
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController msgCtrl;
  const _MessageInput({required this.msgCtrl});

  void _send(BuildContext context) {
    final text = msgCtrl.text;
    if (text.trim().isEmpty) return;
    msgCtrl.clear();
    context.read<AppState>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final name = state.selectedChannel != null
        ? state.channelDisplayName(state.selectedChannel!)
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: msgCtrl,
              maxLines: 6,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message $name',
                filled: true,
                fillColor: const Color(0xFF242428),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => _send(context),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _send(context),
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF7F5AF0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

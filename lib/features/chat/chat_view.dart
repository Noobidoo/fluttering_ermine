import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../servers/providers/server_notifier.dart';
import '../messaging/providers/messaging_notifier.dart';
import 'widgets/chat_header.dart';
import 'widgets/voice_channel_view.dart';
import 'widgets/message_list.dart';
import 'widgets/message_input.dart';
import 'providers/chat_selectors.dart';

class ChatView extends ConsumerStatefulWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const ChatView({super.key, required this.msgCtrl, required this.scrollCtrl});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  bool _showVoice = true;
  bool _splitMode = false;
  bool _maximized = false;
  String? _lastLoadError;

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverStateProvider);
    final channel = serverState.asData?.value.selectedChannel;
    final error = ref.watch(currentChannelErrorProvider);
    final messagingNotifier = ref.read(messagingStateProvider.notifier);

    if (error != null && error != _lastLoadError) {
      _lastLoadError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => messagingNotifier.retryLoadMessages(),
            ),
          ),
        );
      });
    }

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 72, color: Colors.white12),
            SizedBox(height: 16),
            Text(
              'Select a channel',
              style: TextStyle(color: Colors.white38, fontSize: 18),
            ),
            SizedBox(height: 4),
            Text(
              'Pick a channel from the left to start chatting.',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_maximized && channel.isVoice && !_splitMode) {
      return Stack(
        children: [
          VoiceChannelView(channel),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit, size: 20),
                color: Colors.white70,
                tooltip: 'Restore',
                onPressed: () => setState(() => _maximized = false),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        ChatHeader(
          channel,
          actions: channel.isVoice
              ? [
                  if (!_splitMode && _showVoice)
                    IconButton(
                      icon: const Icon(Icons.fullscreen, size: 18),
                      tooltip: 'Maximize streams',
                      color: Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _maximized = true),
                    ),
                  IconButton(
                    icon: Icon(
                      _splitMode
                          ? Icons.tab_rounded
                          : Icons.view_agenda_rounded,
                      size: 18,
                    ),
                    tooltip: _splitMode ? 'Tab layout' : 'Split layout',
                    color: Colors.white38,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _splitMode = !_splitMode;
                      if (_splitMode) _maximized = false;
                    }),
                  ),
                ]
              : const [],
        ),
        if (channel.isVoice) ...[
          if (_splitMode) ...[
            SizedBox(height: 260, child: VoiceChannelView(channel)),
            const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A30)),
            Expanded(child: MessageList(channel, widget.scrollCtrl)),
            MessageInput(msgCtrl: widget.msgCtrl),
          ] else ...[
            VoiceTabBar(
              showVoice: _showVoice,
              onToggle: (v) => setState(() => _showVoice = v),
            ),
            if (_showVoice)
              Expanded(child: VoiceChannelView(channel))
            else ...[
              Expanded(child: MessageList(channel, widget.scrollCtrl)),
              MessageInput(msgCtrl: widget.msgCtrl),
            ],
          ],
        ] else ...[
          Expanded(child: MessageList(channel, widget.scrollCtrl)),
          MessageInput(msgCtrl: widget.msgCtrl),
        ],
      ],
    );
  }
}

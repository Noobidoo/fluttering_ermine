import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';
import 'message_bubble.dart';

class ChatPanel extends StatelessWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const ChatPanel(
      {required this.msgCtrl, required this.scrollCtrl, super.key});

  @override
  Widget build(BuildContext context) {
    final channel = context.watch<ServerState>().selectedChannel;

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
    final messaging = context.watch<MessagingState>();

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
            messaging.channelDisplayName(channel),
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
    final voice = context.watch<VoiceState>();
    final isActive = voice.activeVoiceChannel?.id == channel.id;
    final streams = isActive ? voice.remoteVideoStreams : <RemoteVideoStream>[];

    Widget controls;
    if (isActive) {
      controls = Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => context.read<VoiceState>().toggleMute(),
            icon: Icon(voice.isMuted ? Icons.mic_off : Icons.mic),
            label: Text(voice.isMuted ? 'Unmute' : 'Mute'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  voice.isMuted ? Colors.redAccent : const Color(0xFF2CB67D),
            ),
          ),
          FilledButton.icon(
            onPressed: () => context.read<VoiceState>().toggleScreenShare(),
            icon: Icon(voice.isScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share),
            label: Text(
                voice.isScreenSharing ? 'Stop Sharing' : 'Share Screen'),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isScreenSharing
                  ? Colors.orangeAccent
                  : const Color(0xFF7F5AF0),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.read<VoiceState>().leaveVoiceChannel(),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Leave',
                style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
            ),
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
        onPressed: () => context.read<VoiceState>().joinVoiceChannel(channel),
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
              child: _VideoGrid(streams: streams),
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
                    color:
                        isActive ? const Color(0xFF2CB67D) : Colors.white38,
                  ),
                ),
                const SizedBox(height: 24),
                if (voice.voiceError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      voice.voiceError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
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

class _RemoteVideoTile extends StatelessWidget {
  final RemoteVideoStream stream;
  const _RemoteVideoTile({required this.stream});

  @override
  Widget build(BuildContext context) {
    final isScreen = stream.source == TrackSource.screenShareVideo;
    return ClipRRect(
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}

class _MessageList extends StatelessWidget {
  final RevoltChannel channel;
  final ScrollController ctrl;
  const _MessageList(this.channel, this.ctrl);

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final messages = messaging.currentMessages;

    if (messaging.isLoadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messaging.currentChannelError != null) {
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
                messaging.currentChannelError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.read<MessagingState>().retryLoadMessages(),
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
          author: messaging.getUser(msg.authorId),
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
    context.read<MessagingState>().sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final channel = context.watch<ServerState>().selectedChannel;
    final name = channel != null ? messaging.channelDisplayName(channel) : '';

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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';
import 'message_bubble.dart';
import 'message_input.dart';

class ChatPanel extends StatefulWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const ChatPanel({required this.msgCtrl, required this.scrollCtrl, super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  bool _showVoice = true;
  bool _splitMode = false;
  bool _maximized = false;
  String? _lastLoadError;

  @override
  Widget build(BuildContext context) {
    final channel = context.watch<ServerState>().selectedChannel;
    final messaging = context.watch<MessagingState>();

    final error = channel != null ? messaging.currentChannelError : null;
    if (error != null && error != _lastLoadError) {
      _lastLoadError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () =>
                  context.read<MessagingState>().retryLoadMessages(),
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

    // Maximized: full-area voice view with a floating restore button.
    if (_maximized && channel.isVoice && !_splitMode) {
      return Stack(
        children: [
          _VoiceChannelView(channel),
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
        _ChatHeader(
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
            SizedBox(height: 260, child: _VoiceChannelView(channel)),
            const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A30)),
            Expanded(child: _MessageList(channel, widget.scrollCtrl)),
            MessageInput(msgCtrl: widget.msgCtrl),
          ] else ...[
            _VoiceTabBar(
              showVoice: _showVoice,
              onToggle: (v) => setState(() => _showVoice = v),
            ),
            if (_showVoice)
              Expanded(child: _VoiceChannelView(channel))
            else ...[
              Expanded(child: _MessageList(channel, widget.scrollCtrl)),
              MessageInput(msgCtrl: widget.msgCtrl),
            ],
          ],
        ] else ...[
          Expanded(child: _MessageList(channel, widget.scrollCtrl)),
          MessageInput(msgCtrl: widget.msgCtrl),
        ],
      ],
    );
  }
}

class _VoiceTabBar extends StatelessWidget {
  final bool showVoice;
  final ValueChanged<bool> onToggle;
  const _VoiceTabBar({required this.showVoice, required this.onToggle});

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
                    bottom: BorderSide(
                      color: showVoice ? active : inactive,
                      width: 2,
                    ),
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
                    bottom: BorderSide(
                      color: !showVoice ? active : inactive,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tag,
                      size: 14,
                      color: !showVoice ? active : textInactive,
                    ),
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

class _ChatHeader extends StatelessWidget {
  final RevoltChannel channel;
  final List<Widget> actions;
  const _ChatHeader(this.channel, {this.actions = const []});

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
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    messaging.channelDisplayName(channel),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (channel.description != null &&
                    channel.description!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: Colors.white24),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      channel.description!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
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
              backgroundColor: voice.isMuted
                  ? Colors.redAccent
                  : const Color(0xFF2CB67D),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final voiceState = context.read<VoiceState>();
              if (voice.isScreenSharing) {
                voiceState.stopScreenShare();
                return;
              }
              // On desktop, show a source picker before enabling screen share.
              if (!kIsWeb &&
                  (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)) {
                final dynamic source = await showDialog(
                  context: context,
                  builder: (context) => ScreenSelectDialog(),
                );
                if (source == null) return;
                voiceState.startDesktopScreenShare(source.id as String);
              } else {
                voiceState.toggleScreenShare();
              }
            },
            icon: Icon(
              voice.isScreenSharing
                  ? Icons.stop_screen_share
                  : Icons.screen_share,
            ),
            label: Text(
              voice.isScreenSharing ? 'Stop Sharing' : 'Share Screen',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isScreenSharing
                  ? Colors.orangeAccent
                  : const Color(0xFF7F5AF0),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.read<VoiceState>().leaveVoiceChannel(),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
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
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
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

  void _showVolumeMenu(BuildContext context) {
    final voice = context.read<VoiceState>();
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
                    const Icon(Icons.volume_down_rounded,
                        size: 18, color: Colors.white38),
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
                            voice.setParticipantVolume(identity, v, source: audioSource);
                          },
                          activeColor: const Color(0xFF7F5AF0),
                          inactiveColor: Colors.white24,
                        ),
                      ),
                    ),
                    const Icon(Icons.volume_up_rounded,
                        size: 18, color: Colors.white38),
                  ],
                ),
                Center(
                  child: Text(
                    '${(tempVolume * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                      onPressed: () {
                      setDialogState(() => tempVolume = 1.0);
                      voice.setParticipantVolume(identity, 1.0, source: audioSource);
                    },
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset to 100%'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white60,
                    ),
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
  Widget build(BuildContext context) {
    final isScreen = stream.source == TrackSource.screenShareVideo;
    return GestureDetector(
      onSecondaryTapDown: (_) => _showVolumeMenu(context),
      onLongPress: () => _showVolumeMenu(context),
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
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                messaging.currentChannelError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.read<MessagingState>().retryLoadMessages(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                ),
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
          serverId: context.read<ServerState>().selectedServer?.id,
        );
      },
    );
  }
}

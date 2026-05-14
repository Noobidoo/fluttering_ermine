import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/message_bubble.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 800;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _ServerRail(),
            SizedBox(width: 230, child: _ChannelPanel()),
            Expanded(
              child: _ChatPanel(
                msgCtrl: _msgCtrl,
                scrollCtrl: _scrollCtrl,
              ),
            ),
          ],
        ),
      );
    }

    // Narrow layout – channel panel in drawer
    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: Drawer(
        width: 300,
        child: SafeArea(
          child: Row(
            children: [
              _ServerRail(),
              Expanded(child: _ChannelPanel()),
            ],
          ),
        ),
      ),
      body: _ChatPanel(msgCtrl: _msgCtrl, scrollCtrl: _scrollCtrl),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final channel = context.watch<AppState>().selectedChannel;
    final state = context.watch<AppState>();
    return AppBar(
      backgroundColor: const Color(0xFF16161A),
      title: channel != null
          ? Row(children: [
              Icon(_channelIcon(channel),
                  size: 18, color: Colors.white54),
              const SizedBox(width: 6),
              Text(state.channelDisplayName(channel),
                  style: const TextStyle(fontSize: 16)),
            ])
          : const Text('Fluttering Ermine'),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: () => context.read<AppState>().logout(),
        ),
      ],
    );
  }

  IconData _channelIcon(RevoltChannel channel) => switch (channel.type) {
      ChannelType.textChannel when channel.isVoice => Icons.volume_up_rounded,
      ChannelType.textChannel => Icons.tag,
      ChannelType.directMessage => Icons.person_rounded,
      ChannelType.group => Icons.group_rounded,
      ChannelType.savedMessages => Icons.bookmark_rounded,
      _ => Icons.chat_bubble_outline,
    };
}

// ── Server rail ──────────────────────────────────────────────────────────────

class _ServerRail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 68,
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailIcon(
            tooltip: 'Direct Messages',
            selected: state.showDMs,
            onTap: state.selectDMs,
            child: const Icon(Icons.message_rounded, size: 22),
          ),
          const _Divider(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: state.servers.length,
              itemBuilder: (_, i) {
                final srv = state.servers[i];
                return _RailIcon(
                  tooltip: srv.name,
                  selected: state.selectedServer?.id == srv.id,
                  onTap: () => state.selectServer(srv),
                  child: srv.iconUrlFor(state.autumnBase) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            srv.iconUrlFor(state.autumnBase)!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) =>
                                _Initials(srv.name),
                          ),
                        )
                      : _Initials(srv.name),
                );
              },
            ),
          ),
          _RailIcon(
            tooltip: 'Logout',
            selected: false,
            onTap: () => context.read<AppState>().logout(),
            child: const Icon(Icons.logout,
                size: 20, color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _RailIcon({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF7F5AF0)
                : const Color(0xFF1E1E26),
            borderRadius:
                BorderRadius.circular(selected ? 12 : 22),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  const _Initials(this.name);

  @override
  Widget build(BuildContext context) {
    final initials =
        name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();
    return Text(initials,
        style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.bold));
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 8, thickness: 1, indent: 14, endIndent: 14);
}

// ── Channel panel ─────────────────────────────────────────────────────────────

class _ChannelPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channels = state.selectedServer != null
        ? state.selectedServerChannels
        : state.dmChannels;
    final title = state.selectedServer?.name ??
        (state.showDMs ? 'Direct Messages' : 'Fluttering Ermine');

    return Container(
      color: const Color(0xFF141418),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
            ),
            child: Text(
              title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Text('No channels',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: channels.length,
                    itemBuilder: (_, i) => _ChannelTile(channels[i]),
                  ),
          ),
          if (state.currentUser != null) _UserBar(state.currentUser!),
          if (state.isInVoice || state.isJoiningVoice) const _VoiceBar(),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final RevoltChannel channel;
  const _ChannelTile(this.channel);

  IconData _icon(RevoltChannel channel) => switch (channel.type) {
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
    final selected = state.selectedChannel?.id == channel.id;
    final name = state.channelDisplayName(channel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        selected: selected,
        selectedTileColor: const Color(0x207F5AF0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          _icon(channel),
          size: 18,
          color: selected ? const Color(0xFF7F5AF0) : Colors.white38,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.white : Colors.white60,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          if (channel.isVoice) {
            state.selectVoiceChannel(channel);
          } else {
            state.selectChannel(channel);
          }
          // Close drawer on mobile
          if (Scaffold.of(context).isDrawerOpen) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}

class _UserBar extends StatelessWidget {
  final RevoltUser user;
  const _UserBar(this.user);

  @override
  Widget build(BuildContext context) {
    final apiBase = context.read<AppState>().apiBase;
    final autumnBase = context.read<AppState>().autumnBase;
    return Container(
      padding: const EdgeInsets.all(10),
      color: const Color(0xFF0D0D0F),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(user.avatarUrlFor(autumnBase, apiBase)),
            backgroundColor: const Color(0xFF7F5AF0),
            onBackgroundImageError: (e, stack) {},
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user.displayUsername,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Voice bar ─────────────────────────────────────────────────────────────────

class _VoiceBar extends StatelessWidget {
  const _VoiceBar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channelName = state.activeVoiceChannel != null
        ? state.channelDisplayName(state.activeVoiceChannel!)
        : 'Connecting…';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1A3A2A),
      child: state.isJoiningVoice
          ? const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Connecting to voice…',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])
          : Row(
              children: [
                const Icon(Icons.graphic_eq, size: 16, color: Color(0xFF2CB67D)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Voice Connected',
                          style: TextStyle(
                              color: Color(0xFF2CB67D),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text(channelName,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    state.isMuted ? Icons.mic_off : Icons.mic,
                    size: 18,
                    color: state.isMuted ? Colors.redAccent : Colors.white70,
                  ),
                  tooltip: state.isMuted ? 'Unmute' : 'Mute',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => context.read<AppState>().toggleMute(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.call_end,
                      size: 18, color: Colors.redAccent),
                  tooltip: 'Leave voice',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => context.read<AppState>().leaveVoiceChannel(),
                ),
              ],
            ),
    );
  }
}

// ── Chat panel ────────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const _ChatPanel(
      {required this.msgCtrl, required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final channel = state.selectedChannel;

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 72, color: Colors.white12),
            SizedBox(height: 16),
            Text('Select a channel',
                style:
                    TextStyle(color: Colors.white38, fontSize: 18)),
            SizedBox(height: 4),
            Text('Pick a channel from the left to start chatting.',
                style:
                    TextStyle(color: Colors.white24, fontSize: 13)),
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

  IconData _icon(ChannelType t) => switch (t) {
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
          Icon(_icon(channel.type), size: 20, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            state.channelDisplayName(channel),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (channel.description != null &&
              channel.description!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
                width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.description!,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 13),
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
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
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
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.read<AppState>().retryLoadMessages(),
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
        final grouped =
            prev != null && prev.authorId == msg.authorId;
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

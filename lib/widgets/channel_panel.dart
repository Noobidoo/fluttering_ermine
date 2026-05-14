import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';

class ChannelPanel extends StatelessWidget {
  const ChannelPanel({super.key});

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
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
            ),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
          _icon(),
          size: 18,
          color: selected ? const Color(0xFF7F5AF0) : Colors.white38,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.white : Colors.white60,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          if (channel.isVoice) {
            state.selectVoiceChannel(channel);
          } else {
            state.selectChannel(channel);
          }
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
            backgroundImage:
                NetworkImage(user.avatarUrlFor(autumnBase, apiBase)),
            backgroundColor: const Color(0xFF7F5AF0),
            onBackgroundImageError: (e, stack) {},
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user.displayUsername,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

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
                const Icon(Icons.graphic_eq,
                    size: 16, color: Color(0xFF2CB67D)),
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
                  onPressed: () =>
                      context.read<AppState>().leaveVoiceChannel(),
                ),
              ],
            ),
    );
  }
}

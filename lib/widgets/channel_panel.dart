import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';

class ChannelPanel extends StatelessWidget {
  const ChannelPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerState>();
    final voice = context.watch<VoiceState>();
    final auth = context.watch<AuthState>();
    final channels = server.selectedServer != null
        ? server.selectedServerChannels
        : server.dmChannels;
    final title = server.selectedServer?.name ??
        (server.showDMs ? 'Direct Messages' : 'Fluttering Ermine');

    return Material(
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
          if (auth.currentUser != null)
            _UserBar(auth.currentUser!, auth.autumnBase, auth.apiBase),
          if (voice.isInVoice || voice.isJoiningVoice) const _VoiceBar(),
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
    final server = context.watch<ServerState>();
    final messaging = context.watch<MessagingState>();
    final voice = context.watch<VoiceState>();
    final auth = context.watch<AuthState>();
    final selected = server.selectedChannel?.id == channel.id;
    final name = messaging.channelDisplayName(channel);

    // Server-side voice participant tracking (shows for all channels)
    final participantIds = channel.isVoice
        ? server.voiceParticipantsFor(channel.id)
        : const <String>[];

    // Ensure voice participants are in user cache (they may never have sent a message)
    if (participantIds.isNotEmpty) {
      messaging.ensureUsersCached(List<String>.from(participantIds));
    }

    // LiveKit mute status (local connection) takes priority; fall back to server-side publishing state
    final isActiveVoice =
        channel.isVoice && voice.activeVoiceChannel?.id == channel.id;
    final liveKitByIdentity = {
      for (final p in (isActiveVoice ? voice.voiceParticipants : <VoiceParticipant>[])) p.identity: p,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                server.selectVoiceChannel(channel);
              } else {
                server.selectChannel(channel);
              }
              if (Scaffold.of(context).isDrawerOpen) {
                Navigator.of(context).pop();
              }
            },
          ),
          if (participantIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 4),
              child: Column(
                children: participantIds.map((userId) {
                  final user = messaging.getUser(userId);
                  final lkParticipant = liveKitByIdentity[userId];
                  final isLocal = userId == auth.currentUser?.id;
                  return _VoiceParticipantRow(
                    displayName: user?.displayUsername ?? userId,
                    isLocal: isLocal,
                    isMuted: lkParticipant?.isMuted,
                    isSpeaking: lkParticipant?.isSpeaking ?? false,
                    avatarUrl: user?.avatarUrlFor(auth.autumnBase, auth.apiBase),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceParticipantRow extends StatelessWidget {
  final String displayName;
  final bool isLocal;
  final bool? isMuted;
  final bool isSpeaking;
  final String? avatarUrl;
  const _VoiceParticipantRow({
    required this.displayName,
    required this.isLocal,
    this.isMuted,
    this.isSpeaking = false,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    const speakingColor = Color(0xFF2CB67D);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpeaking ? speakingColor : Colors.transparent,
                width: 2,
              ),
              boxShadow: isSpeaking
                  ? [BoxShadow(
                      color: speakingColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                    )]
                  : null,
            ),
            child: CircleAvatar(
              radius: 10,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              backgroundColor: const Color(0xFF7F5AF0),
              onBackgroundImageError:
                  avatarUrl != null ? (_, _) {} : null,
              child: avatarUrl == null
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          fontSize: 9, color: Colors.white),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            isMuted == true ? Icons.mic_off : Icons.mic,
            size: 11,
            color: isMuted == true ? Colors.redAccent : speakingColor,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              displayName + (isLocal ? ' (you)' : ''),
              style: TextStyle(
                fontSize: 12,
                color: isSpeaking ? Colors.white70 : Colors.white54,
                fontWeight:
                    isSpeaking ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBar extends StatelessWidget {
  final RevoltUser user;
  final String autumnBase;
  final String apiBase;
  const _UserBar(this.user, this.autumnBase, this.apiBase);

  @override
  Widget build(BuildContext context) {
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
    final voice = context.watch<VoiceState>();
    final messaging = context.watch<MessagingState>();
    final channelName = voice.activeVoiceChannel != null
        ? messaging.channelDisplayName(voice.activeVoiceChannel!)
        : 'Connecting…';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF1A3A2A),
      child: voice.isJoiningVoice
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
                    voice.isMuted ? Icons.mic_off : Icons.mic,
                    size: 18,
                    color: voice.isMuted ? Colors.redAccent : Colors.white70,
                  ),
                  tooltip: voice.isMuted ? 'Unmute' : 'Mute',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => context.read<VoiceState>().toggleMute(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.call_end,
                      size: 18, color: Colors.redAccent),
                  tooltip: 'Leave voice',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      context.read<VoiceState>().leaveVoiceChannel(),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';
import '../screens/settings_screen.dart';

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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (server.selectedServer != null)
                  IconButton(
                    icon: const Icon(Icons.settings_rounded,
                        size: 18, color: Colors.white54),
                    tooltip: 'Server settings',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showServerSettings(context),
                  ),
              ],
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
                    itemBuilder: (_, i) => _ChannelTile(channels[i], key: ValueKey('channel_${channels[i].id}')),
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
  const _ChannelTile(this.channel, {super.key});

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
    final unread = server.isChannelUnread(channel.id);
    final mentionCount = server.mentionCountFor(channel.id);

    // Voice participant tracking (shows for all voice channels)
    final participantIds = channel.isVoice
        ? voice.voiceParticipantsFor(channel.id)
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
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _icon(),
                  size: 18,
                  color: selected ? const Color(0xFF7F5AF0) : Colors.white38,
                ),
                if (unread)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2CB67D),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected
                          ? Colors.white
                          : (unread ? Colors.white : Colors.white60),
                      fontWeight:
                          selected || unread ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (mentionCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$mentionCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
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
                    identity: userId,
                    displayName: user?.resolveDisplayName(null) ?? userId,
                    isLocal: isLocal,
                    isMuted: lkParticipant?.isMuted,
                    isSpeaking: lkParticipant?.isSpeaking ?? false,
                    isScreenSharing: lkParticipant?.isScreenSharing ?? false,
                    avatarUrl: user?.resolveAvatarUrl(null, auth.autumnBase, auth.apiBase),
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
  final String identity;
  final String displayName;
  final bool isLocal;
  final bool? isMuted;
  final bool isSpeaking;
  final bool isScreenSharing;
  final String? avatarUrl;
  const _VoiceParticipantRow({
    required this.identity,
    required this.displayName,
    required this.isLocal,
    this.isMuted,
    this.isSpeaking = false,
    this.isScreenSharing = false,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceState>();
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
          if (!isLocal && isScreenSharing)
            GestureDetector(
              onTap: () =>
                  voice.toggleScreenShareSubscription(identity),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: voice.isScreenShareSubscribed(identity)
                      ? const Color(0xFF7F5AF0)
                      : const Color(0xFF2A2A30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: voice.isScreenShareSubscribed(identity)
                        ? const Color(0xFF7F5AF0)
                        : const Color(0xFF3A3A42),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      voice.isScreenShareSubscribed(identity)
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 10,
                      color: voice.isScreenShareSubscribed(identity)
                          ? Colors.white
                          : Colors.white54,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      voice.isScreenShareSubscribed(identity)
                          ? 'Hide'
                          : 'Watch',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: voice.isScreenShareSubscribed(identity)
                            ? Colors.white
                            : Colors.white54,
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

void _showServerSettings(BuildContext context) {
  final server = context.read<ServerState>();
  final srv = server.selectedServer;
  if (srv == null) return;

  showDialog(
    context: context,
    builder: (ctx) => _ServerSettingsDialog(srv: srv),
  );
}

class _ServerSettingsDialog extends StatefulWidget {
  final RevoltServer srv;
  const _ServerSettingsDialog({required this.srv});

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  List<RevoltInvite>? _invites;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    final server = context.read<ServerState>();
    try {
      final invites = await server.fetchInvites(widget.srv.id);
      if (!mounted) return;
      setState(() => _invites = invites);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E26),
      title: Text(widget.srv.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsButton(
            icon: Icons.link,
            label: 'Create invite',
            onTap: () {
              Navigator.of(context).pop();
              _createInvite(context);
            },
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2A2A30), height: 1),
          const SizedBox(height: 12),
          const Text('Existing invites',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 8),
          if (_error != null)
            Text('Failed to load: $_error',
                style:
                    const TextStyle(fontSize: 12, color: Colors.redAccent)),
          if (_invites == null)
            const Center(child: CircularProgressIndicator(strokeWidth: 2))
          else if (_invites!.isEmpty)
            const Text('No invites yet',
                style: TextStyle(fontSize: 12, color: Colors.white38))
          else
            ..._invites!.map(
              (inv) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inv.id,
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

void _createInvite(BuildContext context) async {
  final server = context.read<ServerState>();
  final channel = server.selectedChannel ??
      server.selectedServerChannels.cast<RevoltChannel?>().firstWhere(
            (c) => c?.type == ChannelType.textChannel && !c!.isVoice,
            orElse: () => null,
          );
  if (channel == null) return;
  try {
    final code = await server.createInvite(channel.id);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: const Text('Invite Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with others to invite them:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to create invite: $e')),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
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
    return GestureDetector(
      onTap: () => SettingsScreen.show(context),
      child: Container(
        padding: const EdgeInsets.all(10),
        color: const Color(0xFF0D0D0F),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      NetworkImage(user.resolveAvatarUrl(null, autumnBase, apiBase)),
                  backgroundColor: const Color(0xFF7F5AF0),
                  onBackgroundImageError: (e, stack) {},
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: presenceColor(user.presence),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF0D0D0F), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.resolveDisplayName(null),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.statusText != null &&
                      user.statusText!.isNotEmpty)
                    Text(
                      user.statusText!,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceBar extends StatelessWidget {
  const _VoiceBar();

  Color _deepFilterColor(VoiceState voice) {
    if (!voice.deepFilterEnabled) return Colors.white38;
    if (!VoiceState.deepFilterIsRealLibrary) return Colors.orange;
    if (!voice.deepFilterIsApmAttached) return Colors.amber;
    return const Color(0xFF2CB67D);
  }

  String _deepFilterTooltip(VoiceState voice) {
    if (!voice.deepFilterEnabled) return 'Neural noise suppression: off';
    if (!VoiceState.deepFilterIsRealLibrary) return 'Neural noise suppression: stub (library not loaded)';
    if (!voice.deepFilterIsApmAttached) return 'Neural noise suppression: initializing…';
    return 'Neural noise suppression: active';
  }

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
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                    if (VoiceState.deepFilterSupported) ...[
                      Tooltip(
                        message: _deepFilterTooltip(voice),
                        child: IconButton(
                          icon: Icon(
                            voice.deepFilterEnabled
                                ? Icons.noise_aware
                                : Icons.noise_control_off,
                            size: 18,
                            color: _deepFilterColor(voice),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => context
                              .read<VoiceState>()
                              .setDeepFilterEnabled(!voice.deepFilterEnabled),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
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
                if (VoiceState.deepFilterSupported)
                  const _DeepFilterStatusRow(),
              ],
            ),
    );
  }
}

class _DeepFilterStatusRow extends StatelessWidget {
  const _DeepFilterStatusRow();

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceState>();
    final isReal = VoiceState.deepFilterIsRealLibrary;
    final isActive = voice.deepFilterIsApmAttached;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(
            isReal ? Icons.check_circle_outline : Icons.error_outline,
            size: 11,
            color: isReal ? const Color(0xFF2CB67D) : Colors.orange,
          ),
          const SizedBox(width: 3),
          Text(
            isReal ? 'DeepFilter' : 'DeepFilter (stub)',
            style: TextStyle(
              fontSize: 10,
              color: isReal ? Colors.white38 : Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isActive ? Icons.graphic_eq : Icons.mic_off,
            size: 11,
            color: isActive ? const Color(0xFF2CB67D) : Colors.white38,
          ),
          const SizedBox(width: 3),
          Text(
            isActive
                ? 'APM active'
                : voice.deepFilterEnabled
                    ? 'APM inactive'
                    : 'disabled',
            style: TextStyle(
              fontSize: 10,
              color: isActive ? const Color(0xFF2CB67D) : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

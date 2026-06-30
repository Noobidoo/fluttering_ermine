import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/login_notifier.dart';
import '../../../features/core/providers/service_providers.dart';
import '../../../features/messaging/providers/messaging_notifier.dart';
import '../../../features/servers/providers/permissions_provider.dart';
import '../../../features/servers/providers/server_notifier.dart';
import '../../../features/voice/providers/voice_notifier.dart';
import '../../../models/models.dart';
import '../../servers/channel_permissions_screen.dart';
import 'voice_participant_row.dart';

class ChannelTile extends ConsumerWidget {
  final RevoltChannel channel;
  const ChannelTile(this.channel, {super.key});

  bool get _isDeletable => channel.type == ChannelType.textChannel;
  bool get _isEditable => channel.type == ChannelType.textChannel;

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
    final serverAsync = ref.watch(serverStateProvider);
    final server = serverAsync.asData?.value;
    final messagingNotifier = ref.read(messagingStateProvider.notifier);
    final voice = ref.watch(voiceStateProvider);
    final authData = ref.watch(loginStateProvider).asData?.value;
    final selected = server?.selectedChannel?.id == channel.id;
    final name = messagingNotifier.channelDisplayName(channel);
    final unread = server?.isChannelUnread(channel.id) ?? false;
    final mentionCount = server?.mentionCountFor(channel.id) ?? 0;
    final srvId = server?.selectedServer?.id;
    final permissions = srvId != null
        ? ref.watch(effectivePermissionsProvider(srvId))
        : 0;
    final canManageCh =
        authData != null && (permissions & Permission.manageChannel) != 0;

    final participantIds = channel.isVoice
        ? voice.voiceParticipantsFor(channel.id)
        : const <String>[];

    if (participantIds.isNotEmpty) {
      messagingNotifier.ensureUsersCached(List<String>.from(participantIds));
    }

    final isActiveVoice =
        channel.isVoice && voice.activeVoiceChannel?.id == channel.id;
    final liveKitByIdentity = {
      for (final p
          in (isActiveVoice ? voice.voiceParticipants : <VoiceParticipant>[]))
        p.identity: p,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
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
                      fontWeight: selected || unread
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (mentionCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
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
              final notifier = ref.read(serverStateProvider.notifier);
              if (channel.isVoice) {
                notifier.selectVoiceChannel(channel);
              } else {
                notifier.selectChannel(channel);
              }
              if (Scaffold.of(context).isDrawerOpen) {
                Navigator.of(context).pop();
              }
            },
            onLongPress: () => _showChannelContextMenu(context, ref),
            trailing: canManageCh
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(
                        Icons.settings_rounded,
                        size: 14,
                        color: Colors.white38,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showChannelPermissions(context, ref),
                    ),
                  )
                : null,
          ),
          if (participantIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 4),
              child: Column(
                children: participantIds.map((userId) {
                  final user = ref
                      .read(messagingStateProvider)
                      .userCache[userId];
                  final lkParticipant = liveKitByIdentity[userId];
                  final isLocal = userId == authData?.currentUser?.id;
                  return VoiceParticipantRow(
                    key: ValueKey(userId),
                    identity: userId,
                    displayName: user?.resolveDisplayName(null) ?? userId,
                    isLocal: isLocal,
                    isMuted: lkParticipant?.isMuted,
                    isSpeaking: lkParticipant?.isSpeaking ?? false,
                    isScreenSharing: lkParticipant?.isScreenSharing ?? false,
                    avatarUrl: user?.resolveAvatarUrl(
                      null,
                      ref.read(revoltServiceProvider).autumnBase,
                      ref.read(revoltServiceProvider).apiBase,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _showChannelContextMenu(BuildContext context, WidgetRef ref) {
    final srvId = ref
        .read(serverStateProvider)
        .asData
        ?.value
        .selectedServer
        ?.id;
    final authData = ref.read(loginStateProvider).asData?.value;
    final canManageCh =
        srvId != null &&
        authData != null &&
        (ref.read(effectivePermissionsProvider(srvId)) &
                Permission.manageChannel) !=
            0;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                channel.name ?? 'Channel',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            if (_isEditable && canManageCh)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white70),
                title: const Text('Edit Channel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditChannelDialog(context, ref);
                },
              ),
            if (canManageCh)
              ListTile(
                leading: const Icon(
                  Icons.security_rounded,
                  color: Colors.white70,
                ),
                title: const Text('Channel Permissions'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChannelPermissions(context, ref);
                },
              ),
            if (_isDeletable && canManageCh)
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete Channel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteChannel(context, ref);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditChannelDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController(text: channel.name ?? '');
    final descCtrl = TextEditingController(text: channel.description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Edit Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Channel name',
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doEditChannel(
                context,
                nameCtrl.text.trim(),
                descCtrl.text.trim(),
                ref,
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _doEditChannel(
    BuildContext context,
    String name,
    String description,
    WidgetRef ref,
  ) async {
    if (name.isEmpty) return;
    try {
      await ref
          .read(serverStateProvider.notifier)
          .updateChannel(
            channel.id,
            name: name,
            description: description.isNotEmpty ? description : null,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Channel updated')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update channel: $e')));
    }
  }

  void _confirmDeleteChannel(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Delete Channel'),
        content: Text(
          'Permanently delete #${channel.name ?? channel.id}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doDeleteChannel(context, ref);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _doDeleteChannel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(serverStateProvider.notifier).deleteChannel(channel.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Channel deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete channel: $e')));
    }
  }

  void _showChannelPermissions(BuildContext context, WidgetRef ref) {
    final srv = ref.read(serverStateProvider).asData?.value.selectedServer;
    if (srv == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChannelPermissionsScreen(channel: channel, server: srv),
      ),
    );
  }
}

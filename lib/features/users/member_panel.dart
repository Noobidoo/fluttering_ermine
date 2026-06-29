import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../auth/providers/login_notifier.dart';
import '../messaging/providers/messaging_notifier.dart';
import '../servers/providers/permissions_provider.dart';
import '../servers/providers/server_notifier.dart';
import 'user_profile_sheet.dart';

class MemberPanel extends ConsumerWidget {
  const MemberPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverData = ref.watch(serverStateProvider).value;
    final messagingData = ref.watch(messagingStateProvider);
    final memberIds = serverData?.currentServerMemberIds;
    final serverId = serverData?.selectedServer?.id;

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
            child: const Text(
              'Members',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (serverData?.loadingMembers ?? false)
            const Expanded(child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (memberIds == null || memberIds.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No members', style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            Expanded(
              child: Builder(
                builder: (_) {
                  ref.read(messagingStateProvider.notifier).ensureUsersCached(memberIds);
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: memberIds.length,
                    itemBuilder: (_, i) => _MemberTile(
                      userId: memberIds[i],
                      serverId: serverId!,
                      user: messagingData.userCache[memberIds[i]],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  final String userId;
  final String serverId;
  final RevoltUser? user;

  const _MemberTile({required this.userId, required this.serverId, required this.user});

  Widget? get _statusText {
    final u = user;
    if (u == null || u.statusText == null || u.statusText!.isEmpty) {
      return null;
    }
    return Text(
      u.statusText!,
      style: const TextStyle(color: Colors.white38, fontSize: 11),
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = user;
    final name = u?.resolveDisplayName(serverId) ?? userId;
    final p = u?.presence ?? UserPresence.online;
    final isOnline = p == UserPresence.online || p == UserPresence.focus;
    final authData = ref.read(loginStateProvider).value ?? const LoginStateData();

    // Role colour
    final serverStateWatched = ref.watch(serverStateProvider).value;
    final roleColour = u != null
        ? serverStateWatched?.roleColourFor(serverId, u.serverProfiles[serverId]?.roles ?? [])
        : null;
    final nameColour = roleColour != null
        ? Color(roleColour)
        : (isOnline ? Colors.white : Colors.white54);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundImage: u != null
                  ? NetworkImage(
                      u.resolveAvatarUrl(serverId, authData.autumnBase, authData.apiBase),
                    )
                  : null,
              backgroundColor: const Color(0xFF7F5AF0),
              onBackgroundImageError: u != null ? (_, _) {} : null,
              child: u == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    )
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: presenceColor(p),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF141418), width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: nameColour,
            fontWeight: isOnline ? FontWeight.w500 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _statusText,

        onTap: () => _showProfileSheet(context, ref),
        onLongPress: () => _showMemberContextMenu(context, ref),
      ),
    );
  }

  void _showProfileSheet(BuildContext context, WidgetRef ref) {
    if (user == null) return;
    showUserProfileSheet(context, ref, user!);
  }

  void _showMemberContextMenu(BuildContext context, WidgetRef ref) {
    final authData = ref.read(loginStateProvider).value ?? const LoginStateData();
    final isSelf = userId == authData.currentUser?.id;
    if (isSelf || user == null) return;

    final perms = ref.read(effectivePermissionsProvider(serverId));
    final canKick = (perms & Permission.kickMembers) != 0;
    final canBan = (perms & Permission.banMembers) != 0;
    if (!canKick && !canBan) return;

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
                user!.resolveDisplayName(serverId),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            if (canKick)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: Colors.orangeAccent),
                title: const Text('Kick Member'),
                subtitle: const Text(
                  'Remove from server',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmKick(context, ref);
                },
              ),
            if (canBan)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: const Text('Ban Member'),
                subtitle: const Text(
                  'Remove and prevent rejoin',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmBan(context, ref);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmKick(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Kick Member'),
        content: Text(
          'Remove ${user?.resolveDisplayName(serverId) ?? userId} from the server?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doKick(context, ref);
            },
            child: const Text('Kick', style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  void _doKick(BuildContext context, WidgetRef ref) async {
    try {
      final serverNotifier = ref.read(serverStateProvider.notifier);
      await serverNotifier.kickMember(userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user?.resolveDisplayName(serverId) ?? userId} was kicked')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to kick: $e')));
    }
  }

  void _confirmBan(BuildContext context, WidgetRef ref) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Ban Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ban ${user?.resolveDisplayName(serverId) ?? userId}?',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                hintText: 'Reason (optional)',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doBan(context, ref, reasonCtrl.text.trim());
            },
            child: const Text('Ban', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _doBan(BuildContext context, WidgetRef ref, String reason) async {
    try {
      final serverNotifier = ref.read(serverStateProvider.notifier);
      await serverNotifier.banMember(userId, reason: reason.isNotEmpty ? reason : null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user?.resolveDisplayName(serverId) ?? userId} was banned')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to ban: $e')));
    }
  }
}

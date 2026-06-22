import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import 'user_profile_sheet.dart';

class MemberPanel extends StatelessWidget {
  const MemberPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerState>();
    final messaging = context.watch<MessagingState>();
    final auth = context.watch<AuthState>();
    final memberIds = server.currentServerMemberIds;
    final serverId = server.selectedServer?.id;

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
          if (server.isLoadingMembers)
            const Expanded(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (memberIds == null || memberIds.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No members',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            Expanded(
              child: Builder(
                builder: (ctx) {
                  ctx.read<MessagingState>().ensureUsersCached(memberIds);
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: memberIds.length,
                    itemBuilder: (_, i) => _MemberTile(
                      userId: memberIds[i],
                      serverId: serverId!,
                      user: messaging.getUser(memberIds[i]),
                      autumnBase: auth.autumnBase,
                      apiBase: auth.apiBase,
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

class _MemberTile extends StatelessWidget {
  final String userId;
  final String serverId;
  final RevoltUser? user;
  final String autumnBase;
  final String apiBase;

  const _MemberTile({
    required this.userId,
    required this.serverId,
    required this.user,
    required this.autumnBase,
    required this.apiBase,
  });

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
  Widget build(BuildContext context) {
    final u = user;
    final name = u?.resolveDisplayName(serverId) ?? userId;
    final p = u?.presence ?? UserPresence.online;
    final isOnline = p == UserPresence.online || p == UserPresence.focus;

    // Role colour
    final serverState = context.watch<ServerState>();
    final roleColour = u != null
        ? serverState.roleColourFor(
            serverId,
            u.serverProfiles[serverId]?.roles ?? [],
          )
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
                      u.resolveAvatarUrl(serverId, autumnBase, apiBase),
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

        onTap: () => _showProfileSheet(context),
        onLongPress: () => _showMemberContextMenu(context),
      ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    if (user == null) return;
    showUserProfileSheet(context, user!);
  }

  void _showMemberContextMenu(BuildContext context) {
    final auth = context.read<AuthState>();
    final isSelf = userId == auth.currentUser?.id;
    if (isSelf || user == null) return;

    final canKick = auth.hasPermission(serverId, Permission.kickMembers);
    final canBan = auth.hasPermission(serverId, Permission.banMembers);
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            if (canKick)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline,
                    color: Colors.orangeAccent),
                title: const Text('Kick Member'),
                subtitle: const Text(
                  'Remove from server',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmKick(context);
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
                  _confirmBan(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmKick(BuildContext context) {
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doKick(context);
            },
            child: const Text('Kick',
                style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  void _doKick(BuildContext context) async {
    try {
      final server = context.read<ServerState>();
      final srv = server.selectedServer;
      if (srv == null) return;
      await server.kickMember(userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user?.resolveDisplayName(serverId) ?? userId} was kicked')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to kick: $e')),
      );
    }
  }

  void _confirmBan(BuildContext context) {
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
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
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
              _doBan(context, reasonCtrl.text.trim());
            },
            child: const Text('Ban',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _doBan(BuildContext context, String reason) async {
    try {
      final server = context.read<ServerState>();
      final srv = server.selectedServer;
      if (srv == null) return;
      await server.banMember(userId, reason: reason.isNotEmpty ? reason : null);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user?.resolveDisplayName(serverId) ?? userId} was banned')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ban: $e')),
      );
    }
  }
}

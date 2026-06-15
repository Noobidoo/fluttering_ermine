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
            color: isOnline ? Colors.white : Colors.white54,
            fontWeight: isOnline ? FontWeight.w500 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _statusText,

        onTap: () => _showProfileSheet(context),
      ),
    );
  }

  void _showProfileSheet(BuildContext context) {
    if (user == null) return;
    showUserProfileSheet(context, user!);
  }
}

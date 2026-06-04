import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';

class MemberPanel extends StatelessWidget {
  const MemberPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerState>();
    final messaging = context.watch<MessagingState>();
    final auth = context.watch<AuthState>();
    final members = server.currentServerMembers;

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
          else if (members == null || members.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No members',
                    style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            Expanded(
              child: Builder(builder: (ctx) {
                final userIds = members.map((m) => m.userId).toList();
                ctx.read<MessagingState>().ensureUsersCached(userIds);
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: members.length,
                  itemBuilder: (_, i) => _MemberTile(
                    member: members[i],
                    user: messaging.getUser(members[i].userId),
                    autumnBase: auth.autumnBase,
                    apiBase: auth.apiBase,
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final RevoltMember member;
  final RevoltUser? user;
  final String autumnBase;
  final String apiBase;

  const _MemberTile({
    required this.member,
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
    final name = member.nickname ??
        user?.displayUsername ??
        member.userId;
    final p = user?.presence ?? UserPresence.online;
    final isOnline =
        p == UserPresence.online || p == UserPresence.focus;

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
              backgroundImage: user != null
                  ? NetworkImage(user!.avatarUrlFor(autumnBase, apiBase))
                  : null,
              backgroundColor: const Color(0xFF7F5AF0),
              onBackgroundImageError: user != null ? (_, _) {} : null,
              child: user == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white),
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
                  border: Border.all(
                      color: const Color(0xFF141418), width: 2),
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
    final p = user!.presence;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Banner
            if (user!.banner != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  user!.bannerUrlFor(autumnBase) ?? '',
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(height: 120),
                ),
              ),
            if (user!.banner != null) const SizedBox(height: 12),
            // Avatar + presence
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage: NetworkImage(
                      user!.avatarUrlFor(autumnBase, apiBase)),
                  backgroundColor: const Color(0xFF7F5AF0),
                  child: user!.avatar != null
                      ? null
                      : Text(
                          user!.displayUsername.isNotEmpty
                              ? user!.displayUsername[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 24, color: Colors.white),
                        ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: presenceColor(p),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF1E1E26), width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              user!.displayUsername,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '@${user!.username}',
              style: const TextStyle(color: Colors.white54),
            ),
            // Status text
            if (user!.statusText != null &&
                user!.statusText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user!.statusText!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
            // Bio
            if (user!.profileContent != null &&
                user!.profileContent!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                user!.profileContent!,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

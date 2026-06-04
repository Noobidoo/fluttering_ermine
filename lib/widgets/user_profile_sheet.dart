import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';

void showUserProfileSheet(BuildContext context, RevoltUser user) {
  final auth = context.read<AuthState>();
  final autumnBase = auth.autumnBase;
  final apiBase = auth.apiBase;
  final p = user.presence;

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
          if (user.banner != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                user.bannerUrlFor(autumnBase) ?? '',
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(height: 120),
              ),
            ),
          if (user.banner != null) const SizedBox(height: 12),
          // Avatar + presence
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundImage: NetworkImage(
                    user.avatarUrlFor(autumnBase, apiBase)),
                backgroundColor: const Color(0xFF7F5AF0),
                child: user.avatar != null
                    ? null
                    : Text(
                        user.displayUsername.isNotEmpty
                            ? user.displayUsername[0].toUpperCase()
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
            user.displayUsername,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '@${user.username}',
            style: const TextStyle(color: Colors.white54),
          ),
          // Status text
          if (user.statusText != null &&
              user.statusText!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                user.statusText!,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
          // Bio
          if (user.profileContent != null &&
              user.profileContent!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              user.profileContent!,
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

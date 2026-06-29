import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../auth/providers/login_notifier.dart';
import '../core/providers/service_providers.dart';

void showUserProfileSheet(BuildContext context, WidgetRef ref, RevoltUser user) {
  final authData = ref.read(loginStateProvider).value ?? const LoginStateData();
  final autumnBase = authData.autumnBase;
  final apiBase = authData.apiBase;
  final isSelf = user.id == authData.currentUser?.id;

  final Future<UserProfile>? profileFuture = isSelf
      ? null
      : ref.read(revoltServiceProvider).fetchUserProfile(user.id);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E26),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => FutureBuilder<UserProfile>(
      future: profileFuture,
      builder: (context, snapshot) {
        final p = user.presence;
        final profileContent = isSelf ? user.profileContent : snapshot.data?.content;
        final banner = isSelf ? user.banner : snapshot.data?.background;

        final avatarFallback = SizedBox(
          width: 64,
          height: 64,
          child: Center(
            child: Text(
              user.resolveDisplayName(null).isNotEmpty
                  ? user.resolveDisplayName(null)[0].toUpperCase()
                  : '?',
              style: const TextStyle(fontSize: 24, color: Colors.white),
            ),
          ),
        );

        final avatarWidget = user.avatar != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.network(
                  user.resolveAvatarUrl(null, autumnBase, apiBase),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color.fromARGB(255, 255, 0, 0),
                      shape: BoxShape.circle,
                    ),
                    child: avatarFallback,
                  ),
                ),
              )
            : CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFF7F5AF0),
                child: avatarFallback,
              );

        final avatarStack = Stack(
          clipBehavior: Clip.none,
          children: [
            avatarWidget,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: presenceColor(p),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E1E26), width: 2),
                ),
              ),
            ),
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (banner != null)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        banner.urlFor(autumnBase),
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(height: 120),
                      ),
                    ),
                    Positioned(left: 16, top: 28, child: avatarStack),
                  ],
                ),
              if (banner == null) avatarStack,
              const SizedBox(height: 12),
              Text(
                user.resolveDisplayName(null),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text('@${user.username}', style: const TextStyle(color: Colors.white54)),
              if (user.statusText != null && user.statusText!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              if (profileContent != null && profileContent.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  profileContent,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    ),
  );
}

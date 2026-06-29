import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/login_notifier.dart';
import '../../../features/core/providers/service_providers.dart';
import '../../../models/models.dart';
import '../../settings/settings_screen.dart';

class UserBar extends ConsumerWidget {
  const UserBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(loginStateProvider).asData?.value;
    final user = auth?.currentUser;
    if (user == null) return const SizedBox.shrink();

    final service = ref.read(revoltServiceProvider);
    final autumnBase = service.autumnBase;
    final apiBase = service.apiBase;

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
                  backgroundImage: NetworkImage(user.resolveAvatarUrl(null, autumnBase, apiBase)),
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
                      border: Border.all(color: const Color(0xFF0D0D0F), width: 2),
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (user.statusText != null && user.statusText!.isNotEmpty)
                    Text(
                      user.statusText!,
                      style: const TextStyle(fontSize: 11, color: Colors.white38),
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

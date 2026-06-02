import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_state.dart';
import '../providers/server_state.dart';
import '../screens/settings_screen.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerState>();
    final auth = context.watch<AuthState>();

    return Container(
      width: 68,
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailIcon(
            tooltip: 'Direct Messages',
            selected: server.showDMs,
            onTap: server.selectDMs,
            child: const Icon(Icons.message_rounded, size: 22),
          ),
          const _Divider(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: server.servers.length,
              itemBuilder: (_, i) {
                final srv = server.servers[i];
                return _RailIcon(
                  tooltip: srv.name,
                  selected: server.selectedServer?.id == srv.id,
                  hasUnread: server.serverUnreadCount(srv.id) > 0,
                  onTap: () => server.selectServer(srv),
                  child: srv.iconUrlFor(auth.autumnBase) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            srv.iconUrlFor(auth.autumnBase)!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) =>
                                _Initials(srv.name),
                          ),
                        )
                      : _Initials(srv.name),
                );
              },
            ),
          ),
          _RailIcon(
            tooltip: 'Settings',
            selected: false,
            onTap: () => SettingsScreen.show(context),
            child: const Icon(Icons.settings_outlined, size: 20, color: Colors.white54),
          ),
          _RailIcon(
            tooltip: 'Logout',
            selected: false,
            onTap: () => context.read<AuthState>().logout(),
            child: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final bool hasUnread;
  final VoidCallback onTap;
  final Widget child;

  const _RailIcon({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
    this.hasUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF7F5AF0)
                    : const Color(0xFF1E1E26),
                borderRadius: BorderRadius.circular(selected ? 12 : 22),
              ),
              child: Center(child: child),
            ),
            if (hasUnread && !selected)
              Positioned(
                right: 8,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2CB67D),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  const _Initials(this.name);

  @override
  Widget build(BuildContext context) {
    final initials =
        name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();
    return Text(initials,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold));
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 8, thickness: 1, indent: 14, endIndent: 14);
}

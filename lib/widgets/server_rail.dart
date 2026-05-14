import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 68,
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailIcon(
            tooltip: 'Direct Messages',
            selected: state.showDMs,
            onTap: state.selectDMs,
            child: const Icon(Icons.message_rounded, size: 22),
          ),
          const _Divider(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: state.servers.length,
              itemBuilder: (_, i) {
                final srv = state.servers[i];
                return _RailIcon(
                  tooltip: srv.name,
                  selected: state.selectedServer?.id == srv.id,
                  onTap: () => state.selectServer(srv),
                  child: srv.iconUrlFor(state.autumnBase) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            srv.iconUrlFor(state.autumnBase)!,
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
            tooltip: 'Logout',
            selected: false,
            onTap: () => context.read<AppState>().logout(),
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
  final VoidCallback onTap;
  final Widget child;

  const _RailIcon({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
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

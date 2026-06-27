import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/providers/login_notifier.dart';
import '../features/servers/providers/server_notifier.dart';
import '../screens/settings_screen.dart';

class ServerRail extends ConsumerWidget {
  const ServerRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverStateProvider).value;
    final loginNotifier = ref.read(loginStateProvider.notifier);

    return Container(
      width: 68,
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _RailIcon(
            tooltip: 'Direct Messages',
            selected: server?.showDMs ?? false,
            onTap: () {
              ref.read(serverStateProvider.notifier).selectDMs();
            },
            child: const Icon(Icons.message_rounded, size: 22),
          ),
          const _Divider(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: server?.servers.length ?? 0,
              itemBuilder: (_, i) {
                final srv = server!.servers[i];
                return _RailIcon(
                  key: ValueKey('server_${srv.id}'),
                  tooltip: srv.name,
                  selected: server.selectedServer?.id == srv.id,
                  hasUnread: server.serverUnreadCount(srv.id) > 0,
                  onTap: () {
                    ref
                        .read(serverStateProvider.notifier)
                        .selectServer(srv, userId: loginNotifier.currentUser?.id);
                  },
                  child: srv.iconUrlFor(loginNotifier.autumnBase) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            srv.iconUrlFor(loginNotifier.autumnBase)!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => _Initials(srv.name),
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
            tooltip: 'Create Server',
            selected: false,
            onTap: () => _showCreateServerDialog(context),
            child: const Icon(Icons.add_box_rounded, size: 18, color: Color(0xFF7F5AF0)),
          ),
          _RailIcon(
            tooltip: 'Join Server',
            selected: false,
            onTap: () => _showJoinDialog(context),
            child: const Icon(Icons.add, size: 20, color: Color(0xFF2CB67D)),
          ),
          _RailIcon(
            tooltip: 'Logout',
            selected: false,
            onTap: () => ref.read(loginStateProvider.notifier).logout(),
            child: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

void _showCreateServerDialog(BuildContext context) {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E26),
      title: const Text('Create Server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Server name',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(ctx);
            try {
              final container = ProviderScope.containerOf(context);
              await container
                  .read(serverStateProvider.notifier)
                  .createServer(
                    name,
                    description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  );
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Server "$name" created!')));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Failed to create server: $e')));
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

void _showJoinDialog(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E26),
      title: const Text('Join Server'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Enter invite code',
          hintStyle: TextStyle(color: Colors.white38),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(color: Colors.white),
        autofocus: true,
        onSubmitted: (_) async {
          final code = controller.text.trim();
          if (code.isEmpty) return;
          Navigator.of(dialogCtx).pop();
          try {
            await container.read(serverStateProvider.notifier).joinInvite(code);
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Joined server!')));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to join: $e')));
          }
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () async {
            final code = controller.text.trim();
            if (code.isEmpty) return;
            Navigator.of(dialogCtx).pop();
            try {
              await container.read(serverStateProvider.notifier).joinInvite(code);
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Joined server!')));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Failed to join: $e')));
            }
          },
          child: const Text('Join'),
        ),
      ],
    ),
  );
}

class _RailIcon extends StatelessWidget {
  final String tooltip;
  final bool selected;
  final bool hasUnread;
  final VoidCallback onTap;
  final Widget child;

  const _RailIcon({
    super.key,
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
                color: selected ? const Color(0xFF7F5AF0) : const Color(0xFF1E1E26),
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
                  decoration: const BoxDecoration(color: Color(0xFF2CB67D), shape: BoxShape.circle),
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
    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join();
    return Text(initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold));
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 8, thickness: 1, indent: 14, endIndent: 14);
}

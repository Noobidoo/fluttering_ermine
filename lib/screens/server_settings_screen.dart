import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/server_state.dart';
import 'role_manager_screen.dart';

// =============================================================================
// Server Settings Dialog
// =============================================================================

/// Opens the server settings dialog for the currently selected server.
void showServerSettingsDialog(BuildContext context) {
  final server = context.read<ServerState>();
  final srv = server.selectedServer;
  if (srv == null) return;

  showDialog(
    context: context,
    builder: (ctx) => ServerSettingsDialog(srv: srv),
  );
}

class ServerSettingsDialog extends StatefulWidget {
  final RevoltServer srv;
  const ServerSettingsDialog({super.key, required this.srv});

  @override
  State<ServerSettingsDialog> createState() => ServerSettingsDialogState();
}

class ServerSettingsDialogState extends State<ServerSettingsDialog> {
  List<RevoltInvite>? _invites;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    final server = context.read<ServerState>();
    try {
      final invites = await server.fetchInvites(widget.srv.id);
      if (!mounted) return;
      setState(() => _invites = invites);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    final srvId = widget.srv.id;
    final canManageSrv = auth.hasPermission(srvId, Permission.manageServer);
    final canManageCh = auth.hasPermission(srvId, Permission.manageChannel);
    final canManageRoles = auth.hasPermission(srvId, Permission.manageRole);
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E26),
      title: Text(widget.srv.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Server management ---
            if (canManageSrv)
              SettingsButton(
                icon: Icons.edit_rounded,
                label: 'Edit server',
                onTap: () {
                  Navigator.of(context).pop();
                  showEditServerDialog(context, widget.srv);
                },
              ),
            if (canManageCh)
              SettingsButton(
                icon: Icons.add_rounded,
                label: 'Create channel',
                onTap: () {
                  Navigator.of(context).pop();
                  showCreateChannelDialog(context);
                },
              ),
            if (canManageRoles)
              SettingsButton(
                icon: Icons.security_rounded,
                label: 'Roles & Permissions',
                onTap: () {
                  Navigator.of(context).pop();
                  showRoleManager(context, widget.srv);
                },
              ),
            SettingsButton(
              icon: Icons.link,
              label: 'Create invite',
              onTap: () {
                Navigator.of(context).pop();
                createInvite(context);
              },
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            const SizedBox(height: 12),
            const Text(
              'Existing invites',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(
                'Failed to load: $_error',
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            if (_invites == null)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (_invites!.isEmpty)
              const Text(
                'No invites yet',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              )
            else
              ..._invites!.map(
                (inv) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 14, color: Colors.white38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          inv.id,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF2A2A30), height: 1),
            // Delete server
            if (canManageSrv)
              SettingsButton(
                icon: Icons.delete_forever_rounded,
                label: 'Delete server',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.of(context).pop();
                  confirmDeleteServer(context, widget.srv);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// =============================================================================
// Create invite
// =============================================================================

void createInvite(BuildContext context) async {
  final server = context.read<ServerState>();
  final channel =
      server.selectedChannel ??
      server.selectedServerChannels.cast<RevoltChannel?>().firstWhere(
        (c) => c?.type == ChannelType.textChannel && !c!.isVoice,
        orElse: () => null,
      );
  if (channel == null) return;
  try {
    final code = await server.createInvite(channel.id);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E26),
        title: const Text('Invite Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with others to invite them:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Failed to create invite: $e')));
  }
}

// =============================================================================
// Create channel
// =============================================================================

void showCreateChannelDialog(BuildContext context) {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  bool isVoice = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Create Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Channel name',
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: Colors.white54),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Voice channel',
                    style: TextStyle(fontSize: 14, color: Colors.white70)),
                const Spacer(),
                Switch(
                  value: isVoice,
                  onChanged: (v) => setDialogState(() => isVoice = v),
                  activeThumbColor: const Color(0xFF7F5AF0),
                ),
              ],
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
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              doCreateChannel(context, name, descCtrl.text.trim(), isVoice);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}

void doCreateChannel(BuildContext context, String name, String description,
    bool isVoice) async {
  try {
    final server = context.read<ServerState>();
    await server.createChannel(
      name,
      description: description.isNotEmpty ? description : null,
      isVoice: isVoice,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Channel #$name created')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to create channel: $e')),
    );
  }
}

// =============================================================================
// Edit server
// =============================================================================

void showEditServerDialog(BuildContext context, RevoltServer srv) {
  final nameCtrl = TextEditingController(text: srv.name);
  final descCtrl = TextEditingController(text: srv.description ?? '');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      title: const Text('Edit Server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Server name',
              labelStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            maxLines: 3,
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
            doEditServer(
                context, srv.id, nameCtrl.text.trim(), descCtrl.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void doEditServer(BuildContext context, String serverId, String name,
    String description) async {
  if (name.isEmpty) return;
  try {
    final server = context.read<ServerState>();
    await server.updateSelectedServer(
      name: name,
      description: description.isNotEmpty ? description : null,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server updated')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to update server: $e')),
    );
  }
}

void confirmDeleteServer(BuildContext context, RevoltServer srv) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E24),
      title: const Text('Delete Server'),
      content: Text(
        'Permanently delete ${srv.name}? This cannot be undone.',
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
            doDeleteServer(context);
          },
          child: const Text('Delete',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
}

void doDeleteServer(BuildContext context) async {
  try {
    final server = context.read<ServerState>();
    await server.deleteSelectedServer();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server deleted')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to delete server: $e')),
    );
  }
}

// =============================================================================
// Role manager
// =============================================================================

void showRoleManager(BuildContext context, RevoltServer srv) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RoleManagerScreen(server: srv),
    ),
  );
}

// =============================================================================
// Settings button widget
// =============================================================================

class SettingsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const SettingsButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 14, color: c)),
          ],
        ),
      ),
    );
  }
}

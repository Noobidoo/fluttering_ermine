import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';

// -- Permission definitions -------------------------------------------------

// =============================================================================
// Role Manager Screen — full-screen role & permission editor + member assignment
// =============================================================================

class RoleManagerScreen extends StatefulWidget {
  final RevoltServer server;

  const RoleManagerScreen({super.key, required this.server});

  @override
  State<RoleManagerScreen> createState() => _RoleManagerScreenState();
}

class _RoleManagerScreenState extends State<RoleManagerScreen> {
  Map<String, RevoltRole> _roles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ss = context.read<ServerState>();
    final auth = context.read<AuthState>();
    await ss.fetchRoles(currentUserId: auth.currentUser?.id);
    if (!mounted) return;
    setState(() {
      _roles = ss.selectedServerRoles;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E26),
        title: Text('${widget.server.name} — Roles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            tooltip: 'Assign roles to members',
            onPressed: _showMemberRoleSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create role',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _roles.isEmpty
              ? const Center(
                  child: Text('No roles yet',
                      style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _roles.length,
                  itemBuilder: (_, i) {
                    final entry = _roles.entries.elementAt(i);
                    return _RoleCard(
                      role: entry.value,
                      onEdit: () => _showEditDialog(entry.value),
                      onDelete: entry.key != 'default'
                          ? () => _confirmDelete(entry.key)
                          : null,
                      onAssign: () =>
                          _showMemberPickerForRole(entry.key, entry.value),
                    );
                  },
                ),
    );
  }

  // -- Create role -----------------------------------------------------------

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    int colour = 0xFF7F5AF0;
    int rank = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          title: const Text('Create Role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Role name',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                style: const TextStyle(fontSize: 14),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Colour', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  _ColourPicker(
                    selected: colour,
                    onChanged: (c) => setDlg(() => colour = c),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Rank', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: TextEditingController(text: rank.toString()),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onChanged: (v) => rank = int.tryParse(v) ?? 0,
                    ),
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
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(ctx);
                _doCreate(n, colour, rank);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doCreate(String name, int colour, int rank) async {
    try {
      final ss = context.read<ServerState>();
      await ss.createRole(name);
      final newId = ss.selectedServerRoles.entries
          .lastWhere((e) => e.value.name == name)
          .key;
      await ss.updateRole(newId, colour: colour, rank: rank);
      await _load();
      if (!mounted) return;
      _snack('Role "$name" created');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to create role: $e');
    }
  }

  // -- Edit role -------------------------------------------------------------

  void _showEditDialog(RevoltRole role) {
    final nameCtrl = TextEditingController(text: role.name);
    int colour = role.colour ?? 0xFF7F5AF0;
    int rank = role.rank;
    bool hoist = role.hoist;
    int permMask = permValue(role.permissions);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          title: Text('Edit "${role.name}"'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Role name',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Colour', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    _ColourPicker(
                      selected: colour,
                      onChanged: (c) => setDlg(() => colour = c),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Rank', style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: TextEditingController(
                            text: rank.toString()),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (v) =>
                            setDlg(() => rank = int.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Show separately in member list',
                        style: TextStyle(fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: hoist,
                      onChanged: (v) => setDlg(() => hoist = v),
                      activeThumbColor: const Color(0xFF7F5AF0),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Permissions',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...kServerPermissions.map(
                  (perm) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(perm.label,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(perm.description,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38)),
                    value: (permMask & perm.bit) != 0,
                    activeColor: const Color(0xFF7F5AF0),
                    onChanged: (v) => setDlg(() {
                      if (v == true) {
                        permMask |= perm.bit;
                      } else {
                        permMask &= ~perm.bit;
                      }
                    }),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(ctx);
                _doUpdate(
                    role.id, n, colour, rank, hoist, {'a': permMask, 'd': 0});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doUpdate(
    String roleId,
    String name,
    int colour,
    int rank,
    bool hoist,
    dynamic permissions,
  ) async {
    try {
      final ss = context.read<ServerState>();
      await ss.updateRole(
        roleId,
        name: name,
        colour: colour,
        rank: rank,
        hoist: hoist,
        permissions: permissions,
      );
      await _load();
      if (!mounted) return;
      _snack('Role "$name" updated');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to update role: $e');
    }
  }

  // -- Delete role -----------------------------------------------------------

  void _confirmDelete(String roleId) {
    final role = _roles[roleId];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Delete Role'),
        content: Text(
          'Permanently delete role "${role?.name ?? roleId}"?',
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
              _doDelete(roleId);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _doDelete(String roleId) async {
    try {
      final ss = context.read<ServerState>();
      await ss.deleteRole(roleId);
      await _load();
      if (!mounted) return;
      _snack('Role deleted');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to delete role: $e');
    }
  }

  // -- Member role assignment ------------------------------------------------

  /// Shows a sheet to pick a member and toggle roles on them.
  void _showMemberRoleSheet() {
    final ss = context.read<ServerState>();
    final memberIds = ss.currentServerMemberIds;
    final messaging = context.read<MessagingState>();
    if (memberIds == null || memberIds.isEmpty) {
      _snack('No members loaded');
      return;
    }
    messaging.ensureUsersCached(memberIds);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => _MemberRoleAssignmentSheet(
          serverId: widget.server.id,
          memberIds: memberIds,
          roles: _roles,
          scrollCtrl: scrollCtrl,
          onChanged: _load,
        ),
      ),
    );
  }

  /// Shows a member picker for assigning a specific role.
  void _showMemberPickerForRole(String roleId, RevoltRole role) {
    final ss = context.read<ServerState>();
    final memberIds = ss.currentServerMemberIds;
    final messaging = context.read<MessagingState>();
    if (memberIds == null || memberIds.isEmpty) return;
    messaging.ensureUsersCached(memberIds);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => _RoleMemberToggleSheet(
          serverId: widget.server.id,
          roleId: roleId,
          roleName: role.name,
          memberIds: memberIds,
          scrollCtrl: scrollCtrl,
          onChanged: _load,
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

// =============================================================================
// Role card widget
// =============================================================================

class _RoleCard extends StatelessWidget {
  final RevoltRole role;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onAssign;

  const _RoleCard({
    required this.role,
    required this.onEdit,
    this.onDelete,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final colour = role.colour != null ? Color(role.colour!) : null;
    return Card(
      color: const Color(0xFF1E1E26),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colour ?? const Color(0xFF7F5AF0),
          radius: 14,
          child: Text(
            role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          role.name,
          style: TextStyle(
            color: colour ?? Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Rank ${role.rank} · ${role.isAdmin ? 'Admin' : _permSummary(role.permissions)}',
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.person_add_outlined,
                  size: 18, color: Colors.white54),
              tooltip: 'Assign to members',
              onPressed: onAssign,
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
                onPressed: onDelete,
              ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }

  String _permSummary(dynamic permStr) {
    final val = permValue(permStr);
    final enabled =
        kServerPermissions.where((p) => (val & p.bit) != 0).length;
    return '$enabled permissions';
  }
}

// =============================================================================
// Member ↔ Role assignment sheet
// =============================================================================

class _MemberRoleAssignmentSheet extends StatelessWidget {
  final String serverId;
  final List<String> memberIds;
  final Map<String, RevoltRole> roles;
  final ScrollController scrollCtrl;
  final VoidCallback onChanged;

  const _MemberRoleAssignmentSheet({
    required this.serverId,
    required this.memberIds,
    required this.roles,
    required this.scrollCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.people_outline,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Assign Roles to Members',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF2A2A30), height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollCtrl,
            itemCount: memberIds.length,
            itemBuilder: (_, i) {
              final uid = memberIds[i];
              final user = messaging.getUser(uid);
              final name = user?.resolveDisplayName(serverId) ?? uid;
              final userRoles =
                  user?.serverProfiles[serverId]?.roles ?? [];
              return _MemberRoleTile(
                userId: uid,
                displayName: name,
                assignedRoleIds: userRoles,
                roles: roles,
                serverId: serverId,
                onChanged: onChanged,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MemberRoleTile extends StatelessWidget {
  final String userId;
  final String displayName;
  final List<String> assignedRoleIds;
  final Map<String, RevoltRole> roles;
  final String serverId;
  final VoidCallback onChanged;

  const _MemberRoleTile({
    required this.userId,
    required this.displayName,
    required this.assignedRoleIds,
    required this.roles,
    required this.serverId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF7F5AF0),
          child: Text(
            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
        title: Text(displayName, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '${assignedRoleIds.length} role(s)',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        children: roles.entries.map((entry) {
          final isAssigned = assignedRoleIds.contains(entry.key);
          final colour =
              entry.value.colour != null
                  ? Color(entry.value.colour!)
                  : null;
          return CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 16),
            title: Text(
              entry.value.name,
              style: TextStyle(
                color: colour ?? Colors.white70,
                fontSize: 13,
              ),
            ),
            value: isAssigned,
            activeColor: const Color(0xFF7F5AF0),
            onChanged: (v) async {
              try {
                final ss = context.read<ServerState>();
                if (v == true) {
                  await ss.assignRoleToMember(userId, entry.key);
                } else {
                  await ss.removeRoleFromMember(userId, entry.key);
                }
                onChanged();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed: $e')),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// Members who have a specific role (toggle per member)
// =============================================================================

class _RoleMemberToggleSheet extends StatelessWidget {
  final String serverId;
  final String roleId;
  final String roleName;
  final List<String> memberIds;
  final ScrollController scrollCtrl;
  final VoidCallback onChanged;

  const _RoleMemberToggleSheet({
    required this.serverId,
    required this.roleId,
    required this.roleName,
    required this.memberIds,
    required this.scrollCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.person_add_outlined,
                  size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text('Assign "$roleName"',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(color: Color(0xFF2A2A30), height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollCtrl,
            itemCount: memberIds.length,
            itemBuilder: (_, i) {
              final uid = memberIds[i];
              final user = messaging.getUser(uid);
              final name = user?.resolveDisplayName(serverId) ?? uid;
              final hasRole =
                  user?.serverProfiles[serverId]?.roles.contains(roleId) ??
                      false;
              return CheckboxListTile(
                dense: true,
                title: Text(name, style: const TextStyle(fontSize: 14)),
                value: hasRole,
                activeColor: const Color(0xFF7F5AF0),
                onChanged: (v) async {
                  try {
                    final ss = context.read<ServerState>();
                    if (v == true) {
                      await ss.assignRoleToMember(uid, roleId);
                    } else {
                      await ss.removeRoleFromMember(uid, roleId);
                    }
                    onChanged();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Colour picker widget
// =============================================================================

class _ColourPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ColourPicker({required this.selected, required this.onChanged});

  static const _colours = [
    0xFF7F5AF0, // purple
    0xFF2CB67D, // green
    0xFFFFAA33, // orange
    0xFFFF6B6B, // red
    0xFF4ECDC4, // teal
    0xFF45B7D1, // blue
    0xFF96CEB4, // sage
    0xFFFFEAA7, // yellow
    0xFFDDA0DD, // plum
    0xFF98D8C8, // mint
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _colours.map((c) {
        final isSelected = c == selected;
        return GestureDetector(
          onTap: () => onChanged(c),
          child: Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

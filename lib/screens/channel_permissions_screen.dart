import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../features/servers/providers/server_notifier.dart';

int permVal(String? s) => int.tryParse(s ?? '') ?? 0;

// =============================================================================
// Channel Permissions Override Screen
// =============================================================================

class ChannelPermissionsScreen extends ConsumerStatefulWidget {
  final RevoltChannel channel;
  final RevoltServer server;

  const ChannelPermissionsScreen({super.key, required this.channel, required this.server});

  @override
  ConsumerState<ChannelPermissionsScreen> createState() => _ChannelPermissionsScreenState();
}

class _ChannelPermissionsScreenState extends ConsumerState<ChannelPermissionsScreen> {
  final _rolePermCtrl = TextEditingController();
  final _userPermCtrl = TextEditingController();
  final _defaultPermCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Load current values (RevoltChannel doesn't store these currently,
    // so we start empty and the user can set them).
  }

  @override
  void dispose() {
    _rolePermCtrl.dispose();
    _userPermCtrl.dispose();
    _defaultPermCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ss = ref.watch(serverStateProvider).value;
    final roles = ss?.selectedServerRoles ?? {};

    return Scaffold(
      backgroundColor: const Color(0xFF141418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E26),
        title: Text('Permissions — #${widget.channel.name ?? widget.channel.id}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Default permissions ---
            const Text(
              'Default Permissions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Permissions granted to all members by default in this channel.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            ...kChannelPermissions.map(
              (d) => _PermToggle(
                label: d.label,
                value: (permVal(_defaultPermCtrl.text) & d.bit) != 0,
                onChanged: (v) {
                  var val = permVal(_defaultPermCtrl.text);
                  if (v) {
                    val |= d.bit;
                  } else {
                    val &= ~d.bit;
                  }
                  _defaultPermCtrl.text = val.toString();
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 24),

            // --- Role overrides ---
            const Text(
              'Role Permission Overrides',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Override specific permissions for individual roles.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            if (roles.isEmpty)
              const Text('No roles defined yet.', style: TextStyle(color: Colors.white38))
            else
              ...roles.entries.map((entry) {
                final role = entry.value;
                final roleColour = role.colour != null ? Color(role.colour!) : null;
                return ExpansionTile(
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: roleColour ?? const Color(0xFF7F5AF0),
                    child: Text(
                      role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  title: Text(
                    role.name,
                    style: TextStyle(color: roleColour ?? Colors.white, fontSize: 14),
                  ),
                  children: kChannelPermissions
                      .map(
                        (d) => _PermToggle(
                          label: d.label,
                          value: (permVal(_rolePermCtrl.text) & d.bit) != 0,
                          onChanged: (v) {
                            var val = permVal(_rolePermCtrl.text);
                            if (v) {
                              val |= d.bit;
                            } else {
                              val &= ~d.bit;
                            }
                            _rolePermCtrl.text = val.toString();
                            setState(() {});
                          },
                        ),
                      )
                      .toList(),
                );
              }),
            const SizedBox(height: 24),

            // --- Individual user overrides ---
            const Text(
              'Individual User Overrides',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Override permissions for specific users. '
              'Use the member list to find user IDs.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _userPermCtrl,
              decoration: const InputDecoration(
                labelText: 'User permissions value (optional)',
                hintText: 'e.g. 32768',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ss = ref.read(serverStateProvider.notifier);
      await ss.updateChannel(
        widget.channel.id,
        defaultPermissions: _defaultPermCtrl.text.isNotEmpty ? _defaultPermCtrl.text : null,
        rolePermissions: _rolePermCtrl.text.isNotEmpty ? _rolePermCtrl.text : null,
        userPermissions: _userPermCtrl.text.isNotEmpty ? _userPermCtrl.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Channel permissions updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// =============================================================================
// Permission toggle row
// =============================================================================

class _PermToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermToggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      activeColor: const Color(0xFF7F5AF0),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}

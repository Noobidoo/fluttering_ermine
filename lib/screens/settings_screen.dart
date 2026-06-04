import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';

enum _Section { profile, voice }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => const SettingsScreen(),
      );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Section _section = _Section.profile;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: (size.width * 0.08).clamp(16.0, 100.0),
        vertical: (size.height * 0.07).clamp(16.0, 60.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: size.width < 500
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: const Color(0xFF16161A),
                    child: Row(
                      children: [
                        Expanded(
                          child: _NavItem(
                            icon: Icons.person_outline,
                            label: 'Profile',
                            selected: _section == _Section.profile,
                            onTap: () =>
                                setState(() => _section = _Section.profile),
                          ),
                        ),
                        Expanded(
                          child: _NavItem(
                            icon: Icons.mic_none_rounded,
                            label: 'Voice',
                            selected: _section == _Section.voice,
                            onTap: () =>
                                setState(() => _section = _Section.voice),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFF1E1E26),
                      child: _section == _Section.profile
                          ? const _ProfileSection()
                          : const _VoiceSection(),
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Sidebar(
                    selected: _section,
                    onSelect: (s) => setState(() => _section = s),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFF1E1E26),
                      child: _section == _Section.profile
                          ? const _ProfileSection()
                          : const _VoiceSection(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final _Section selected;
  final void Function(_Section) onSelect;

  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: const Color(0xFF16161A),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('USER SETTINGS'),
          _NavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            selected: selected == _Section.profile,
            onTap: () => onSelect(_Section.profile),
          ),
          const SizedBox(height: 16),
          _sectionHeader('CLIENT SETTINGS'),
          _NavItem(
            icon: Icons.mic_none_rounded,
            label: 'Voice',
            selected: selected == _Section.voice,
            onTap: () => onSelect(_Section.voice),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 14, color: Colors.white38),
              label: const Text(
                'ESC',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF7F5AF0).withAlpha(38)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? const Color(0xFF7F5AF0)
                      : Colors.white54),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Profile section ───────────────────────────────────────────────────────────

class _ProfileSection extends StatefulWidget {
  const _ProfileSection();

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  late TextEditingController _displayNameCtrl;
  late TextEditingController _statusTextCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _serverNicknameCtrl;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().currentUser;
    _displayNameCtrl = TextEditingController(
        text: user?.displayName ?? user?.username ?? '');
    _statusTextCtrl =
        TextEditingController(text: user?.statusText ?? '');
    _bioCtrl =
        TextEditingController(text: user?.profileContent ?? '');
    _serverNicknameCtrl = TextEditingController(text: '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServerNickname());
  }

  void _initServerNickname() {
    if (!mounted) return;
    final serverState = context.read<ServerState>();
    final server = serverState.selectedServer;
    if (server == null) return;
    final uid = context.read<AuthState>().currentUser?.id;
    if (uid == null) return;
    final nickname = serverState.memberInServer(server.id, uid)?.nickname;
    _serverNicknameCtrl.text = nickname ?? '';
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _statusTextCtrl.dispose();
    _bioCtrl.dispose();
    _serverNicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveServerProfile() async {
    final serverState = context.read<ServerState>();
    final server = serverState.selectedServer;
    if (server == null) return;
    final auth = context.read<AuthState>();
    final nickname = _serverNicknameCtrl.text.trim();
    await auth.updateServerProfile(
      server.id,
      nickname: nickname.isEmpty ? null : nickname,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final auth = context.read<AuthState>();
      await auth.updateDisplayName(_displayNameCtrl.text.trim());
      await auth.updateBio(_bioCtrl.text.trim());
      if (mounted) setState(() => _success = 'Profile saved!');
    } catch (e) {
      if (mounted) {
        setState(
            () => _error = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (!context.mounted) return;
    final auth = context.read<AuthState>();
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (!context.mounted) return;
    await auth.updateAvatar(bytes, file.name);
  }

  Future<void> _pickBanner() async {
    if (!context.mounted) return;
    final auth = context.read<AuthState>();
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (!context.mounted) return;
    await auth.updateBanner(bytes, file.name);
  }

  void _saveStatus() {
    final auth = context.read<AuthState>();
    final user = auth.currentUser;
    final presence = user?.presence ?? UserPresence.online;
    auth.updateStatus(
      presence: presence.toString().split('.').last,
      statusText: _statusTextCtrl.text.trim().isEmpty
          ? null
          : _statusTextCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.currentUser;
    final currentPresence = user?.presence ?? UserPresence.online;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          // Identity card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF7F5AF0),
                        backgroundImage: user?.avatar != null
                            ? NetworkImage(user!.avatarUrlFor(
                                auth.autumnBase, auth.apiBase))
                            : null,
                        child: user?.avatar == null
                            ? Text(
                                ((user?.displayName ??
                                        user?.username ?? '?'))[0]
                                    .toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 22),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: user != null
                                ? presenceColor(user.presence)
                                : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF16161A),
                                width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? user?.username ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      Text(
                        '${user?.username ?? ''}#${user?.discriminator ?? ''}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                      if (user != null &&
                          user.statusText != null &&
                          user.statusText!.isNotEmpty)
                        Text(
                          user.statusText!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Banner area
          const Text('Profile Banner',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _pickBanner,
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: BorderRadius.circular(8),
                image: user?.banner != null
                    ? DecorationImage(
                        image: NetworkImage(
                            user!.bannerUrlFor(auth.autumnBase)!),
                        fit: BoxFit.cover,
                        onError: (_, _) {},
                      )
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      user?.banner != null
                          ? Icons.edit
                          : Icons.add_photo_alternate_outlined,
                      size: 20,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      user?.banner != null
                          ? 'Tap to change banner'
                          : 'Tap to add banner',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Online Status',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          // Presence dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UserPresence>(
                value: currentPresence,
                dropdownColor: const Color(0xFF16161A),
                isExpanded: true,
                items: UserPresence.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: presenceColor(p),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _presenceLabel(p),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  context.read<AuthState>().updateStatus(
                        presence: v.toString().split('.').last,
                        statusText: _statusTextCtrl.text.trim().isEmpty
                            ? null
                            : _statusTextCtrl.text.trim(),
                      );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Custom status text
          const Text('Custom Status',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _statusTextCtrl,
                  style: const TextStyle(color: Colors.white),
                  maxLength: 128,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF16161A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                    hintText: 'What\'s on your mind?',
                    hintStyle:
                        const TextStyle(color: Colors.white30),
                  ),
                  onSubmitted: (_) => _saveStatus(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveStatus,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0)),
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text('Edit Global Profile',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('Display Name',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _displayNameCtrl,
            style: const TextStyle(color: Colors.white),
            maxLength: 32,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF16161A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              counterStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              hintText: 'Display name',
              hintStyle: const TextStyle(color: Colors.white30),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Bio',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _bioCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            maxLength: 1024,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF16161A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              counterStyle:
                  const TextStyle(color: Colors.white38, fontSize: 11),
              hintText: 'Tell us about yourself...',
              hintStyle: const TextStyle(color: Colors.white30),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          if (_success != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_success!,
                  style: const TextStyle(color: Colors.greenAccent)),
            ),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        final u = context.read<AuthState>().currentUser;
                        _displayNameCtrl.text =
                            u?.displayName ?? u?.username ?? '';
                        _bioCtrl.text = u?.profileContent ?? '';
                        setState(() {
                          _error = null;
                          _success = null;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                child: const Text('Reset'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0)),
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
          // ── Server Profile ─────────────────────────────────────────────────
          if (context.watch<ServerState>().selectedServer != null) ...[
            const SizedBox(height: 32),
            Text(
              'Server Profile — ${context.watch<ServerState>().selectedServer!.name}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            const Text('Server Nickname',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverNicknameCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLength: 32,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF16161A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      counterStyle: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      hintText: 'Leave empty to use global name',
                      hintStyle:
                          const TextStyle(color: Colors.white30),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saveServerProfile,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7F5AF0)),
                  child: const Text('Set'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _presenceLabel(UserPresence p) => switch (p) {
        UserPresence.online => 'Online',
        UserPresence.idle => 'Idle',
        UserPresence.focus => 'Focus',
        UserPresence.invisible => 'Invisible',
      };
}

// ── Voice section ─────────────────────────────────────────────────────────────

class _VoiceSection extends StatelessWidget {
  const _VoiceSection();

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Voice',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          // Output Volume
          _SettingsCard(
            children: [
              const Text('Output Volume',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded,
                      color: Colors.white38, size: 20),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        value: voice.outputVolume,
                        onChanged: (v) =>
                            context.read<VoiceState>().setOutputVolume(v),
                        activeColor: const Color(0xFF7F5AF0),
                        inactiveColor: Colors.white24,
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up_rounded,
                      color: Colors.white38, size: 20),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${(voice.outputVolume * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Voice Processing',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _ToggleRow(
                label: 'Noise Suppression',
                subtitle: 'Filter background noise from your microphone',
                value: voice.noiseSuppression,
                onChanged: (v) =>
                    context.read<VoiceState>().setNoiseSuppression(v),
              ),
              const Divider(color: Colors.white12, height: 1),
              _ToggleRow(
                label: 'Echo Cancellation',
                subtitle: 'Prevent your speakers from bleeding into the mic',
                value: voice.echoCancellation,
                onChanged: (v) =>
                    context.read<VoiceState>().setEchoCancellation(v),
              ),
              const Divider(color: Colors.white12, height: 1),
              _ToggleRow(
                label: 'Automatic Gain Control',
                subtitle: 'Automatically adjust microphone volume',
                value: voice.autoGainControl,
                onChanged: (v) =>
                    context.read<VoiceState>().setAutoGainControl(v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Voice processing options take effect the next time you join a channel.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final void Function(bool) onChanged;

  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF7F5AF0),
            activeTrackColor:
                const Color(0xFF7F5AF0).withAlpha(80),
          ),
        ],
      ),
    );
  }
}

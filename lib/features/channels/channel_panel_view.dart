import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers/login_notifier.dart';
import '../../features/servers/providers/permissions_provider.dart';
import '../../features/servers/providers/server_notifier.dart';
import '../../features/voice/providers/voice_notifier.dart';
import '../../models/models.dart';
import '../servers/server_settings_screen.dart';
import 'widgets/channel_tile.dart';
import 'widgets/user_bar.dart';
import 'widgets/voice_bar.dart';

void showCreateChannelDialog(BuildContext context) {
  // kept as top-level for now – uses Navigator
}

class ChannelPanelView extends ConsumerWidget {
  const ChannelPanelView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAsync = ref.watch(serverStateProvider);
    final server = serverAsync.asData?.value;
    final authAsync = ref.watch(loginStateProvider);
    final authData = authAsync.asData?.value;
    final voiceData = ref.watch(voiceStateProvider);
    final channels = server != null && server.selectedServer != null
        ? server.selectedServerChannels
        : server?.dmChannels ?? [];
    final title =
        server?.selectedServer?.name ??
        (server?.showDMs == true ? 'Direct Messages' : 'Fluttering Ermine');
    final srvId = server?.selectedServer?.id;
    final perms = srvId != null ? ref.watch(effectivePermissionsProvider(srvId)) : 0;

    return Material(
      color: const Color(0xFF141418),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (server != null && server.selectedServer != null) ...[
                  if (authData != null &&
                      (perms & Permission.manageChannel) != 0)
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white54),
                      tooltip: 'Create channel',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => showCreateChannelDialog(context),
                    ),
                  if (authData != null &&
                      ((perms & Permission.manageServer) != 0 ||
                          (perms & Permission.manageChannel) != 0 ||
                          (perms & Permission.manageRole) != 0))
                    IconButton(
                      icon: const Icon(Icons.settings_rounded, size: 18, color: Colors.white38),
                      tooltip: 'Server settings',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => showServerSettingsDialog(context),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: channels.isEmpty
                ? const Center(
                    child: Text('No channels', style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: channels.length,
                    itemBuilder: (_, i) =>
                        ChannelTile(channels[i], key: ValueKey('channel_${channels[i].id}')),
                  ),
          ),
          if (authData?.currentUser != null) const UserBar(),
          if (voiceData.isInVoice || voiceData.isJoiningVoice) const VoiceBar(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers/login_notifier.dart';
import '../channels/channel_panel_view.dart';
import '../chat/chat_view.dart';
import '../messaging/providers/messaging_notifier.dart';
import '../servers/providers/server_notifier.dart';
import '../../models/models.dart';
import '../users/member_panel.dart';
import '../servers/widgets/server_rail.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 800;
    final serverState = ref.watch(serverStateProvider).asData?.value;
    final selectedServer = serverState?.selectedServer;
    final selectedChannel = serverState?.selectedChannel;

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            const ServerRail(),
            SizedBox(width: 230, child: ChannelPanelView()),
            Expanded(
              child: ChatView(msgCtrl: _msgCtrl, scrollCtrl: _scrollCtrl),
            ),
            if (selectedServer != null)
              const SizedBox(width: 280, child: MemberPanel()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(context, selectedChannel),
      drawer: Drawer(
        width: 300,
        child: SafeArea(
          child: Row(
            children: [
              const ServerRail(),
              Expanded(child: ChannelPanelView()),
            ],
          ),
        ),
      ),
      body: ChatView(msgCtrl: _msgCtrl, scrollCtrl: _scrollCtrl),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    RevoltChannel? channel,
  ) {
    return AppBar(
      backgroundColor: const Color(0xFF16161A),
      title: channel != null
          ? Row(
              children: [
                Icon(_channelIcon(channel), size: 18, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  ref
                      .read(messagingStateProvider.notifier)
                      .channelDisplayName(channel),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            )
          : const Text('Fluttering Ermine'),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: () => ref.read(loginStateProvider.notifier).logout(),
        ),
      ],
    );
  }

  IconData _channelIcon(RevoltChannel channel) => switch (channel.type) {
    ChannelType.textChannel when channel.isVoice => Icons.volume_up_rounded,
    ChannelType.textChannel => Icons.tag,
    ChannelType.directMessage => Icons.person_rounded,
    ChannelType.group => Icons.group_rounded,
    ChannelType.savedMessages => Icons.bookmark_rounded,
    _ => Icons.chat_bubble_outline,
  };
}

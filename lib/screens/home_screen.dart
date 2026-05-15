import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../widgets/server_rail.dart';
import '../widgets/channel_panel.dart';
import '../widgets/chat_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            const ServerRail(),
            SizedBox(width: 230, child: ChannelPanel()),
            Expanded(
              child: ChatPanel(
                msgCtrl: _msgCtrl,
                scrollCtrl: _scrollCtrl,
              ),
            ),
          ],
        ),
      );
    }

    // Narrow layout – channel panel in drawer
    return Scaffold(
      appBar: _buildAppBar(context),
      drawer: Drawer(
        width: 300,
        child: SafeArea(
          child: Row(
            children: [
              const ServerRail(),
              Expanded(child: ChannelPanel()),
            ],
          ),
        ),
      ),
      body: ChatPanel(msgCtrl: _msgCtrl, scrollCtrl: _scrollCtrl),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final channel = context.watch<ServerState>().selectedChannel;
    final messaging = context.watch<MessagingState>();
    return AppBar(
      backgroundColor: const Color(0xFF16161A),
      title: channel != null
          ? Row(children: [
              Icon(_channelIcon(channel), size: 18, color: Colors.white54),
              const SizedBox(width: 6),
              Text(messaging.channelDisplayName(channel),
                  style: const TextStyle(fontSize: 16)),
            ])
          : const Text('Fluttering Ermine'),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: () => context.read<AuthState>().logout(),
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


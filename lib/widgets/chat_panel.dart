import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import '../providers/voice_state.dart';
import 'message_bubble.dart';

class ChatPanel extends StatefulWidget {
  final TextEditingController msgCtrl;
  final ScrollController scrollCtrl;

  const ChatPanel(
      {required this.msgCtrl, required this.scrollCtrl, super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  bool _showVoice = true;
  bool _splitMode = false;
  bool _maximized = false;

  @override
  Widget build(BuildContext context) {
    final channel = context.watch<ServerState>().selectedChannel;

    if (channel == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 72, color: Colors.white12),
            SizedBox(height: 16),
            Text('Select a channel',
                style: TextStyle(color: Colors.white38, fontSize: 18)),
            SizedBox(height: 4),
            Text('Pick a channel from the left to start chatting.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }

    // Maximized: full-area voice view with a floating restore button.
    if (_maximized && channel.isVoice && !_splitMode) {
      return Stack(
        children: [
          _VoiceChannelView(channel),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
              child: IconButton(
                icon: const Icon(Icons.fullscreen_exit, size: 20),
                color: Colors.white70,
                tooltip: 'Restore',
                onPressed: () => setState(() => _maximized = false),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _ChatHeader(
          channel,
          actions: channel.isVoice
              ? [
                  if (!_splitMode && _showVoice)
                    IconButton(
                      icon: const Icon(Icons.fullscreen, size: 18),
                      tooltip: 'Maximize streams',
                      color: Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _maximized = true),
                    ),
                  IconButton(
                    icon: Icon(
                      _splitMode
                          ? Icons.tab_rounded
                          : Icons.view_agenda_rounded,
                      size: 18,
                    ),
                    tooltip: _splitMode ? 'Tab layout' : 'Split layout',
                    color: Colors.white38,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      _splitMode = !_splitMode;
                      if (_splitMode) _maximized = false;
                    }),
                  ),
                ]
              : const [],
        ),
        if (channel.isVoice) ...[
          if (_splitMode) ...[
            SizedBox(height: 260, child: _VoiceChannelView(channel)),
            const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A30)),
            Expanded(child: _MessageList(channel, widget.scrollCtrl)),
            _MessageInput(msgCtrl: widget.msgCtrl),
          ] else ...[
            _VoiceTabBar(
              showVoice: _showVoice,
              onToggle: (v) => setState(() => _showVoice = v),
            ),
            if (_showVoice)
              Expanded(child: _VoiceChannelView(channel))
            else ...[
              Expanded(child: _MessageList(channel, widget.scrollCtrl)),
              _MessageInput(msgCtrl: widget.msgCtrl),
            ],
          ],
        ] else ...[
          Expanded(child: _MessageList(channel, widget.scrollCtrl)),
          _MessageInput(msgCtrl: widget.msgCtrl),
        ],
      ],
    );
  }
}

class _VoiceTabBar extends StatelessWidget {
  final bool showVoice;
  final ValueChanged<bool> onToggle;
  const _VoiceTabBar({required this.showVoice, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    const active = Color(0xFF7F5AF0);
    const inactive = Color(0xFF2A2A30);
    const textActive = Colors.white;
    const textInactive = Colors.white38;

    return Container(
      height: 36,
      color: const Color(0xFF16161A),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(true),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: showVoice ? active : inactive,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_rounded,
                        size: 14,
                        color: showVoice ? active : textInactive),
                    const SizedBox(width: 6),
                    Text('Voice',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: showVoice ? textActive : textInactive,
                        )),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onToggle(false),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: !showVoice ? active : inactive,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag,
                        size: 14,
                        color: !showVoice ? active : textInactive),
                    const SizedBox(width: 6),
                    Text('Chat',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !showVoice ? textActive : textInactive,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final RevoltChannel channel;
  final List<Widget> actions;
  const _ChatHeader(this.channel, {this.actions = const []});

  IconData _icon() => switch (channel.type) {
        ChannelType.textChannel when channel.isVoice => Icons.volume_up_rounded,
        ChannelType.textChannel => Icons.tag,
        ChannelType.directMessage => Icons.person_rounded,
        ChannelType.group => Icons.group_rounded,
        ChannelType.savedMessages => Icons.bookmark_rounded,
        _ => Icons.chat_bubble_outline,
      };

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF16161A),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Row(
        children: [
          Icon(_icon(), size: 20, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    messaging.channelDisplayName(channel),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (channel.description != null &&
                    channel.description!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: Colors.white24),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      channel.description!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...actions,
          ],
        ],
      ),
    );
  }
}

class _VoiceChannelView extends StatelessWidget {
  final RevoltChannel channel;
  const _VoiceChannelView(this.channel);

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceState>();
    final isActive = voice.activeVoiceChannel?.id == channel.id;
    final streams = isActive ? voice.remoteVideoStreams : <RemoteVideoStream>[];

    Widget controls;
    if (isActive) {
      controls = Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => context.read<VoiceState>().toggleMute(),
            icon: Icon(voice.isMuted ? Icons.mic_off : Icons.mic),
            label: Text(voice.isMuted ? 'Unmute' : 'Mute'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  voice.isMuted ? Colors.redAccent : const Color(0xFF2CB67D),
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final voiceState = context.read<VoiceState>();
              if (voice.isScreenSharing) {
                voiceState.stopScreenShare();
                return;
              }
              // On desktop, show a source picker before enabling screen share.
              if (!kIsWeb &&
                  (Platform.isWindows ||
                      Platform.isLinux ||
                      Platform.isMacOS)) {
                final dynamic source = await showDialog(
                  context: context,
                  builder: (context) => ScreenSelectDialog(),
                );
                if (source == null) return;
                voiceState.startDesktopScreenShare(source.id as String);
              } else {
                voiceState.toggleScreenShare();
              }
            },
            icon: Icon(voice.isScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share),
            label: Text(
                voice.isScreenSharing ? 'Stop Sharing' : 'Share Screen'),
            style: FilledButton.styleFrom(
              backgroundColor: voice.isScreenSharing
                  ? Colors.orangeAccent
                  : const Color(0xFF7F5AF0),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => context.read<VoiceState>().leaveVoiceChannel(),
            icon: const Icon(Icons.call_end, color: Colors.redAccent),
            label: const Text('Leave',
                style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ],
      );
    } else if (voice.isJoiningVoice) {
      controls = const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Connecting…', style: TextStyle(color: Colors.white38)),
        ],
      );
    } else {
      controls = FilledButton.icon(
        onPressed: () => context.read<VoiceState>().joinVoiceChannel(channel),
        icon: const Icon(Icons.call),
        label: const Text('Join Voice'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2CB67D),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        ),
      );
    }

    return Column(
      children: [
        if (streams.isNotEmpty)
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _VideoGrid(streams: streams),
            ),
          ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? Icons.graphic_eq : Icons.volume_up_rounded,
                  size: 72,
                  color: isActive ? const Color(0xFF2CB67D) : Colors.white12,
                ),
                const SizedBox(height: 16),
                Text(
                  isActive ? 'You are in this channel' : 'Voice Channel',
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        isActive ? const Color(0xFF2CB67D) : Colors.white38,
                  ),
                ),
                const SizedBox(height: 24),
                if (voice.voiceError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      voice.voiceError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                controls,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoGrid extends StatelessWidget {
  final List<RemoteVideoStream> streams;
  const _VideoGrid({required this.streams});

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = streams.length <= 1
        ? 1
        : streams.length <= 4
            ? 2
            : 3;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: streams.length,
      itemBuilder: (_, i) => _RemoteVideoTile(stream: streams[i]),
    );
  }
}

class _RemoteVideoTile extends StatelessWidget {
  final RemoteVideoStream stream;
  const _RemoteVideoTile({required this.stream});

  @override
  Widget build(BuildContext context) {
    final isScreen = stream.source == TrackSource.screenShareVideo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoTrackRenderer(stream.track),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isScreen ? Icons.screen_share : Icons.videocam,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      stream.participantIdentity,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final RevoltChannel channel;
  final ScrollController ctrl;
  const _MessageList(this.channel, this.ctrl);

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final messages = messaging.currentMessages;

    if (messaging.isLoadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messaging.currentChannelError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                messaging.currentChannelError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.read<MessagingState>().retryLoadMessages(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7F5AF0)),
              ),
            ],
          ),
        ),
      );
    }

    if (messages.isEmpty) {
      return const Center(
          child: Text('No messages yet',
              style: TextStyle(color: Colors.white38)));
    }

    return ListView.builder(
      controller: ctrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        final prev = i + 1 < messages.length ? messages[i + 1] : null;
        final grouped = prev != null && prev.authorId == msg.authorId;
        return MessageBubble(
          message: msg,
          author: messaging.getUser(msg.authorId),
          grouped: grouped,
        );
      },
    );
  }
}

class _MessageInput extends StatefulWidget {
  final TextEditingController msgCtrl;
  const _MessageInput({required this.msgCtrl});

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  // Pending attachments: list of (autumnId, displayName)
  final List<(String, String)> _pendingAttachments = [];
  bool _uploading = false;

  // Mention autocomplete state
  String _mentionQuery = '';
  int _mentionIndex = 0;
  List<MapEntry<String, String>> _mentionResults = const [];
  final FocusNode _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.msgCtrl.addListener(_onTextChanged);
    _inputFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.msgCtrl.removeListener(_onTextChanged);
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_inputFocus.hasFocus) _hideMentions();
  }

  void _onTextChanged() {
    if (!context.mounted) return;
    context.read<MessagingState>().sendTypingIndicator();
    _updateMentionState();
  }

  void _updateMentionState() {
    final text = widget.msgCtrl.text;
    final sel = widget.msgCtrl.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      _hideMentions();
      return;
    }
    final pos = sel.baseOffset;
    if (pos == 0 || pos > text.length) {
      _hideMentions();
      return;
    }
    // Walk backwards from cursor to find @
    int start = pos - 1;
    while (start >= 0 && text[start] != '@') {
      if (text[start] == ' ') break;
      start--;
    }
    if (start < 0 || text[start] != '@') {
      if (_mentionResults.isNotEmpty) _hideMentions();
      return;
    }
    final query = text.substring(start + 1, pos).trim().toLowerCase();
    if (query == _mentionQuery && _mentionResults.isNotEmpty) return;
    _mentionQuery = query;

    final messaging = context.read<MessagingState>();
    final server = context.read<ServerState>();
    final members = server.currentServerMembers ?? [];
    final results = <MapEntry<String, String>>[];
    final seen = <String>{};
    for (final m in members) {
      if (seen.contains(m.userId)) continue;
      seen.add(m.userId);
      final user = messaging.getUser(m.userId);
      final display = m.nickname ?? user?.displayUsername ?? '';
      if (query.isEmpty ||
          display.toLowerCase().contains(query) ||
          user?.username.toLowerCase().contains(query) == true) {
        results.add(MapEntry(m.userId, display));
      }
    }
    // Also include cached users not in this server (for DM mentions)
    if (server.selectedServer == null) {
      for (final u in messaging.cachedUsers) {
        if (seen.contains(u.id)) continue;
        if (query.isEmpty ||
            u.displayUsername.toLowerCase().contains(query) ||
            u.username.toLowerCase().contains(query)) {
          results.add(MapEntry(u.id, u.displayUsername));
        }
      }
    }
    results.sort((a, b) => a.value.compareTo(b.value));
    setState(() {
      _mentionResults = results.take(10).toList();
      _mentionIndex = 0;
    });
  }

  void _hideMentions() {
    if (_mentionResults.isEmpty) return;
    setState(() {
      _mentionResults = const [];
      _mentionQuery = '';
      _mentionIndex = 0;
    });
  }

  void _insertMention(String userId) {
    final text = widget.msgCtrl.text;
    final sel = widget.msgCtrl.selection;
    if (!sel.isValid) return;
    final pos = sel.baseOffset;
    int start = pos - 1;
    while (start >= 0 && text[start] != '@') {
      if (text[start] == ' ') break;
      start--;
    }
    if (start < 0) start = 0;
    final before = text.substring(0, start);
    final after = text.substring(pos);
    final replacement = '<@$userId> ';
    widget.msgCtrl.value = TextEditingValue(
      text: '$before$replacement$after',
      selection: TextSelection.collapsed(
          offset: before.length + replacement.length),
    );
    _hideMentions();
  }

  Future<void> _pickFile() async {
    final service = context.read<MessagingState>().service;
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final id = await service.uploadAttachment(
          file.bytes!, file.name);
      setState(() {
        _pendingAttachments.add((id, file.name));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _send(BuildContext context) {
    final text = widget.msgCtrl.text;
    final ids = _pendingAttachments.map((a) => a.$1).toList();
    if (text.trim().isEmpty && ids.isEmpty) return;
    widget.msgCtrl.clear();
    setState(() => _pendingAttachments.clear());
    context
        .read<MessagingState>()
        .sendMessage(text, attachmentIds: ids);
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final channel = context.watch<ServerState>().selectedChannel;
    final name = channel != null ? messaging.channelDisplayName(channel) : '';
    final typingIds = channel != null
        ? messaging.typingUsersFor(channel.id).toList()
        : <String>[];
    final replyTarget = messaging.replyTarget;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (typingIds.isNotEmpty)
          _TypingIndicator(userIds: typingIds, messaging: messaging),
        if (replyTarget != null)
          _ReplyBar(
            message: replyTarget,
            author: messaging.getUser(replyTarget.authorId),
            onDismiss: messaging.clearReplyTarget,
          ),
        // Pending attachment chips
        if (_pendingAttachments.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _pendingAttachments.map((a) {
                return Chip(
                  backgroundColor: const Color(0xFF242428),
                  side: const BorderSide(color: Color(0xFF3A3A42)),
                  label: Text(a.$2,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70)),
                  deleteIcon: const Icon(Icons.close,
                      size: 14, color: Colors.white38),
                  onDeleted: () =>
                      setState(() => _pendingAttachments.remove(a)),
                );
              }).toList(),
            ),
          ),
        if (_mentionResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E26),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A42)),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _mentionResults.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => _insertMention(_mentionResults[i].key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  color: i == _mentionIndex
                      ? const Color(0x207F5AF0)
                      : null,
                  child: Text(
                    '@${_mentionResults[i].value}',
                    style: TextStyle(
                      color: i == _mentionIndex
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: i == _mentionIndex
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attach button
              _uploading
                  ? const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF7F5AF0))),
                    )
                  : IconButton(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file_rounded),
                      color: Colors.white38,
                      tooltip: 'Attach file',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
              const SizedBox(width: 4),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (_mentionResults.isEmpty) {
                      return KeyEventResult.ignored;
                    }
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      setState(() {
                        _mentionIndex = (_mentionIndex + 1) %
                            _mentionResults.length;
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      setState(() {
                        _mentionIndex = (_mentionIndex - 1 +
                                _mentionResults.length) %
                            _mentionResults.length;
                      });
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.enter) {
                      _insertMention(_mentionResults[_mentionIndex].key);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      _hideMentions();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.msgCtrl,
                    focusNode: _inputFocus,
                    maxLines: 6,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message $name',
                      filled: true,
                      fillColor: const Color(0xFF242428),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _mentionResults.isNotEmpty
                        ? (_) => _insertMention(
                            _mentionResults[_mentionIndex].key)
                        : (_) => _send(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _send(context),
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Reply bar ─────────────────────────────────────────────────────────────────

class _ReplyBar extends StatelessWidget {
  final RevoltMessage message;
  final RevoltUser? author;
  final VoidCallback onDismiss;

  const _ReplyBar({
    required this.message,
    this.author,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final name = author?.displayUsername ?? message.authorId;
    final preview = message.content?.trim() ?? '';
    final truncated =
        preview.length > 60 ? '${preview.substring(0, 60)}…' : preview;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A20),
        border: Border(
          left: BorderSide(color: Color(0xFF7F5AF0), width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded,
              size: 14, color: Color(0xFF7F5AF0)),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                TextSpan(
                  text: '$name  ',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBBDF7),
                      fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: truncated.isEmpty ? '(attachment)' : truncated,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ]),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child:
                  Icon(Icons.close, size: 14, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final List<String> userIds;
  final MessagingState messaging;

  const _TypingIndicator(
      {required this.userIds, required this.messaging});

  @override
  Widget build(BuildContext context) {
    String text;
    if (userIds.length == 1) {
      final name =
          messaging.getUser(userIds[0])?.displayUsername ?? userIds[0];
      text = '$name is typing…';
    } else if (userIds.length == 2) {
      final a =
          messaging.getUser(userIds[0])?.displayUsername ?? userIds[0];
      final b =
          messaging.getUser(userIds[1])?.displayUsername ?? userIds[1];
      text = '$a and $b are typing…';
    } else {
      text = 'Several people are typing…';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 16, 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white54,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}


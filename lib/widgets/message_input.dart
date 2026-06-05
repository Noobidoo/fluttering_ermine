import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/messaging_state.dart';
import '../providers/server_state.dart';
import 'mention_chip.dart';

class _MentionRenderController extends TextEditingController {
  final MessagingState Function() _getMessaging;

  _MentionRenderController({required String text, required MessagingState Function() getMessaging})
      : _getMessaging = getMessaging,
        super(text: text);

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final raw = text;
    if (!raw.contains('<@')) {
      return TextSpan(text: raw, style: style);
    }
    final messaging = _getMessaging();
    final spans = <InlineSpan>[];
    final regex = RegExp(r'<@([A-Za-z0-9]+)>');
    int lastEnd = 0;
    for (final m in regex.allMatches(raw)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: raw.substring(lastEnd, m.start), style: style));
      }
      final userId = m.group(1)!;
      spans.add(buildMentionChip(userId, messaging, baseStyle: style));
      lastEnd = m.end;
    }
    if (lastEnd < raw.length) {
      spans.add(TextSpan(text: raw.substring(lastEnd), style: style));
    }
    return TextSpan(children: spans);
  }
}

class MessageInput extends StatefulWidget {
  final TextEditingController msgCtrl;
  const MessageInput({required this.msgCtrl, super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  // Pending attachments: list of (autumnId, displayName)
  final List<(String, String)> _pendingAttachments = [];
  bool _uploading = false;

  // Mention autocomplete state
  String _mentionQuery = '';
  int _mentionIndex = 0;
  List<MapEntry<String, String>> _mentionResults = const [];
  final FocusNode _inputFocus = FocusNode();
  late final _MentionRenderController _renderCtrl;

  @override
  void initState() {
    super.initState();
    _renderCtrl = _MentionRenderController(
      text: widget.msgCtrl.text,
      getMessaging: () => context.read<MessagingState>(),
    );
    _renderCtrl.addListener(_onTextChanged);
    _inputFocus.addListener(_onFocusChanged);
    _inputFocus.onKeyEvent = _onKeyEvent;
    // Sync external controller on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.msgCtrl.text = _renderCtrl.text;
    });
  }

  @override
  void dispose() {
    _renderCtrl.removeListener(_onTextChanged);
    widget.msgCtrl.text = _renderCtrl.text;
    _renderCtrl.dispose();
    _inputFocus.removeListener(_onFocusChanged);
    _inputFocus.onKeyEvent = null;
    _inputFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_inputFocus.hasFocus) _hideMentions();
  }

  void _onTextChanged() {
    // Sync back to external controller
    widget.msgCtrl.text = _renderCtrl.text;
    if (!context.mounted) return;
    context.read<MessagingState>().sendTypingIndicator();
    _updateMentionState();
  }

  void _requestInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  void _updateMentionState() {
    final text = _renderCtrl.text;
    final sel = _renderCtrl.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      _hideMentions();
      _requestInputFocus();
      return;
    }
    final pos = sel.baseOffset;
    if (pos == 0 || pos > text.length) {
      _hideMentions();
      _requestInputFocus();
      return;
    }
    // Walk backwards from cursor to find @
    int start = pos - 1;
    while (start >= 0 && text[start] != '@') {
      if (text[start] == ' ') break;
      start--;
    }
    if (start < 0 || text[start] != '@') {
      if (_mentionResults.isNotEmpty) {
        _hideMentions();
        _requestInputFocus();
      }
      return;
    }
    final query = text.substring(start + 1, pos).trim().toLowerCase();
    if (query == _mentionQuery && _mentionResults.isNotEmpty) {
      return;
    }
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
    if (results.isEmpty) {
      _hideMentions();
      _requestInputFocus();
      return;
    }
    results.sort((a, b) => a.value.compareTo(b.value));
    setState(() {
      _mentionResults = results.take(10).toList();
      _mentionIndex = 0;
    });
    _requestInputFocus();
  }

  void _hideMentions() {
    if (_mentionResults.isEmpty) return;
    setState(() {
      _mentionResults = const [];
      _mentionQuery = '';
      _mentionIndex = 0;
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_mentionResults.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _mentionIndex =
            (_mentionIndex + 1) % _mentionResults.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _mentionIndex = (_mentionIndex - 1 + _mentionResults.length) %
            _mentionResults.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _insertMention(_mentionResults[_mentionIndex].key, _mentionResults[_mentionIndex].value);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hideMentions();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertMention(String userId, String displayName) {
    final text = _renderCtrl.text;
    final sel = _renderCtrl.selection;
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
    _renderCtrl.value = TextEditingValue(
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
    final text = _renderCtrl.text;
    final ids = _pendingAttachments.map((a) => a.$1).toList();
    if (text.trim().isEmpty && ids.isEmpty) return;
    widget.msgCtrl.text = text;
    _renderCtrl.clear();
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
                onTap: () => _insertMention(_mentionResults[i].key, _mentionResults[i].value),
                child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                child: TextField(
                  controller: _renderCtrl,
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
                  onSubmitted: (_) => _send(context),
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

// -- Reply bar -----------------------------------------------------------------

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

// -- Typing indicator ----------------------------------------------------------

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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/service_providers.dart';
import '../messaging/providers/messaging_notifier.dart';
import '../servers/providers/server_notifier.dart';
import 'reply_bar.dart';
import 'typing_indicator.dart';

class MentionRenderController extends TextEditingController {
  final MessagingStateData Function() _getMessaging;

  MentionRenderController({
    required String text,
    required MessagingStateData Function() getMessaging,
  }) : _getMessaging = getMessaging,
       super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
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
      final user = messaging.userCache[userId];
      final name = '@${user?.resolveDisplayName(null) ?? userId}';
      final chipStyle = (style ?? const TextStyle()).copyWith(
        color: const Color(0xFFCBBDF7),
        fontWeight: FontWeight.w500,
        fontSize: style?.fontSize ?? 14,
        height: 1.2,
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0x337F5AF0),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(name, style: chipStyle),
          ),
        ),
      );
      lastEnd = m.end;
    }
    if (lastEnd < raw.length) {
      spans.add(TextSpan(text: raw.substring(lastEnd), style: style));
    }
    return TextSpan(children: spans);
  }
}

class MessageInput extends ConsumerStatefulWidget {
  final TextEditingController msgCtrl;
  const MessageInput({required this.msgCtrl, super.key});

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final List<(String, String)> _pendingAttachments = [];
  bool _uploading = false;

  String _mentionQuery = '';
  int _mentionIndex = 0;
  List<MapEntry<String, String>> _mentionResults = const [];
  final FocusNode _inputFocus = FocusNode();
  late final MentionRenderController _renderCtrl;

  @override
  void initState() {
    super.initState();
    _renderCtrl = MentionRenderController(
      text: widget.msgCtrl.text,
      getMessaging: () => ref.read(messagingStateProvider),
    );
    _renderCtrl.addListener(_onTextChanged);
    _inputFocus.addListener(_onFocusChanged);
    _inputFocus.onKeyEvent = _onKeyEvent;
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
    widget.msgCtrl.text = _renderCtrl.text;
    if (!mounted) return;
    ref.read(messagingStateProvider.notifier).sendTypingIndicator();
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

    final messaging = ref.read(messagingStateProvider);
    final server = ref.read(serverStateProvider).asData?.value;
    final serverId = server?.selectedServer?.id;
    final memberIds = server?.currentServerMemberIds ?? [];
    final results = <MapEntry<String, String>>[];
    final seen = <String>{};
    for (final userId in memberIds) {
      if (seen.contains(userId)) continue;
      seen.add(userId);
      final user = messaging.userCache[userId];
      final display = user?.resolveDisplayName(serverId) ?? '';
      if (query.isEmpty ||
          display.toLowerCase().contains(query) ||
          user?.username.toLowerCase().contains(query) == true) {
        results.add(MapEntry(userId, display));
      }
    }
    if (server?.selectedServer == null) {
      for (final u in messaging.userCache.values) {
        if (seen.contains(u.id)) continue;
        if (query.isEmpty ||
            u.resolveDisplayName(null).toLowerCase().contains(query) ||
            u.username.toLowerCase().contains(query)) {
          results.add(MapEntry(u.id, u.resolveDisplayName(null)));
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
        _mentionIndex = (_mentionIndex + 1) % _mentionResults.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _mentionIndex = (_mentionIndex - 1 + _mentionResults.length) % _mentionResults.length;
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
      selection: TextSelection.collapsed(offset: before.length + replacement.length),
    );
    _hideMentions();
  }

  Future<void> _pickFile() async {
    final service = ref.read(revoltServiceProvider);
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final id = await service.uploadAttachment(file.bytes!, file.name);
      setState(() {
        _pendingAttachments.add((id, file.name));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _send() {
    final text = _renderCtrl.text;
    final ids = _pendingAttachments.map((a) => a.$1).toList();
    if (text.trim().isEmpty && ids.isEmpty) return;
    widget.msgCtrl.text = text;
    _renderCtrl.clear();
    setState(() => _pendingAttachments.clear());
    ref.read(messagingStateProvider.notifier).sendMessage(text, attachmentIds: ids);
  }

  @override
  Widget build(BuildContext context) {
    final messaging = ref.watch(messagingStateProvider);
    final serverState = ref.watch(serverStateProvider).asData?.value;
    final channel = serverState?.selectedChannel;
    final name = channel != null
        ? ref.read(messagingStateProvider.notifier).channelDisplayName(channel)
        : '';
    final replyTarget = messaging.replyTarget;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TypingIndicator(),
        if (replyTarget != null)
          ReplyBar(
            message: replyTarget,
            author: messaging.userCache[replyTarget.authorId],
            onDismiss: () => ref.read(messagingStateProvider.notifier).clearReplyTarget(),
          ),
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
                  label: Text(a.$2, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white38),
                  onDeleted: () => setState(() => _pendingAttachments.remove(a)),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: i == _mentionIndex ? const Color(0x207F5AF0) : null,
                child: Text(
                  '@${_mentionResults[i].value}',
                  style: TextStyle(
                    color: i == _mentionIndex ? Colors.white : Colors.white70,
                    fontWeight: i == _mentionIndex ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _uploading
                  ? const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7F5AF0)),
                      ),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _send,
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

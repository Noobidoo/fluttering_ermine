import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';
import 'mention_chip.dart';
import 'user_profile_sheet.dart';

enum _MsgAction { reply, react, edit, delete, copy }

// Curated list of common Unicode emojis for the picker
const _kCommonEmojis = [
  '👍',
  '👎',
  '❤️',
  '😂',
  '😮',
  '😢',
  '😡',
  '🎉',
  '🔥',
  '✅',
  '❌',
  '⭐',
  '🙏',
  '👀',
  '💯',
  '🚀',
  '😀',
  '😃',
  '😄',
  '😁',
  '😅',
  '🤣',
  '😊',
  '😇',
  '🥰',
  '😍',
  '🤩',
  '😘',
  '😜',
  '🤔',
  '🤭',
  '😎',
  '😴',
  '🥳',
  '😤',
  '😭',
  '😱',
  '🤯',
  '🥺',
  '😏',
  '👋',
  '🤝',
  '✌️',
  '🤞',
  '🙌',
  '👏',
  '🫂',
  '💪',
  '🐱',
  '🐶',
  '🦊',
  '🐻',
  '🐼',
  '🐨',
  '🦁',
  '🐸',
  '🍕',
  '🍔',
  '🍣',
  '🍜',
  '☕',
  '🍺',
  '🥂',
  '🍭',
  '⚽',
  '🏀',
  '🎮',
  '🎵',
  '🎸',
  '🎹',
  '🎲',
  '🃏',
  '🌍',
  '🌈',
  '⚡',
  '❄️',
  '🌊',
  '🍀',
  '🌸',
  '🌻',
];

class MessageBubble extends StatefulWidget {
  final RevoltMessage message;
  final RevoltUser? author;
  final bool grouped;
  final String? serverId;

  const MessageBubble({
    super.key,
    required this.message,
    this.author,
    this.grouped = false,
    this.serverId,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;
  bool _editing = false;
  late TextEditingController _editCtrl;

  String get _username =>
      widget.author?.resolveDisplayName(widget.serverId) ??
      widget.message.authorId;

  TextSpan _renderContent(String content) {
    final messaging = context.read<MessagingState>();
    final spans = <InlineSpan>[];
    final regex = RegExp(r'<@([A-Za-z0-9]+)>');
    int lastEnd = 0;
    for (final m in regex.allMatches(content)) {
      if (m.start > lastEnd) {
        spans.add(TextSpan(text: content.substring(lastEnd, m.start)));
      }
      final userId = m.group(1)!;
      spans.add(buildMentionChip(userId, messaging));
      lastEnd = m.end;
    }
    if (lastEnd < content.length) {
      spans.add(TextSpan(text: content.substring(lastEnd)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: content));
    return TextSpan(children: spans);
  }

  String _avatarUrl(String autumnBase, String apiBase) =>
      widget.author?.resolveAvatarUrl(widget.serverId, autumnBase, apiBase) ??
      '$apiBase/users/${widget.message.authorId}/default_avatar';

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      final hm =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (msgDay == today) return 'Today at $hm';
      final yesterday = today.subtract(const Duration(days: 1));
      if (msgDay == yesterday) return 'Yesterday at $hm';
      return '${dt.month}/${dt.day}/${dt.year} $hm';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.message.content ?? '');
  }

  @override
  void didUpdateWidget(MessageBubble old) {
    super.didUpdateWidget(old);
    if (!_editing && old.message.content != widget.message.content) {
      _editCtrl.text = widget.message.content ?? '';
    }
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _editing = true;
      _editCtrl.text = widget.message.content ?? '';
    });
  }

  void _cancelEdit() => setState(() => _editing = false);

  void _commitEdit(BuildContext context) {
    final text = _editCtrl.text.trim();
    if (text.isEmpty || text == (widget.message.content ?? '').trim()) {
      _cancelEdit();
      return;
    }
    context.read<MessagingState>().editMessage(
      widget.message.channelId,
      widget.message.id,
      text,
    );
    setState(() => _editing = false);
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Delete Message'),
        content: const Text(
          'This message will be permanently deleted.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<MessagingState>().deleteMessage(
                widget.message.channelId,
                widget.message.id,
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmojiPicker(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 320,
          height: 340,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add Reaction',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: _kCommonEmojis.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      context.read<MessagingState>().addReaction(
                        widget.message.channelId,
                        widget.message.id,
                        _kCommonEmojis[i],
                      );
                    },
                    child: Center(
                      child: Text(
                        _kCommonEmojis[i],
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openContextMenu(BuildContext context, Offset globalPosition) {
    final auth = context.read<AuthState>();
    final isOwn = widget.message.authorId == auth.currentUser?.id;

    showMenu<_MsgAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: const Color(0xFF1E1E24),
      elevation: 8,
      items: [
        const PopupMenuItem(
          value: _MsgAction.reply,
          child: _MenuItem(Icons.reply_rounded, 'Reply'),
        ),
        const PopupMenuItem(
          value: _MsgAction.react,
          child: _MenuItem(Icons.add_reaction_outlined, 'React'),
        ),
        if (isOwn)
          const PopupMenuItem(
            value: _MsgAction.edit,
            child: _MenuItem(Icons.edit_rounded, 'Edit'),
          ),
        if (widget.message.content?.isNotEmpty == true)
          const PopupMenuItem(
            value: _MsgAction.copy,
            child: _MenuItem(Icons.copy_rounded, 'Copy Text'),
          ),
        if (isOwn) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _MsgAction.delete,
            child: _MenuItem(
              Icons.delete_rounded,
              'Delete',
              color: Colors.redAccent,
            ),
          ),
        ],
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      switch (action) {
        case _MsgAction.reply:
          context.read<MessagingState>().setReplyTarget(widget.message);
        case _MsgAction.react:
          _showEmojiPicker(context);
        case _MsgAction.edit:
          _startEdit();
        case _MsgAction.delete:
          _confirmDelete(context);
        case _MsgAction.copy:
          Clipboard.setData(ClipboardData(text: widget.message.content ?? ''));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final isOwn = widget.message.authorId == auth.currentUser?.id;

    Widget content;
    if (widget.grouped) {
      content = _groupedBubble(auth.autumnBase, context);
    } else {
      content = _fullBubble(auth.apiBase, auth.autumnBase, context);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => _openContextMenu(context, d.globalPosition),
        onLongPressStart: (d) => _openContextMenu(context, d.globalPosition),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              color: _hovered ? const Color(0x0AFFFFFF) : Colors.transparent,
              child: content,
            ),
            if (_hovered && !_editing)
              Positioned(
                top: 2,
                right: 8,
                child: _HoverBar(
                  isOwn: isOwn,
                  onReply: () => context.read<MessagingState>().setReplyTarget(
                    widget.message,
                  ),
                  onReact: () => _showEmojiPicker(context),
                  onEdit: isOwn ? _startEdit : null,
                  onMore: (pos) => _openContextMenu(context, pos),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openProfile(BuildContext context) {
    final user = widget.author;
    if (user == null) return;
    showUserProfileSheet(context, user);
  }

  Widget _fullBubble(String apiBase, String autumnBase, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openProfile(context),
            child: CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(_avatarUrl(autumnBase, apiBase)),
              backgroundColor: const Color(0xFF7F5AF0),
              onBackgroundImageError: (e, stack) {},
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Text(
                        _username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFFCBBDF7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(widget.message.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                    if (widget.message.edited != null) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '(edited)',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ],
                ),
                _messageBody(autumnBase, context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupedBubble(String autumnBase, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 1, 16, 1),
      child: _messageBody(autumnBase, context),
    );
  }

  Widget _messageBody(String autumnBase, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message.replies.isNotEmpty)
          _ReplyPreview(
            replyId: widget.message.replies.first,
            channelId: widget.message.channelId,
          ),
        if (_editing)
          _EditField(
            controller: _editCtrl,
            onCommit: () => _commitEdit(context),
            onCancel: _cancelEdit,
          )
        else if (widget.message.content != null &&
            widget.message.content!.isNotEmpty)
          SelectableText.rich(
            _renderContent(widget.message.content!),
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xDEFFFFFF),
              height: 1.45,
            ),
          ),
        for (final file in widget.message.attachments)
          _AttachmentWidget(file: file, autumnBase: autumnBase),
        if (widget.message.reactions.isNotEmpty)
          _ReactionsRow(
            reactions: widget.message.reactions,
            currentUserId: context.read<AuthState>().currentUser?.id ?? '',
            onToggle: (emoji) {
              final uid = context.read<AuthState>().currentUser?.id ?? '';
              final messaging = context.read<MessagingState>();
              if (widget.message.reactions[emoji]?.contains(uid) == true) {
                messaging.removeReaction(
                  widget.message.channelId,
                  widget.message.id,
                  emoji,
                );
              } else {
                messaging.addReaction(
                  widget.message.channelId,
                  widget.message.id,
                  emoji,
                );
              }
            },
          ),
      ],
    );
  }
}

// -- Hover action bar ----------------------------------------------------------

class _HoverBar extends StatelessWidget {
  final bool isOwn;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final VoidCallback? onEdit;
  final void Function(Offset) onMore;

  const _HoverBar({
    required this.isOwn,
    required this.onReply,
    required this.onReact,
    this.onEdit,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF242428),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverBtn(Icons.reply_rounded, 'Reply', onReply),
          _HoverBtn(Icons.add_reaction_outlined, 'React', onReact),
          if (onEdit != null) _HoverBtn(Icons.edit_rounded, 'Edit', onEdit!),
          _HoverMoreBtn(onMore),
        ],
      ),
    );
  }
}

class _HoverBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HoverBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Icon(icon, size: 15, color: Colors.white54),
        ),
      ),
    );
  }
}

class _HoverMoreBtn extends StatelessWidget {
  final void Function(Offset) onTapAt;
  const _HoverMoreBtn(this.onTapAt);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'More',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTapUp: (d) => onTapAt(d.globalPosition),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Icon(Icons.more_horiz, size: 15, color: Colors.white54),
        ),
      ),
    );
  }
}

// -- Context menu item ---------------------------------------------------------

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MenuItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: c, fontSize: 14)),
      ],
    );
  }
}

// -- Inline edit field ---------------------------------------------------------

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  const _EditField({
    required this.controller,
    required this.onCommit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          onCommit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xDEFFFFFF),
              height: 1.45,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1A1A20),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF7F5AF0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Color(0xFF7F5AF0),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Escape to ',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              GestureDetector(
                onTap: onCancel,
                child: const Text(
                  'cancel',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7F5AF0)),
                ),
              ),
              const Text(
                ' · ',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const Text(
                'Enter to ',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              GestureDetector(
                onTap: onCommit,
                child: const Text(
                  'save',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7F5AF0)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Reply preview (quote above a message that is a reply) ---------------------

class _ReplyPreview extends StatelessWidget {
  final String replyId;
  final String channelId;
  const _ReplyPreview({required this.replyId, required this.channelId});

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final msg = messaging.getMessageById(channelId, replyId);
    final author = msg != null ? messaging.getUser(msg.authorId) : null;
    final name = author?.resolveDisplayName(null) ?? msg?.authorId ?? 'Unknown';
    final preview = msg?.content?.trim() ?? '(message unavailable)';
    final truncated = preview.length > 80
        ? '${preview.substring(0, 80)}…'
        : preview;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
        border: const Border(
          left: BorderSide(color: Color(0xFF7F5AF0), width: 2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reply_rounded, size: 12, color: Color(0xFF7F5AF0)),
          const SizedBox(width: 4),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$name  ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFCBBDF7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: truncated,
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
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

// -- Reaction chips ------------------------------------------------------------

class _ReactionsRow extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final void Function(String emoji) onToggle;

  const _ReactionsRow({
    required this.reactions,
    required this.currentUserId,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactions.entries.map((e) {
          final emoji = e.key;
          final count = e.value.length;
          final mine = e.value.contains(currentUserId);
          return _ReactionChip(
            emoji: emoji,
            count: count,
            mine: mine,
            onTap: () => onToggle(emoji),
          );
        }).toList(),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: mine ? const Color(0x337F5AF0) : const Color(0xFF2A2A30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: mine ? const Color(0xFF7F5AF0) : const Color(0xFF3A3A42),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: mine ? const Color(0xFFCBBDF7) : Colors.white54,
                fontWeight: mine ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Attachment ----------------------------------------------------------------

class _AttachmentWidget extends StatelessWidget {
  final RevoltFile file;
  final String autumnBase;
  const _AttachmentWidget({required this.file, required this.autumnBase});

  bool get _isImage {
    final lower = file.filename.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
  }

  void _openImage(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  file.urlFor(autumnBase),
                  fit: BoxFit.contain,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (ctx, err, stack) => const Icon(
                    Icons.broken_image,
                    size: 64,
                    color: Colors.white38,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    final url = file.urlFor(autumnBase);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => _openImage(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 120,
                minHeight: 80,
                maxWidth: 400,
                maxHeight: 300,
              ),
              child: Image.network(
                file.urlFor(autumnBase),
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => const Icon(
                  Icons.broken_image,
                  size: 48,
                  color: Colors.white24,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: GestureDetector(
        onTap: () => _openFile(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF242428),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.attach_file, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Text(
                file.filename,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7F5AF0)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

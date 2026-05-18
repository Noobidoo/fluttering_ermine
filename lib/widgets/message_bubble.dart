import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';
import '../providers/messaging_state.dart';

enum _MsgAction { reply, edit, delete, copy }

class MessageBubble extends StatefulWidget {
  final RevoltMessage message;
  final RevoltUser? author;
  final bool grouped;

  const MessageBubble({
    super.key,
    required this.message,
    this.author,
    this.grouped = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;
  bool _editing = false;
  late TextEditingController _editCtrl;

  String get _username =>
      widget.author?.displayUsername ?? widget.message.authorId;

  String _avatarUrl(String autumnBase, String apiBase) =>
      widget.author?.avatarUrlFor(autumnBase, apiBase) ??
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
        widget.message.channelId, widget.message.id, text);
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
                  widget.message.channelId, widget.message.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
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
            child: _MenuItem(Icons.delete_rounded, 'Delete',
                color: Colors.redAccent),
          ),
        ],
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      switch (action) {
        case _MsgAction.reply:
          context.read<MessagingState>().setReplyTarget(widget.message);
        case _MsgAction.edit:
          _startEdit();
        case _MsgAction.delete:
          _confirmDelete(context);
        case _MsgAction.copy:
          Clipboard.setData(
              ClipboardData(text: widget.message.content ?? ''));
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
                  onReply: () => context
                      .read<MessagingState>()
                      .setReplyTarget(widget.message),
                  onEdit: isOwn ? _startEdit : null,
                  onMore: (pos) => _openContextMenu(context, pos),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fullBubble(String apiBase, String autumnBase, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(_avatarUrl(autumnBase, apiBase)),
            backgroundColor: const Color(0xFF7F5AF0),
            onBackgroundImageError: (e, stack) {},
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFCBBDF7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(widget.message.timestamp),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38),
                    ),
                    if (widget.message.edited != null) ...[
                      const SizedBox(width: 4),
                      const Text('(edited)',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white38)),
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
          SelectableText(
            widget.message.content!,
            style: const TextStyle(
                fontSize: 14, color: Color(0xDEFFFFFF), height: 1.45),
          ),
        for (final file in widget.message.attachments)
          _AttachmentWidget(file: file, autumnBase: autumnBase),
      ],
    );
  }
}

// ── Hover action bar ──────────────────────────────────────────────────────────

class _HoverBar extends StatelessWidget {
  final bool isOwn;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final void Function(Offset) onMore;

  const _HoverBar({
    required this.isOwn,
    required this.onReply,
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
          BoxShadow(
              color: Colors.black38, blurRadius: 4, offset: Offset(0, 1))
        ],
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverBtn(Icons.reply_rounded, 'Reply', onReply),
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

// ── Context menu item ─────────────────────────────────────────────────────────

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

// ── Inline edit field ─────────────────────────────────────────────────────────

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
                fontSize: 14, color: Color(0xDEFFFFFF), height: 1.45),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1A1A20),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF7F5AF0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF7F5AF0), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Escape to ',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              GestureDetector(
                onTap: onCancel,
                child: const Text('cancel',
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF7F5AF0))),
              ),
              const Text(' · ',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              const Text('Enter to ',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              GestureDetector(
                onTap: onCommit,
                child: const Text('save',
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFF7F5AF0))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Reply preview (quote above a message that is a reply) ─────────────────────

class _ReplyPreview extends StatelessWidget {
  final String replyId;
  final String channelId;
  const _ReplyPreview({required this.replyId, required this.channelId});

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingState>();
    final msg = messaging.getMessageById(channelId, replyId);
    final author = msg != null ? messaging.getUser(msg.authorId) : null;
    final name = author?.displayUsername ?? msg?.authorId ?? 'Unknown';
    final preview = msg?.content?.trim() ?? '(message unavailable)';
    final truncated =
        preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(4),
        border: const Border(
            left: BorderSide(color: Color(0xFF7F5AF0), width: 2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.reply_rounded,
              size: 12, color: Color(0xFF7F5AF0)),
          const SizedBox(width: 4),
          Flexible(
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
                  text: truncated,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 400, maxHeight: 300),
            child: Image.network(
              file.urlFor(autumnBase),
              fit: BoxFit.contain,
              errorBuilder: (ctx, err, stack) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF242428),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.attach_file,
                size: 16, color: Colors.white54),
            const SizedBox(width: 8),
            Text(file.filename,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF7F5AF0))),
          ],
        ),
      ),
    );
  }
}

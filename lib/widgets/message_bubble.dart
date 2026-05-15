import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_state.dart';

class MessageBubble extends StatelessWidget {
  final RevoltMessage message;
  final RevoltUser? author;
  final bool grouped;

  const MessageBubble({
    super.key,
    required this.message,
    this.author,
    this.grouped = false,
  });

  String get _username =>
      author?.displayUsername ?? message.authorId;

  String _avatarUrl(String autumnBase, String apiBase) =>
      author?.avatarUrlFor(autumnBase, apiBase) ??
      '$apiBase/users/${message.authorId}/default_avatar';

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
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (grouped) return _groupedBubble(auth.autumnBase);
    return _fullBubble(auth.apiBase, auth.autumnBase);
  }

  Widget _fullBubble(String apiBase, String autumnBase) {
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
                      _formatTimestamp(message.timestamp),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white38),
                    ),
                    if (message.edited != null) ...[
                      const SizedBox(width: 4),
                      const Text('(edited)',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white38)),
                    ],
                  ],
                ),
                _messageBody(autumnBase),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupedBubble(String autumnBase) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 1, 16, 1),
      child: _messageBody(autumnBase),
    );
  }

  Widget _messageBody(String autumnBase) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.content != null && message.content!.isNotEmpty)
          SelectableText(
            message.content!,
            style: const TextStyle(
                fontSize: 14, color: Color(0xDEFFFFFF), height: 1.45),
          ),
        for (final file in message.attachments)
          _AttachmentWidget(file: file, autumnBase: autumnBase),
      ],
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

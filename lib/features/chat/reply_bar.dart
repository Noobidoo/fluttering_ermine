import 'package:flutter/material.dart';

import '../../models/revolt_message.dart';
import '../../models/revolt_user.dart';

class ReplyBar extends StatelessWidget {
  final RevoltMessage message;
  final RevoltUser? author;
  final VoidCallback onDismiss;

  const ReplyBar({super.key, required this.message, this.author, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final name = author?.resolveDisplayName(null) ?? message.authorId;
    final preview = message.content?.trim() ?? '';
    final truncated = preview.length > 60 ? '${preview.substring(0, 60)}…' : preview;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A20),
        border: Border(left: BorderSide(color: Color(0xFF7F5AF0), width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF7F5AF0)),
          const SizedBox(width: 6),
          Expanded(
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
                    text: truncated.isEmpty ? '(attachment)' : truncated,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}

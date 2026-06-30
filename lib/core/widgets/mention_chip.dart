import 'package:flutter/material.dart';

import '../../features/messaging/providers/messaging_notifier.dart';

InlineSpan buildMentionChip(
  String userId,
  MessagingStateData messaging, {
  TextStyle? baseStyle,
}) {
  final user = messaging.userCache[userId];
  final name = '@${user?.resolveDisplayName(null) ?? userId}';
  final style = (baseStyle ?? const TextStyle()).copyWith(
    color: const Color(0xFFCBBDF7),
    fontWeight: FontWeight.w500,
    fontSize: baseStyle?.fontSize ?? 14,
    height: 1.2,
  );
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0x337F5AF0),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text(name, style: style),
    ),
  );
}

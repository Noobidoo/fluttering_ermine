import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/revolt_channel.dart';
import '../../../models/revolt_message.dart';
import '../../messaging/providers/messaging_notifier.dart';
import '../../servers/providers/server_notifier.dart';

/// The currently selected channel from server state.
final currentChannelProvider = Provider<RevoltChannel?>((ref) {
  return ref.watch(serverStateProvider).asData?.value.selectedChannel;
});

/// Messages for the currently selected channel.
final currentMessagesProvider = Provider<List<RevoltMessage>>((ref) {
  final channelId = ref.watch(currentChannelProvider)?.id;
  if (channelId == null) return [];
  return ref.watch(messagingStateProvider).messages[channelId] ?? [];
});

final isLoadingMessagesProvider = Provider<bool>((ref) {
  final channelId = ref.watch(currentChannelProvider)?.id;
  if (channelId == null) return false;
  return ref.watch(messagingStateProvider).loadingChannels.contains(channelId);
});

/// Error for the currently selected channel.
final currentChannelErrorProvider = Provider<String?>((ref) {
  final channelId = ref.watch(currentChannelProvider)?.id;
  if (channelId == null) return null;
  return ref.watch(messagingStateProvider).channelErrors[channelId];
});

/// Reply target from messaging state.
final currentReplyTargetProvider = Provider((ref) {
  return ref.watch(messagingStateProvider).replyTarget;
});

/// Typing user IDs for the currently selected channel.
final typingUserIdsProvider = Provider<Set<String>>((ref) {
  final channelId = ref.watch(currentChannelProvider)?.id;
  if (channelId == null) return {};
  return ref.watch(messagingStateProvider).typingUsers[channelId] ?? {};
});

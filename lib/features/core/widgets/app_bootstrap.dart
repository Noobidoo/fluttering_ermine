import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../messaging/providers/messaging_notifier.dart';
import '../../servers/providers/server_notifier.dart';
import '../../voice/providers/voice_providers.dart';

class AppBootstrap extends ConsumerWidget {
  final Widget child;
  const AppBootstrap({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverStateProvider);
    ref.watch(voiceStateProvider);

    final messagingNotifier = ref.read(messagingStateProvider.notifier);
    ref.read(serverStateProvider.notifier).onUsersFetched = messagingNotifier.cacheUsers;
    ref.read(serverStateProvider.notifier).onServerProfileUpdated =
        messagingNotifier.updateServerProfile;

    return child;
  }
}

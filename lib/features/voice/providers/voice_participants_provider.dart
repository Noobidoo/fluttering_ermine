import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_notifier.dart';

final voiceParticipantsProvider = Provider.family<List<String>, String>(
  (ref, channelId) =>
      ref.watch(voiceStateProvider).voiceParticipantsFor(channelId),
);

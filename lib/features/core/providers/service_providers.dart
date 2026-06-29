import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/revolt_service.dart';
import '../../../services/voice_event_service.dart';

final revoltServiceProvider = Provider<RevoltService>((ref) {
  return RevoltService();
});

final voiceEventServiceProvider = Provider<VoiceEventService>((ref) {
  return VoiceEventService(ref.watch(revoltServiceProvider));
});
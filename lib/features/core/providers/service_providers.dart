import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/revolt_service.dart';
import '../../../services/voice_event_service.dart';

final revoltServiceProvider = Provider<RevoltService>((ref) {
  throw UnimplementedError('Must be overridden in main.dart');
});

final voiceEventServiceProvider = Provider<VoiceEventService>((ref) {
  throw UnimplementedError('Must be overridden in main.dart');
});

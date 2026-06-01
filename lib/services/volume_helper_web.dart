import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Sets the volume of all active LiveKit audio elements on the web page.
/// [volume] is clamped to [0.0, 1.0].
void applyLiveKitVolume(double volume) {
  final clamped = volume.clamp(0.0, 1.0);
  final container =
      web.document.getElementById('livekit_audio_container');
  if (container == null) return;

  final audioEls = container.querySelectorAll('audio');
  for (var i = 0; i < audioEls.length; i++) {
    final el = audioEls.item(i);
    if (el != null) {
      (el as web.HTMLAudioElement).volume = clamped;
    }
  }
}

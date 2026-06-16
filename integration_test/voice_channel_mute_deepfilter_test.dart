import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  late FlutterDriver driver;

  setUpAll(() async {
    driver = await FlutterDriver.connect();
  });

  tearDownAll(() async {
    await driver.close();
  });

  Future<void> navigateToVoiceChannel() async {
    await driver.waitFor(find.byType('HomeScreen'));
    await driver.tap(find.text('Voice'));
    await driver.waitFor(find.text('Join Voice'));
  }

  Future<void> joinVoice() async {
    await driver.tap(find.text('Join Voice'));
    await driver.waitFor(find.text('You are in this channel'));
  }

  test('toggle mute and deepfilter in voice channel', () async {
    await navigateToVoiceChannel();
    await joinVoice();

    // Mute: toggle on and verify
    await driver.tap(find.text('Mute'));
    await driver.waitFor(find.text('Unmute'));

    // Mute: toggle off and verify
    await driver.tap(find.text('Unmute'));
    await driver.waitFor(find.text('Mute'));

    // DeepFilter: toggle on
    await driver.tap(find.byTooltip('Neural noise suppression: off'));
    await driver.waitFor(find.byTooltip('Neural noise suppression: initializing…'));

    // DeepFilter: toggle off
    await driver.tap(find.byTooltip('Neural noise suppression: initializing…'));
    await driver.waitFor(find.byTooltip('Neural noise suppression: off'));
  });
}

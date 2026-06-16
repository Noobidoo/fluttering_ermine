// User journey: Join a voice channel
// 1. On the home screen with a server selected, tap a voice channel tile
// 2. In the voice channel view, tap "Join Voice"
// 3. Verify the connection succeeds

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

  test('join voice channel', () async {
    await driver.waitFor(find.byType('HomeScreen'));

    await driver.tap(find.text('Voice'));

    await driver.waitFor(find.text('Join Voice'));

    await driver.tap(find.text('Join Voice'));

    await driver.waitFor(find.text('You are in this channel'));

    await driver.waitFor(find.text('Voice Connected'));
  });
}

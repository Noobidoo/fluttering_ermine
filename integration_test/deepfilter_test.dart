import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluttering_ermine/main.dart' as app;
import 'package:fluttering_ermine/features/servers/providers/server_providers.dart';
import 'package:fluttering_ermine/features/home/home_screen.dart';
import 'env_values.dart';

const _channel = MethodChannel('io.deepfilter.livekit');
final _env = envValues;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform
        .instance = InMemorySharedPreferencesAsync.withData({
      'revolt_session_token': _env['REVOLT_TOKEN'] ?? '',
      'revolt_api_base': _env['REVOLT_API_BASE'] ?? 'https://api.revolt.chat',
      'revolt_ws_url': _env['REVOLT_WS_URL'] ?? 'wss://ws.revolt.chat',
    });
  });

  testWidgets(
    'DeepFilter native init succeeds on device',
    (tester) async {
      // Verify native lib loads
      final isAvailable = await _channel.invokeMethod<bool>('isAvailable');
      expect(isAvailable, isTrue, reason: 'libdeep_filter_jni.so must load');

      // init with empty path → resolveModelPath finds bundled asset
      final initResult = await _channel.invokeMethod<String>('init', {
        'modelPath': '',
        'sampleRate': 48000,
      });
      expect(
        initResult,
        'ok',
        reason: 'init should load the bundled model and succeed',
      );

      // Verify the model is loaded by querying frame size
      final frameSize = await _channel.invokeMethod<int>('getFrameSize');
      expect(
        frameSize,
        greaterThan(0),
        reason: 'df_get_frame_length should return valid frame size',
      );

      // Clean up
      await _channel.invokeMethod<void>('dispose');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'voice join with deepfilter does not crash',
    (tester) async {
      final serverId = _env['VOICE_SERVER_ID'] ?? '';
      final channelId = _env['VOICE_CHANNEL_ID'] ?? '';
      if (serverId.isEmpty || channelId.isEmpty) {
        debugPrint(
          '[integration] Skipping: set VOICE_SERVER_ID and VOICE_CHANNEL_ID in .env',
        );
        return;
      }

      app.main();
      await tester.pump();

      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(
        find.byType(HomeScreen),
        findsOneWidget,
        reason: 'Should reach home screen after auto-login',
      );

      // Select the voice server via provider
      bool voiceJoined = false;
      final homeCtx = find.byType(HomeScreen).evaluate().first;
      final container = ProviderScope.containerOf(homeCtx);
      final notifier = container.read(serverStateProvider.notifier);
      final servers = container.read(serverStateProvider).requireValue.servers;
      final server = servers.firstWhere(
        (s) => s.id == serverId,
        orElse: () {
          debugPrint(
            '[integration] Server $serverId not in serverState.servers',
          );
          return servers.first;
        },
      );
      debugPrint('[integration] Selecting server ${server.name} ($serverId)');
      notifier.selectServer(server);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final channelTile = find.byKey(ValueKey('channel_$channelId'));
      if (channelTile.evaluate().isEmpty) {
        debugPrint('[integration] Voice channel tile not found for $channelId');
      } else {
        await tester.scrollUntilVisible(channelTile, 200.0);
        await tester.tap(channelTile);
        voiceJoined = true;
        await tester.pumpAndSettle(const Duration(seconds: 10));
      }

      debugPrint('[integration] voiceJoined=$voiceJoined');

      // init with empty path → resolveModelPath finds bundled model
      final initResult = await _channel.invokeMethod<String>('init', {
        'modelPath': '',
        'sampleRate': 48000,
      });
      expect(
        initResult,
        'ok',
        reason: 'deepfilter init must succeed after voice join',
      );

      // Verify we can query frame size (model is loaded)
      final frameSize = await _channel.invokeMethod<int>('getFrameSize');
      expect(frameSize, greaterThan(0), reason: 'frame size must be valid');

      // Stay alive for a few seconds to verify no crash during processing
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      await _channel.invokeMethod<void>('dispose');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

import 'package:connectivity_plus_linux_portal/connectivity_plus_linux_portal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/revolt_service.dart';
import 'services/voice_event_service.dart';
import 'features/auth/providers/login_notifier.dart';
import 'features/core/providers/service_providers.dart';
import 'features/core/widgets/app_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    ConnectivityPlusLinuxPortalPlugin.registerWith();
  }

  final service = RevoltService();
  final voiceEventService = VoiceEventService(service);

  runApp(
    ProviderScope(
      overrides: [
        revoltServiceProvider.overrideWithValue(service),
        voiceEventServiceProvider.overrideWithValue(voiceEventService),
      ],
      child: AppBootstrap(child: const FlutteringErmineApp()),
    ),
  );
}

class FlutteringErmineApp extends ConsumerWidget {
  const FlutteringErmineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Fluttering Ermine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7F5AF0),
          secondary: Color(0xFF2CB67D),
          surface: Color(0xFF16161A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E26),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3A3A46)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3A3A46)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF7F5AF0), width: 2),
          ),
        ),
      ),
      home: ref
          .watch(loginStateProvider)
          .when(
            loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (e, st) => const LoginScreen(),
            data: (auth) => auth.isLoggedIn ? const HomeScreen() : const LoginScreen(),
          ),
    );
  }
}

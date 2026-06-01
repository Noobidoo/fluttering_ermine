import 'package:connectivity_plus_linux_portal/connectivity_plus_linux_portal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_state.dart';
import 'providers/messaging_state.dart';
import 'providers/server_state.dart';
import 'providers/voice_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/revolt_service.dart';
import 'services/voice_event_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    ConnectivityPlusLinuxPortalPlugin.registerWith();
  }

  final service = RevoltService();
  final voiceEventService = VoiceEventService(service);
  final serverState = ServerState(service);
  final voiceState = VoiceState(service, voiceEventService);
  final messagingState = MessagingState(service, serverState);
  final authState = AuthState(
    service,
    serverState,
    messagingState,
    voiceState,
    voiceEventService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authState),
        ChangeNotifierProvider.value(value: serverState),
        ChangeNotifierProvider.value(value: messagingState),
        ChangeNotifierProvider.value(value: voiceState),
      ],
      child: const FlutteringErmineApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    authState.init();
  });
}

class FlutteringErmineApp extends StatelessWidget {
  const FlutteringErmineApp({super.key});

  @override
  Widget build(BuildContext context) {
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
            borderSide:
                const BorderSide(color: Color(0xFF7F5AF0), width: 2),
          ),
        ),
      ),
      home: Consumer<AuthState>(
        builder: (context, auth, child) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}


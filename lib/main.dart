import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const FlutteringErmineApp(),
    ),
  );
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
      home: Consumer<AppState>(
        builder: (context, state, child) {
          if (state.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return state.isLoggedIn ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}


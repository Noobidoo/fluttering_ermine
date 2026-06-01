import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/providers/auth_state.dart';
import 'package:fluttering_ermine/providers/messaging_state.dart';
import 'package:fluttering_ermine/providers/server_state.dart';
import 'package:fluttering_ermine/providers/voice_state.dart';
import 'mocks.dart';

/// Builds a test app that wraps [child] with the same provider structure
/// as the real app, but using mock services.
///
/// Pass custom [mockService] and [mockVoiceEvent] to configure stubs
/// before pumping. Created providers are returned for inspection.
class TestApp extends StatelessWidget {
  final Widget child;
  final MockRevoltService mockService;
  final MockVoiceEventService mockVoiceEvent;

  TestApp({
    super.key,
    required this.child,
    MockRevoltService? mockService,
    MockVoiceEventService? mockVoiceEvent,
  })  : mockService = mockService ?? MockRevoltService(),
        mockVoiceEvent = mockVoiceEvent ?? MockVoiceEventService();

  @override
  Widget build(BuildContext context) {
    final serverState = ServerState(mockService);
    final voiceState = VoiceState(mockService, mockVoiceEvent);
    final messagingState = MessagingState(mockService, serverState);
    final authState = AuthState(
      mockService,
      serverState,
      messagingState,
      voiceState,
      mockVoiceEvent,
    );

    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7F5AF0),
          secondary: Color(0xFF2CB67D),
          surface: Color(0xFF16161A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
      ),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authState),
          ChangeNotifierProvider.value(value: serverState),
          ChangeNotifierProvider.value(value: messagingState),
          ChangeNotifierProvider.value(value: voiceState),
        ],
        child: child,
      ),
    );
  }
}

/// Message data for golden test scenarios.
class TestMessage {
  static RevoltMessage withImageAttachment() => RevoltMessage(
        id: 'msg-img',
        channelId: 'chan1',
        authorId: 'u1',
        content: 'Check out this image',
        timestamp: '2026-06-01T12:00:00.000Z',
        attachments: [
          RevoltFile(
            id: 'file1',
            tag: 'attachments',
            filename: 'screenshot.png',
          ),
        ],
      );

  static RevoltMessage withFileAttachment() => RevoltMessage(
        id: 'msg-file',
        channelId: 'chan1',
        authorId: 'u1',
        content: 'Here is the document',
        timestamp: '2026-06-01T12:00:00.000Z',
        attachments: [
          RevoltFile(
            id: 'file2',
            tag: 'attachments',
            filename: 'report.pdf',
          ),
        ],
      );

  static RevoltMessage withReactions() => RevoltMessage(
        id: 'msg-react',
        channelId: 'chan1',
        authorId: 'u1',
        content: 'Hello everyone!',
        timestamp: '2026-06-01T12:00:00.000Z',
        reactions: {
          '👍': ['u1', 'u2'],
          '🔥': ['u2'],
        },
      );
}

RevoltUser testUser(String id) => RevoltUser(
      id: id,
      username: 'testuser_$id',
      discriminator: '0000',
    );

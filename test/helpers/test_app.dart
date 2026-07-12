import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluttering_ermine/features/core/providers/service_providers.dart';
import 'package:fluttering_ermine/models/models.dart';
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
  }) : mockService = mockService ?? MockRevoltService(),
       mockVoiceEvent = mockVoiceEvent ?? MockVoiceEventService() {
    SharedPreferencesAsyncPlatform.instance ??=
        InMemorySharedPreferencesAsync.empty();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        revoltServiceProvider.overrideWithValue(mockService),
        voiceEventServiceProvider.overrideWithValue(mockVoiceEvent),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF7F5AF0),
            secondary: Color(0xFF2CB67D),
            surface: Color(0xFF16161A),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F0F13),
        ),
        home: child,
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
      RevoltFile(id: 'file1', tag: 'attachments', filename: 'screenshot.png'),
    ],
  );

  static RevoltMessage withFileAttachment() => RevoltMessage(
    id: 'msg-file',
    channelId: 'chan1',
    authorId: 'u1',
    content: 'Here is the document',
    timestamp: '2026-06-01T12:00:00.000Z',
    attachments: [
      RevoltFile(id: 'file2', tag: 'attachments', filename: 'report.pdf'),
    ],
  );

  static RevoltMessage withReactions() => RevoltMessage(
    id: 'msg-react',
    channelId: 'chan1',
    authorId: 'u1',
    content: 'Hello everyone!',
    timestamp: '2026-06-01T12:00:00.000Z',
    reactions: {
      '\u{1F44D}': ['u1', 'u2'],
      '\u{1F525}': ['u2'],
    },
  );
}

RevoltUser testUser(String id) =>
    RevoltUser(id: id, username: 'testuser_$id', discriminator: '0000');

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/widgets/user_profile_sheet.dart';

import '../helpers/mocks.dart';
import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileSheet', () {
    testWidgets('shows display name and username', (tester) async {
      final mockService = MockRevoltService();
      when(() => mockService.fetchUserProfile(any())).thenAnswer(
        (_) async => UserProfile(content: null, background: null),
      );

      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
      );

      await tester.pumpWidget(TestApp(
        mockService: mockService,
        child: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () => showUserProfileSheet(context, ref, user),
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('testuser'), findsOneWidget);
    });

    testWidgets('shows status text when present', (tester) async {
      final mockService = MockRevoltService();
      when(() => mockService.fetchUserProfile(any())).thenAnswer(
        (_) async => UserProfile(content: null, background: null),
      );

      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
        statusText: 'busy coding',
      );

      await tester.pumpWidget(TestApp(
        mockService: mockService,
        child: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () => showUserProfileSheet(context, ref, user),
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('busy coding'), findsOneWidget);
    });

    testWidgets('shows bio from profile endpoint', (tester) async {
      final mockService = MockRevoltService();
      when(() => mockService.fetchUserProfile(any())).thenAnswer(
        (_) async => UserProfile(content: 'Hello world', background: null),
      );

      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
      );

      await tester.pumpWidget(TestApp(
        mockService: mockService,
        child: Consumer(builder: (context, ref, _) {
          return ElevatedButton(
            onPressed: () => showUserProfileSheet(context, ref, user),
            child: const Text('Show'),
          );
        }),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Hello world'), findsOneWidget);
    });
  });
}

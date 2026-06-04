import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/widgets/user_profile_sheet.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileSheet', () {
    testWidgets('shows display name and username', (tester) async {
      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
      );

      await tester.pumpWidget(TestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showUserProfileSheet(ctx, user),
            child: const Text('Show'),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('testuser'), findsOneWidget);
    });

    testWidgets('shows status text when present', (tester) async {
      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
        statusText: 'busy coding',
      );

      await tester.pumpWidget(TestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showUserProfileSheet(ctx, user),
            child: const Text('Show'),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('busy coding'), findsOneWidget);
    });

    testWidgets('shows bio when present', (tester) async {
      final user = RevoltUser(
        id: 'u1',
        username: 'testuser',
        discriminator: '0001',
        profileContent: 'Hello world',
      );

      await tester.pumpWidget(TestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showUserProfileSheet(ctx, user),
            child: const Text('Show'),
          ),
        ),
      ));

      await tester.tap(find.text('Show'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Hello world'), findsOneWidget);
    });
  });
}

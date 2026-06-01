import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttering_ermine/models/models.dart';
import 'package:fluttering_ermine/widgets/message_bubble.dart';

import '../helpers/test_app.dart';

void main() {
  group('MessageBubble', () {
    testWidgets('renders text content', (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: RevoltMessage(
                id: 'm1',
                channelId: 'chan1',
                authorId: 'u1',
                content: 'Hello world',
                timestamp: '2026-06-01T12:00:00.000Z',
              ),
            ),
          ),
        ),
      ));

      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('u1'), findsOneWidget);
    });

    testWidgets('renders image attachment area', (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: TestMessage.withImageAttachment(),
            ),
          ),
        ),
      ));

      expect(
        find.byWidgetPredicate(
            (w) => w is ConstrainedBox && w.constraints.maxWidth == 400),
        findsOneWidget,
      );
    });

    testWidgets('tapping image area opens full-screen viewer',
        (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: TestMessage.withImageAttachment(),
            ),
          ),
        ),
      ));

      final constrained = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.minWidth == 120,
      );
      await tester.ensureVisible(constrained);
      await tester.pump();
      await tester.tap(constrained);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('renders file attachment with filename', (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: TestMessage.withFileAttachment(),
            ),
          ),
        ),
      ));

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });

    testWidgets('renders reaction chips', (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: TestMessage.withReactions(),
            ),
          ),
        ),
      ));

      expect(find.text('👍'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('context menu via long press', (tester) async {
      await tester.pumpWidget(TestApp(
        child: Scaffold(
          body: SingleChildScrollView(
            child: MessageBubble(
              message: RevoltMessage(
                id: 'm1',
                channelId: 'chan1',
                authorId: 'u1',
                content: 'Test message',
                timestamp: '2026-06-01T12:00:00.000Z',
              ),
            ),
          ),
        ),
      ));

      await tester.ensureVisible(find.text('Test message'));
      await tester.pump();

      final center = tester.getCenter(find.byType(MessageBubble));
      await tester.longPressAt(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('React'), findsOneWidget);
      expect(find.text('Copy Text'), findsWidgets);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/widgets/app_icon_badge.dart';

void main() {
  group('formatIconBadgeCount', () {
    test('empty when zero or negative', () {
      expect(formatIconBadgeCount(0), '');
      expect(formatIconBadgeCount(-1), '');
    });

    test('raw count from 1 to 9', () {
      expect(formatIconBadgeCount(1), '1');
      expect(formatIconBadgeCount(9), '9');
    });

    test('caps above 9 as 9+', () {
      expect(formatIconBadgeCount(10), '9+');
      expect(formatIconBadgeCount(99), '9+');
    });
  });

  testWidgets('AppIconBadge shows minimized 9+ label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconBadge(
            icon: const Icon(Icons.chat_bubble_outline),
            count: 12,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('9+'), findsOneWidget);
    expect(find.text('12'), findsNothing);
  });

  testWidgets('AppIconBadge hides badge when count is zero', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconBadge(
            icon: const Icon(Icons.notifications_outlined),
            count: 0,
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.text('9+'), findsNothing);
  });
}

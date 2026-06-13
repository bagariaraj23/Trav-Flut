import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';

void main() {
  testWidgets('ChatAvatar shows initial when no image URL is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatAvatar(
            username: 'alice',
            name: 'Alice Example',
          ),
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('ChatAvatar uses name initial when username is missing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatAvatar(
            name: 'Bob',
          ),
        ),
      ),
    );

    expect(find.text('B'), findsOneWidget);
  });
}

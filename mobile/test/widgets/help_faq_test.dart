import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/screens/settings/help_faq_screen.dart';
import 'package:tripthread/screens/settings/help_topics.dart';

void main() {
  test('help covers the rules people ask about', () {
    final text = helpTopics
        .expand((topic) => topic.items)
        .map((item) => '${item.question} ${item.answer}')
        .join('\n');
    expect(helpTopics.map((topic) => topic.id), contains('safety'));
    expect(text, contains('15 minutes'));
    expect(text, contains('512'));
    expect(text, contains('private'));
    expect(text, contains('Discover'));
    expect(text, contains('final post'));
    expect(text, contains('admin'));
  });

  testWidgets('help search opens the matching answer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpFaqScreen()));
    await tester.enterText(find.byType(TextField), '512');
    await tester.pump();
    expect(find.text('How long can I edit or delete a message?'), findsOneWidget);
    expect(find.textContaining('512 characters'), findsOneWidget);
  });

  testWidgets('safety info explains restrict and block', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: IconButton(
              tooltip: 'What Restrict and Block do',
              onPressed: () => showSafetyInfo(context),
              icon: const Icon(Icons.info_outline),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('What Restrict and Block do'));
    await tester.pumpAndSettle();
    expect(find.text('Restrict and Block'), findsOneWidget);
    expect(find.textContaining('direct message both ways'), findsOneWidget);
    expect(find.text('Read the full guide'), findsOneWidget);
  });
}
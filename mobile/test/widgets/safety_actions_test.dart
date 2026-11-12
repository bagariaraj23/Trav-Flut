import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/widgets/safety/safety_actions.dart';

void main() {
  test('safety choices follow the current action', () {
    expect(safetyChoices(null).map((choice) => choice.label).toList(), [
      'Restrict',
      'Block',
    ]);
    expect(safetyChoices('RESTRICT').map((choice) => choice.label).toList(), [
      'Remove restriction',
      'Block',
    ]);
    expect(safetyChoices('BLOCK').single.label, 'Unblock');
    expect(safetyChoices('BLOCK').single.clears, isTrue);
  });

  testWidgets('choice list calls the selected action', (tester) async {
    SafetyChoice? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyChoiceList(
            choices: safetyChoices(null),
            onSelected: (choice) => selected = choice,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Block'));
    expect(selected?.action, 'BLOCK');
    expect(selected?.destructive, isTrue);
  });
}
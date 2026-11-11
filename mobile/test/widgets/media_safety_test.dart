import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/screens/settings/safety_list_screen.dart';
import 'package:tripthread/widgets/media/media_seek.dart';

void main() {
  test('seek stays inside the video', () {
    expect(
      clampSeek(const Duration(seconds: 2), -skipStep, const Duration(seconds: 20)),
      Duration.zero,
    );
    expect(
      clampSeek(const Duration(seconds: 18), skipStep, const Duration(seconds: 20)),
      const Duration(seconds: 20),
    );
    expect(
      clampSeek(const Duration(seconds: 8), skipStep, const Duration(seconds: 20)),
      const Duration(seconds: 13),
    );
    expect(nextPlaybackSpeed(1), 1.25);
  });

  testWidgets('double tap skips five seconds by side', (tester) async {
    Duration? skipped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: GallerySkipLayer(
                onSkip: (delta) => skipped = delta,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final topLeft = tester.getTopLeft(find.byType(GallerySkipLayer));
    await tester.tapAt(topLeft + const Offset(20, 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(topLeft + const Offset(20, 40));
    await tester.pump();
    expect(skipped, -skipStep);

    skipped = null;
    await tester.tapAt(topLeft + const Offset(170, 40));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(topLeft + const Offset(170, 40));
    await tester.pump();
    expect(skipped, skipStep);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('selected photo shows its order', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PhotoOrderBadge(position: 3)),
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('safety row can undo a block', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafetyPersonTile(
            name: 'Asha',
            detail: 'Blocked',
            undoLabel: 'Unblock',
            onUndo: () => undone = true,
          ),
        ),
      ),
    );
    expect(find.text('Asha'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Unblock'));
    expect(undone, isTrue);
  });
}

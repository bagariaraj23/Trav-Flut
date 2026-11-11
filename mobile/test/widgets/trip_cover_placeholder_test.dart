import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/widgets/trip_cover_placeholder.dart';

void main() {
  testWidgets('shows the destination, then the title, then a fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TripCoverPlaceholder(
            title: 'Coast road',
            destination: 'Goa',
          ),
        ),
      ),
    );
    expect(find.text('Goa'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TripCoverPlaceholder(title: 'Coast road')),
      ),
    );
    expect(find.text('Coast road'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TripCoverPlaceholder(title: '   ')),
      ),
    );
    expect(find.text('Add a cover'), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });
}

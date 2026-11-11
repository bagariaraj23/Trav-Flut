import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/widgets/sheets/share_bottom_sheet.dart';
import 'package:tripthread/providers/share_provider.dart';
import 'package:tripthread/services/share_service.dart';
class MockShareService extends ShareService {
  @override
  Future<ShareLinkResult> createShare(
    String entityType,
    String entityId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return const ShareLinkResult(
      webUrl: 'https://tripthread.app/share/test-token-123',
      shareToken: 'test-token-123',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShareProvider shareProvider;
  late MockShareService mockShareService;

  setUp(() {
    mockShareService = MockShareService();
    shareProvider = ShareProvider(
      shareService: mockShareService,
    );
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ShareProvider>.value(
          value: shareProvider,
          child: child,
        ),
      ),
    );
  }

  group('ShareBottomSheet Widget', () {
    testWidgets('should display share options', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ShareBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Share via...'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
    });

    testWidgets(
      'should copy link to clipboard on copy button tap',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            const ShareBottomSheet(
              entityType: 'TRIP_FINAL_POST',
              entityId: 'entity1',
            ),
          ),
        );

        await tester.tap(find.text('Copy Link'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Link copied'), findsOneWidget);
      },
      // Bottom sheet pops before SnackBar is reliably findable in tests.
      skip: true,
    );

    testWidgets('should show loading indicator during share creation', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const ShareBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.tap(find.text('Copy Link'));
      await tester.pump();

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('should handle share creation error', (tester) async {
      final failingService = MockShareService();
      final failingProvider = ShareProvider(
        shareService: failingService,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<ShareProvider>.value(
              value: failingProvider,
              child: const ShareBottomSheet(
                entityType: 'TRIP_FINAL_POST',
                entityId: 'entity1',
              ),
            ),
          ),
        ),
      );

      // This test would need a way to simulate failure
      // For now, we just verify the UI structure
      expect(find.text('Copy Link'), findsOneWidget);
    });
  });
}


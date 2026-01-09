import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/ui/widgets/like_button.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/like_service.dart';

class MockLikeService extends LikeService {
  bool shouldFail = false;
  int toggleCallCount = 0;

  @override
  Future<void> toggleLike(String entityType, String entityId) async {
    toggleCallCount++;
    if (shouldFail) {
      throw Exception('Like failed');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late EngagementProvider engagementProvider;
  late MockLikeService mockLikeService;

  setUp(() {
    mockLikeService = MockLikeService();
    engagementProvider = EngagementProvider(likeService: mockLikeService);
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<EngagementProvider>.value(
          value: engagementProvider,
          child: child,
        ),
      ),
    );
  }

  group('LikeButton Widget', () {
    testWidgets('should display like button with initial state', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('should display liked state when entity is liked', (tester) async {
      engagementProvider.setLikeStatus('entity1', true, count: 5);

      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('should toggle like on tap', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byType(LikeButton));
      await tester.pump();

      // Optimistic update
      expect(engagementProvider.isLiked('entity1'), true);

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(mockLikeService.toggleCallCount, 1);
    });

    testWidgets('should show loading indicator during toggle', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.tap(find.byType(LikeButton));
      await tester.pump();

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should format count correctly', (tester) async {
      engagementProvider.setLikeStatus('entity1', true, count: 1234);

      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1.2K'), findsOneWidget);
    });

    testWidgets('should handle error and show snackbar', (tester) async {
      mockLikeService.shouldFail = true;

      await tester.pumpWidget(
        createTestWidget(
          const LikeButton(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.tap(find.byType(LikeButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to'), findsOneWidget);
    });
  });
}


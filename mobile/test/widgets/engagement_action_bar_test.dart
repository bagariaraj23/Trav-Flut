import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/ui/widgets/engagement_action_bar.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/like_service.dart';

class MockLikeService extends LikeService {
  @override
  Future<void> toggleLike(String entityType, String entityId) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late EngagementProvider engagementProvider;
  late MockLikeService mockLikeService;
  bool commentTapped = false;
  bool shareTapped = false;

  setUp(() {
    mockLikeService = MockLikeService();
    engagementProvider = EngagementProvider(likeService: mockLikeService);
    commentTapped = false;
    shareTapped = false;
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

  group('EngagementActionBar Widget', () {
    testWidgets('should display all action buttons', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          EngagementActionBar(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            likeCount: 10,
            commentCount: 5,
            shareCount: 2,
            onCommentTap: () => commentTapped = true,
            onShareTap: () => shareTapped = true,
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('should call onCommentTap when comment button is tapped', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          EngagementActionBar(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            onCommentTap: () => commentTapped = true,
            onShareTap: () => shareTapped = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.comment_outlined));
      await tester.pump();

      expect(commentTapped, true);
    });

    testWidgets('should call onShareTap when share button is tapped', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          EngagementActionBar(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            onCommentTap: () => commentTapped = true,
            onShareTap: () => shareTapped = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pump();

      expect(shareTapped, true);
    });

    testWidgets('should update counts from provider', (tester) async {
      engagementProvider.setLikeCount('entity1', 20);

      await tester.pumpWidget(
        createTestWidget(
          EngagementActionBar(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            likeCount: 10,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should use provider count if available
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('should not display count when count is zero', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          EngagementActionBar(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            likeCount: 0,
            commentCount: 0,
            shareCount: 0,
          ),
        ),
      );

      // Should not find count text
      expect(find.text('0'), findsNothing);
    });
  });
}


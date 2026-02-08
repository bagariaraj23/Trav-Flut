import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/screens/engagement/liked_by_screen.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/models/user.dart';

class MockLikeService extends LikeService {
  @override
  Future<List<User>> getLikeUsers(
    String entityType,
    String entityId,
    int page,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [
      User(
        id: 'user1',
        email: 'user1@test.com',
        name: 'User One',
        username: 'user1',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      User(
        id: 'user2',
        email: 'user2@test.com',
        name: 'User Two',
        username: 'user2',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
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

  group('LikedByScreen Widget', () {
    testWidgets('should display app bar with title', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikedByScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.text('Liked by'), findsOneWidget);
    });

    testWidgets('should show loading indicator initially', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikedByScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('should display list of users who liked', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikedByScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('User One'), findsOneWidget);
      expect(find.text('User Two'), findsOneWidget);
      expect(find.text('@user1'), findsOneWidget);
      expect(find.text('@user2'), findsOneWidget);
    });

    testWidgets('should show empty state when no likes', (tester) async {
      final emptyProvider = EngagementProvider(likeService: MockLikeService());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<EngagementProvider>.value(
              value: emptyProvider,
              child: const LikedByScreen(
                entityType: 'TRIP_FINAL_POST',
                entityId: 'entity1',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No likes yet'), findsOneWidget);
    });

    testWidgets('should display follow button for each user', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikedByScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Follow'), findsNWidgets(2));
    });

    testWidgets('should support pull to refresh', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const LikedByScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the list and perform pull to refresh
      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      // Simulate pull to refresh
      await tester.drag(listFinder, const Offset(0, 300));
      await tester.pumpAndSettle();
    });
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/models/user.dart';

class MockLikeService extends LikeService {
  bool shouldFail = false;
  String? failError;

  @override
  Future<void> toggleLike(String entityType, String entityId) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Like failed');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<List<User>> getLikeUsers(
    String entityType,
    String entityId,
    int page,
  ) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to get like users');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return [
      User(
        id: 'user1',
        email: 'user1@test.com',
        name: 'User One',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      User(
        id: 'user2',
        email: 'user2@test.com',
        name: 'User Two',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<Map<String, bool>> checkLikeStatus(
    List<String> entityIds,
    String entityType,
  ) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to check like status');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return {
      for (final id in entityIds) id: id == 'entity1',
    };
  }
}

void main() {
  late EngagementProvider provider;
  late MockLikeService mockLikeService;

  setUp(() {
    mockLikeService = MockLikeService();
    provider = EngagementProvider(likeService: mockLikeService);
  });

  group('EngagementProvider', () {
    test('initial state - should have empty like status and counts', () {
      expect(provider.isLiked('entity1'), false);
      expect(provider.getLikeCount('entity1'), 0);
      expect(provider.likeStatus, isEmpty);
      expect(provider.likeCounts, isEmpty);
    });

    test('toggleLike - should optimistically update like status', () async {
      expect(provider.isLiked('entity1'), false);
      expect(provider.getLikeCount('entity1'), 0);

      final toggleFuture = provider.toggleLike('TRIP_FINAL_POST', 'entity1');

      // Optimistic update should happen immediately
      expect(provider.isLiked('entity1'), true);
      expect(provider.getLikeCount('entity1'), 1);

      await toggleFuture;

      // State should remain after successful API call
      expect(provider.isLiked('entity1'), true);
      expect(provider.getLikeCount('entity1'), 1);
    });

    test('toggleLike - should rollback on API failure', () async {
      mockLikeService.shouldFail = true;
      mockLikeService.failError = 'Network error';

      expect(provider.isLiked('entity1'), false);
      expect(provider.getLikeCount('entity1'), 0);

      try {
        await provider.toggleLike('TRIP_FINAL_POST', 'entity1');
        fail('Should have thrown an exception');
      } catch (e) {
        // Rollback should have occurred
        expect(provider.isLiked('entity1'), false);
        expect(provider.getLikeCount('entity1'), 0);
        expect(provider.error, isNotNull);
      }
    });

    test('toggleLike - should prevent duplicate toggles', () async {
      final toggle1 = provider.toggleLike('TRIP_FINAL_POST', 'entity1');
      final toggle2 = provider.toggleLike('TRIP_FINAL_POST', 'entity1');

      await Future.wait([toggle1, toggle2]);

      // Should only be toggled once
      expect(provider.isLiked('entity1'), true);
      expect(provider.getLikeCount('entity1'), 1);
    });

    test('setLikeStatus - should update like status and count', () {
      provider.setLikeStatus('entity1', true, count: 5);

      expect(provider.isLiked('entity1'), true);
      expect(provider.getLikeCount('entity1'), 5);
    });

    test('setLikeCount - should update count only', () {
      provider.setLikeCount('entity1', 10);

      expect(provider.getLikeCount('entity1'), 10);
      expect(provider.isLiked('entity1'), false);
    });

    test('getLikeUsers - should fetch and cache like users', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      expect(provider.getLikeUsersList(entityKey), isEmpty);
      expect(provider.isLoadingUsers(entityKey), false);

      await provider.getLikeUsers('TRIP_FINAL_POST', 'entity1', 1);

      expect(provider.isLoadingUsers(entityKey), false);
      expect(provider.getLikeUsersList(entityKey), isNotEmpty);
      expect(provider.getLikeUsersList(entityKey).length, 2);
    });

    test('getLikeUsers - should handle pagination', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      await provider.getLikeUsers('TRIP_FINAL_POST', 'entity1', 1);
      final page1Users = provider.getLikeUsersList(entityKey);

      await provider.getLikeUsers('TRIP_FINAL_POST', 'entity1', 2);
      final page2Users = provider.getLikeUsersList(entityKey);

      expect(page2Users.length, greaterThan(page1Users.length));
    });

    test('checkLikeStatus - should update status for multiple entities', () async {
      provider.checkLikeStatus(
        ['entity1', 'entity2', 'entity3'],
        'TRIP_FINAL_POST',
      );

      // Wait for async update
      await Future.delayed(const Duration(milliseconds: 150));

      expect(provider.isLiked('entity1'), true);
      expect(provider.isLiked('entity2'), false);
      expect(provider.isLiked('entity3'), false);
    });
  });
}


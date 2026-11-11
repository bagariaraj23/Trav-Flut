import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/comment_user.dart';
import 'package:tripthread/models/api_response.dart';

class MockCommentService extends CommentService {
  bool shouldFail = false;
  String? failError;
  int createCallCount = 0;
  int updateCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<Comment> createComment(
    String entityType,
    String entityId,
    String text,
    String? parentId,
  ) async {
    createCallCount++;
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to create comment');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return Comment(
      id: 'comment-$createCallCount',
      userId: 'user1',
      entityType: entityType,
      entityId: entityId,
      contentText: text,
      parentCommentId: parentId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: CommentUser(id: 'user1', username: 'user1', name: 'User One'),
      replyCount: 0,
    );
  }

  @override
  Future<PaginatedResponse<Comment>> getComments(
    String entityType,
    String entityId,
    int page,
  ) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to get comments');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return PaginatedResponse(
      data: [
        Comment(
          id: 'comment1',
          userId: 'user1',
          entityType: entityType,
          entityId: entityId,
          contentText: 'Test comment',
          parentCommentId: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: CommentUser(id: 'user1', username: 'user1', name: 'User One'),
          replyCount: 0,
        ),
      ],
      pagination: PaginationInfo(
        page: page,
        limit: 20,
        total: 1,
        totalPages: 1,
      ),
    );
  }

  @override
  Future<Comment> updateComment(String commentId, String newText) async {
    updateCallCount++;
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to update comment');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return Comment(
      id: commentId,
      userId: 'user1',
      entityType: 'TRIP_FINAL_POST',
      entityId: 'entity1',
      contentText: newText,
      parentCommentId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: CommentUser(id: 'user1', username: 'user1', name: 'User One'),
      replyCount: 0,
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCallCount++;
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to delete comment');
    }
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<PaginatedResponse<Comment>> getReplies(
    String commentId,
    int page,
  ) async {
    if (shouldFail) {
      throw Exception(failError ?? 'Failed to get replies');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return PaginatedResponse(
      data: [
        Comment(
          id: 'reply1',
          userId: 'user2',
          entityType: 'TRIP_FINAL_POST',
          entityId: 'entity1',
          contentText: 'Test reply',
          parentCommentId: commentId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: CommentUser(id: 'user2', username: 'user2', name: 'User Two'),
          replyCount: 0,
        ),
      ],
      pagination: PaginationInfo(
        page: page,
        limit: 20,
        total: 1,
        totalPages: 1,
      ),
    );
  }
}

void main() {
  late CommentProvider provider;
  late MockCommentService mockCommentService;

  setUp(() {
    mockCommentService = MockCommentService();
    provider = CommentProvider(commentService: mockCommentService);
  });

  group('CommentProvider', () {
    test('initial state - should have empty comments', () {
      final entityKey = 'TRIP_FINAL_POST:entity1';
      expect(provider.getCommentsList(entityKey), isEmpty);
      expect(provider.isLoading(entityKey), false);
      expect(provider.hasMore(entityKey), false);
    });

    test('getComments - should fetch and cache comments', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      expect(provider.getCommentsList(entityKey), isEmpty);

      await provider.getComments('TRIP_FINAL_POST', 'entity1');

      final comments = provider.getCommentsList(entityKey);
      expect(comments, isNotEmpty);
      expect(comments.length, 1);
      expect(comments[0].contentText, 'Test comment');
    });

    test('getComments - should handle pagination', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      await provider.getComments('TRIP_FINAL_POST', 'entity1');
      expect(provider.hasMore(entityKey), false);

      // Simulate multiple pages
      mockCommentService.shouldFail = false;
      await provider.getComments('TRIP_FINAL_POST', 'entity1');
    });

    test('createComment - should optimistically insert comment', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';

      expect(provider.getCommentsList(entityKey), isEmpty);
      expect(provider.isCreating(entityKey), false);

      final createFuture = provider.createComment(
        'TRIP_FINAL_POST',
        'entity1',
        'New comment',
        null,
        currentUserId: 'user1',
        currentUserPreview:
            const CommentUser(id: 'user1', username: 'user1', name: 'User One'),
      );

      // Optimistic update should happen immediately
      expect(provider.isCreating(entityKey), true);
      final optimisticComments = provider.getCommentsList(entityKey);
      expect(optimisticComments, isNotEmpty);

      await createFuture;

      expect(provider.isCreating(entityKey), false);
      final finalComments = provider.getCommentsList(entityKey);
      expect(finalComments.length, 1);
      expect(finalComments[0].contentText, 'New comment');
    });

    test('createComment - should rollback on API failure', () async {
      mockCommentService.shouldFail = true;
      mockCommentService.failError = 'Network error';

      final entityKey = 'TRIP_FINAL_POST:entity1';

      try {
        await provider.createComment(
          'TRIP_FINAL_POST',
          'entity1',
          'Failed comment',
          null,
          currentUserId: 'user1',
          currentUserPreview:
              const CommentUser(id: 'user1', username: 'user1', name: 'User One'),
        );
        fail('Should have thrown an exception');
      } catch (e) {
        // Rollback should have occurred
        expect(provider.getCommentsList(entityKey), isEmpty);
        expect(provider.error, isNotNull);
      }
    });

    test('updateComment - should optimistically update comment', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';
      await provider.getComments('TRIP_FINAL_POST', 'entity1');
      final originalComment = provider.getCommentsList(entityKey)[0];

      expect(provider.isUpdating(originalComment.id), false);

      final updateFuture = provider.updateComment(
        originalComment.id,
        'Updated text',
      );

      expect(provider.isUpdating(originalComment.id), true);

      await updateFuture;

      expect(provider.isUpdating(originalComment.id), false);
      final updatedComment = provider.getCommentsList(entityKey)[0];
      expect(updatedComment.contentText, 'Updated text');
    });

    test('deleteComment - should optimistically remove comment', () async {
      final entityKey = 'TRIP_FINAL_POST:entity1';
      await provider.getComments('TRIP_FINAL_POST', 'entity1');
      final comment = provider.getCommentsList(entityKey)[0];

      expect(provider.isDeleting(comment.id), false);

      final deleteFuture = provider.deleteComment(comment.id);

      expect(provider.isDeleting(comment.id), true);

      await deleteFuture;

      expect(provider.isDeleting(comment.id), false);
      expect(provider.getCommentsList(entityKey), isEmpty);
    });

    test('getReplies - should fetch and cache replies', () async {
      expect(provider.getRepliesList('comment1'), isEmpty);

      await provider.getReplies('comment1');

      final replies = provider.getRepliesList('comment1');
      expect(replies, isNotEmpty);
      expect(replies.length, 1);
      expect(replies[0].parentCommentId, 'comment1');
    });

    test('getReplies - should handle pagination', () async {
      await provider.getReplies('comment1');
      final page1Replies = provider.getRepliesList('comment1');

      await provider.getReplies('comment1');
      final page2Replies = provider.getRepliesList('comment1');

      expect(page2Replies.length, greaterThanOrEqualTo(page1Replies.length));
    });
  });
}

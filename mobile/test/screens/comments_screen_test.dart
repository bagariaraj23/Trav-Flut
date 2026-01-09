import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/ui/screens/comments_screen.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/api_response.dart';

class MockCommentService extends CommentService {
  @override
  Future<PaginatedResponse<Comment>> getComments(
    String entityType,
    String entityId,
    int page,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return PaginatedResponse(
      data: [
        Comment(
          id: 'comment1',
          userId: 'user1',
          entityType: entityType,
          entityId: entityId,
          contentText: 'Test comment 1',
          parentCommentId: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: User(
            id: 'user1',
            email: 'user1@test.com',
            name: 'User One',
            isPrivate: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
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
  Future<Comment> createComment(
    String entityType,
    String entityId,
    String text,
    String? parentId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return Comment(
      id: 'new-comment',
      userId: 'user1',
      entityType: entityType,
      entityId: entityId,
      contentText: text,
      parentCommentId: parentId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: User(
        id: 'user1',
        email: 'user1@test.com',
        name: 'User One',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      replyCount: 0,
    );
  }

  @override
  Future<PaginatedResponse<Comment>> getReplies(
    String commentId,
    int page,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return PaginatedResponse(
      data: [
        Comment(
          id: 'reply1',
          userId: 'user2',
          entityType: 'TRIP_FINAL_POST',
          entityId: 'entity1',
          contentText: 'Reply 1',
          parentCommentId: commentId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: User(
            id: 'user2',
            email: 'user2@test.com',
            name: 'User Two',
            isPrivate: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
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
  late CommentProvider commentProvider;
  late MockCommentService mockCommentService;

  setUp(() {
    mockCommentService = MockCommentService();
    commentProvider = CommentProvider(commentService: mockCommentService);
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<CommentProvider>.value(
          value: commentProvider,
          child: child,
        ),
      ),
    );
  }

  group('CommentsScreen Widget', () {
    testWidgets('should display app bar with title', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.text('Comments'), findsOneWidget);
    });

    testWidgets('should show loading indicator initially', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('should display comments list', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test comment 1'), findsOneWidget);
      expect(find.text('User One'), findsOneWidget);
    });

    testWidgets('should show empty state when no comments', (tester) async {
      final emptyProvider = CommentProvider(commentService: MockCommentService());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<CommentProvider>.value(
              value: emptyProvider,
              child: const CommentsScreen(
                entityType: 'TRIP_FINAL_POST',
                entityId: 'entity1',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No comments yet'), findsOneWidget);
      expect(find.text('Be the first to comment!'), findsOneWidget);
    });

    testWidgets('should display comment composer at bottom', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should support pull to refresh', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      await tester.drag(listFinder, const Offset(0, 300));
      await tester.pumpAndSettle();
    });

    testWidgets('should scroll to specific comment when scrollToCommentId is provided', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            scrollToCommentId: 'comment1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Comment should be visible
      expect(find.text('Test comment 1'), findsOneWidget);
    });
  });
}


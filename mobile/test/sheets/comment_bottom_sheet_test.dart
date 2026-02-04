import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/widgets/sheets/comment_bottom_sheet.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/comment_user.dart';
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
          user: CommentUser(id: 'user1', username: 'user1', name: 'User One'),
          replyCount: 0,
        ),
        Comment(
          id: 'comment2',
          userId: 'user2',
          entityType: entityType,
          entityId: entityId,
          contentText: 'Test comment 2',
          parentCommentId: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: CommentUser(id: 'user2', username: 'user2', name: 'User Two'),
          replyCount: 2,
        ),
      ],
      pagination: PaginationInfo(
        page: page,
        limit: 20,
        total: 2,
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
      user: CommentUser(id: 'user1', username: 'user1', name: 'User One'),
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
          userId: 'user3',
          entityType: 'TRIP_FINAL_POST',
          entityId: 'entity1',
          contentText: 'Reply 1',
          parentCommentId: commentId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          user: CommentUser(id: 'user3', username: 'user3', name: 'User Three'),
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

  group('CommentBottomSheet Widget', () {
    testWidgets('should display comments list', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Test comment 1'), findsOneWidget);
      expect(find.text('Test comment 2'), findsOneWidget);
    });

    testWidgets('should show empty state when no comments', (tester) async {
      // Override to return empty list
      final emptyProvider = CommentProvider(
        commentService: MockCommentService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<CommentProvider>.value(
              value: emptyProvider,
              child: const CommentBottomSheet(
                entityType: 'TRIP_FINAL_POST',
                entityId: 'entity1',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No comments yet'), findsOneWidget);
    });

    testWidgets('should show loading indicator initially', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('should display comment composer at bottom', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('should expand replies when view replies is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentBottomSheet(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find comment with replies
      expect(find.text('2 replies'), findsOneWidget);

      await tester.tap(find.text('2 replies'));
      await tester.pumpAndSettle();

      // Should show replies
      expect(find.text('Reply 1'), findsOneWidget);
    });

    testWidgets('should close on close button tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<CommentProvider>.value(
              value: commentProvider,
              child: Builder(
                builder: (context) {
                  return CommentBottomSheet(
                    entityType: 'TRIP_FINAL_POST',
                    entityId: 'entity1',
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Sheet should be dismissed
      expect(find.text('Comments'), findsNothing);
    });
  });
}

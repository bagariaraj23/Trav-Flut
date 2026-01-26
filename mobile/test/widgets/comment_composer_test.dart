import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/widgets/engagement/comment_composer.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/user.dart';

class MockCommentService extends CommentService {
  bool shouldFail = false;

  @override
  Future<Comment> createComment(
    String entityType,
    String entityId,
    String text,
    String? parentId,
  ) async {
    if (shouldFail) {
      throw Exception('Failed to create comment');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    return Comment(
      id: 'comment1',
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

  group('CommentComposer Widget', () {
    testWidgets('should display text input field', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Add a comment...'), findsOneWidget);
    });

    testWidgets('should show reply indicator when replying', (tester) async {
      final parentComment = Comment(
        id: 'parent1',
        userId: 'user2',
        entityType: 'TRIP_FINAL_POST',
        entityId: 'entity1',
        contentText: 'Parent comment',
        parentCommentId: null,
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
      );

      await tester.pumpWidget(
        createTestWidget(
          CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            parentCommentId: 'parent1',
            parentComment: parentComment,
          ),
        ),
      );

      expect(find.text('Replying to User Two'), findsOneWidget);
      expect(find.text('Write a reply...'), findsOneWidget);
    });

    testWidgets('should enable send button when text is entered', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      expect(find.byIcon(Icons.send), findsNothing);

      await tester.enterText(find.byType(TextField), 'Test comment');
      await tester.pump();

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('should show character counter when approaching limit', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'a' * 200);
      await tester.pump();

      expect(find.textContaining('200/250'), findsOneWidget);
    });

    testWidgets('should submit comment on send button tap', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          const CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test comment');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Text should be cleared after successful submission
      expect(find.text('Test comment'), findsNothing);
    });

    testWidgets('should handle cancel reply', (tester) async {
      bool cancelCalled = false;

      final parentComment = Comment(
        id: 'parent1',
        userId: 'user2',
        entityType: 'TRIP_FINAL_POST',
        entityId: 'entity1',
        contentText: 'Parent comment',
        parentCommentId: null,
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
      );

      await tester.pumpWidget(
        createTestWidget(
          CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
            parentCommentId: 'parent1',
            parentComment: parentComment,
            onCancel: () => cancelCalled = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(cancelCalled, true);
    });

    testWidgets('should show error snackbar on failure', (tester) async {
      mockCommentService.shouldFail = true;

      await tester.pumpWidget(
        createTestWidget(
          const CommentComposer(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test comment');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to post comment'), findsOneWidget);
    });
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/widgets/engagement/comment_list_item.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/comment_user.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/storage_service.dart';

class MockCommentService extends CommentService {
  @override
  Future<void> deleteComment(String commentId) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<Comment> updateComment(String commentId, String newText) async {
    await Future.delayed(const Duration(milliseconds: 50));
    return Comment(
      id: commentId,
      userId: 'user1',
      entityType: 'TRIP_FINAL_POST',
      entityId: 'entity1',
      contentText: newText,
      parentCommentId: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: const CommentUser(
        id: 'user1',
        username: 'userone',
        name: 'User One',
      ),
      replyCount: 0,
    );
  }
}

class MockAuthProvider extends AuthProvider {
  MockAuthProvider()
    : super(apiService: ApiService(), storageService: StorageService());

  User? _currentUser;

  @override
  User? get currentUser => _currentUser;

  void setUser(User user) {
    _currentUser = user;
    notifyListeners();
  }
}

void main() {
  late CommentProvider commentProvider;
  late MockCommentService mockCommentService;
  late MockAuthProvider mockAuthProvider;

  setUp(() {
    mockCommentService = MockCommentService();
    commentProvider = CommentProvider(commentService: mockCommentService);
    mockAuthProvider = MockAuthProvider();
    mockAuthProvider.setUser(
      User(
        id: 'user1',
        email: 'user1@test.com',
        name: 'User One',
        isPrivate: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<CommentProvider>.value(
              value: commentProvider,
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
          ],
          child: child,
        ),
      ),
    );
  }

  Comment createTestComment({
    String? id,
    String? userId,
    String? contentText,
    String? parentCommentId,
    int? replyCount,
  }) {
    return Comment(
      id: id ?? 'comment1',
      userId: userId ?? 'user1',
      entityType: 'TRIP_FINAL_POST',
      entityId: 'entity1',
      contentText: contentText ?? 'Test comment',
      parentCommentId: parentCommentId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: CommentUser(
        id: userId ?? 'user1',
        username: userId ?? 'userone',
        name: 'User ${userId ?? 'One'}',
      ),
      replyCount: replyCount ?? 0,
    );
  }

  group('CommentListItem Widget', () {
    testWidgets('should display comment with user info', (tester) async {
      final comment = createTestComment();

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      expect(find.text('User One'), findsOneWidget);
      expect(find.text('Test comment'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('should show reply button for top-level comments', (
      tester,
    ) async {
      final comment = createTestComment(parentCommentId: null);

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('should show view replies button when replies exist', (
      tester,
    ) async {
      final comment = createTestComment(replyCount: 5);

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      expect(find.text('5 replies'), findsOneWidget);
    });

    testWidgets('should show edit/delete menu for own comments', (
      tester,
    ) async {
      final comment = createTestComment(userId: 'user1');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('should not show menu for other users comments', (
      tester,
    ) async {
      final comment = createTestComment(userId: 'user2');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('should expand long comments on tap', (tester) async {
      final longComment = createTestComment(contentText: 'a' * 200);

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: longComment)),
      );

      expect(find.textContaining('...'), findsOneWidget);

      await tester.tap(find.textContaining('...'));
      await tester.pump();

      expect(find.textContaining('...'), findsNothing);
    });

    testWidgets('should indent reply comments', (tester) async {
      final reply = createTestComment(parentCommentId: 'parent1');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: reply, isReply: true)),
      );

      // Reply should have left margin
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Test comment'),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(container.margin, isA<EdgeInsets>());
    });

    testWidgets('should handle delete confirmation', (tester) async {
      final comment = createTestComment(userId: 'user1');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Comment'), findsOneWidget);
      expect(find.text('Are you sure'), findsOneWidget);
    });
  });
}

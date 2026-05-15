import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/widgets/engagement/comment_list_item.dart';
import 'package:tripthread/widgets/mention_text.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/comment_user.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/services/like_service.dart';

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

/// A minimal mock that implements AuthProvider's interface without calling
/// the real constructor (which requires ApiService/StorageService and triggers
/// network initialization).
class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  User? _mockUser;

  @override
  User? get currentUser => _mockUser;

  void setUser(User user) {
    _mockUser = user;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => _mockUser != null;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  bool get shouldShowError => false;

  @override
  ChangeNotifier get uiNotifier => ChangeNotifier();

  @override
  ChangeNotifier get routingNotifier => ChangeNotifier();

  @override
  Future<bool> signup({
    required String email,
    required String password,
    required String name,
    String? username,
  }) async => false;

  @override
  Future<bool> login({required String email, required String password}) async =>
      false;

  @override
  Future<void> logout({bool logoutAll = false}) async {}

  @override
  Future<bool> deleteAccount() async => false;

  @override
  Future<bool> forgotPassword({required String email}) async => false;

  @override
  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async => false;

  @override
  void clearError() {}

  @override
  void markErrorAsShown() {}

  @override
  void updateUser(User user) {
    _mockUser = user;
    notifyListeners();
  }

  @override
  Future<void> forceLogout({String? message}) async {}

  // Catch-all for any dynamic calls
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockLikeService extends LikeService {
  @override
  Future<void> toggleLike(String entityType, String entityId) async {
    await Future.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<Map<String, bool>> checkLikeStatus(
    List<String> entityIds,
    String entityType,
  ) async {
    return {};
  }
}

void main() {
  late CommentProvider commentProvider;
  late MockCommentService mockCommentService;
  late MockAuthProvider mockAuthProvider;
  late EngagementProvider engagementProvider;
  late MockLikeService mockLikeService;

  setUp(() {
    mockCommentService = MockCommentService();
    commentProvider = CommentProvider(commentService: mockCommentService);
    mockLikeService = MockLikeService();
    engagementProvider = EngagementProvider(likeService: mockLikeService);
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
            ChangeNotifierProvider<EngagementProvider>.value(
              value: engagementProvider,
            ),
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
    DateTime? createdAt,
  }) {
    return Comment(
      id: id ?? 'comment1',
      userId: userId ?? 'user1',
      entityType: 'TRIP_FINAL_POST',
      entityId: 'entity1',
      contentText: contentText ?? 'Test comment',
      parentCommentId: parentCommentId,
      createdAt: createdAt ?? DateTime.now(),
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

      await tester.pumpAndSettle();

      expect(find.text('User One'), findsOneWidget);
      final mention = find.byType(MentionText);
      expect(mention, findsOneWidget);
      expect(tester.widget<MentionText>(mention).text, 'Test comment');
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('should show reply button when onReplyTap is set', (
      tester,
    ) async {
      final comment = createTestComment(parentCommentId: null);

      await tester.pumpWidget(
        createTestWidget(
          CommentListItem(comment: comment, onReplyTap: () {}),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
    });

    testWidgets('should show view replies button when replies exist', (
      tester,
    ) async {
      final comment = createTestComment(replyCount: 5);

      await tester.pumpWidget(
        createTestWidget(
          CommentListItem(comment: comment, onViewReplies: () {}),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('View 5 replies'), findsOneWidget);
    });

    testWidgets(
      'should show edit and delete buttons for own comments within 15 minutes',
      (tester) async {
        // Create a recent comment (within 15 minutes)
        final comment = createTestComment(
          userId: 'user1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        await tester.pumpWidget(
          createTestWidget(CommentListItem(comment: comment)),
        );

        await tester.pumpAndSettle();

        // Should show both Edit and Delete buttons
        expect(find.text('Edit'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets('should hide edit and delete after 15 minutes', (
      tester,
    ) async {
      // Create an old comment (older than 15 minutes)
      final comment = createTestComment(
        userId: 'user1',
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      );

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('should not show edit/delete for other users comments', (
      tester,
    ) async {
      final comment = createTestComment(userId: 'user2');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('should expand long comments on tap', (tester) async {
      final longComment = createTestComment(contentText: 'a' * 200);

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: longComment)),
      );

      await tester.pumpAndSettle();

      final mention = find.byType(MentionText);
      expect(mention, findsOneWidget);
      final truncated = tester.widget<MentionText>(mention).text;
      expect(truncated.endsWith('...'), isTrue);
      expect(truncated.length, 153);

      final tapTarget = find.ancestor(
        of: mention,
        matching: find.byType(GestureDetector),
      );
      await tester.tap(tapTarget.first);
      await tester.pumpAndSettle();

      expect(tester.widget<MentionText>(mention).text.length, 200);
      expect(tester.widget<MentionText>(mention).text.contains('...'), isFalse);
    });

    testWidgets('should indent reply comments', (tester) async {
      final reply = createTestComment(parentCommentId: 'parent1');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: reply, isReply: true)),
      );

      await tester.pumpAndSettle();

      // Reply should have left margin - check for Dismissible wrapping Container
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(Dismissible),
          matching: find.byType(Container),
        ),
      );

      // The inner container should have left margin for replies
      expect(containers.any((c) => c.margin is EdgeInsets), isTrue);
    });

    testWidgets('should handle delete confirmation via button', (tester) async {
      final comment = createTestComment(userId: 'user1');

      await tester.pumpWidget(
        createTestWidget(CommentListItem(comment: comment)),
      );

      await tester.pumpAndSettle();

      // Tap the Delete button directly
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Should show confirmation dialog
      expect(find.text('Delete Comment'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this comment?'),
        findsOneWidget,
      );
    });

    testWidgets(
      'should support swipe-to-delete for own comments within 15 minutes',
      (tester) async {
        final comment = createTestComment(
          userId: 'user1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        );

        await tester.pumpWidget(
          createTestWidget(CommentListItem(comment: comment)),
        );

        await tester.pumpAndSettle();

        expect(find.byType(Dismissible), findsOneWidget);

        await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
        await tester.pumpAndSettle();

        expect(find.text('Delete Comment'), findsOneWidget);
      },
    );
  });
}

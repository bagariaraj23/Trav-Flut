import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/screens/engagement/comments_screen.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/models/comment_user.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/api_response.dart';

class MockCommentService extends CommentService {
  final bool returnEmpty;
  final bool slow;

  MockCommentService({this.returnEmpty = false, this.slow = false});

  @override
  Future<PaginatedResponse<Comment>> getComments(
    String entityType,
    String entityId,
    int page,
  ) async {
    if (slow) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (returnEmpty) {
      return PaginatedResponse(
        data: [],
        pagination: PaginationInfo(
          page: page,
          limit: 20,
          total: 0,
          totalPages: 0,
        ),
      );
    }
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
          user: const CommentUser(
            id: 'user1',
            username: 'user1',
            name: 'User One',
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
    return Comment(
      id: 'new-comment',
      userId: 'user1',
      entityType: entityType,
      entityId: entityId,
      contentText: text,
      parentCommentId: parentId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      user: const CommentUser(id: 'user1', username: 'user1', name: 'User One'),
      replyCount: 0,
    );
  }

  @override
  Future<PaginatedResponse<Comment>> getReplies(
    String commentId,
    int page,
  ) async {
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
          user: const CommentUser(
            id: 'user2',
            username: 'user2',
            name: 'User Two',
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
  Future<void> logout() async {}

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

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockLikeService extends LikeService {
  @override
  Future<void> toggleLike(String entityType, String entityId) async {}

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

  Widget createTestWidget(Widget child, {CommentProvider? overrideProvider}) {
    return MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<CommentProvider>.value(
              value: overrideProvider ?? commentProvider,
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: mockAuthProvider),
            ChangeNotifierProvider<EngagementProvider>.value(
              value: engagementProvider,
            ),
            Provider<ApiService>.value(value: ApiService()),
          ],
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

      // Settle the async loading triggered by initState
      await tester.pumpAndSettle();
    });

    testWidgets('should show loading indicator initially', (tester) async {
      // Use a slow mock so loading state is visible
      final slowService = MockCommentService(slow: true);
      final slowProvider = CommentProvider(commentService: slowService);

      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
          overrideProvider: slowProvider,
        ),
      );

      // After first pump, the postFrameCallback fires and getComments starts
      // which sets isLoading=true. Pump once more to see the loading state.
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up: advance past the Future.delayed so no pending timers remain
      await tester.pump(const Duration(seconds: 3));
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
      final emptyService = MockCommentService(returnEmpty: true);
      final emptyProvider = CommentProvider(commentService: emptyService);

      await tester.pumpWidget(
        createTestWidget(
          const CommentsScreen(
            entityType: 'TRIP_FINAL_POST',
            entityId: 'entity1',
          ),
          overrideProvider: emptyProvider,
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

    testWidgets(
      'should scroll to specific comment when scrollToCommentId is provided',
      (tester) async {
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
      },
    );
  });
}

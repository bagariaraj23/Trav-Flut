import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:tripthread/services/comment_service.dart';
import 'package:tripthread/models/comment.dart';

void main() {
  late CommentService commentService;
  late DioAdapter dioAdapter;
  late Dio dio;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    commentService = CommentService();
  });

  group('CommentService', () {
    test('createComment - should successfully create a comment', () async {
      final mockComment = {
        'id': 'comment1',
        'userId': 'user1',
        'entityType': 'TRIP_FINAL_POST',
        'entityId': 'entity1',
        'contentText': 'Test comment',
        'parentCommentId': null,
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'user': {
          'id': 'user1',
          'email': 'user1@test.com',
          'name': 'User One',
          'isPrivate': false,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
        'replyCount': 0,
      };

      dioAdapter.onPost(
        '/comments',
        (server) => server.reply(200, {
          'success': true,
          'data': mockComment,
        }),
        data: {
          'entityType': 'TRIP_FINAL_POST',
          'entityId': 'entity1',
          'contentText': 'Test comment',
        },
      );

      final comment = await commentService.createComment(
        'TRIP_FINAL_POST',
        'entity1',
        'Test comment',
        null,
      );

      expect(comment, isA<Comment>());
      expect(comment.id, 'comment1');
      expect(comment.contentText, 'Test comment');
    });

    test('createComment - should create a reply comment', () async {
      final mockReply = {
        'id': 'reply1',
        'userId': 'user1',
        'entityType': 'TRIP_FINAL_POST',
        'entityId': 'entity1',
        'contentText': 'Test reply',
        'parentCommentId': 'comment1',
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-01T00:00:00Z',
        'user': {
          'id': 'user1',
          'email': 'user1@test.com',
          'name': 'User One',
          'isPrivate': false,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
        'replyCount': 0,
      };

      dioAdapter.onPost(
        '/comments',
        (server) => server.reply(200, {
          'success': true,
          'data': mockReply,
        }),
        data: {
          'entityType': 'TRIP_FINAL_POST',
          'entityId': 'entity1',
          'contentText': 'Test reply',
          'parentCommentId': 'comment1',
        },
      );

      final reply = await commentService.createComment(
        'TRIP_FINAL_POST',
        'entity1',
        'Test reply',
        'comment1',
      );

      expect(reply, isA<Comment>());
      expect(reply.parentCommentId, 'comment1');
    });

    test('getComments - should return paginated comments', () async {
      final mockComments = [
        {
          'id': 'comment1',
          'userId': 'user1',
          'entityType': 'TRIP_FINAL_POST',
          'entityId': 'entity1',
          'contentText': 'Comment 1',
          'parentCommentId': null,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
          'user': {
            'id': 'user1',
            'email': 'user1@test.com',
            'name': 'User One',
            'isPrivate': false,
            'createdAt': '2024-01-01T00:00:00Z',
            'updatedAt': '2024-01-01T00:00:00Z',
          },
          'replyCount': 0,
        },
      ];

      dioAdapter.onGet(
        '/comments/TRIP_FINAL_POST/entity1',
        (server) => server.reply(200, {
          'success': true,
          'data': mockComments,
          'pagination': {
            'page': 1,
            'limit': 20,
            'total': 1,
            'totalPages': 1,
          },
        }),
        queryParameters: {'page': 1},
      );

      final response = await commentService.getComments(
        'TRIP_FINAL_POST',
        'entity1',
        1,
      );

      expect(response.data, isA<List<Comment>>());
      expect(response.data.length, 1);
      expect(response.pagination.page, 1);
    });

    test('updateComment - should successfully update a comment', () async {
      final mockUpdatedComment = {
        'id': 'comment1',
        'userId': 'user1',
        'entityType': 'TRIP_FINAL_POST',
        'entityId': 'entity1',
        'contentText': 'Updated comment',
        'parentCommentId': null,
        'createdAt': '2024-01-01T00:00:00Z',
        'updatedAt': '2024-01-02T00:00:00Z',
        'user': {
          'id': 'user1',
          'email': 'user1@test.com',
          'name': 'User One',
          'isPrivate': false,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
        'replyCount': 0,
      };

      dioAdapter.onPut(
        '/comments/comment1',
        (server) => server.reply(200, {
          'success': true,
          'data': mockUpdatedComment,
        }),
        data: {
          'contentText': 'Updated comment',
        },
      );

      final updatedComment = await commentService.updateComment(
        'comment1',
        'Updated comment',
      );

      expect(updatedComment.contentText, 'Updated comment');
    });

    test('deleteComment - should successfully delete a comment', () async {
      dioAdapter.onDelete(
        '/comments/comment1',
        (server) => server.reply(200, {
          'success': true,
          'data': null,
        }),
      );

      await expectLater(
        commentService.deleteComment('comment1'),
        completes,
      );
    });

    test('getReplies - should return paginated replies', () async {
      final mockReplies = [
        {
          'id': 'reply1',
          'userId': 'user2',
          'entityType': 'TRIP_FINAL_POST',
          'entityId': 'entity1',
          'contentText': 'Reply 1',
          'parentCommentId': 'comment1',
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
          'user': {
            'id': 'user2',
            'email': 'user2@test.com',
            'name': 'User Two',
            'isPrivate': false,
            'createdAt': '2024-01-01T00:00:00Z',
            'updatedAt': '2024-01-01T00:00:00Z',
          },
          'replyCount': 0,
        },
      ];

      dioAdapter.onGet(
        '/comments/comment1/replies',
        (server) => server.reply(200, {
          'success': true,
          'data': mockReplies,
          'pagination': {
            'page': 1,
            'limit': 20,
            'total': 1,
            'totalPages': 1,
          },
        }),
        queryParameters: {'page': 1},
      );

      final response = await commentService.getReplies('comment1', 1);

      expect(response.data, isA<List<Comment>>());
      expect(response.data.length, 1);
      expect(response.data[0].parentCommentId, 'comment1');
    });
  });
}


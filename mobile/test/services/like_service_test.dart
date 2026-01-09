import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/models/user.dart';

void main() {
  late LikeService likeService;
  late DioAdapter dioAdapter;
  late Dio dio;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    likeService = LikeService();
    // Use reflection or a test-friendly constructor to inject mock Dio
    // For now, we'll test with real Dio but mock the HTTP responses
  });

  group('LikeService', () {
    test('toggleLike - should successfully like an entity', () async {
      dioAdapter.onPost(
        '/likes',
        (server) => server.reply(200, {
          'success': true,
          'data': null,
        }),
        data: {
          'entityType': 'TRIP_FINAL_POST',
          'entityId': 'test-entity-id',
        },
      );

      await expectLater(
        likeService.toggleLike('TRIP_FINAL_POST', 'test-entity-id'),
        completes,
      );
    });

    test('toggleLike - should handle API error', () async {
      dioAdapter.onPost(
        '/likes',
        (server) => server.reply(400, {
          'success': false,
          'error': 'Invalid entity',
        }),
      );

      expect(
        () => likeService.toggleLike('TRIP_FINAL_POST', 'invalid-id'),
        throwsA(isA<Exception>()),
      );
    });

    test('getLikeUsers - should return paginated list of users', () async {
      final mockUsers = [
        {
          'id': 'user1',
          'email': 'user1@test.com',
          'name': 'User One',
          'isPrivate': false,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
        {
          'id': 'user2',
          'email': 'user2@test.com',
          'name': 'User Two',
          'isPrivate': false,
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-01T00:00:00Z',
        },
      ];

      dioAdapter.onGet(
        '/likes/TRIP_FINAL_POST/test-entity-id/users',
        (server) => server.reply(200, {
          'success': true,
          'data': mockUsers,
        }),
        queryParameters: {'page': 1},
      );

      final users = await likeService.getLikeUsers(
        'TRIP_FINAL_POST',
        'test-entity-id',
        1,
      );

      expect(users, isA<List<User>>());
      expect(users.length, 2);
      expect(users[0].id, 'user1');
      expect(users[1].id, 'user2');
    });

    test('checkLikeStatus - should return status map for multiple entities', () async {
      dioAdapter.onGet(
        '/likes/status',
        (server) => server.reply(200, {
          'success': true,
          'data': {
            'entity1': true,
            'entity2': false,
            'entity3': true,
          },
        }),
        queryParameters: {
          'entityType': 'TRIP_FINAL_POST',
          'entityIds': 'entity1,entity2,entity3',
        },
      );

      final statusMap = await likeService.checkLikeStatus(
        ['entity1', 'entity2', 'entity3'],
        'TRIP_FINAL_POST',
      );

      expect(statusMap, isA<Map<String, bool>>());
      expect(statusMap['entity1'], true);
      expect(statusMap['entity2'], false);
      expect(statusMap['entity3'], true);
    });

    test('checkLikeStatus - should handle empty entity list', () async {
      final statusMap = await likeService.checkLikeStatus(
        [],
        'TRIP_FINAL_POST',
      );

      expect(statusMap, isEmpty);
    });
  });
}


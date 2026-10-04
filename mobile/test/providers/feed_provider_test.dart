import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/services/api_service.dart';

Map<String, dynamic> _post(String id) => {
      'id': id,
      'tripId': 'trip-$id',
      'summaryText': 'Day $id',
      'curatedMedia': <String>[],
      'generationStatus': 'DRAFT',
      'isPublished': true,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'likeCount': 1,
      'commentCount': 0,
      'shareCount': 0,
      'hasLiked': false,
    };

Map<String, dynamic> _trip(String title) => {
      'id': 'trip-$title',
      'userId': 'user-1',
      'title': title,
      'startDate': '2026-01-01T00:00:00.000Z',
      'endDate': '2026-01-08T00:00:00.000Z',
      'status': 'ONGOING',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

class _HomeFeedApi extends ApiService {
  final List<String?> cursors = [];

  @override
  Future<ApiResponse<Map<String, dynamic>>> getHomeFeed({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) async {
    cursors.add(cursor);
    final firstPage = cursor == null || cursor.isEmpty;
    return ApiResponse(
      success: true,
      data: {
        'items': [_post(firstPage ? 'a' : 'b')],
        'hasNext': firstPage && cursors.length == 1,
        'nextCursor': firstPage && cursors.length == 1 ? 'cursor-b' : null,
      },
    );
  }
}

class _DiscoverApi extends ApiService {
  final List<String?> moods = [];
  final Map<String, Completer<void>> gates = {};

  @override
  Future<ApiResponse<Map<String, dynamic>>> getDiscoverTrips({
    int page = 1,
    int limit = 20,
    String? status,
    String? mood,
    bool includePrivate = false,
  }) async {
    final key = mood ?? '';
    moods.add(mood);
    gates.putIfAbsent(key, Completer<void>.new);
    await gates[key]!.future;
    return ApiResponse(
      success: true,
      data: {
        'items': [_trip(key.isEmpty ? 'all' : key)],
        'hasNext': false,
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('home feed sends the server cursor and drops it on reset', () async {
    final api = _HomeFeedApi();
    final provider = FeedProvider(apiService: api);

    await provider.loadHomeFeed(refresh: true);
    await provider.loadHomeFeed();

    expect(api.cursors, [null, 'cursor-b']);
    expect(provider.homeFeedPosts.map((post) => post.id), ['a', 'b']);

    provider.resetHomeFeed();
    await provider.loadHomeFeed();
    expect(api.cursors.last, isNull);
    expect(provider.homeFeedPosts.single.id, 'a');
  });

  test('the same discover refresh is shared', () async {
    final api = _DiscoverApi();
    final provider = FeedProvider(apiService: api);

    final first = provider.loadDiscoverTrips(refresh: true, mood: 'ADVENTURE');
    final second = provider.loadDiscoverTrips(refresh: true, mood: 'ADVENTURE');
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(api.moods, ['ADVENTURE']);

    api.gates['ADVENTURE']!.complete();
    await first;
    expect(provider.discoverTrips.single.title, 'ADVENTURE');
  });

  test('a new discover filter replaces the in-flight refresh', () async {
    final api = _DiscoverApi();
    final provider = FeedProvider(apiService: api);

    final adventure = provider.loadDiscoverTrips(
      refresh: true,
      mood: 'ADVENTURE',
    );
    await Future<void>.delayed(Duration.zero);
    final party = provider.loadDiscoverTrips(refresh: true, mood: 'PARTY');
    await Future<void>.delayed(Duration.zero);

    expect(api.moods, ['ADVENTURE', 'PARTY']);

    api.gates['PARTY']!.complete();
    await party;
    expect(provider.discoverTrips.single.title, 'PARTY');

    api.gates['ADVENTURE']!.complete();
    await adventure;
    expect(provider.discoverTrips.single.title, 'PARTY');
  });
}

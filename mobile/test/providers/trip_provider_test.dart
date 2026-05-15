import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/thread_entries_page.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/services/trip_service.dart';

class MockTripService extends TripService {
  ThreadEntriesPage? contextPage;
  final List<ThreadEntriesPage> threadPages = [];
  int contextCalls = 0;
  int olderCalls = 0;

  @override
  Future<ApiResponse<ThreadEntriesPage>> getThreadEntryContext(
    String tripId,
    String entryId, {
    int contextSize = 25,
  }) async {
    contextCalls++;
    if (contextPage == null) {
      return ApiResponse<ThreadEntriesPage>(
        success: false,
        error: 'context failed',
      );
    }
    return ApiResponse<ThreadEntriesPage>(success: true, data: contextPage);
  }

  @override
  Future<ApiResponse<ThreadEntriesPage>> getThreadEntries(
    String tripId, {
    int limit = 30,
    String? olderThanCursor,
  }) async {
    olderCalls++;
    if (threadPages.isEmpty) {
      return ApiResponse<ThreadEntriesPage>(
        success: false,
        error: 'older page failed',
      );
    }
    return ApiResponse<ThreadEntriesPage>(
      success: true,
      data: threadPages.removeAt(0),
    );
  }
}

User _user(String id) => User(
      id: id,
      email: '$id@test.com',
      username: id,
      name: id,
      isPrivate: false,
      createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
      updatedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
    );

TripThreadEntry _entry(String id, DateTime createdAt) => TripThreadEntry(
      id: id,
      tripId: 'trip-1',
      authorId: 'u1',
      type: ThreadEntryType.text,
      contentText: id,
      createdAt: createdAt,
      author: _user('u1'),
    );

void main() {
  group('TripProvider.loadUntilEntryPresent', () {
    test('uses context endpoint and finds target without older paging', () async {
      final mockService = MockTripService();
      mockService.contextPage = ThreadEntriesPage(
        items: [
          _entry('e1', DateTime.parse('2026-01-01T10:00:00.000Z')),
          _entry('target', DateTime.parse('2026-01-01T10:01:00.000Z')),
          _entry('e3', DateTime.parse('2026-01-01T10:02:00.000Z')),
        ],
        hasMoreOlder: true,
        nextOlderCursor: 'cursor-1',
      );
      final provider = TripProvider(tripService: mockService);

      final found = await provider.loadUntilEntryPresent('trip-1', 'target');

      expect(found, isTrue);
      expect(mockService.contextCalls, 1);
      expect(mockService.olderCalls, 0);
      expect(provider.currentTripEntries.any((e) => e.id == 'target'), isTrue);
      expect(provider.threadEntriesHasMoreOlder, isTrue);
    });

    test('falls back to older paging when context endpoint fails', () async {
      final mockService = MockTripService();
      mockService.contextPage = null;
      mockService.threadPages.addAll([
        ThreadEntriesPage(
          items: [_entry('latest', DateTime.parse('2026-01-01T10:10:00.000Z'))],
          hasMoreOlder: true,
          nextOlderCursor: 'cursor-older',
        ),
        ThreadEntriesPage(
          items: [
            _entry('old-1', DateTime.parse('2026-01-01T09:59:00.000Z')),
            _entry('target', DateTime.parse('2026-01-01T10:00:00.000Z')),
          ],
          hasMoreOlder: false,
          nextOlderCursor: null,
        ),
      ]);
      final provider = TripProvider(tripService: mockService);

      await provider.loadCurrentTripEntries('trip-1');
      final found = await provider.loadUntilEntryPresent('trip-1', 'target');

      expect(found, isTrue);
      expect(mockService.contextCalls, 1);
      expect(mockService.olderCalls, greaterThanOrEqualTo(2));
      expect(provider.currentTripEntries.any((e) => e.id == 'target'), isTrue);
    });
  });
}

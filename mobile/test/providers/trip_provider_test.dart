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
  final List<List<Trip>> tripsResponses = [];
  final List<Trip?> currentTripResponses = [];
  ApiResponse<void> leaveResponse = ApiResponse<void>(success: true);
  int leaveCalls = 0;
  bool? lastRemoveMyData;
  int contextCalls = 0;
  int olderCalls = 0;

  @override
  Future<ApiResponse<List<Trip>>> getTrips({TripStatus? status}) async {
    return ApiResponse<List<Trip>>(
      success: true,
      data: tripsResponses.isNotEmpty ? tripsResponses.removeAt(0) : <Trip>[],
    );
  }

  @override
  Future<ApiResponse<Trip?>> getCurrentTrip() async {
    return ApiResponse<Trip?>(
      success: true,
      data: currentTripResponses.isNotEmpty
          ? currentTripResponses.removeAt(0)
          : null,
    );
  }

  @override
  Future<ApiResponse<void>> leaveTrip(
    String tripId, {
    required bool removeMyData,
  }) async {
    leaveCalls++;
    lastRemoveMyData = removeMyData;
    return leaveResponse;
  }

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

Trip _trip(String id) => Trip(
      id: id,
      userId: 'owner-1',
      title: 'Test Trip',
      startDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
      endDate: DateTime.parse('2026-01-05T00:00:00.000Z'),
      destinations: const ['Paris'],
      status: TripStatus.ongoing,
      entryCount: 0,
      participantCount: 2,
      createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
      updatedAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
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

  group('TripProvider.leaveTrip', () {
    test('calls service, clears local trip list, and refreshes state on success',
        () async {
      final mockService = MockTripService();
      mockService.tripsResponses.addAll([
        [_trip('trip-1')],
        <Trip>[],
      ]);
      final provider = TripProvider(tripService: mockService);

      await provider.loadTrips();
      expect(provider.trips.map((t) => t.id), contains('trip-1'));

      final left = await provider.leaveTrip('trip-1', removeMyData: true);

      expect(left, isTrue);
      expect(mockService.leaveCalls, 1);
      expect(mockService.lastRemoveMyData, isTrue);
      expect(provider.trips.where((t) => t.id == 'trip-1'), isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('keeps state and exposes service error on failure', () async {
      final mockService = MockTripService()
        ..leaveResponse = ApiResponse<void>(
          success: false,
          error: 'Cannot leave ended trip',
        );
      final provider = TripProvider(tripService: mockService);

      final left = await provider.leaveTrip('trip-1', removeMyData: true);

      expect(left, isFalse);
      expect(mockService.leaveCalls, 1);
      expect(provider.isLoading, isFalse);
      expect(provider.error, 'Cannot leave ended trip');
    });
  });
}

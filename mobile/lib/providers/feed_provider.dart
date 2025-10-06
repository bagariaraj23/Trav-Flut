import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';

class FeedProvider extends ChangeNotifier {
  final ApiService _apiService;

  FeedProvider({required ApiService apiService}) : _apiService = apiService;

  // Home Feed State
  final List<TripFinalPost> _homeFeedPosts = [];
  bool _isHomeFeedLoading = false;
  String? _homeFeedError;
  int _homeFeedPage = 1;
  bool _hasMoreHomeFeedPosts = true;

  // Discover Trips State
  final List<Trip> _discoverTrips = [];
  bool _isDiscoverTripsLoading = false;
  String? _discoverTripsError;
  int _discoverTripsPage = 1;
  bool _hasMoreDiscoverTrips = true;

  // Getters
  List<TripFinalPost> get homeFeedPosts => _homeFeedPosts;
  bool get isHomeFeedLoading => _isHomeFeedLoading;
  String? get homeFeedError => _homeFeedError;
  bool get hasMoreHomeFeedPosts => _hasMoreHomeFeedPosts;

  List<Trip> get discoverTrips => _discoverTrips;
  bool get isDiscoverTripsLoading => _isDiscoverTripsLoading;
  String? get discoverTripsError => _discoverTripsError;
  bool get hasMoreDiscoverTrips => _hasMoreDiscoverTrips;

  // Home Feed Methods
  Future<void> loadHomeFeed({bool refresh = false}) async {
    try {
      // Prevent concurrent loads: if a load is already in progress, skip this call.
      if (_isHomeFeedLoading) {
        debugPrint('[FeedProvider] loadHomeFeed already in progress, skipping');
        return;
      }
      if (refresh) {
        _homeFeedPage = 1;
        _homeFeedPosts.clear();
        _hasMoreHomeFeedPosts = true;
        _homeFeedError = null;
        debugPrint('[FeedProvider] Refreshing home feed, page: $_homeFeedPage');
      }

      if (!_hasMoreHomeFeedPosts) {
        debugPrint('[FeedProvider] No more home feed posts to load');
        return;
      }

      _isHomeFeedLoading = true;
      notifyListeners();

      debugPrint('[FeedProvider] Loading home feed, page: $_homeFeedPage, limit: 20');
      final response = await _apiService.getHomeFeed(
        page: _homeFeedPage,
        limit: 20,
      );

      debugPrint('[FeedProvider] Home feed API response: success=${response.success}, error=${response.error}');

      if (response.success && response.data != null) {
        final data = response.data!;
        debugPrint('[FeedProvider] Home feed data keys: ${data.keys.toList()}');

        // Validate response structure
        if (!data.containsKey('items') || !data.containsKey('hasNext')) {
          throw Exception('Invalid response structure: missing required fields');
        }

        final items = data['items'];
        final hasNext = data['hasNext'];

        if (items is! List || hasNext is! bool) {
          throw Exception('Invalid response data types');
        }

        debugPrint('[FeedProvider] Parsing ${items.length} home feed posts');

        final List<TripFinalPost> posts = [];
        for (int i = 0; i < items.length; i++) {
          try {
            final item = items[i];
            if (item is! Map<String, dynamic>) {
              debugPrint('[FeedProvider] Warning: item $i is not a Map, got ${item.runtimeType}');
              continue;
            }

            // Skip posts from private accounts that we're not following
            final isPrivate = item['isPrivate'] ?? false;
            final isFollowing = item['isFollowing'] ?? false;
            if (isPrivate && !isFollowing) {
              debugPrint('[FeedProvider] Skipping private post from non-followed user');
              continue;
            }

            debugPrint('[FeedProvider] Parsing post $i: ${item.keys.toList()}');
            final post = TripFinalPost.fromJson(item);
            posts.add(post);
            debugPrint('[FeedProvider] Successfully parsed post: ${post.id}');
          } catch (parseError) {
            debugPrint('[FeedProvider] Error parsing post $i: $parseError');
            debugPrint('[FeedProvider] Post $i data: $items[i]');
          }
        }

        if (refresh) {
          _homeFeedPosts.clear();
          debugPrint('[FeedProvider] Cleared existing home feed posts');
        }

        _homeFeedPosts.addAll(posts);
        _hasMoreHomeFeedPosts = hasNext && posts.isNotEmpty;
        _homeFeedPage++;
        _homeFeedError = null;

        debugPrint('[FeedProvider] Home feed updated: ${_homeFeedPosts.length} posts, hasNext: $_hasMoreHomeFeedPosts, page: $_homeFeedPage');
      } else {
        _homeFeedError = response.error ?? 'Failed to load home feed';
        debugPrint('[FeedProvider] Home feed failed: $_homeFeedError');
      }
    } catch (e) {
      _homeFeedError = 'An unexpected error occurred: $e';
      debugPrint('[FeedProvider] Load home feed error: $e');
      debugPrint('[FeedProvider] Stack trace: ${StackTrace.current}');
    } finally {
      _isHomeFeedLoading = false;
      notifyListeners();
    }
  }

  // Discover Trips Methods
  Future<void> loadDiscoverTrips({
    bool refresh = false,
    String? status,
    String? mood,
  }) async {
    try {
      if (refresh) {
        _discoverTripsPage = 1;
        _discoverTrips.clear();
        _hasMoreDiscoverTrips = true;
        _discoverTripsError = null;
        debugPrint(
            '[FeedProvider] Refreshing discover trips, page: $_discoverTripsPage');
      }

      if (!_hasMoreDiscoverTrips) {
        debugPrint('[FeedProvider] No more discover trips to load');
        return;
      }

      _isDiscoverTripsLoading = true;
      notifyListeners();

      debugPrint(
          '[FeedProvider] Loading discover trips, page: $_discoverTripsPage, limit: 20, status: $status, mood: $mood');
      final response = await _apiService.getDiscoverTrips(
        page: _discoverTripsPage,
        limit: 20,
        status: status,
        mood: mood,
        includePrivate: false, // Only fetch public and followed user trips
      );

      debugPrint(
          '[FeedProvider] Discover trips API response: success=${response.success}, error=${response.error}');

      if (response.success && response.data != null) {
        final data = response.data!;

        // Validate response structure
        if (!data.containsKey('items') || !data.containsKey('hasNext')) {
          throw Exception('Invalid response structure: missing required fields');
        }

        final items = data['items'];
        final hasNext = data['hasNext'];

        if (items is! List || hasNext is! bool) {
          throw Exception('Invalid response data types');
        }

        debugPrint('[FeedProvider] Parsing ${items.length} discover trips');

        final List<Trip> trips = [];
        for (int i = 0; i < items.length; i++) {
          try {
            final item = items[i];
            if (item is! Map<String, dynamic>) {
              debugPrint(
                  '[FeedProvider] Warning: item $i is not a Map, got ${item.runtimeType}');
              continue;
            }

            debugPrint('[FeedProvider] Parsing trip $i: ${item.keys.toList()}');
            final trip = Trip.fromJson(item);

            // Only add trips that are either public or from followed users
            if (trip.user?.isPrivate != true || item['isFollowing'] == true) {
              trips.add(trip);
            }

            debugPrint('[FeedProvider] Successfully parsed trip: ${trip.id}');
          } catch (parseError) {
            debugPrint('[FeedProvider] Error parsing trip $i: $parseError');
            debugPrint('[FeedProvider] Trip $i data: $items[i]');
          }
        }

        if (refresh) {
          _discoverTrips.clear();
          debugPrint('[FeedProvider] Cleared existing discover trips');
        }

        _discoverTrips.addAll(trips);
        _hasMoreDiscoverTrips = hasNext && trips.isNotEmpty;
        _discoverTripsPage++;
        _discoverTripsError = null;

        debugPrint(
            '[FeedProvider] Discover trips updated: ${_discoverTrips.length} trips, hasNext: $_hasMoreDiscoverTrips, page: $_discoverTripsPage');
      } else {
        _discoverTripsError = response.error ?? 'Failed to load discover trips';
        debugPrint(
            '[FeedProvider] Discover trips failed: $_discoverTripsError');
      }
    } catch (e) {
      _discoverTripsError = 'An unexpected error occurred: $e';
      debugPrint('[FeedProvider] Load discover trips error: $e');
      debugPrint('[FeedProvider] Stack trace: ${StackTrace.current}');
    } finally {
      _isDiscoverTripsLoading = false;
      notifyListeners();
    }
  }

  // Clear methods
  void clearHomeFeedError() {
    debugPrint('[FeedProvider] Clearing home feed error');
    _homeFeedError = null;
    notifyListeners();
  }

  void clearDiscoverTripsError() {
    debugPrint('[FeedProvider] Clearing discover trips error');
    _discoverTripsError = null;
    notifyListeners();
  }

  void resetHomeFeed() {
    debugPrint('[FeedProvider] Resetting home feed');
    _homeFeedPosts.clear();
    _homeFeedPage = 1;
    _hasMoreHomeFeedPosts = true;
    _homeFeedError = null;
    notifyListeners();
  }

  void resetDiscoverTrips() {
    debugPrint('[FeedProvider] Resetting discover trips');
    _discoverTrips.clear();
    _discoverTripsPage = 1;
    _hasMoreDiscoverTrips = true;
    _discoverTripsError = null;
    notifyListeners();
  }

  void clearData() {
    debugPrint('[FeedProvider] Clearing all feed data');
    _homeFeedPosts.clear();
    _discoverTrips.clear();
    _homeFeedError = null;
    _discoverTripsError = null;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';

class FeedProvider extends ChangeNotifier {
  final ApiService _apiService;

  FeedProvider({required ApiService apiService}) : _apiService = apiService;

  final List<Trip> _feedTrips = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  // Getters
  List<Trip> get feedTrips => _feedTrips;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;

  Future<void> loadFeed({bool refresh = false}) async {
    try {
      if (refresh) {
        _currentPage = 1;
        _feedTrips.clear();
        _hasMore = true;
        _error = null;
      }

      if (!_hasMore) return;

      if (refresh || _currentPage == 1) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
      
      notifyListeners();

      final response = await _apiService.getFeed(
        page: _currentPage,
        limit: 20,
      );

      if (response.success && response.data != null) {
        if (refresh) {
          _feedTrips.clear();
        }

        _feedTrips.addAll(response.data!.items);
        _hasMore = response.data!.hasNext;
        _currentPage++;
        _error = null;
      } else {
        _error = response.error ?? 'Failed to load feed';
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      debugPrint('Load feed error: $e');
    } finally {
      _isLoading = false;
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearFeed() {
    _feedTrips.clear();
    _currentPage = 1;
    _hasMore = true;
    _error = null;
    notifyListeners();
  }
}
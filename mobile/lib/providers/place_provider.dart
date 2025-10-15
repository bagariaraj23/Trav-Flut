import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/services/api_service.dart';

class PlaceProvider extends ChangeNotifier {
  final ApiService _apiService;
  Timer? _debounceTimer;

  // State for search results
  List<Place> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  List<Place> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;

  PlaceProvider({required ApiService apiService}) : _apiService = apiService;

  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Method to search for places (for autocomplete)
  Future<void> searchPlaces(String query,
      {double? lat, double? lng, String? placeType, int limit = 20}) async {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      _searchResults = [];
      _searchError = null;
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      _isSearching = true;
      _searchError = null;
      notifyListeners();

      try {
        final response = await _apiService.searchPlaces(
          query: query,
          lat: lat,
          lng: lng,
          placeType: placeType,
          limit: limit,
        );

        if (response.success && response.data != null) {
          _searchResults = response.data!;
        } else {
          _searchError = response.error ?? 'Failed to search places';
          _searchResults = [];
        }
      } catch (e) {
        _searchError = 'An unexpected error occurred during search: $e';
        _searchResults = [];
        debugPrint('Place search error: $e');
      } finally {
        _isSearching = false;
        notifyListeners();
      }
    });
  }

  // Method to resolve a place (get canonical ID or create new)
  Future<Place?> resolvePlace(Place placeCandidate) async {
    try {
      final response = await _apiService.resolvePlace(placeCandidate);
      if (response.success && response.data != null) {
        return response.data!.place; // Returns the canonical Place object
      } else {
        debugPrint('Failed to resolve place: ${response.error}');
        return null;
      }
    } catch (e) {
      debugPrint('Resolve place error: $e');
      return null;
    }
  }

  // Method to attach a place to a trip (record a visit)
  Future<bool> attachPlaceToTrip(
    String tripId,
    String placeId, {
    DateTime? visitedAt,
    int? dayIndex,
    String? notes,
    bool createThreadEntry = false,
  }) async {
    try {
      final response = await _apiService.attachPlaceToTrip(
        tripId,
        placeId,
        visitedAt: visitedAt,
        dayIndex: dayIndex,
        notes: notes,
        createThreadEntry: createThreadEntry,
      );
      return response.success;
    } catch (e) {
      debugPrint('Attach place to trip error: $e');
      return false;
    }
  }

  // Method to get places for a specific trip
  Future<List<PlaceOnTrip>> getTripPlaces(String tripId) async {
    try {
      final response = await _apiService.getTripPlaces(tripId);
      if (response.success && response.data != null) {
        return response.data!;
      } else {
        debugPrint('Failed to get trip places: ${response.error}');
        return [];
      }
    } catch (e) {
      debugPrint('Get trip places error: $e');
      return [];
    }
  }

  // Clear search results
  void clearSearchResults() {
    _searchResults = [];
    _searchError = null;
    notifyListeners();
  }
}

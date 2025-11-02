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

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Method to search for places (for autocomplete)
  Future<void> searchPlaces(String query,
      {double? lat, double? lng, PlaceType? placeType, int limit = 20}) async {
    debugPrint('[PlaceProvider] searchPlaces called with query: "$query"');
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      debugPrint('[PlaceProvider] Query empty, clearing results.');
      _searchResults = [];
      _searchError = null;
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      debugPrint(
          '[PlaceProvider] Debounce triggered. Starting search for: "$query"');
      _isSearching = true;
      _searchError = null;
      notifyListeners();

      try {
        debugPrint('[PlaceProvider] Calling apiService.searchPlaces...');
        final response = await _apiService.searchPlaces(
          query: query,
          lat: lat,
          lng: lng,
          placeType: placeType?.toString(),
          limit: limit,
        );
        debugPrint(
            '[PlaceProvider] API response received: success=${response.success}, error=${response.error}, data=${response.data?.length} items');

        if (response.success && response.data != null) {
          _searchResults = response.data!;
          debugPrint(
              '[PlaceProvider] Search successful. Found ${_searchResults.length} results.');
        } else {
          _searchError = response.error ?? 'Failed to search places';
          _searchResults = [];
          debugPrint('[PlaceProvider] Search failed: $_searchError');
        }
      } catch (e) {
        _searchError = 'An unexpected error occurred during search: $e';
        _searchResults = [];
        debugPrint('[PlaceProvider] Place search EXCEPTION: $e');
      } finally {
        _isSearching = false;
        debugPrint('[PlaceProvider] Search finished. Notifying listeners.');
        notifyListeners();
      }
    });
  }

  // Method to resolve a place (get canonical ID or create new)
  Future<Place?> resolvePlace(Place placeCandidate) async {
    // Changed Place to PlaceCandidate
    debugPrint(
        '[PlaceProvider] resolvePlace called for: ${placeCandidate.name}');
    try {
      final response = await _apiService.resolvePlace(placeCandidate);
      debugPrint(
          '[PlaceProvider] resolvePlace API response: success=${response.success}, error=${response.error}');

      if (response.success && response.data != null) {
        debugPrint(
            '[PlaceProvider] Place resolved successfully. ID: ${response.data!.place}');
        return response.data!.place; // Returns the canonical Place object
      } else {
        debugPrint(
            '[PlaceProvider] Failed to resolve place: ${response.error}');
        return null;
      }
    } catch (e) {
      debugPrint('[PlaceProvider] Resolve place EXCEPTION: $e');
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
    debugPrint(
        '[PlaceProvider] attachPlaceToTrip called. TripID: $tripId, PlaceID: $placeId');
    try {
      final response = await _apiService.attachPlaceToTrip(
        tripId,
        placeId,
        visitedAt: visitedAt,
        dayIndex: dayIndex,
        notes: notes,
        createThreadEntry: createThreadEntry,
      );
      debugPrint(
          '[PlaceProvider] attachPlaceToTrip API response: success=${response.success}, error=${response.error}');
      return response.success;
    } catch (e) {
      debugPrint('[PlaceProvider] Attach place to trip EXCEPTION: $e');
      return false;
    }
  }

  // Method to get places for a specific trip (MapPlace-aware)
  Future<List<MapPlace>> getTripPlaces(String tripId) async {
    debugPrint('[PlaceProvider] getTripPlaces called for TripID: $tripId');
    try {
      final response = await _apiService.getTripPlaces(tripId);
      debugPrint(
          '[PlaceProvider] getTripPlaces API response: success=${response.success}, found ${response.data?.length ?? 0} items, error=${response.error}');
      if (response.success && response.data != null) {
        return response.data!;
      } else {
        debugPrint(
            '[PlaceProvider] Failed to get trip places: ${response.error}');
        return [];
      }
    } catch (e) {
      debugPrint('[PlaceProvider] Get trip places EXCEPTION: $e');
      return [];
    }
  }

  // Clear search results
  void clearSearchResults() {
    debugPrint('[PlaceProvider] clearSearchResults called.');
    if (_searchResults.isNotEmpty || _searchError != null) {
      // Only notify if there's a change
      _searchResults = [];
      _searchError = null;
      notifyListeners();
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/trip_service.dart';

class TripProvider extends ChangeNotifier {
  final TripService _tripService;

  TripProvider({required TripService tripService}) : _tripService = tripService;

  // State
  Trip? _currentTrip;
  List<Trip> _trips = [];
  List<TripThreadEntry> _currentTripEntries = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  Trip? get currentTrip => _currentTrip;
  List<Trip> get trips => _trips;
  List<TripThreadEntry> get currentTripEntries => _currentTripEntries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasOngoingTrip => _currentTrip?.status == TripStatus.ongoing;

  // Initialize
  Future<void> initialize() async {
    await Future.wait([
      loadCurrentTrip(),
      loadTrips(),
    ]);
  }

  // Load current ongoing trip
  Future<void> loadCurrentTrip() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _tripService.getCurrentTrip();

      if (response.success) {
        _currentTrip = response.data;

        // Load entries if there's a current trip
        if (_currentTrip != null) {
          await loadCurrentTripEntries();
        }
      } else {
        _error = response.error;
      }
    } catch (e) {
      _error = 'Failed to load current trip';
      debugPrint('Load current trip error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load all user trips
  Future<void> loadTrips({TripStatus? status}) async {
    try {
      final response = await _tripService.getTrips(status: status);

      if (response.success && response.data != null) {
        _trips = response.data!;
        notifyListeners();
      } else {
        _error = response.error;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to load trips';
      notifyListeners();
      debugPrint('Load trips error: $e');
    }
  }

  // Create new trip
  Future<bool> createTrip(CreateTripRequest request) async {
    try {
      print('[DEBUG] TripProvider.createTrip called');
      print('[DEBUG] Request data: ${request.toJson()}');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _tripService.createTrip(request);

      print('[DEBUG] API response received:');
      print('[DEBUG] Success: ${response.success}');
      print('[DEBUG] Error: ${response.error}');
      print('[DEBUG] Data: ${response.data}');

      if (response.success && response.data != null) {
        _currentTrip = response.data;
        _currentTripEntries = [];

        // Refresh trips list
        await loadTrips();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to create trip';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('[DEBUG] Exception in createTrip: $e');
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Create trip error: $e');
      return false;
    }
  }

  // End current trip
  Future<bool> endTrip() async {
    if (_currentTrip == null) return false;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _tripService.endTrip(_currentTrip!.id);

      if (response.success && response.data != null) {
        _currentTrip = response.data;

        // Refresh trips list
        await loadTrips();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to end trip';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('End trip error: $e');
      return false;
    }
  }

  // Load thread entries for current trip
  Future<void> loadCurrentTripEntries() async {
    if (_currentTrip == null) return;

    try {
      final response = await _tripService.getThreadEntries(_currentTrip!.id);

      if (response.success && response.data != null) {
        _currentTripEntries = response.data!;
        notifyListeners();
      } else {
        _error = response.error;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to load trip entries';
      notifyListeners();
      debugPrint('Load trip entries error: $e');
    }
  }

  // Add thread entry
  Future<bool> addThreadEntry(CreateThreadEntryRequest request) async {
    if (_currentTrip == null) return false;

    try {
      final response =
          await _tripService.createThreadEntry(_currentTrip!.id, request);

      if (response.success && response.data != null) {
        _currentTripEntries.add(response.data!);
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to add entry';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      notifyListeners();
      debugPrint('Add thread entry error: $e');
      return false;
    }
  }

  // Add text entry
  Future<bool> addTextEntry(String text) async {
    return await addThreadEntry(CreateThreadEntryRequest(
      type: ThreadEntryType.text,
      contentText: text,
    ));
  }

  // Add media entry
  Future<bool> addMediaEntry(String mediaUrl, {String? caption}) async {
    return await addThreadEntry(CreateThreadEntryRequest(
      type: ThreadEntryType.media,
      mediaUrl: mediaUrl,
      contentText: caption,
    ));
  }

  // Add location entry
  Future<bool> addLocationEntry(
    String locationName, {
    double? lat,
    double? lng,
    String? notes,
  }) async {
    return await addThreadEntry(CreateThreadEntryRequest(
      type: ThreadEntryType.location,
      locationName: locationName,
      gpsCoordinates: lat != null && lng != null
          ? GpsCoordinates(lat: lat, lng: lng)
          : null,
      contentText: notes,
    ));
  }

  // Get trip by ID
  Future<Trip?> getTrip(String tripId) async {
    try {
      final response = await _tripService.getTrip(tripId);

      if (response.success && response.data != null) {
        return response.data;
      } else {
        _error = response.error;
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'Failed to load trip';
      notifyListeners();
      debugPrint('Get trip error: $e');
      return null;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear current trip (for logout)
  void clearData() {
    _currentTrip = null;
    _trips = [];
    _currentTripEntries = [];
    _error = null;
    notifyListeners();
  }
}

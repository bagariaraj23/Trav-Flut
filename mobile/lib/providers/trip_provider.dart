import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/trip_join_request.dart';
import 'package:tripthread/services/trip_service.dart';

class TripProvider extends ChangeNotifier {
  final TripService _tripService;

  TripProvider({required TripService tripService}) : _tripService = tripService;

  // State
  Trip? _currentTrip;
  List<Trip> _trips = [];
  List<TripThreadEntry> _currentTripEntries = [];
  List<TripJoinRequest> _pendingTripInvitations = [];
  List<TripJoinRequest> _sentTripInvitations = [];
  bool _isLoading = false;
  bool _isTripInvitesLoading = false;
  String? _error;
  String? _tripInvitesError;

  // Getters
  Trip? get currentTrip => _currentTrip;
  List<Trip> get trips => _trips;
  List<TripThreadEntry> get currentTripEntries => _currentTripEntries;
  List<TripJoinRequest> get pendingTripInvitations => _pendingTripInvitations;
  List<TripJoinRequest> get sentTripInvitations => _sentTripInvitations;
  bool get isLoading => _isLoading;
  bool get isTripInvitesLoading => _isTripInvitesLoading;
  String? get error => _error;
  String? get tripInvitesError => _tripInvitesError;
  bool get hasOngoingTrip => _currentTrip?.status == TripStatus.ongoing;

  // Initialize
  Future<void> initialize() async {
    await Future.wait([
      loadCurrentTrip(),
      loadTrips(),
      loadPendingTripInvitations(),
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
  Future<void> loadCurrentTripEntries([String? tripId]) async {
    final id = tripId ?? _currentTrip?.id;
    if (id == null) return;

    try {
      final response = await _tripService.getThreadEntries(id);

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
  Future<bool> addThreadEntry(CreateThreadEntryRequest request,
      {String? tripId}) async {
    final id = tripId ?? _currentTrip?.id;
    if (id == null) return false;

    try {
      final response = await _tripService.createThreadEntry(id, request);

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
  Future<bool> addTextEntry(String text, {String? tripId}) async {
    return await addThreadEntry(
        CreateThreadEntryRequest(
          type: ThreadEntryType.text,
          contentText: text,
        ),
        tripId: tripId);
  }

  // Add media entry
  Future<bool> addMediaEntry(String mediaUrl,
      {String? caption, String? tripId}) async {
    return await addThreadEntry(
        CreateThreadEntryRequest(
          type: ThreadEntryType.media,
          mediaUrl: mediaUrl,
          contentText: caption,
        ),
        tripId: tripId);
  }

  // Add location entry
  Future<bool> addLocationEntry(
    String locationName, {
    double? lat,
    double? lng,
    String? notes,
    String? tripId,
  }) async {
    return await addThreadEntry(
        CreateThreadEntryRequest(
          type: ThreadEntryType.location,
          locationName: locationName,
          gpsCoordinates: lat != null && lng != null
              ? GpsCoordinates(lat: lat, lng: lng)
              : null,
          contentText: notes,
        ),
        tripId: tripId);
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

  // Trip invitation methods
  Future<bool> sendTripInvitation(String tripId, String receiverId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response =
          await _tripService.sendTripInvitation(tripId, receiverId);

      if (response.success) {
        // Optionally refresh sent invitations for this trip
        await loadSentTripInvitations(tripId);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to send invitation';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Send trip invitation error: $e');
      return false;
    }
  }

  Future<void> loadPendingTripInvitations() async {
    _isTripInvitesLoading = true;
    _tripInvitesError = null;
    notifyListeners();
    try {
      final response = await _tripService.getPendingTripInvitations();
      if (response.success && response.data != null) {
        _pendingTripInvitations = response.data!;
      } else {
        _tripInvitesError = response.error ?? 'Failed to load invitations';
      }
    } catch (e) {
      _tripInvitesError =
          'An unexpected error occurred while loading invitations.';
      debugPrint('Load pending trip invitations error: $e');
    } finally {
      _isTripInvitesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSentTripInvitations(String tripId) async {
    try {
      final response = await _tripService.getSentTripInvitations(tripId);
      if (response.success && response.data != null) {
        _sentTripInvitations = response.data!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Load sent trip invitations error: $e');
    }
  }

  Future<bool> respondToTripInvitation(String inviteId, bool accept) async {
    _isTripInvitesLoading = true;
    _tripInvitesError = null;
    notifyListeners();
    try {
      final response =
          await _tripService.respondToTripInvitation(inviteId, accept);
      if (response.success) {
        // Remove the responded invitation from the list
        _pendingTripInvitations.removeWhere((req) => req.id == inviteId);
        // If accepted, refresh user's trips to show new participant status
        if (accept) {
          await loadTrips();
        }
        notifyListeners();
        return true;
      } else {
        _tripInvitesError = response.error ?? 'Failed to respond to invitation';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _tripInvitesError = 'An unexpected error occurred while responding.';
      notifyListeners();
      debugPrint('Respond to trip invitation error: $e');
      return false;
    } finally {
      _isTripInvitesLoading = false;
      notifyListeners();
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    _tripInvitesError = null;
    notifyListeners();
  }

  // Clear current trip (for logout)
  void clearData() {
    _currentTrip = null;
    _trips = [];
    _currentTripEntries = [];
    _pendingTripInvitations = [];
    _sentTripInvitations = [];
    _error = null;
    _tripInvitesError = null;
    notifyListeners();
  }
}

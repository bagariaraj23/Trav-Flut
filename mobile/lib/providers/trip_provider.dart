import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/trip_join_request.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/widgets/floating_trip_nav_button.dart';

class TripProvider extends ChangeNotifier {
  final TripService _tripService;

  TripProvider({required TripService tripService}) : _tripService = tripService;

  // State
  Trip? _currentTrip;
  List<Trip> _trips = [];
  List<TripThreadEntry> _currentTripEntries = [];
  String? _threadEntriesOlderCursor;
  bool _threadEntriesHasMoreOlder = false;
  bool _isLoadingOlderThreadEntries = false;
  List<TripJoinRequest> _pendingTripInvitations = [];
  List<TripJoinRequest> _sentTripInvitations = [];
  bool _isLoading = false;
  bool _isTripInvitesLoading = false;
  String? _error;
  String? _tripInvitesError;
  bool _hasCompletedInitialOngoingTripRedirect = false;

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
  bool get threadEntriesHasMoreOlder => _threadEntriesHasMoreOlder;
  bool get isLoadingOlderThreadEntries => _isLoadingOlderThreadEntries;

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

  // Check for trip conflicts
  Future<TripConflictInfo?> checkTripConflicts() async {
    try {
      final response = await _tripService.checkTripConflicts();
      if (response.success && response.data != null) {
        return response.data;
      }
      return null;
    } catch (e) {
      debugPrint('Check trip conflicts error: $e');
      return null;
    }
  }

  // Create new trip
  Future<bool> createTrip(
    CreateTripRequest request, {
    bool replaceExisting = false,
  }) async {
    try {
      debugPrint('[DEBUG] TripProvider.createTrip called');
      debugPrint('[DEBUG] Request data: ${request.toJson()}');
      debugPrint('[DEBUG] Replace existing: $replaceExisting');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _tripService.createTrip(
        request,
        replaceExisting: replaceExisting,
      );

      debugPrint('[DEBUG] API response received:');
      debugPrint('[DEBUG] Success: ${response.success}');
      debugPrint('[DEBUG] Error: ${response.error}');
      debugPrint('[DEBUG] Data: ${response.data}');

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
      debugPrint('[DEBUG] Exception in createTrip: $e');
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Create trip error: $e');
      return false;
    }
  }

  // End trip (defaults to current ongoing trip)
  Future<bool> endTrip({String? tripId}) async {
    final targetTripId = tripId ?? _currentTrip?.id;
    if (targetTripId == null) return false;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _tripService.endTrip(targetTripId);

      if (response.success && response.data != null) {
        if (_currentTrip?.id == targetTripId) {
          _currentTrip = response.data;
        }

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

  static const int _threadPageSize = 30;

  // Load latest page of thread entries (chronological ascending within page).
  Future<void> loadCurrentTripEntries([String? tripId]) async {
    final id = tripId ?? _currentTrip?.id;
    if (id == null) return;

    _currentTripEntries = [];
    _threadEntriesOlderCursor = null;
    _threadEntriesHasMoreOlder = false;
    notifyListeners();

    try {
      final response = await _tripService.getThreadEntries(
        id,
        limit: _threadPageSize,
      );

      if (response.success && response.data != null) {
        final page = response.data!;
        _currentTripEntries = page.items;
        _threadEntriesHasMoreOlder = page.hasMoreOlder;
        _threadEntriesOlderCursor = page.nextOlderCursor;
        _error = null;
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

  /// Loads older entries (prepend). Cursor-based; call when user scrolls up.
  Future<void> loadOlderThreadEntries(String tripId) async {
    if (!_threadEntriesHasMoreOlder ||
        _isLoadingOlderThreadEntries ||
        _threadEntriesOlderCursor == null) {
      return;
    }

    // Do not notifyListeners() here — a loading header would change list extent
    // and break scroll anchoring. Only notify after the page is merged.
    _isLoadingOlderThreadEntries = true;

    try {
      final response = await _tripService.getThreadEntries(
        tripId,
        limit: _threadPageSize,
        olderThanCursor: _threadEntriesOlderCursor,
      );

      if (response.success && response.data != null) {
        final page = response.data!;
        final existingIds = _currentTripEntries.map((e) => e.id).toSet();
        final older = page.items
            .where((e) => !existingIds.contains(e.id))
            .toList();
        _currentTripEntries = [...older, ..._currentTripEntries];
        _threadEntriesHasMoreOlder = page.hasMoreOlder;
        _threadEntriesOlderCursor = page.nextOlderCursor;
        _error = null;
      } else {
        _error = response.error;
      }
    } catch (e) {
      _error = 'Failed to load older entries';
      debugPrint('Load older thread entries error: $e');
    } finally {
      _isLoadingOlderThreadEntries = false;
      notifyListeners();
    }
  }

  /// Fetches older pages until [entryId] is in memory or history is exhausted.
  Future<void> loadUntilEntryPresent(String tripId, String entryId) async {
    var guard = 0;
    while (guard < 100 &&
        !_currentTripEntries.any((e) => e.id == entryId) &&
        _threadEntriesHasMoreOlder &&
        _threadEntriesOlderCursor != null) {
      guard++;
      await loadOlderThreadEntries(tripId);
    }
  }

  // Clear current trip entries (useful when switching trips)
  void clearCurrentTripEntries() {
    _currentTripEntries = [];
    _threadEntriesOlderCursor = null;
    _threadEntriesHasMoreOlder = false;
    _isLoadingOlderThreadEntries = false;
    notifyListeners();
  }

  // Add thread entry
  Future<bool> addThreadEntry(CreateThreadEntryRequest request,
      {String? tripId}) async {
    final id = tripId ?? _currentTrip?.id;
    if (id == null) return false;

    try {
      final response = await _tripService.createThreadEntry(
        tripId: id,
        request: request,
      );

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
  Future<bool> addTextEntry(String text, {String? tripId, List<String>? taggedUsernames}) async {
    return await addThreadEntry(
        CreateThreadEntryRequest(
          type: ThreadEntryType.text,
          contentText: text,
          taggedUsernames: taggedUsernames,
        ),
        tripId: tripId);
  }

  // Add media entry
  Future<bool> addMediaEntry(String mediaId,
      {String? caption, String? tripId, List<String>? taggedUsernames}) async {
    return await addThreadEntry(
        CreateThreadEntryRequest(
          type: ThreadEntryType.media,
          mediaId: mediaId,
          contentText: caption,
          taggedUsernames: taggedUsernames,
        ),
        tripId: tripId);
  }

  // Add location entry
  Future<bool> addThreadEntryWithPlace({
    required String tripId,
    required ThreadEntryType type,
    String? contentText,
    String? placeId,
    List<String>? taggedUserIds,
    List<String>? taggedUsernames,
  }) async {
    try {
      // Clear any previous errors
      _error = null;
      notifyListeners();
      
      debugPrint(
          '[TripProvider] Adding thread entry: type=$type, placeId=$placeId');

      if (type == ThreadEntryType.location && placeId == null) {
        _error = 'A place is required for location entries';
        notifyListeners();
        return false;
      }

      final request = CreateThreadEntryRequest(
        type: type,
        contentText: contentText,
        mediaId: null,
        placeId: placeId,
        taggedUserIds: taggedUserIds,
        taggedUsernames: taggedUsernames,
      );

      final response = await _tripService.createThreadEntry(
        tripId: tripId,
        request: request,
      );

      debugPrint('[TripProvider] Create entry response: ${response.success}');
      debugPrint('[TripProvider] Create entry error: ${response.error}');

      if (response.success && response.data != null) {
        _error = null;
        _currentTripEntries.add(response.data!);

        // Update current trip if loaded
        if (_currentTrip?.id == tripId) {
          _currentTrip = _currentTrip!.copyWith(
            threadEntries: _currentTripEntries,
            entryCount: _currentTripEntries.length,
          );
        }

        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to add entry';
        debugPrint('[TripProvider] Entry creation failed: $_error');
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      _error = 'An unexpected error occurred: ${e.toString()}';
      debugPrint('[TripProvider] Add thread entry error: $e');
      debugPrint('[TripProvider] Stack trace: $stackTrace');
      notifyListeners();
      return false;
    }
  }

  // Add location entry
  @Deprecated('Use addThreadEntryWithPlace instead')
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

  Future<bool> deleteThreadEntry({
    required String tripId,
    required String entryId,
  }) async {
    try {
      final response = await _tripService.deleteThreadEntry(
        tripId: tripId,
        entryId: entryId,
      );
      if (response.success) {
        _currentTripEntries.removeWhere((e) => e.id == entryId);
        if (_currentTrip?.id == tripId) {
          final raw = _currentTrip!.entryCount - 1;
          final nextCount = raw < 0 ? 0 : raw;
          _currentTrip = _currentTrip!.copyWith(
            threadEntries: List<TripThreadEntry>.from(_currentTripEntries),
            entryCount: nextCount,
          );
        }
        _error = null;
        notifyListeners();
        return true;
      }
      _error = response.error ?? 'Failed to delete entry';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to delete entry';
      notifyListeners();
      debugPrint('Delete thread entry error: $e');
      return false;
    }
  }

  Future<bool> updateThreadEntryText({
    required String tripId,
    required String entryId,
    required String contentText,
  }) async {
    try {
      final response = await _tripService.patchThreadEntryText(
        tripId: tripId,
        entryId: entryId,
        contentText: contentText,
      );
      if (response.success && response.data != null) {
        final idx = _currentTripEntries.indexWhere((e) => e.id == entryId);
        if (idx >= 0) {
          _currentTripEntries[idx] = response.data!;
        }
        if (_currentTrip?.id == tripId) {
          _currentTrip = _currentTrip!.copyWith(
            threadEntries: List<TripThreadEntry>.from(_currentTripEntries),
          );
        }
        _error = null;
        notifyListeners();
        return true;
      }
      _error = response.error ?? 'Failed to update entry';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to update entry';
      notifyListeners();
      debugPrint('Update thread entry error: $e');
      return false;
    }
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

  Future<bool> updateTripCover({
    required String tripId,
    required String coverMediaId,
    Media? fallbackMedia,
  }) async {
    try {
      final response = await _tripService.updateTripCover(
        tripId,
        coverMediaId,
      );

      if (!response.success) {
        _error = response.error ?? 'Failed to update trip cover';
        notifyListeners();
        return false;
      }

      final media = response.data ?? fallbackMedia;
      if (media == null) {
        _error = 'Trip cover updated but media payload was missing';
        notifyListeners();
        return false;
      }

      try {
        if (_currentTrip?.id == tripId) {
          _currentTrip = _currentTrip!.copyWith(
            coverMediaId: media.id,
            coverMedia: media,
          );
        }

        // Update trips list safely
        final updatedTrips = <Trip>[];
        for (final trip in _trips) {
          if (trip.id == tripId) {
            updatedTrips.add(
              trip.copyWith(
                coverMediaId: media.id,
                coverMedia: media,
              ),
            );
          } else {
            updatedTrips.add(trip);
          }
        }
        _trips = updatedTrips;

        notifyListeners();
        return true;
      } catch (e, stackTrace) {
        debugPrint('Update trip cover error updating state: $e');
        debugPrint('Stack trace: $stackTrace');
        _error = 'Failed to update trip cover state: $e';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      _error = 'Failed to update trip cover';
      notifyListeners();
      debugPrint('Update trip cover error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
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

  Future<bool> cancelTripInvitation(String tripId, String inviteId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response =
          await _tripService.cancelTripInvitation(tripId, inviteId);

      if (response.success) {
        // Remove the cancelled invitation from the list
        _sentTripInvitations.removeWhere((invite) => invite.id == inviteId);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to cancel invitation';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Cancel trip invitation error: $e');
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

  void markInitialOngoingTripRedirectComplete() {
    _hasCompletedInitialOngoingTripRedirect = true;
    notifyListeners();
  }

  bool get hasCompletedInitialOngoingTripRedirect =>
      _hasCompletedInitialOngoingTripRedirect;

  // Clear current trip (for logout)
  void clearData() {
    _currentTrip = null;
    _trips = [];
    _currentTripEntries = [];
    _pendingTripInvitations = [];
    _sentTripInvitations = [];
    _error = null;
    _tripInvitesError = null;
    _hasCompletedInitialOngoingTripRedirect = false;
    // Reset floating bubble position so it doesn't persist across user sessions
    FloatingTripNavButton.resetPosition();
    notifyListeners();
  }
}

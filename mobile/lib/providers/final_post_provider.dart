import 'package:flutter/foundation.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/utils/debouncer.dart';

class FinalPostProvider extends ChangeNotifier {
  FinalPostProvider({required TripService tripService})
      : _tripService = tripService;

  final TripService _tripService;
  final Debouncer _debouncer =
      Debouncer(delay: const Duration(seconds: 2));

  TripFinalPost? _draft;
  String? _tripId;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isPublishing = false;
  String? _error;
  final Map<String, dynamic> _pendingUpdates = {};

  TripFinalPost? get draft => _draft;
  bool get _canEdit => _draft != null && !_draft!.isPublished;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isPublishing => _isPublishing;
  String? get error => _error;

  Future<void> loadDraft(String tripId) async {
    _tripId = tripId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _tripService.getFinalPost(tripId);

    if (response.success && response.data != null) {
      _draft = response.data;
    } else {
      _error = response.error ?? 'Failed to load final post';
    }

    _isLoading = false;
    notifyListeners();
  }

  void updateSummary(String value) {
    if (!_canEdit || _draft == null) return;
    _draft = _draft!.copyWith(summaryText: value);
    _pendingUpdates['summaryText'] = value;
    _scheduleAutoSave();
    notifyListeners();
  }

  void updateCaption(String value) {
    if (!_canEdit || _draft == null) return;
    _draft = _draft!.copyWith(caption: value);
    _pendingUpdates['caption'] = value;
    _scheduleAutoSave();
    notifyListeners();
  }

  void setCuratedMedia(List<String> mediaUrls) {
    if (!_canEdit || _draft == null) return;
    final sanitized = mediaUrls.toSet().toList();
    _draft = _draft!.copyWith(
      curatedMedia: sanitized,
      coverMediaUrl:
          sanitized.isNotEmpty ? sanitized.first : _draft!.coverMediaUrl,
    );
    _pendingUpdates['curatedMedia'] = sanitized;
    if (sanitized.isNotEmpty) {
      _pendingUpdates['coverMediaUrl'] = sanitized.first;
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  void toggleMedia(String mediaUrl) {
    if (!_canEdit || _draft == null) return;
    final next = List<String>.from(_draft!.curatedMedia);
    if (next.contains(mediaUrl)) {
      next.remove(mediaUrl);
    } else {
      next.add(mediaUrl);
    }
    setCuratedMedia(next);
  }

  void setCoverMedia(String? url) {
    if (!_canEdit || _draft == null) return;
    if (url != null && !_draft!.curatedMedia.contains(url)) {
      final updated = List<String>.from(_draft!.curatedMedia)..insert(0, url);
      _draft = _draft!.copyWith(
        curatedMedia: updated,
        coverMediaUrl: url,
      );
      _pendingUpdates['curatedMedia'] = updated;
    } else {
      _draft = _draft!.copyWith(coverMediaUrl: url);
    }

    _pendingUpdates['coverMediaUrl'] = url;
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<bool> saveDraft() async {
    if (_tripId == null || _pendingUpdates.isEmpty) {
      return true;
    }

    return _persistUpdates(force: true);
  }

  Future<bool> publish() async {
    if (_tripId == null) return false;
    await _persistUpdates(force: true);

    _isPublishing = true;
    _error = null;
    notifyListeners();

    final response = await _tripService.publishFinalPost(_tripId!);

    _isPublishing = false;

    if (response.success) {
      await loadDraft(_tripId!);
      return true;
    } else {
      _error = response.error ?? 'Failed to publish final post';
      notifyListeners();
      return false;
    }
  }

  void _scheduleAutoSave() {
    if (_tripId == null || _pendingUpdates.isEmpty) return;
    _debouncer.run(() {
      _persistUpdates();
    });
  }

  Future<bool> _persistUpdates({bool force = false}) async {
    if (_tripId == null || _pendingUpdates.isEmpty) return true;

    if (!force) {
      _isSaving = true;
      notifyListeners();
    }

    final updates = Map<String, dynamic>.from(_pendingUpdates);
    final response = await _tripService.updateFinalPost(
      _tripId!,
      updates,
    );

    _isSaving = false;

    if (response.success && response.data != null) {
      _draft = response.data;
      for (final key in updates.keys) {
        _pendingUpdates.remove(key);
      }
      notifyListeners();
      return true;
    } else {
      _error = response.error ?? 'Failed to save draft';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }
}


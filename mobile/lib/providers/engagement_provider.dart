import 'package:flutter/foundation.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/services/like_service.dart';
import 'package:tripthread/utils/error_handler.dart';

class EngagementProvider extends ChangeNotifier {
  final LikeService _likeService;

  EngagementProvider({required LikeService likeService})
      : _likeService = likeService;

  final Map<String, bool> _likeStatus = {};
  final Map<String, int> _likeCounts = {};
  final Map<String, bool> _isToggling = {};
  final Map<String, List<User>> _likeUsers = {};
  final Map<String, bool> _isLoadingUsers = {};
  String? _error;

  Map<String, bool> get likeStatus => Map.unmodifiable(_likeStatus);
  Map<String, int> get likeCounts => Map.unmodifiable(_likeCounts);
  String? get error => _error;
  bool isToggling(String entityId) => _isToggling[entityId] ?? false;
  List<User> getLikeUsersList(String entityId) => _likeUsers[entityId] ?? [];
  bool isLoadingUsers(String entityId) => _isLoadingUsers[entityId] ?? false;

  bool isLiked(String entityId) => _likeStatus[entityId] ?? false;
  int getLikeCount(String entityId) => _likeCounts[entityId] ?? 0;

  void setLikeStatus(String entityId, bool liked, {int? count}) {
    _likeStatus[entityId] = liked;
    if (count != null) {
      _likeCounts[entityId] = count;
    } else if (liked) {
      _likeCounts[entityId] = (_likeCounts[entityId] ?? 0) + 1;
    } else {
      _likeCounts[entityId] = (_likeCounts[entityId] ?? 1) - 1;
      if (_likeCounts[entityId]! < 0) {
        _likeCounts[entityId] = 0;
      }
    }
    notifyListeners();
  }

  void setLikeCount(String entityId, int count) {
    _likeCounts[entityId] = count;
    notifyListeners();
  }

  Future<void> toggleLike(String entityType, String entityId) async {
    if (_isToggling[entityId] == true) {
      debugPrint('[EngagementProvider] Already toggling like for $entityId');
      return;
    }

    final previousLiked = _likeStatus[entityId] ?? false;
    final previousCount = _likeCounts[entityId] ?? 0;

    _isToggling[entityId] = true;
    _error = null;
    setLikeStatus(entityId, !previousLiked, count: null);
    notifyListeners();

    try {
      await _likeService.toggleLike(entityType, entityId);
      _isToggling[entityId] = false;
      notifyListeners();
    } catch (e) {
      _isToggling[entityId] = false;
      _error = ErrorHandler.handleError(e).message;
      _likeStatus[entityId] = previousLiked;
      _likeCounts[entityId] = previousCount;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> getLikeUsers(
    String entityType,
    String entityId,
    int page,
  ) async {
    final cacheKey = '$entityType:$entityId';
    if (_isLoadingUsers[cacheKey] == true) {
      return;
    }

    _isLoadingUsers[cacheKey] = true;
    _error = null;
    notifyListeners();

    try {
      final users = await _likeService.getLikeUsers(entityType, entityId, page);
      if (page == 1) {
        _likeUsers[cacheKey] = users;
      } else {
        _likeUsers[cacheKey] = [...(_likeUsers[cacheKey] ?? []), ...users];
      }
      _isLoadingUsers[cacheKey] = false;
      notifyListeners();
    } catch (e) {
      _isLoadingUsers[cacheKey] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> checkLikeStatus(
    List<String> entityIds,
    String entityType,
  ) async {
    try {
      final statusMap = await _likeService.checkLikeStatus(entityIds, entityType);
      for (final entry in statusMap.entries) {
        _likeStatus[entry.key] = entry.value;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[EngagementProvider] checkLikeStatus error: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear all engagement state. Call on logout so the next user's feed
  /// and like state are not mixed with the previous user's cached data.
  void clear() {
    _likeStatus.clear();
    _likeCounts.clear();
    _isToggling.clear();
    _likeUsers.clear();
    _isLoadingUsers.clear();
    _error = null;
    notifyListeners();
  }
}


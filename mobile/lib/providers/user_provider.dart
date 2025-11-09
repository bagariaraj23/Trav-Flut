import 'package:flutter/foundation.dart';
import 'package:tripthread/models/follow_status.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/services/api_service.dart';

class FollowStatus {
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isRequestPending;
  final bool isPrivate;
  final String? requestId;
  final String? requestStatus;

  FollowStatus({
    this.isFollowing = false,
    this.isFollowedBy = false,
    this.isRequestPending = false,
    this.isPrivate = false,
    this.requestId,
    this.requestStatus,
  });

  factory FollowStatus.fromJson(Map<String, dynamic> json) {
    return FollowStatus(
      isFollowing: json['isFollowing'] ?? false,
      isFollowedBy: json['isFollowedBy'] ?? false,
      isRequestPending: json['isRequestPending'] ?? false,
      isPrivate: json['isPrivate'] ?? false,
      requestId: json['requestId'],
      requestStatus: json['requestStatus'],
    );
  }
}

class DetailedFollowStatus {
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isRequestPending;
  final bool isPrivate;
  final String? requestId;
  final String? requestStatus;

  DetailedFollowStatus({
    this.isFollowing = false,
    this.isFollowedBy = false,
    this.isRequestPending = false,
    this.isPrivate = false,
    this.requestId,
    this.requestStatus,
  });

  factory DetailedFollowStatus.fromJson(Map<String, dynamic> json) {
    return DetailedFollowStatus(
      isFollowing: json['isFollowing'] ?? false,
      isFollowedBy: json['isFollowedBy'] ?? false,
      isRequestPending: json['isRequestPending'] ?? false,
      isPrivate: json['isPrivate'] ?? false,
      requestId: json['requestId'],
      requestStatus: json['requestStatus'],
    );
  }

  Map<String, dynamic> toJson() => {
        'isFollowing': isFollowing,
        'isFollowedBy': isFollowedBy,
        'isRequestPending': isRequestPending,
        'isPrivate': isPrivate,
        'requestId': requestId,
        'requestStatus': requestStatus,
      };
}

class UserProvider extends ChangeNotifier {
  final ApiService _apiService;
  String? _followRequestsError;
  String? isProcessingRequestId;

  UserProvider({required ApiService apiService}) : _apiService = apiService;

  Future<User?> getCurrentUser() async {
    try {
      final response = await _apiService.getCurrentUser();
      if (response.success && response.data != null) {
        _userCache[response.data!.id] = response.data!;
        notifyListeners();
        return response.data;
      }
      return null;
    } catch (e) {
      debugPrint('Get current user error: $e');
      return null;
    }
  }

  // --- STATE ---
  final Map<String, User?> _userCache = {};
  final Map<String, UserStats?> _statsCache = {};
  final Map<String, DetailedFollowStatus?> _detailedFollowStatusCache = {};
  final List<FollowRequestDto> _pendingFollowRequests = [];

  final List<Map<String, dynamic>> _discoverUsers = [];
  bool _isLoading = false;
  bool _isDiscoverLoading = false;
  bool _isFollowRequestsLoading = false;
  String? _error;
  String? _discoverError;
  int _discoverPage = 1;
  bool _hasMoreUsers = true;

  // --- GETTERS ---
  bool get isLoading => _isLoading;
  bool get isDiscoverLoading => _isDiscoverLoading;
  bool get isFollowRequestsLoading => _isFollowRequestsLoading;
  String? get error => _error;
  String? get discoverError => _discoverError;
  List<Map<String, dynamic>> get discoverUsers => _discoverUsers;
  bool get hasMoreUsers => _hasMoreUsers;
  List<FollowRequestDto> get pendingFollowRequests => _pendingFollowRequests;
  String? get followRequestsError => _followRequestsError;

  User? getUser(String userId) => _userCache[userId];
  UserStats? getUserStats(String userId) => _statsCache[userId];
  DetailedFollowStatus? getDetailedFollowStatus(String userId) =>
      _detailedFollowStatusCache[userId];

  // --- METHODS ---
  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> loadProfileData(String userId, String currentUserId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await Future.wait([
        fetchUser(userId),
        fetchUserStats(userId),
        fetchDetailedFollowStatus(userId),
        if (userId == currentUserId) loadPendingFollowRequests(),
      ]);
    } catch (e) {
      _error =
          "Failed to load profile data:  [31m]"; // short for demo, replace as needed
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<User?> fetchUser(String userId) async {
    try {
      final response = await _apiService.getUser(userId);
      if (response.success && response.data != null) {
        _userCache[userId] = response.data!;
        notifyListeners();
        return response.data;
      } else {
        _error = response.error ?? 'Failed to fetch user';
        notifyListeners();
      }
    } catch (e) {
      _error = 'An unexpected error occurred while fetching user.';
      notifyListeners();
      debugPrint('Fetch user error: $e');
    }
    return null;
  }

  Future<UserStats?> fetchUserStats(String userId) async {
    try {
      final response = await _apiService.getUserStats(userId);
      if (response.success && response.data != null) {
        _statsCache[userId] = response.data!;
        notifyListeners();
        return response.data;
      }
    } catch (e) {
      debugPrint('Fetch user stats error: $e');
    }
    return null;
  }

  Future<DetailedFollowStatus?> fetchDetailedFollowStatus(String userId) async {
    try {
      final response = await _apiService.getDetailedFollowStatus(userId);
      if (response.success && response.data != null) {
        final status = DetailedFollowStatus.fromJson(response.data!.toJson());
        _detailedFollowStatusCache[userId] = status;
        notifyListeners();
        return status;
      }
    } catch (e) {
      _error = "Failed to fetch follow status";
      notifyListeners();
      debugPrint('Fetch detailed follow status error: $e');
    }
    return null;
  }

  Future<void> loadPendingFollowRequests() async {
    _isFollowRequestsLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.getPendingFollowRequests();
      if (response.success && response.data != null) {
        _pendingFollowRequests.clear();
        _pendingFollowRequests.addAll(response.data!);
      } else {
        _followRequestsError =
            response.error ?? "Failed to load follow requests";
      }
    } catch (e) {
      _followRequestsError =
          "An unexpected error occurred while loading requests.";
      debugPrint('Load pending follow requests error: $e');
    } finally {
      _isFollowRequestsLoading = false;
      notifyListeners();
    }
  }

  // --- ACTIONS (Follow, Unfollow, Requests) ---
  Future<bool> sendFollowRequest(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
      final response = await _apiService.followUser(userId);
      if (response.success) {
        await fetchDetailedFollowStatus(userId);
        notifyListeners();
        return true;
      } else {
        _followRequestsError =
            response.error ?? 'Failed to send follow request';
        return false;
      }
    } catch (e) {
      _followRequestsError = 'Failed to send follow request';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> followUser(String userId, {String? currentUserId}) async {
    return sendFollowRequest(userId);
  }

  Future<bool> unfollowUser(String userId, {String? currentUserId}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      final response = await _apiService.unfollowUser(userId);
      if (response.success) {
        await fetchDetailedFollowStatus(userId);
        if (currentUserId != null) {
          await fetchUserStats(currentUserId);
        }
        await fetchUserStats(userId);
        notifyListeners();
        return true;
      }
      _error = response.error ?? 'Failed to unfollow user';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelFollowRequest(String userId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      final response = await _apiService.unfollowUser(userId);
      if (response.success) {
        await fetchDetailedFollowStatus(userId);
        notifyListeners();
        return true;
      }
      _error = response.error ?? 'Failed to cancel request';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to cancel request';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> acceptFollowRequest(String requestId) async {
    try {
      _isFollowRequestsLoading = true;
      isProcessingRequestId = requestId;
      notifyListeners();
      final response = await _apiService.acceptFollowRequest(requestId);
      if (response.success) {
        _pendingFollowRequests
            .removeWhere((request) => request.id == requestId);
        notifyListeners();
        return true;
      }
      _followRequestsError =
          response.error ?? 'Failed to accept follow request';
      return false;
    } catch (e) {
      _followRequestsError = 'Failed to accept follow request';
      return false;
    } finally {
      _isFollowRequestsLoading = false;
      isProcessingRequestId = null;
      notifyListeners();
    }
  }

  Future<bool> rejectFollowRequest(String requestId) async {
    try {
      _isFollowRequestsLoading = true;
      isProcessingRequestId = requestId;
      notifyListeners();
      final response = await _apiService.rejectFollowRequest(requestId);
      if (response.success) {
        _pendingFollowRequests
            .removeWhere((request) => request.id == requestId);
        notifyListeners();
        return true;
      }
      _followRequestsError =
          response.error ?? 'Failed to reject follow request';
      return false;
    } catch (e) {
      _followRequestsError = 'Failed to reject follow request';
      return false;
    } finally {
      isProcessingRequestId = null;
      _isFollowRequestsLoading = false;
      notifyListeners();
    }
  }

  // --- Discover Functions ---
  Future<void> searchUsers(
      {String? search,
      bool refresh = false,
      bool prioritizeFollowed = false}) async {
    if (refresh) {
      _discoverPage = 1;
      _discoverUsers.clear();
      _hasMoreUsers = true;
    }
    if (_isDiscoverLoading || !_hasMoreUsers) return;
    _isDiscoverLoading = true;
    notifyListeners();
    try {
      final response = await _apiService.searchUsers(
        search: search,
        page: _discoverPage,
        prioritizeFollowed: prioritizeFollowed,
      );
      if (response.success && response.data != null) {
        _discoverUsers.addAll(response.data!);
        const int pageSize = 20;
        _hasMoreUsers = response.data!.length == pageSize;
        if (_hasMoreUsers) {
          _discoverPage++;
        }
      } else {
        _discoverError = response.error ?? "Failed to search users";
      }
    } catch (e) {
      _discoverError = "An error occurred while searching users";
    } finally {
      _isDiscoverLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile(
      {required String userId,
      String? name,
      String? username,
      String? bio,
      String? avatarUrl,
      bool? isPrivate}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      final response = await _apiService.updateProfile(
        name: name,
        username: username,
        bio: bio,
        avatarUrl: avatarUrl,
        isPrivate: isPrivate,
      );
      if (response.success && response.data != null) {
        _userCache[userId] = response.data!;
        notifyListeners();
        return true;
      }
      _error = response.error ?? 'Failed to update profile';
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Discover Methods ---
  void updateFollowStatus(String userId, bool isFollowing) {
    final index = _discoverUsers.indexWhere((user) => user['id'] == userId);
    if (index != -1) {
      _discoverUsers[index]['isFollowing'] = isFollowing;
    }
    _detailedFollowStatusCache[userId] = DetailedFollowStatus(
      isFollowing: isFollowing,
      isFollowedBy: _detailedFollowStatusCache[userId]?.isFollowedBy ?? false,
      isRequestPending: false,
      isPrivate: _detailedFollowStatusCache[userId]?.isPrivate ?? false,
    );
    notifyListeners();
  }

  void clearDiscoverError() {
    _discoverError = null;
    notifyListeners();
  }

  void resetDiscover() {
    _discoverUsers.clear();
    _discoverPage = 1;
    _hasMoreUsers = true;
    _discoverError = null;
    notifyListeners();
  }

  bool isUserPrivate(String userId) {
    final user = _userCache[userId];
    return user?.isPrivate ?? false;
  }

  void clearCache() {
    _userCache.clear();
    _statsCache.clear();
    _detailedFollowStatusCache.clear();
    _pendingFollowRequests.clear();
    notifyListeners();
  }
}

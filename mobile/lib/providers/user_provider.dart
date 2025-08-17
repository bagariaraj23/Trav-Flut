import 'package:flutter/foundation.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/services/api_service.dart';

class UserProvider extends ChangeNotifier {
  final ApiService _apiService;

  UserProvider({required ApiService apiService}) : _apiService = apiService;

  final Map<String, User> _userCache = {};
  final Map<String, UserStats> _statsCache = {};
  final Map<String, bool> _followStatusCache = {};
  final List<DiscoverUser> _discoverUsers = [];
  final List<FollowRequest> _followRequests = [];
  bool _isLoading = false;
  bool _isDiscoverLoading = false;
  bool _isFollowRequestsLoading = false;
  String? _error;
  String? _discoverError;
  String? _followRequestsError;
  int _discoverPage = 1;
  int _followRequestsPage = 1;
  bool _hasMoreUsers = true;
  bool _hasMoreFollowRequests = true;

  // Getters
  bool get isLoading => _isLoading;
  bool get isDiscoverLoading => _isDiscoverLoading;
  bool get isFollowRequestsLoading => _isFollowRequestsLoading;
  String? get error => _error;
  String? get discoverError => _discoverError;
  String? get followRequestsError => _followRequestsError;
  bool isFollowing(String userId) => _followStatusCache[userId] ?? false;
  List<DiscoverUser> get discoverUsers => _discoverUsers;
  List<FollowRequest> get followRequests => _followRequests;
  bool get hasMoreUsers => _hasMoreUsers;
  bool get hasMoreFollowRequests => _hasMoreFollowRequests;

  User? getUser(String userId) => _userCache[userId];
  UserStats? getUserStats(String userId) => _statsCache[userId];

  Future<User?> fetchUser(String userId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _apiService.getUser(userId);

      if (response.success && response.data != null) {
        _userCache[userId] = response.data!;
        _isLoading = false;
        notifyListeners();
        return response.data;
      } else {
        _error = response.error ?? 'Failed to fetch user';
        _isLoading = false;
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Fetch user error: $e');
      return null;
    }
  }

  Future<UserStats?> fetchUserStats(String userId) async {
    try {
      final response = await _apiService.getUserStats(userId);

      if (response.success && response.data != null) {
        _statsCache[userId] = response.data!;
        notifyListeners();
        return response.data;
      } else {
        _error = response.error ?? 'Failed to fetch user stats';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      notifyListeners();
      debugPrint('Fetch user stats error: $e');
      return null;
    }
  }

  Future<bool> updateProfile({
    required String userId,
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _apiService.updateProfile(
        userId: userId,
        name: name,
        username: username,
        bio: bio,
        avatarUrl: avatarUrl,
        isPrivate: isPrivate,
      );

      if (response.success && response.data != null) {
        _userCache[userId] = response.data!;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to update profile';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Update profile error: $e');
      return false;
    }
  }

  Future<bool> togglePrivacy(String userId) async {
    try {
      final response = await _apiService.togglePrivacy(userId);

      if (response.success && response.data != null) {
        _userCache[userId] = response.data!;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to toggle privacy';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      notifyListeners();
      debugPrint('Toggle privacy error: $e');
      return false;
    }
  }

  Future<bool> fetchFollowStatus(String userId) async {
    try {
      final response = await _apiService.getFollowStatus(userId);

      if (response.success) {
        _followStatusCache[userId] = response.data ?? false;
        notifyListeners();
        return response.data ?? false;
      } else {
        _followStatusCache[userId] = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _followStatusCache[userId] = false;
      notifyListeners();
      debugPrint('Fetch follow status error: $e');
      return false;
    }
  }

  Future<void> searchUsers({String? search, bool refresh = false}) async {
    try {
      if (refresh) {
        _discoverPage = 1;
        _discoverUsers.clear();
        _hasMoreUsers = true;
        _discoverError = null;
      }

      if (!_hasMoreUsers) return;

      _isDiscoverLoading = true;
      notifyListeners();

      final response = await _apiService.searchUsers(
        search: search,
        page: _discoverPage,
        limit: 20,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        final users = (data['items'] as List<dynamic>)
            .map((json) => DiscoverUser.fromJson(json))
            .toList();
        final hasNext = data['hasNext'] as bool;

        if (refresh) {
          _discoverUsers.clear();
        }

        _discoverUsers.addAll(users);
        _hasMoreUsers = hasNext;
        _discoverPage++;
        _discoverError = null;
      } else {
        _discoverError = response.error ?? 'Failed to fetch users';
      }
    } catch (e) {
      _discoverError = 'An unexpected error occurred';
      debugPrint('Search users error: $e');
    } finally {
      _isDiscoverLoading = false;
      notifyListeners();
    }
  }

  // Follow request methods
  Future<void> fetchFollowRequests({
    String type = 'received',
    bool refresh = false,
  }) async {
    try {
      if (refresh) {
        _followRequestsPage = 1;
        _followRequests.clear();
        _hasMoreFollowRequests = true;
        _followRequestsError = null;
      }

      if (!_hasMoreFollowRequests) return;

      _isFollowRequestsLoading = true;
      notifyListeners();

      final response = await _apiService.getFollowRequests(
        type: type,
        page: _followRequestsPage,
        limit: 20,
      );

      if (response.success && response.data != null) {
        if (refresh) {
          _followRequests.clear();
        }

        _followRequests.addAll(response.data!.items);
        _hasMoreFollowRequests = response.data!.hasNext;
        _followRequestsPage++;
        _followRequestsError = null;
      } else {
        _followRequestsError = response.error ?? 'Failed to fetch follow requests';
      }
    } catch (e) {
      _followRequestsError = 'An unexpected error occurred';
      debugPrint('Fetch follow requests error: $e');
    } finally {
      _isFollowRequestsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> respondToFollowRequest(String requestId, String action) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _apiService.respondToFollowRequest(requestId, action);

      if (response.success) {
        // Remove the request from the list
        _followRequests.removeWhere((request) => request.id == requestId);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to respond to follow request';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Respond to follow request error: $e');
      return false;
    }
  }

  Future<bool> cancelFollowRequest(String requestId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _apiService.cancelFollowRequest(requestId);

      if (response.success) {
        // Remove the request from the list
        _followRequests.removeWhere((request) => request.id == requestId);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to cancel follow request';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Cancel follow request error: $e');
      return false;
    }
  }

  void updateDiscoverUserFollowStatus(String userId, bool isFollowing, {String? followRequestStatus}) {
    final userIndex = _discoverUsers.indexWhere((user) => user.id == userId);
    if (userIndex != -1) {
      final user = _discoverUsers[userIndex];
      _discoverUsers[userIndex] = user.copyWith(
        isFollowing: isFollowing,
        followRequestStatus: followRequestStatus,
        hasRequestedToFollow: followRequestStatus == 'PENDING',
      );
    }
    _followStatusCache[userId] = isFollowing;
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

  void updateFollowStatus(String userId, bool isFollowing) {
    _followStatusCache[userId] = isFollowing;
    notifyListeners();
  }

  Future<bool> followUser(String userId, {String? currentUserId}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _apiService.followUser(userId);

      if (response.success) {
        // Update follow status cache
        _followStatusCache[userId] = true;

        // Refresh target user's stats
        await fetchUserStats(userId);

        // Refresh current user's stats if provided
        if (currentUserId != null) {
          await fetchUserStats(currentUserId);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to follow user';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      debugPrint('Follow user error: $e');
      return false;
    }
  }

  Future<bool> unfollowUser(String userId, {String? currentUserId}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _apiService.unfollowUser(userId);

      if (response.success) {
        // Update follow status cache
        _followStatusCache[userId] = false;

        // Refresh target user's stats
        await fetchUserStats(userId);

        // Refresh current user's stats if provided
        if (currentUserId != null) {
          await fetchUserStats(currentUserId);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response.error ?? 'Failed to unfollow user';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'An unexpected error occurred';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearFollowStatusCache() {
    _followStatusCache.clear();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearCache() {
    _userCache.clear();
    _statsCache.clear();
    notifyListeners();
  }

  // Method to refresh current user's stats after follow/unfollow actions
  Future<void> refreshCurrentUserStats(String currentUserId) async {
    await fetchUserStats(currentUserId);
  }
}

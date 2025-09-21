import 'package:dio/dio.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/follow_status.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/pagination.dart';
import 'package:tripthread/models/trip_join_request.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  final Dio _dio;
  StorageService? _storageService;
  VoidCallback? _onUnauthorized;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: AppConfig.defaultHeaders,
        )) {
    _setupInterceptors();
  }

  void setStorageService(StorageService storageService) {
    debugPrint('[ApiService] Setting storage service');
    _storageService = storageService;
  }

  void setUnauthorizedCallback(VoidCallback callback) {
    debugPrint('[ApiService] Setting unauthorized callback');
    _onUnauthorized = callback;
  }

  void _setupInterceptors() {
    debugPrint('[ApiService] Setting up interceptors');

    // Request interceptor to add auth token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        debugPrint('[ApiService] Request: ${options.method} ${options.path}');
        debugPrint('[ApiService] Request headers: ${options.headers}');
        if (options.data != null) {
          debugPrint('[ApiService] Request data: ${options.data}');
        }

        if (_storageService != null) {
          final token = await _storageService!.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
            debugPrint(
                '[ApiService] Added auth token: ${token.substring(0, 10)}...');
          } else {
            debugPrint('[ApiService] No auth token available');
          }
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint(
            '[ApiService] Response: ${response.statusCode} ${response.requestOptions.path}');
        debugPrint('[ApiService] Response data: ${response.data}');
        handler.next(response);
      },
      onError: (error, handler) async {
        debugPrint(
            '[ApiService] Error: ${error.type} ${error.response?.statusCode} ${error.requestOptions.path}');
        debugPrint('[ApiService] Error message: ${error.message}');
        if (error.response?.data != null) {
          debugPrint(
              '[ApiService] Error response data: ${error.response?.data}');
        }

        // Handle token refresh on 401
        if (error.response?.statusCode == 401 && _storageService != null) {
          debugPrint('[ApiService] Attempting token refresh...');
          final refreshToken = await _storageService!.getRefreshToken();
          if (refreshToken != null) {
            try {
              debugPrint('[ApiService] Calling refresh token endpoint');
              final response = await _dio.post('/auth/refresh-token', data: {
                'refreshToken': refreshToken,
              });

              if (response.statusCode == 200 &&
                  response.data['success'] == true) {
                final newToken = response.data['data']['accessToken'];
                await _storageService!.saveAccessToken(newToken);
                debugPrint('[ApiService] Token refreshed successfully');

                // Retry original request
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                debugPrint(
                    '[ApiService] Retrying original request with new token');
                final cloneReq = await _dio.fetch(opts);
                return handler.resolve(cloneReq);
              } else {
                debugPrint(
                    '[ApiService] Token refresh failed: ${response.data}');
                // Refresh failed, clear tokens and notify
                await _storageService!.clearTokens();
                if (_onUnauthorized != null) {
                  _onUnauthorized!();
                }
              }
            } catch (e) {
              debugPrint('[ApiService] Token refresh error: $e');
              // Refresh failed, clear tokens and notify
              await _storageService!.clearTokens();
              if (_onUnauthorized != null) {
                _onUnauthorized!();
              }
            }
          } else {
            debugPrint('[ApiService] No refresh token available');
            // No refresh token, clear tokens and notify
            await _storageService!.clearTokens();
            if (_onUnauthorized != null) {
              _onUnauthorized!();
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  // Auth endpoints
  Future<ApiResponse<AuthResponse>> signup({
    required String email,
    required String password,
    required String name,
    String? username,
  }) async {
    try {
      debugPrint(
          '[ApiService] Signup called with email: $email, name: $name, username: $username');
      final response = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'name': name,
        if (username != null) 'username': username,
      });

      debugPrint('[ApiService] Signup response: ${response.statusCode}');
      return ApiResponse<AuthResponse>(
        success: response.data['success'],
        data: AuthResponse.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Signup DioException: ${e.message}');
      return ApiResponse<AuthResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Signup unexpected error: $e');
      return ApiResponse<AuthResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<AuthResponse>> login({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('[ApiService] Login called with email: $email');
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      debugPrint('[ApiService] Login response: ${response.statusCode}');
      return ApiResponse<AuthResponse>(
        success: response.data['success'],
        data: AuthResponse.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Login DioException: ${e.message}');
      return ApiResponse<AuthResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Login unexpected error: $e');
      return ApiResponse<AuthResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> logout() async {
    try {
      debugPrint('[ApiService] Logout called');
      final response = await _dio.post('/auth/logout');
      debugPrint('[ApiService] Logout response: ${response.statusCode}');
      return ApiResponse<void>(
        success: response.data['success'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Logout DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Logout unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> forgotPassword({
    required String email,
  }) async {
    try {
      debugPrint('[ApiService] Forgot password called with email: $email');
      final response = await _dio.post('/auth/forgot-password', data: {
        'email': email,
      });

      debugPrint(
          '[ApiService] Forgot password response: ${response.statusCode}');
      debugPrint('[ApiService] Response data: ${response.data}');
      // Map 'ok' from backend to 'success' in ApiResponse, defaulting to false if missing
      final bool success =
          response.data['success'] ?? response.data['ok'] ?? false;
      return ApiResponse<void>(
        success: success,
        message: response.data['message'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Forgot password DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Forgot password unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      debugPrint('[ApiService] Reset password called');
      final response = await _dio.post('/auth/reset-password', data: {
        'token': token,
        'newPassword': newPassword,
      });

      debugPrint(
          '[ApiService] Reset password response: ${response.statusCode}');
      debugPrint('[ApiService] Response data: ${response.data}');
      final bool success =
          response.data['success'] ?? response.data['ok'] ?? false;
      return ApiResponse<void>(
        success: success,
        message: response.data['message'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Reset password DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Reset password unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // User endpoints
  Future<ApiResponse<User>> getCurrentUser() async {
    try {
      debugPrint('[ApiService] Getting current user');
      final response = await _dio.get('/users/me');
      debugPrint(
          '[ApiService] Get current user response: ${response.statusCode}');
      return ApiResponse<User>(
        success: response.data['success'],
        data: User.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Get current user DioException: ${e.message}');
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get current user unexpected error: $e');
      return ApiResponse<User>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<User>> getUser(String userId) async {
    try {
      debugPrint('[ApiService] Getting user: $userId');
      final response = await _dio.get('/users/$userId');
      debugPrint('[ApiService] Get user response: ${response.statusCode}');
      return ApiResponse<User>(
        success: response.data['success'],
        data: User.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Get user DioException: ${e.message}');
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get user unexpected error: $e');
      return ApiResponse<User>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<User>> updateProfile({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    try {
      debugPrint(
          '[ApiService] Updating profile: name=$name, username=$username, bio=$bio, avatarUrl=$avatarUrl');
      final response = await _dio.put('/users/me', data: {
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (isPrivate != null) 'isPrivate': isPrivate,
      });
      debugPrint(
          '[ApiService] Update profile response: ${response.statusCode}');
      return ApiResponse<User>(
        success: response.data['success'],
        data: User.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Update profile DioException: ${e.message}');
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Update profile unexpected error: $e');
      return ApiResponse<User>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<UserStats>> getUserStats(String userId) async {
    try {
      debugPrint('[ApiService] Getting stats for user: $userId');
      final response = await _dio.get('/users/$userId/stats');
      debugPrint(
          '[ApiService] Get user stats response: ${response.statusCode}');
      return ApiResponse<UserStats>(
        success: response.data['success'],
        data: UserStats.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Get user stats DioException: ${e.message}');
      return ApiResponse<UserStats>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get user stats unexpected error: $e');
      return ApiResponse<UserStats>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<User>> togglePrivacy(String userId) async {
    try {
      debugPrint('[ApiService] Toggling privacy for user: $userId');
      final response = await _dio.post('/users/$userId/privacy');
      debugPrint(
          '[ApiService] Toggle privacy response: ${response.statusCode}');
      return ApiResponse<User>(
        success: response.data['success'],
        data: User.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Toggle privacy DioException: ${e.message}');
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Toggle privacy unexpected error: $e');
      return ApiResponse<User>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<Map<String, dynamic>>>> searchUsers({
    String? search,
    int page = 1,
    int limit = 20,
    bool prioritizeFollowed = false,
  }) async {
    try {
      debugPrint(
          '[ApiService] Searching users: search=$search, page=$page, limit=$limit, prioritizeFollowed=$prioritizeFollowed');
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
        'prioritizeFollowed': prioritizeFollowed.toString(),
      };
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _dio.get('/users', queryParameters: queryParams);
      debugPrint('[ApiService] Search users response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final users = (data['items'] as List<dynamic>)
            .map((user) => Map<String, dynamic>.from(user))
            .toList();
        final hasNext = data['hasNext'] as bool;

        debugPrint(
            '[ApiService] Found ${users.length} users, hasNext: $hasNext');
        return ApiResponse<List<Map<String, dynamic>>>(
          success: true,
          data: users,
        );
      } else {
        debugPrint(
            '[ApiService] Search users failed: ${response.data['error']}');
        return ApiResponse<List<Map<String, dynamic>>>(
          success: false,
          error: response.data['error'] ?? 'Failed to search users',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Search users DioException: ${e.message}');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Search users unexpected error: $e');
      return ApiResponse<List<Map<String, dynamic>>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> followUser(String userId,
      {String? currentUserId}) async {
    try {
      debugPrint('[ApiService] Following user: $userId');
      final response = await _dio.post('/follow/$userId');
      debugPrint('[ApiService] Follow user response: ${response.statusCode}');
      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Follow user DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Follow user unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> unfollowUser(String userId,
      {String? currentUserId}) async {
    try {
      debugPrint('[ApiService] Unfollowing user: $userId');
      final response = await _dio.delete('/follow/$userId');
      debugPrint('[ApiService] Unfollow user response: ${response.statusCode}');
      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Unfollow user DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Unfollow user unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<PaginatedUsers>> getFollowers(String userId,
      {int page = 1, int limit = 20}) async {
    try {
      debugPrint('[ApiService] Getting followers for user: $userId');
      final response =
          await _dio.get('/users/$userId/followers', queryParameters: {
        'page': page,
        'limit': limit,
      });
      debugPrint('[ApiService] Get followers response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final users = (data['followers'] as List<dynamic>)
            .map((follower) => User.fromJson(follower))
            .toList();

        final paginatedUsers = PaginatedUsers(
          users: users,
          pagination: Pagination(
            page: data['pagination']['page'] as int,
            limit: data['pagination']['limit'] as int,
            total: data['pagination']['total'] as int,
            totalPages: data['pagination']['totalPages'] as int,
          ),
        );

        debugPrint(
            '[ApiService] Found ${users.length} followers (page ${paginatedUsers.pagination.page} of ${paginatedUsers.pagination.totalPages})');
        return ApiResponse<PaginatedUsers>(
          success: true,
          data: paginatedUsers,
        );
      } else {
        debugPrint(
            '[ApiService] Get followers failed: ${response.data['error']}');
        return ApiResponse<PaginatedUsers>(
          success: false,
          error: response.data['error'] ?? 'Failed to get followers',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get followers DioException: ${e.message}');
      return ApiResponse<PaginatedUsers>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get followers unexpected error: $e');
      return ApiResponse<PaginatedUsers>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<PaginatedUsers>> getFollowing(String userId,
      {int page = 1, int limit = 20}) async {
    try {
      debugPrint('[ApiService] Getting following for user: $userId');
      final response =
          await _dio.get('/users/$userId/following', queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
      });
      debugPrint('[ApiService] Get following response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final users = (data['following'] as List<dynamic>)
            .map((user) => User.fromJson(user))
            .toList();

        final paginatedUsers = PaginatedUsers(
          users: users,
          pagination: Pagination(
            page: data['pagination']['page'] as int,
            limit: data['pagination']['limit'] as int,
            total: data['pagination']['total'] as int,
            totalPages: data['pagination']['totalPages'] as int,
          ),
        );

        debugPrint(
            '[ApiService] Found ${users.length} following users (page ${paginatedUsers.pagination.page} of ${paginatedUsers.pagination.totalPages})');
        return ApiResponse<PaginatedUsers>(
          success: true,
          data: paginatedUsers,
        );
      } else {
        debugPrint(
            '[ApiService] Get following failed: ${response.data['error']}');
        return ApiResponse<PaginatedUsers>(
          success: false,
          error: response.data['error'] ?? 'Failed to get following users',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get following DioException: ${e.message}');
      return ApiResponse<PaginatedUsers>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get following unexpected error: $e');
      return ApiResponse<PaginatedUsers>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<FollowStatusResponse>> getFollowStatus(
      String userId) async {
    try {
      debugPrint('[ApiService] Getting follow status for user: $userId');
      final response = await _dio.get('/follow/$userId');
      debugPrint(
          '[ApiService] Get follow status response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final isFollowing = data['isFollowing'] as bool;

        final status = FollowStatusResponse(isFollowing: isFollowing);
        return ApiResponse<FollowStatusResponse>(success: true, data: status);
      } else {
        debugPrint(
            '[ApiService] Get follow status failed: ${response.data['error']}');
        return ApiResponse<FollowStatusResponse>(
            success: false,
            error: response.data['error'] ?? 'Failed to get follow status');
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get follow status DioException: ${e.message}');
      return ApiResponse<FollowStatusResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get follow status unexpected error: $e');
      return ApiResponse<FollowStatusResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<FollowStatusResponse>> getDetailedFollowStatus(
      String userId) async {
    try {
      debugPrint(
          '[ApiService] Getting detailed follow status for user: $userId');
      final response = await _dio.get('/follow/$userId');
      debugPrint(
          '[ApiService] Get detailed follow status response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final isFollowing = data['isFollowing'] as bool;
        final isFollowedBy = data['isFollowedBy'] as bool;
        final isRequestPending = data['isRequestPending'] as bool;
        final isPrivate = data['isPrivate'] as bool;

        final status = FollowStatusResponse(
          isFollowing: isFollowing,
          isFollowedBy: isFollowedBy,
          isRequestPending: isRequestPending,
          isPrivate: isPrivate,
        );
        return ApiResponse<FollowStatusResponse>(success: true, data: status);
      } else {
        debugPrint(
            '[ApiService] Get detailed follow status failed: ${response.data['error']}');
        return ApiResponse<FollowStatusResponse>(
            success: false,
            error: response.data['error'] ??
                'Failed to get detailed follow status');
      }
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Get detailed follow status DioException: ${e.message}');
      return ApiResponse<FollowStatusResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
          '[ApiService] Get detailed follow status unexpected error: $e');
      return ApiResponse<FollowStatusResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<FollowRequestDto>>> getPendingFollowRequests() async {
    try {
      debugPrint('[ApiService] Getting pending follow requests');
      final response = await _dio.get('/follow/requests');
      debugPrint(
          '[ApiService] Get pending follow requests response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests = requestsData
            .map((data) => FollowRequestDto.fromJson(data))
            .toList();
        return ApiResponse<List<FollowRequestDto>>(
          success: true,
          data: requests,
        );
      }

      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: 'Failed to get pending follow requests',
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Get pending follow requests DioException: ${e.message}');
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
          '[ApiService] Get pending follow requests unexpected error: $e');
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Trip endpoints
  Future<ApiResponse<Trip>> createTrip({
    required String title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    required List<String> destinations,
    String? mood,
    String? type,
    String? coverMediaUrl,
  }) async {
    try {
      debugPrint(
          '[ApiService] Creating trip: title=$title, destinations=$destinations');
      final data = {
        'title': title,
        if (description != null) 'description': description,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'destinations': destinations,
        if (mood != null) 'mood': mood,
        if (type != null) 'type': type,
        if (coverMediaUrl != null) 'coverMediaUrl': coverMediaUrl,
      };

      final response = await _dio.post('/trips', data: data);
      debugPrint('[ApiService] Create trip response: ${response.statusCode}');
      return ApiResponse<Trip>(
        success: response.data['success'],
        data: Trip.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Create trip DioException: ${e.message}');
      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Create trip unexpected error: $e');
      return ApiResponse<Trip>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Feed endpoints
  Future<ApiResponse<Map<String, dynamic>>> getHomeFeed({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('[ApiService] Getting home feed: page=$page, limit=$limit');
      final response = await _dio.get('/feed/home', queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
      });
      debugPrint('[ApiService] Get home feed response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data['data'] as Map<String, dynamic>,
        );
      } else {
        debugPrint(
            '[ApiService] Get home feed failed: ${response.data['error']}');
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get home feed',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get home feed DioException: ${e.message}');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get home feed unexpected error: $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<Trip>>> getUserTrips() async {
    try {
      debugPrint('[ApiService] Getting user trips');
      final response = await _dio.get('/trips');
      debugPrint(
          '[ApiService] Get user trips response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final trips = (data['items'] as List<dynamic>)
            .map((trip) => Trip.fromJson(trip))
            .toList();

        debugPrint('[ApiService] Found ${trips.length} user trips');
        return ApiResponse<List<Trip>>(
          success: true,
          data: trips,
        );
      } else {
        debugPrint(
            '[ApiService] Get user trips failed: ${response.data['error']}');
        return ApiResponse<List<Trip>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get user trips',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get user trips DioException: ${e.message}');
      return ApiResponse<List<Trip>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get user trips unexpected error: $e');
      return ApiResponse<List<Trip>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<Trip>> getTrip(String tripId) async {
    try {
      debugPrint('[ApiService] Getting trip: $tripId');
      final response = await _dio.get('/trips/$tripId');
      debugPrint('[ApiService] Get trip response: ${response.statusCode}');
      return ApiResponse<Trip>(
        success: response.data['success'],
        data: Trip.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Get trip DioException: ${e.message}');
      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get trip unexpected error: $e');
      return ApiResponse<Trip>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> endTrip(String tripId) async {
    try {
      debugPrint('[ApiService] Ending trip: $tripId');
      final response = await _dio.post('/trips/$tripId/end');
      debugPrint('[ApiService] End trip response: ${response.statusCode}');
      return ApiResponse<void>(
        success: response.data['success'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] End trip DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] End trip unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> publishFinalPost(String tripId) async {
    try {
      debugPrint('[ApiService] Publishing final post for trip: $tripId');
      final response = await _dio.post('/trips/$tripId/publish');
      debugPrint(
          '[ApiService] Publish final post response: ${response.statusCode}');
      return ApiResponse<void>(
        success: response.data['success'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Publish final post DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Publish final post unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripThreadEntry>>> getTripEntries(
      String tripId) async {
    try {
      debugPrint('[ApiService] Getting trip entries for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/entries');
      debugPrint(
          '[ApiService] Get trip entries response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final entries = (response.data['data'] as List)
            .map((json) =>
                TripThreadEntry.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('[ApiService] Found ${entries.length} trip entries');
        return ApiResponse<List<TripThreadEntry>>(
          success: true,
          data: entries,
        );
      } else {
        debugPrint(
            '[ApiService] Get trip entries failed: ${response.data['error']}');
        return ApiResponse<List<TripThreadEntry>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get trip entries',
          message: response.data['message'],
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get trip entries DioException: ${e.message}');
      return ApiResponse<List<TripThreadEntry>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get trip entries unexpected error: $e');
      return ApiResponse<List<TripThreadEntry>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripThreadEntry>>> getThreadEntries(
      String tripId) async {
    try {
      debugPrint('[ApiService] Getting thread entries for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/entries');
      debugPrint(
          '[ApiService] Get thread entries response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final entries = (response.data['data'] as List)
            .map((json) =>
                TripThreadEntry.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('[ApiService] Found ${entries.length} thread entries');
        return ApiResponse<List<TripThreadEntry>>(
          success: true,
          data: entries,
        );
      } else {
        debugPrint(
            '[ApiService] Get thread entries failed: ${response.data['error']}');
        return ApiResponse<List<TripThreadEntry>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get thread entries',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get thread entries DioException: ${e.message}');
      return ApiResponse<List<TripThreadEntry>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get thread entries unexpected error: $e');
      return ApiResponse<List<TripThreadEntry>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Add this method for manual refresh
  Future<ApiResponse<Map<String, dynamic>>> refreshAccessToken(
      String refreshToken) async {
    try {
      debugPrint('[ApiService] Refreshing access token');
      final response = await _dio.post('/auth/refresh-token', data: {
        'refreshToken': refreshToken,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('[ApiService] Token refresh successful');
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: Map<String, dynamic>.from(response.data['data']),
        );
      } else {
        debugPrint('[ApiService] Token refresh failed: ${response.data}');
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: response.data['error'] ?? 'Failed to refresh token',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Token refresh DioException: ${e.message}');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Token refresh unexpected error: $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'Unknown error occurred',
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getDiscoverTrips({
    int page = 1,
    int limit = 20,
    String? status,
    String? mood,
    bool includePrivate = false,
  }) async {
    try {
      debugPrint(
          '[ApiService] Getting discover trips: page=$page, limit=$limit, status=$status, mood=$mood');
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (mood != null) 'mood': mood,
        'includePrivate': includePrivate.toString(),
      };

      final response =
          await _dio.get('/discover/trips', queryParameters: queryParams);
      debugPrint(
          '[ApiService] Get discover trips response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data['data'] as Map<String, dynamic>,
        );
      } else {
        debugPrint(
            '[ApiService] Get discover trips failed: ${response.data['error']}');
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: response.data['error'] ?? 'Failed to load discover trips',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get discover trips DioException: ${e.message}');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get discover trips unexpected error: $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Follow request endpoints
  Future<ApiResponse<void>> sendFollowRequest(String userId) async {
    try {
      debugPrint('[ApiService] Sending follow request to user: $userId');
      final response = await _dio.post('/follow/requests', data: {
        'followeeId': userId,
      });
      debugPrint(
          '[ApiService] Send follow request response: ${response.statusCode}');

      // Both 200 (already pending) and 201 (newly created) are success cases
      if (response.statusCode == 200 || response.statusCode == 201) {
        return ApiResponse<void>(
          success: true,
          error: null,
        );
      } else {
        return ApiResponse<void>(
          success: false,
          error: response.data['error'] ?? 'Unknown error occurred',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Send follow request DioException: ${e.message}');

      // Handle the case where follow request already exists
      if (e.response?.statusCode == 400 &&
          e.response?.data['error'] == 'Follow request already pending') {
        return ApiResponse<void>(
          success: true,
          error: null,
        );
      }

      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Send follow request error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<FollowRequestDto>>> getFollowRequests() async {
    try {
      debugPrint('[ApiService] Getting follow requests');
      final response = await _dio.get('/follow/requests');
      debugPrint(
          '[ApiService] Get follow requests response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests = requestsData
            .map((data) => FollowRequestDto.fromJson(data))
            .toList();

        return ApiResponse<List<FollowRequestDto>>(
          success: true,
          data: requests,
        );
      } else {
        debugPrint(
            '[ApiService] Get follow requests failed: ${response.data['error']}');
        return ApiResponse<List<FollowRequestDto>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get follow requests',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get follow requests DioException: ${e.message}');
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get follow requests unexpected error: $e');
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> respondToFollowRequest(
      String userId, bool accept) async {
    try {
      debugPrint(
          '[ApiService] Responding to follow request from user: $userId with accept: $accept');

      // First get the request ID for this user
      final requestsResponse = await _dio.get('/follow/requests');
      if (requestsResponse.data['success'] &&
          requestsResponse.data['data'] != null) {
        final requests = requestsResponse.data['data'] as List<dynamic>;
        final request = requests.firstWhere(
          (r) => r['follower']['id'] == userId,
          orElse: () => null,
        );

        if (request != null) {
          final endpoint = accept
              ? '/follow/requests/${request['id']}/accept'
              : '/follow/requests/${request['id']}/reject';
          final response = await _dio.put(endpoint);
          debugPrint(
              '[ApiService] Respond to follow request response: ${response.statusCode}');

          return ApiResponse<void>(
            success: response.data['success'],
            error: response.data['error'],
          );
        } else {
          return ApiResponse<void>(
            success: false,
            error: 'No pending follow request found for this user',
          );
        }
      } else {
        return ApiResponse<void>(
          success: false,
          error: 'Failed to get follow requests',
        );
      }
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Respond to follow request DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Respond to follow request unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> cancelFollowRequest(String userId) async {
    try {
      debugPrint('[ApiService] Canceling follow request for user: $userId');
      // First get the request ID for this user
      final requestsResponse = await _dio.get('/follow/requests');
      if (requestsResponse.data['success'] &&
          requestsResponse.data['data'] != null) {
        final requests = requestsResponse.data['data'] as List<dynamic>;
        final request = requests.firstWhere(
          (r) => r['follower']['id'] == userId,
          orElse: () => null,
        );

        if (request != null) {
          final response = await _dio.delete('/follow/requests', data: {
            'requestId': request['id'],
          });
          debugPrint(
              '[ApiService] Cancel follow request response: ${response.statusCode}');

          return ApiResponse<void>(
            success: response.data['success'],
            error: response.data['error'],
          );
        } else {
          return ApiResponse<void>(
            success: false,
            error: 'No pending follow request found for this user',
          );
        }
      } else {
        return ApiResponse<void>(
          success: false,
          error: 'Failed to get follow requests',
        );
      }
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Cancel follow request DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Cancel follow request unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> acceptFollowRequest(String requestId) async {
    try {
      debugPrint('[ApiService] Accepting follow request: $requestId');
      final response = await _dio.put('/follow/requests/$requestId/accept');
      debugPrint(
          '[ApiService] Accept follow request response: ${response.statusCode}');

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Accept follow request DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Accept follow request unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> rejectFollowRequest(String requestId) async {
    try {
      debugPrint('[ApiService] Rejecting follow request: $requestId');
      final response = await _dio.put('/follow/requests/$requestId/reject');
      debugPrint(
          '[ApiService] Reject follow request response: ${response.statusCode}');

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Reject follow request DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Reject follow request unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Participant Management Methods
  Future<List<TripParticipant>> getTripParticipants(String tripId) async {
    try {
      debugPrint('[ApiService] Getting participants for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/participants');
      debugPrint(
          '[ApiService] Get participants response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final participants = response.data['data'] as List<dynamic>;
        return participants.map((p) => TripParticipant.fromJson(p)).toList();
      } else {
        throw Exception(response.data['error'] ?? 'Failed to get participants');
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get participants DioException: ${e.message}');
      throw Exception(e.response?.data['error'] ?? 'Network error occurred');
    } catch (e) {
      debugPrint('[ApiService] Get participants unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  Future<void> removeTripParticipant(String tripId, String userId) async {
    try {
      debugPrint(
          '[ApiService] Removing participant $userId from trip: $tripId');
      final response =
          await _dio.delete('/trips/$tripId/participants?userId=$userId');
      debugPrint(
          '[ApiService] Remove participant response: ${response.statusCode}');

      if (!response.data['success']) {
        throw Exception(
            response.data['error'] ?? 'Failed to remove participant');
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Remove participant DioException: ${e.message}');
      throw Exception(e.response?.data['error'] ?? 'Network error occurred');
    } catch (e) {
      debugPrint('[ApiService] Remove participant unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  // Trip Join Request Methods
  Future<ApiResponse<Map<String, dynamic>>> sendTripInvitation(
      String tripId, String receiverId) async {
    try {
      debugPrint(
          '[ApiService] Sending trip invitation to $receiverId for trip $tripId');
      final response = await _dio.post('/trips/$tripId/invites', data: {
        'receiverId': receiverId,
      });
      debugPrint(
          '[ApiService] Send trip invitation response: ${response.statusCode}');
      return ApiResponse<Map<String, dynamic>>(
        success: response.data['success'],
        data: response.data['data'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Send trip invitation DioException: ${e.message}');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Send trip invitation unexpected error: $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripJoinRequest>>> getPendingTripInvitations() async {
    try {
      debugPrint('[ApiService] Getting pending trip invitations');
      final response = await _dio.get('/users/me/trip-invites');
      debugPrint(
          '[ApiService] Get pending trip invitations response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests =
            requestsData.map((data) => TripJoinRequest.fromJson(data)).toList();
        return ApiResponse<List<TripJoinRequest>>(
          success: true,
          data: requests,
        );
      }
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: 'Failed to get pending trip invitations',
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Get pending trip invitations DioException: ${e.message}');
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
          '[ApiService] Get pending trip invitations unexpected error: $e');
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> respondToTripInvitation(
      String inviteId, bool accept) async {
    try {
      debugPrint(
          '[ApiService] Responding to trip invitation $inviteId with accept: $accept');
      final endpoint = accept
          ? '/trip-invites/$inviteId/accept'
          : '/trip-invites/$inviteId/reject';
      final response = await _dio.put(endpoint);
      debugPrint(
          '[ApiService] Respond to trip invitation response: ${response.statusCode}');

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Respond to trip invitation DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
          '[ApiService] Respond to trip invitation unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripJoinRequest>>> getSentTripInvitations(
      String tripId) async {
    try {
      debugPrint(
          '[ApiService] Getting sent trip invitations for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/invites');
      debugPrint(
          '[ApiService] Get sent trip invitations response: ${response.statusCode}');

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests =
            requestsData.map((data) => TripJoinRequest.fromJson(data)).toList();
        return ApiResponse<List<TripJoinRequest>>(
          success: true,
          data: requests,
        );
      }
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: 'Failed to get sent trip invitations',
      );
    } on DioException catch (e) {
      debugPrint(
          '[ApiService] Get sent trip invitations DioException: ${e.message}');
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get sent trip invitations unexpected error: $e');
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }
}

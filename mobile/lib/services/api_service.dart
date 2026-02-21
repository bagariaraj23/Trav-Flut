import 'package:dio/dio.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/api_response_with_place.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/follow_status.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/pagination.dart';
import 'package:tripthread/models/trip_join_request.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/token_refresh_manager.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  final Dio _dio;
  final Dio _refreshDio;
  StorageService? _storageService;
  VoidCallback? _onUnauthorized;

  ApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: AppConfig.defaultHeaders,
        ),
      ),
      _refreshDio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: AppConfig.connectTimeout,
          receiveTimeout: AppConfig.receiveTimeout,
          headers: AppConfig.defaultHeaders,
        ),
      ) {
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

  /// Wraps a network request with retry logic using RetryHandler.
  /// IMPORTANT: Only retries idempotent methods (GET, HEAD) to prevent
  /// duplicate mutations. POST/PUT/DELETE may have already committed
  /// their changes before the error response was sent.
  Future<T> _retryRequest<T>(
    Future<T> Function() request, {
    bool Function(dynamic error)? shouldRetry,
  }) async {
    return RetryHandler.retry<T>(
      request,
      maxRetries: 3,
      delay: const Duration(milliseconds: 500),
      retryIf: (error) {
        if (error is DioException) {
          // Only retry safe, idempotent methods to prevent data duplication.
          // POST/PUT/DELETE may have already committed on the server before
          // the error response was sent back to the client.
          final method = error.requestOptions.method.toUpperCase();
          if (method != 'GET' && method != 'HEAD') {
            return false;
          }

          // Don't retry auth endpoints
          final path = error.requestOptions.path;
          if (path.contains('/auth/login') ||
              path.contains('/auth/signup') ||
              path.contains('/auth/refresh-token') ||
              path.contains('/auth/forgot-password') ||
              path.contains('/auth/reset-password')) {
            return false;
          }

          // Retry on network errors and 5xx server errors
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError) {
            return true;
          }

          // Retry on 5xx server errors (but not 401 which is handled separately)
          if (error.response?.statusCode != null) {
            final statusCode = error.response!.statusCode!;
            if (statusCode >= 500 && statusCode < 600 && statusCode != 401) {
              return true;
            }
          }
        }

        // Use custom retry logic if provided
        if (shouldRetry != null) {
          return shouldRetry(error);
        }

        return false;
      },
    );
  }

  // Helper method to sanitize sensitive data from logs
  dynamic _sanitizeRequestData(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      final sanitized = Map<String, dynamic>.from(data);
      // Remove or mask sensitive fields
      if (sanitized.containsKey('password')) {
        sanitized['password'] = '***REDACTED***';
      }
      if (sanitized.containsKey('newPassword')) {
        sanitized['newPassword'] = '***REDACTED***';
      }
      if (sanitized.containsKey('currentPassword')) {
        sanitized['currentPassword'] = '***REDACTED***';
      }
      return sanitized;
    }

    return data;
  }

  void _setupInterceptors() {
    debugPrint('[ApiService] Setting up interceptors');

    // Request interceptor to add auth token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          debugPrint('[ApiService] Request: ${options.method} ${options.path}');
          debugPrint('[ApiService] Request headers: ${options.headers}');
          if (options.data != null) {
            final sanitizedData = _sanitizeRequestData(options.data);
            debugPrint('[ApiService] Request data: $sanitizedData');
          }

          if (_storageService != null) {
            final token = await _storageService!.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
              debugPrint(
                '[ApiService] Added auth token: ${token.substring(0, 10)}...',
              );
            } else {
              debugPrint('[ApiService] No auth token available');
            }
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[ApiService] Response: ${response.statusCode} ${response.requestOptions.path}',
          );
          debugPrint('[ApiService] Response data: ${response.data}');
          handler.next(response);
        },
        onError: (error, handler) async {
          debugPrint(
            '[ApiService] Error: ${error.type} ${error.response?.statusCode} ${error.requestOptions.path}',
          );
          debugPrint('[ApiService] Error message: ${error.message}');
          if (error.response?.data != null) {
            debugPrint(
              '[ApiService] Error response data: ${error.response?.data}',
            );
          }

          // Handle 401 Unauthorized
          if (error.response?.statusCode == 401 && _storageService != null) {
            final path = error.requestOptions.path;

            // Don't retry auth endpoints
            if (path.contains('/auth/login') ||
                path.contains('/auth/signup') ||
                path.contains('/auth/refresh-token') ||
                path.contains('/auth/forgot-password') ||
                path.contains('/auth/reset-password')) {
              debugPrint('[ApiService] 401 on auth endpoint, not retrying');
              return handler.next(error);
            }

            // Avoid infinite retry loops: only retry a request once
            final alreadyRetried =
                error.requestOptions.extra['retried'] == true;
            if (alreadyRetried) {
              debugPrint(
                '[ApiService] Request already retried, forcing logout',
              );
              await _storageService!.clearTokens();
              if (_onUnauthorized != null) {
                debugPrint(
                  '[ApiService] Calling unauthorized callback (already retried)',
                );
                _onUnauthorized!();
              } else {
                debugPrint('[ApiService] No unauthorized callback set!');
              }
              return handler.reject(error);
            }

            debugPrint('[ApiService] Attempting token refresh...');

            try {
              final newToken = await TokenRefreshManager.instance.refresh(
                storage: _storageService!,
                refreshClient: _refreshDio,
              );

              if (newToken != null && newToken.isNotEmpty) {
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                opts.extra['retried'] = true;
                debugPrint(
                  '[ApiService] Retrying original request with new token',
                );
                final cloneReq = await _dio.fetch(opts);
                return handler.resolve(cloneReq);
              }

              debugPrint(
                '[ApiService] Refresh did not yield a token, forcing logout',
              );
              await _storageService!.clearTokens();
              if (_onUnauthorized != null) {
                debugPrint(
                  '[ApiService] Calling unauthorized callback (refresh failed)',
                );
                _onUnauthorized!();
              } else {
                debugPrint('[ApiService] No unauthorized callback set!');
              }
              return handler.reject(error);
            } catch (e) {
              debugPrint('[ApiService] Token refresh error: $e');
              await _storageService!.clearTokens();
              if (_onUnauthorized != null) {
                debugPrint(
                  '[ApiService] Calling unauthorized callback (refresh failed)',
                );
                _onUnauthorized!();
              } else {
                debugPrint('[ApiService] No unauthorized callback set!');
              }
              return handler.reject(error);
            }
          }

          handler.next(error);
        },
      ),
    );
  }

  // Auth endpoints
  Future<ApiResponse<AuthResponse>> signup({
    required String email,
    required String password,
    required String name,
    required String username,
  }) async {
    try {
      debugPrint(
        '[ApiService] Signup called with email: $email, name: $name, username: $username',
      );
      final response = await _dio.post(
        '/auth/signup',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'username': username,
        },
      );

      debugPrint('[ApiService] Signup response: ${response.statusCode}');
      final data = response.data;
      final success = data['success'] == true;
      final payload = data['data'];
      if (success && payload != null) {
        return ApiResponse<AuthResponse>(
          success: true,
          data: AuthResponse.fromJson(payload),
        );
      }
      return ApiResponse<AuthResponse>(
        success: false,
        error:
            data['error'] ??
            data['message'] ??
            'Signup failed. Please try again.',
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Signup DioException: ${e.message}');
      final body = e.response?.data;
      final errorMsg = body is Map
          ? (body['error'] ?? body['message'] ?? 'Network error occurred')
          : 'Network error occurred';
      return ApiResponse<AuthResponse>(
        success: false,
        error: errorMsg is String ? errorMsg : 'Network error occurred',
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
    required String email, // Can be email or username
    required String password,
  }) async {
    try {
      debugPrint('[ApiService] Login called with email/username: $email');
      // Auth endpoints don't use retry (handled by interceptor)
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      debugPrint('[ApiService] Login response: ${response.statusCode}');
      return ApiResponse<AuthResponse>(
        success: response.data['success'],
        data: AuthResponse.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Login DioException: ${e.message}');
      final appException = ErrorHandler.handleError(e);
      return ApiResponse<AuthResponse>(
        success: false,
        error: appException.message,
      );
    } catch (e) {
      debugPrint('[ApiService] Login unexpected error: $e');
      return ApiResponse<AuthResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  /// Returns [AuthResponse] on success.
  Future<ApiResponse<AuthResponse>> signInWithGoogle(String idToken) async {
    try {
      debugPrint('[ApiService] Sign in with Google');
      final response = await _dio.post(
        '/auth/google',
        data: {'idToken': idToken},
      );
      debugPrint(
        '[ApiService] Sign in with Google response: ${response.statusCode}',
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        return const ApiResponse<AuthResponse>(
          success: false,
          error: 'Invalid response',
        );
      }
      final authData = data['data'];
      return ApiResponse<AuthResponse>(
        success: data['success'] == true,
        data: authData != null
            ? AuthResponse.fromJson(authData as Map<String, dynamic>)
            : null,
        error: data['error']?.toString(),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Sign in with Google DioException: ${e.message}');
      final body = e.response?.data;
      final error = body is Map ? body['error']?.toString() : null;
      return ApiResponse<AuthResponse>(
        success: false,
        error: error ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Sign in with Google unexpected error: $e');
      return const ApiResponse<AuthResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<AuthResponse>> completeProfile({
    required String username,
    required String password,
    String? name,
  }) async {
    try {
      debugPrint('[ApiService] Complete profile');
      final response = await _dio.post(
        '/auth/complete-profile',
        data: {
          'username': username,
          'password': password,
          if (name != null && name.isNotEmpty) 'name': name,
        },
      );
      debugPrint(
        '[ApiService] Complete profile response: ${response.statusCode}',
      );
      final data = response.data;
      return ApiResponse<AuthResponse>(
        success: data['success'] == true,
        data: data['data'] != null ? AuthResponse.fromJson(data['data']) : null,
        error: data['error'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Complete profile DioException: ${e.message}');
      return ApiResponse<AuthResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Complete profile unexpected error: $e');
      return ApiResponse<AuthResponse>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> linkGoogle(String idToken) async {
    try {
      debugPrint('[ApiService] Link Google');
      final response = await _dio.post(
        '/auth/link-google',
        data: {'idToken': idToken},
      );
      debugPrint('[ApiService] Link Google response: ${response.statusCode}');
      final data = response.data;
      return ApiResponse<void>(
        success: data['success'] == true,
        error: data['error'],
        message: data['message'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Link Google DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Link Google unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> logout({bool logoutAll = false}) async {
    try {
      debugPrint('[ApiService] Logout called (logoutAll: $logoutAll)');

      // Get refresh token from storage to revoke only the current session
      final refreshToken = _storageService?.getRefreshToken();
      final token = refreshToken != null ? await refreshToken : null;

      final response = await _dio.post(
        '/auth/logout',
        data: {
          if (token != null) 'refreshToken': token,
          if (logoutAll) 'logoutAll': true,
        },
      );
      debugPrint('[ApiService] Logout response: ${response.statusCode}');
      return ApiResponse<void>(success: response.data['success']);
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

  Future<ApiResponse<void>> deleteAccount() async {
    try {
      debugPrint('[ApiService] Delete account called');
      final response = await _dio.delete('/users/me');
      debugPrint(
        '[ApiService] Delete account response: ${response.statusCode}',
      );
      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Delete account DioException: ${e.message}');
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Delete account unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> forgotPassword({required String email}) async {
    try {
      debugPrint('[ApiService] Forgot password called with email: $email');
      final response = await _dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );

      debugPrint(
        '[ApiService] Forgot password response: ${response.statusCode}',
      );
      return ApiResponse<void>(
        success: response.data['ok'] ?? false,
        message: response.data['message'],
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
      final response = await _dio.post(
        '/auth/reset-password',
        data: {'token': token, 'newPassword': newPassword},
      );

      debugPrint(
        '[ApiService] Reset password response: ${response.statusCode}',
      );
      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['message'],
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
        '[ApiService] Get current user response: ${response.statusCode}',
      );
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
        '[ApiService] Updating profile: name=$name, username=$username, bio=${bio == null ? "null" : (bio.isEmpty ? "(empty)" : bio)}, avatarUrl=$avatarUrl',
      );
      final response = await _dio.put(
        '/users/me',
        data: {
          if (name != null) 'name': name,
          if (username != null) 'username': username,
          // Include bio when not null so backend can clear it (empty string => null)
          if (bio != null) 'bio': bio,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
          if (isPrivate != null) 'isPrivate': isPrivate,
        },
      );
      debugPrint(
        '[ApiService] Update profile response: ${response.statusCode}',
      );
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
        '[ApiService] Get user stats response: ${response.statusCode}',
      );
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
        '[ApiService] Toggle privacy response: ${response.statusCode}',
      );
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
        '[ApiService] Searching users: search=$search, page=$page, limit=$limit, prioritizeFollowed=$prioritizeFollowed',
      );
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
          '[ApiService] Found ${users.length} users, hasNext: $hasNext',
        );
        return ApiResponse<List<Map<String, dynamic>>>(
          success: true,
          data: users,
        );
      } else {
        debugPrint(
          '[ApiService] Search users failed: ${response.data['error']}',
        );
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

  Future<ApiResponse<void>> followUser(
    String userId, {
    String? currentUserId,
  }) async {
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

  Future<ApiResponse<void>> unfollowUser(
    String userId, {
    String? currentUserId,
  }) async {
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

  Future<ApiResponse<PaginatedUsers>> getFollowers(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('[ApiService] Getting followers for user: $userId');
      final response = await _dio.get(
        '/users/$userId/followers',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      debugPrint('[ApiService] Get followers response: ${response.statusCode}');
      debugPrint('[ApiService] Get followers response data: ${response.data}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        debugPrint('[ApiService] Followers data keys: ${data.keys}');
        debugPrint('[ApiService] Followers array: ${data['followers']}');

        // Handle both 'followers' and 'items' keys for compatibility
        final followersList = data['followers'] ?? data['items'] ?? [];
        final users = (followersList as List<dynamic>)
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
          '[ApiService] Found ${users.length} followers (page ${paginatedUsers.pagination.page} of ${paginatedUsers.pagination.totalPages})',
        );
        return ApiResponse<PaginatedUsers>(success: true, data: paginatedUsers);
      } else {
        debugPrint(
          '[ApiService] Get followers failed: ${response.data['error']}',
        );
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

  Future<ApiResponse<PaginatedUsers>> getFollowing(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('[ApiService] Getting following for user: $userId');
      final response = await _dio.get(
        '/users/$userId/following',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      debugPrint('[ApiService] Get following response: ${response.statusCode}');
      debugPrint('[ApiService] Get following response data: ${response.data}');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        debugPrint('[ApiService] Following data keys: ${data.keys}');
        debugPrint('[ApiService] Following array: ${data['following']}');

        // Handle both 'following' and 'items' keys for compatibility
        final followingList = data['following'] ?? data['items'] ?? [];
        final users = (followingList as List<dynamic>)
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
          '[ApiService] Found ${users.length} following users (page ${paginatedUsers.pagination.page} of ${paginatedUsers.pagination.totalPages})',
        );
        return ApiResponse<PaginatedUsers>(success: true, data: paginatedUsers);
      } else {
        debugPrint(
          '[ApiService] Get following failed: ${response.data['error']}',
        );
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
    String userId,
  ) async {
    try {
      debugPrint('[ApiService] Getting follow status for user: $userId');
      final response = await _dio.get('/follow/$userId');
      debugPrint(
        '[ApiService] Get follow status response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final isFollowing = data['isFollowing'] as bool;
        final isFollowedBy = data['isFollowedBy'] as bool? ?? false;
        final isRequestPending = data['isRequestPending'] as bool? ?? false;
        final isPrivate = data['isPrivate'] as bool? ?? false;

        final status = FollowStatusResponse(
          isFollowing: isFollowing,
          isFollowedBy: isFollowedBy,
          isRequestPending: isRequestPending,
          isPrivate: isPrivate,
        );
        return ApiResponse<FollowStatusResponse>(success: true, data: status);
      } else {
        debugPrint(
          '[ApiService] Get follow status failed: ${response.data['error']}',
        );
        return ApiResponse<FollowStatusResponse>(
          success: false,
          error: response.data['error'] ?? 'Failed to get follow status',
        );
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
    String userId,
  ) async {
    try {
      debugPrint(
        '[ApiService] Getting detailed follow status for user: $userId',
      );
      final response = await _dio.get('/follow/$userId');
      debugPrint(
        '[ApiService] Get detailed follow status response: ${response.statusCode}',
      );

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
          '[ApiService] Get detailed follow status failed: ${response.data['error']}',
        );
        return ApiResponse<FollowStatusResponse>(
          success: false,
          error:
              response.data['error'] ?? 'Failed to get detailed follow status',
        );
      }
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Get detailed follow status DioException: ${e.message}',
      );
      return ApiResponse<FollowStatusResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
        '[ApiService] Get detailed follow status unexpected error: $e',
      );
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
        '[ApiService] Get pending follow requests response: ${response.statusCode}',
      );

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
        '[ApiService] Get pending follow requests DioException: ${e.message}',
      );
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
        '[ApiService] Get pending follow requests unexpected error: $e',
      );
      return ApiResponse<List<FollowRequestDto>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Place endpoints
  Future<ApiResponse<List<Place>>> searchPlaces({
    required String query,
    double? lat,
    double? lng,
    String? placeType,
    int limit = 20,
  }) async {
    try {
      debugPrint(
        '[ApiService] Searching places: query=$query, lat=$lat, lng=$lng, limit=$limit',
      );
      // Use retry for place search (external Mapbox API)
      final response = await _retryRequest(
        () => _dio.get(
          '/places/search',
          queryParameters: {
            'q': query,
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            if (placeType != null) 'placeType': placeType,
            'limit': limit,
          },
        ),
      );

      if (response.data['success'] && response.data['data'] != null) {
        final places = (response.data['data'] as List)
            .map((json) => Place.fromJson(json))
            .toList();
        return ApiResponse<List<Place>>(success: true, data: places);
      } else {
        return ApiResponse<List<Place>>(
          success: false,
          error: response.data['error'] ?? 'Failed to search places',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Search places DioException: ${e.message}');
      return ApiResponse<List<Place>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<ApiResponseWithPlace>> resolvePlace(
    Place placeCandidate,
  ) async {
    try {
      debugPrint('[ApiService] Resolving place: ${placeCandidate.name}');

      // Validate place candidate has required fields
      if (placeCandidate.name.isEmpty) {
        return ApiResponse<ApiResponseWithPlace>(
          success: false,
          error: 'Place name is required',
        );
      }

      final response = await _dio.post(
        '/places/resolve',
        data: placeCandidate.toJson(),
      );

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];

        // Validate response structure - backend returns Place directly in data
        if (data is! Map<String, dynamic>) {
          debugPrint(
            '[ApiService] resolvePlace: Invalid data structure, expected Map',
          );
          return ApiResponse<ApiResponseWithPlace>(
            success: false,
            error: 'Invalid response format from server',
          );
        }

        // Validate required Place fields exist
        if (!data.containsKey('id') ||
            !data.containsKey('name') ||
            !data.containsKey('lat') ||
            !data.containsKey('lng')) {
          debugPrint(
            '[ApiService] resolvePlace: Missing required Place fields (id, name, lat, or lng)',
          );
          return ApiResponse<ApiResponseWithPlace>(
            success: false,
            error: 'Invalid response from server - missing place data',
          );
        }

        try {
          // Backend returns Place object directly, parse it as Place
          final place = Place.fromJson(data);
          debugPrint(
            '[ApiService] resolvePlace: Successfully parsed place: ${place.id}',
          );
          return ApiResponse<ApiResponseWithPlace>(
            success: true,
            data: ApiResponseWithPlace(
              success: true,
              placeId: place.id, // Use place.id from parsed Place
              place: place,
            ),
          );
        } catch (e, stackTrace) {
          debugPrint('[ApiService] resolvePlace: Failed to parse place: $e');
          debugPrint('[ApiService] Stack trace: $stackTrace');
          return ApiResponse<ApiResponseWithPlace>(
            success: false,
            error: 'Failed to parse place data: $e',
          );
        }
      } else {
        final errorMsg = response.data['error'] ?? 'Failed to resolve place';
        debugPrint('[ApiService] resolvePlace: API returned error: $errorMsg');
        return ApiResponse<ApiResponseWithPlace>(
          success: false,
          error: errorMsg,
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] resolvePlace DioException: ${e.message}');
      debugPrint('[ApiService] Response status: ${e.response?.statusCode}');
      debugPrint('[ApiService] Response data: ${e.response?.data}');

      String errorMsg = 'Network error occurred';
      if (e.response != null) {
        if (e.response!.statusCode == 400) {
          errorMsg = 'Invalid place data provided';
        } else if (e.response!.statusCode == 401) {
          errorMsg = 'Unauthorized - please login again';
        } else if (e.response!.statusCode == 429) {
          errorMsg = 'Too many requests - please try again later';
        } else if (e.response!.data != null &&
            e.response!.data['error'] != null) {
          errorMsg = e.response!.data['error'];
        } else {
          errorMsg = 'Server error (${e.response!.statusCode})';
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMsg = 'Connection timeout - please check your internet';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = 'No internet connection';
      }

      return ApiResponse<ApiResponseWithPlace>(success: false, error: errorMsg);
    } catch (e, stackTrace) {
      debugPrint('[ApiService] resolvePlace: Unexpected error: $e');
      debugPrint('[ApiService] Stack trace: $stackTrace');
      return ApiResponse<ApiResponseWithPlace>(
        success: false,
        error: 'An unexpected error occurred while resolving place',
      );
    }
  }

  Future<ApiResponse<List<MapPlace>>> getTripPlaces(String tripId) async {
    try {
      debugPrint('[ApiService] Getting places for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/places');

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];

        // Validate data is a List
        if (data is! List) {
          debugPrint(
            '[ApiService] getTripPlaces: Invalid data type, expected List',
          );
          return ApiResponse<List<MapPlace>>(
            success: false,
            error: 'Invalid response format from server',
          );
        }

        // Parse each MapPlace with validation
        final List<MapPlace> places = [];
        for (int i = 0; i < data.length; i++) {
          try {
            final item = data[i];

            // Validate required fields exist
            if (item is! Map<String, dynamic>) {
              debugPrint('[ApiService] getTripPlaces: Item $i is not a Map');
              continue;
            }

            if (!item.containsKey('place') || !item.containsKey('origin')) {
              debugPrint(
                '[ApiService] getTripPlaces: Item $i missing required fields (place or origin)',
              );
              continue;
            }

            // Validate place is a Map
            if (item['place'] is! Map<String, dynamic>) {
              debugPrint(
                '[ApiService] getTripPlaces: Item $i has invalid place structure',
              );
              continue;
            }

            final mapPlace = MapPlace.fromJson(item);
            places.add(mapPlace);
          } catch (e, stackTrace) {
            debugPrint(
              '[ApiService] getTripPlaces: Failed to parse item $i: $e',
            );
            debugPrint('[ApiService] Stack trace: $stackTrace');
            // Continue parsing other items instead of failing completely
            continue;
          }
        }

        debugPrint(
          '[ApiService] getTripPlaces: Successfully parsed ${places.length}/${data.length} places',
        );
        return ApiResponse<List<MapPlace>>(success: true, data: places);
      } else {
        final errorMsg = response.data['error'] ?? 'Failed to get trip places';
        debugPrint('[ApiService] getTripPlaces: API returned error: $errorMsg');
        return ApiResponse<List<MapPlace>>(success: false, error: errorMsg);
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] getTripPlaces DioException: ${e.message}');
      debugPrint('[ApiService] Response status: ${e.response?.statusCode}');
      debugPrint('[ApiService] Response data: ${e.response?.data}');

      String errorMsg = 'Network error occurred';
      if (e.response != null) {
        if (e.response!.statusCode == 404) {
          errorMsg = 'Trip not found';
        } else if (e.response!.statusCode == 401) {
          errorMsg = 'Unauthorized - please login again';
        } else if (e.response!.statusCode == 403) {
          errorMsg = 'Access denied to this trip';
        } else if (e.response!.data != null &&
            e.response!.data['error'] != null) {
          errorMsg = e.response!.data['error'];
        } else {
          errorMsg = 'Server error (${e.response!.statusCode})';
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMsg = 'Connection timeout - please check your internet';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = 'No internet connection';
      }

      return ApiResponse<List<MapPlace>>(success: false, error: errorMsg);
    } catch (e, stackTrace) {
      debugPrint('[ApiService] getTripPlaces: Unexpected error: $e');
      debugPrint('[ApiService] Stack trace: $stackTrace');
      return ApiResponse<List<MapPlace>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> attachPlaceToTrip(
    String tripId,
    String placeId, {
    DateTime? visitedAt,
    int? dayIndex,
    String? notes,
    bool createThreadEntry = false,
  }) async {
    try {
      debugPrint('[ApiService] Attaching place $placeId to trip: $tripId');
      final response = await _dio.post(
        '/trips/$tripId/places',
        data: {
          'placeId': placeId,
          if (visitedAt != null) 'visitedAt': visitedAt.toIso8601String(),
          if (dayIndex != null) 'dayIndex': dayIndex,
          if (notes != null) 'notes': notes,
          'createThreadEntry': createThreadEntry,
        },
      );

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Attach place to trip DioException: ${e.message}',
      );
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
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
    String? coverMediaId, // Link to Media model
  }) async {
    try {
      debugPrint(
        '[ApiService] Creating trip: title=$title, destinations=$destinations',
      );
      final data = {
        'title': title,
        if (description != null) 'description': description,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
        'destinations': destinations,
        if (mood != null) 'mood': mood,
        if (type != null) 'type': type,
        if (coverMediaId != null) 'coverMediaId': coverMediaId,
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

  // Media endpoints
  Future<ApiResponse<Map<String, dynamic>>> getCloudinarySignature({
    required String filename,
    required String contentType,
    String? tripId,
    String usage = 'general',
  }) async {
    try {
      debugPrint(
        '[ApiService] Getting Cloudinary signature for file: $filename, contentType: $contentType, tripId: $tripId, usage: $usage',
      );
      // Use retry for Cloudinary signature (important for media uploads)
      final response = await _retryRequest(
        () => _dio.post(
          '/media/cloudinary-signature',
          data: {
            'filename': filename,
            'contentType': contentType,
            if (tripId != null) 'tripId': tripId,
            'usage': usage,
          },
        ),
      );
      debugPrint(
        '[ApiService] Get Cloudinary signature response: ${response.statusCode}',
      );
      return ApiResponse<Map<String, dynamic>>(
        success: response.data['success'],
        data: response.data['data'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Get Cloudinary signature DioException: ${e.message}',
      );
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Get Cloudinary signature unexpected error: $e');
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<Media>> confirmMediaUpload({
    required String url,
    required String secureUrl,
    required String publicId,
    required String format,
    required String resourceType,
    required int bytes,
    required String originalFilename,
    String? tripId,
    String usage = 'general',
    int? width,
    int? height,
    num? duration,
  }) async {
    try {
      debugPrint('[ApiService] Confirming media upload: $publicId');
      // Use retry for media confirmation (important for uploads)
      final response = await _retryRequest(
        () => _dio.post(
          '/media/confirm',
          data: {
            'url': url,
            'secure_url': secureUrl,
            'public_id': publicId,
            'format': format,
            'resource_type': resourceType,
            'bytes': bytes,
            'original_filename': originalFilename,
            if (width != null) 'width': width,
            if (height != null) 'height': height,
            if (duration != null) 'duration': duration,
            if (tripId != null) 'tripId': tripId,
            'usage': usage,
          },
        ),
      );
      debugPrint(
        '[ApiService] Confirm media upload response: ${response.statusCode}',
      );
      return ApiResponse<Media>(
        success: response.data['success'],
        data: Media.fromJson(response.data['data']),
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Confirm media upload DioException: ${e.message}',
      );
      return ApiResponse<Media>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Confirm media upload unexpected error: $e');
      return ApiResponse<Media>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<void> deleteMediaAsset(String publicId) async {
    try {
      debugPrint('[ApiService] Deleting media asset: $publicId');
      // Use retry for media deletion (Cloudinary operation)
      await _retryRequest(
        () => _dio.post('/media/delete', data: {'publicId': publicId}),
      );
    } on DioException catch (e) {
      debugPrint('[ApiService] Delete media asset DioException: ${e.message}');
    } catch (e) {
      debugPrint('[ApiService] Delete media asset unexpected error: $e');
    }
  }

  // Feed endpoints
  Future<ApiResponse<Map<String, dynamic>>> getHomeFeed({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      debugPrint('[ApiService] Getting home feed: page=$page, limit=$limit');
      final response = await _dio.get(
        '/feed/home',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );
      debugPrint('[ApiService] Get home feed response: ${response.statusCode}');

      // Check if response is valid JSON
      if (response.data is! Map<String, dynamic>) {
        debugPrint(
          '[ApiService] Get home feed: Invalid response format (expected JSON)',
        );
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: 'Invalid server response format',
        );
      }

      if (response.data['success'] && response.data['data'] != null) {
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data['data'] as Map<String, dynamic>,
        );
      } else {
        debugPrint(
          '[ApiService] Get home feed failed: ${response.data['error']}',
        );
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: response.data['error'] ?? 'Failed to get home feed',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Get home feed DioException: ${e.message}');
      String errorMessage = 'Network error occurred';
      if (e.response?.data != null) {
        if (e.response!.data is Map<String, dynamic>) {
          errorMessage = e.response!.data['error'] ?? 'Network error occurred';
        } else if (e.response!.data is String) {
          // Server returned HTML error page (e.g., 500 error)
          errorMessage =
              'Server error (${e.response?.statusCode ?? 'unknown'})';
        }
      }
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: errorMessage,
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
        '[ApiService] Get user trips response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final data = response.data['data'];
        final trips = (data['items'] as List<dynamic>)
            .map((trip) => Trip.fromJson(trip))
            .toList();

        debugPrint('[ApiService] Found ${trips.length} user trips');
        return ApiResponse<List<Trip>>(success: true, data: trips);
      } else {
        debugPrint(
          '[ApiService] Get user trips failed: ${response.data['error']}',
        );
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
      return ApiResponse<void>(success: response.data['success']);
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
        '[ApiService] Publish final post response: ${response.statusCode}',
      );
      return ApiResponse<void>(success: response.data['success']);
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
    String tripId,
  ) async {
    try {
      debugPrint('[ApiService] Getting trip entries for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/entries');
      debugPrint(
        '[ApiService] Get trip entries response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final entries = (response.data['data'] as List)
            .map(
              (json) => TripThreadEntry.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        debugPrint('[ApiService] Found ${entries.length} trip entries');
        return ApiResponse<List<TripThreadEntry>>(success: true, data: entries);
      } else {
        debugPrint(
          '[ApiService] Get trip entries failed: ${response.data['error']}',
        );
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
    String tripId,
  ) async {
    try {
      debugPrint('[ApiService] Getting thread entries for trip: $tripId');
      final response = await _dio.get('/trips/$tripId/entries');
      debugPrint(
        '[ApiService] Get thread entries response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final entries = (response.data['data'] as List)
            .map(
              (json) => TripThreadEntry.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        debugPrint('[ApiService] Found ${entries.length} thread entries');
        return ApiResponse<List<TripThreadEntry>>(success: true, data: entries);
      } else {
        debugPrint(
          '[ApiService] Get thread entries failed: ${response.data['error']}',
        );
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

  Future<ApiResponse<Map<String, dynamic>>> refreshAccessToken(
    String refreshToken,
  ) async {
    try {
      debugPrint('[ApiService] Refreshing access token');
      final response = await _dio.post(
        '/auth/refresh-token',
        data: {'refreshToken': refreshToken},
      );
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
        '[ApiService] Getting discover trips: page=$page, limit=$limit, status=$status, mood=$mood',
      );
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (mood != null) 'mood': mood,
        'includePrivate': includePrivate.toString(),
      };

      final response = await _dio.get(
        '/discover/trips',
        queryParameters: queryParams,
      );
      debugPrint(
        '[ApiService] Get discover trips response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: response.data['data'] as Map<String, dynamic>,
        );
      } else {
        debugPrint(
          '[ApiService] Get discover trips failed: ${response.data['error']}',
        );
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
      final response = await _dio.post(
        '/follow/requests',
        data: {'followeeId': userId},
      );
      debugPrint(
        '[ApiService] Send follow request response: ${response.statusCode}',
      );

      // Both 200 (already pending) and 201 (newly created) are success cases
      if (response.statusCode == 200 || response.statusCode == 201) {
        return ApiResponse<void>(success: true, error: null);
      } else {
        return ApiResponse<void>(
          success: false,
          error: response.data['error'] ?? 'Unknown error occurred',
        );
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] Send follow request DioException: ${e.message}');

      if (e.response?.statusCode == 400 &&
          e.response?.data['error'] == 'Follow request already pending') {
        return ApiResponse<void>(success: true, error: null);
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
        '[ApiService] Get follow requests response: ${response.statusCode}',
      );

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
          '[ApiService] Get follow requests failed: ${response.data['error']}',
        );
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
    String userId,
    bool accept,
  ) async {
    try {
      debugPrint(
        '[ApiService] Responding to follow request from user: $userId with accept: $accept',
      );

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
            '[ApiService] Respond to follow request response: ${response.statusCode}',
          );

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
        '[ApiService] Respond to follow request DioException: ${e.message}',
      );
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
          final response = await _dio.delete(
            '/follow/requests',
            data: {'requestId': request['id']},
          );
          debugPrint(
            '[ApiService] Cancel follow request response: ${response.statusCode}',
          );

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
        '[ApiService] Cancel follow request DioException: ${e.message}',
      );
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
        '[ApiService] Accept follow request response: ${response.statusCode}',
      );

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Accept follow request DioException: ${e.message}',
      );
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
        '[ApiService] Reject follow request response: ${response.statusCode}',
      );

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Reject follow request DioException: ${e.message}',
      );
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
        '[ApiService] Get participants response: ${response.statusCode}',
      );

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
        '[ApiService] Removing participant $userId from trip: $tripId',
      );
      final response = await _dio.delete(
        '/trips/$tripId/participants?userId=$userId',
      );
      debugPrint(
        '[ApiService] Remove participant response: ${response.statusCode}',
      );

      if (!response.data['success']) {
        throw Exception(
          response.data['error'] ?? 'Failed to remove participant',
        );
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
    String tripId,
    String receiverId,
  ) async {
    try {
      debugPrint(
        '[ApiService] Sending trip invitation to $receiverId for trip $tripId',
      );
      final response = await _dio.post(
        '/trips/$tripId/invites',
        data: {'receiverId': receiverId},
      );
      debugPrint(
        '[ApiService] Send trip invitation response: ${response.statusCode}',
      );
      return ApiResponse<Map<String, dynamic>>(
        success: response.data['success'],
        data: response.data['data'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Send trip invitation DioException: ${e.message}',
      );
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
        '[ApiService] Get pending trip invitations response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests = requestsData
            .map((data) => TripJoinRequest.fromJson(data))
            .toList();
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
        '[ApiService] Get pending trip invitations DioException: ${e.message}',
      );
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
        '[ApiService] Get pending trip invitations unexpected error: $e',
      );
      return ApiResponse<List<TripJoinRequest>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<void>> respondToTripInvitation(
    String inviteId,
    bool accept,
  ) async {
    try {
      debugPrint(
        '[ApiService] Responding to trip invitation $inviteId with accept: $accept',
      );
      final endpoint = accept
          ? '/trip-invites/$inviteId/accept'
          : '/trip-invites/$inviteId/reject';
      final response = await _dio.put(endpoint);
      debugPrint(
        '[ApiService] Respond to trip invitation response: ${response.statusCode}',
      );

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Respond to trip invitation DioException: ${e.message}',
      );
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint(
        '[ApiService] Respond to trip invitation unexpected error: $e',
      );
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripJoinRequest>>> getSentTripInvitations(
    String tripId,
  ) async {
    try {
      debugPrint(
        '[ApiService] Getting sent trip invitations for trip: $tripId',
      );
      final response = await _dio.get('/trips/$tripId/invites');
      debugPrint(
        '[ApiService] Get sent trip invitations response: ${response.statusCode}',
      );

      if (response.data['success'] && response.data['data'] != null) {
        final List<dynamic> requestsData = response.data['data'];
        final requests = requestsData
            .map((data) => TripJoinRequest.fromJson(data))
            .toList();
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
        '[ApiService] Get sent trip invitations DioException: ${e.message}',
      );
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

  Future<ApiResponse<void>> cancelTripInvitation(
    String tripId,
    String inviteId,
  ) async {
    try {
      debugPrint(
        '[ApiService] Cancelling trip invitation $inviteId for trip: $tripId',
      );
      final response = await _dio.delete(
        '/trips/$tripId/invites',
        queryParameters: {'inviteId': inviteId},
      );
      debugPrint(
        '[ApiService] Cancel trip invitation response: ${response.statusCode}',
      );

      return ApiResponse<void>(
        success: response.data['success'],
        error: response.data['error'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      debugPrint(
        '[ApiService] Cancel trip invitation DioException: ${e.message}',
      );
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      debugPrint('[ApiService] Cancel trip invitation unexpected error: $e');
      return ApiResponse<void>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }
}

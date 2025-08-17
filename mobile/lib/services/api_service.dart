import 'package:dio/dio.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  // static const String baseUrl = 'http://localhost:3000/api';
  // static const String baseUrl = 'http://10.61.114.100:3000/api';
  static const String baseUrl = 'http://192.168.0.110:3000/api';
  // static const String baseUrl = 'http://192.168.0.111:3000/api';

  late final Dio _dio;
  StorageService? _storageService;
  VoidCallback? _onUnauthorized;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
      },
    ));

    _setupInterceptors();
  }

  void setStorageService(StorageService storageService) {
    _storageService = storageService;
  }

  void setUnauthorizedCallback(VoidCallback callback) {
    _onUnauthorized = callback;
  }

  void _setupInterceptors() {
    // Request interceptor to add auth token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_storageService != null) {
          final token = await _storageService!.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Handle token refresh on 401
        if (error.response?.statusCode == 401 && _storageService != null) {
          final refreshToken = await _storageService!.getRefreshToken();
          if (refreshToken != null) {
            try {
              final response = await _dio.post('/auth/refresh-token', data: {
                'refreshToken': refreshToken,
              });

              if (response.statusCode == 200 &&
                  response.data['success'] == true) {
                final newToken = response.data['data']['accessToken'];
                await _storageService!.saveAccessToken(newToken);

                // Retry original request
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final cloneReq = await _dio.fetch(opts);
                return handler.resolve(cloneReq);
              } else {
                // Refresh failed, clear tokens and notify
                await _storageService!.clearTokens();
                if (_onUnauthorized != null) {
                  _onUnauthorized!();
                }
              }
            } catch (e) {
              // Refresh failed, clear tokens and notify
              await _storageService!.clearTokens();
              if (_onUnauthorized != null) {
                _onUnauthorized!();
              }
            }
          } else {
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
      print(
          '[ApiService] signup called with email: $email, name: $name, username: $username');
      final response = await _dio.post('/auth/signup', data: {
        'email': email,
        'password': password,
        'name': name,
        if (username != null) 'username': username,
      });

      return ApiResponse<AuthResponse>.fromJson(
        response.data,
        (json) => AuthResponse.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      print('[ApiService] signup DioException: ${e.toString()}');
      print('[ApiService] signup DioException response: ${e.response?.data}');
      return ApiResponse<AuthResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<AuthResponse>> login({
    required String email,
    required String password,
  }) async {
    try {
      print('[ApiService] login called with email: $email');
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      return ApiResponse<AuthResponse>.fromJson(
        response.data,
        (json) => AuthResponse.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      print('[ApiService] login DioException: ${e.toString()}');
      print('[ApiService] login DioException response: ${e.response?.data}');
      return ApiResponse<AuthResponse>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<void>> logout(String refreshToken) async {
    try {
      final response = await _dio.post('/auth/logout', data: {
        'refreshToken': refreshToken,
      });

      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // User endpoints
  Future<ApiResponse<User>> getUser(String userId) async {
    try {
      final response = await _dio.get('/users/$userId');

      return ApiResponse<User>.fromJson(
        response.data,
        (json) => User.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<User>> updateProfile({
    required String userId,
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
    bool? isPrivate,
  }) async {
    try {
      final response = await _dio.put('/users/$userId', data: {
        if (name != null) 'name': name,
        if (username != null) 'username': username,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (isPrivate != null) 'isPrivate': isPrivate,
      });

      return ApiResponse<User>.fromJson(
        response.data,
        (json) => User.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<User>> togglePrivacy(String userId) async {
    try {
      final response = await _dio.patch('/users/$userId/privacy');

      return ApiResponse<User>.fromJson(
        response.data,
        (json) => User.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<User>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<UserStats>> getUserStats(String userId) async {
    try {
      final response = await _dio.get('/users/$userId/stats');

      return ApiResponse<UserStats>.fromJson(
        response.data,
        (json) => UserStats.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<UserStats>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // Follow endpoints
  Future<ApiResponse<void>> followUser(String userId) async {
    try {
      final response = await _dio.post('/follow/$userId');

      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<void>> unfollowUser(String userId) async {
    try {
      final response = await _dio.delete('/follow/$userId');

      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // Follow request endpoints
  Future<ApiResponse<PaginatedResponse<FollowRequest>>> getFollowRequests({
    String type = 'received', // 'received' or 'sent'
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get('/follow-requests', queryParameters: {
        'type': type,
        'page': page,
        'limit': limit,
      });

      final paginatedResponse = PaginatedResponse<FollowRequest>(
        items: (response.data['data']['items'] as List)
            .map((json) => FollowRequest.fromJson(json))
            .toList(),
        page: response.data['data']['page'],
        limit: response.data['data']['limit'],
        total: response.data['data']['total'],
        hasNext: response.data['data']['hasNext'],
      );

      return ApiResponse<PaginatedResponse<FollowRequest>>(
        success: response.data['success'],
        data: paginatedResponse,
      );
    } on DioException catch (e) {
      return ApiResponse<PaginatedResponse<FollowRequest>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<void>> respondToFollowRequest(
    String requestId,
    String action, // 'accept' or 'reject'
  ) async {
    try {
      final response = await _dio.patch('/follow-requests/$requestId', data: {
        'action': action,
      });

      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<void>> cancelFollowRequest(String requestId) async {
    try {
      final response = await _dio.delete('/follow-requests/$requestId');

      return ApiResponse<void>(
        success: response.data['success'],
        message: response.data['message'],
      );
    } on DioException catch (e) {
      return ApiResponse<void>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // Feed endpoints
  Future<ApiResponse<PaginatedResponse<Trip>>> getFeed({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _dio.get('/feed', queryParameters: {
        'page': page,
        'limit': limit,
      });

      final paginatedResponse = PaginatedResponse<Trip>(
        items: (response.data['data']['items'] as List)
            .map((json) => Trip.fromJson(json))
            .toList(),
        page: response.data['data']['page'],
        limit: response.data['data']['limit'],
        total: response.data['data']['total'],
        hasNext: response.data['data']['hasNext'],
      );

      return ApiResponse<PaginatedResponse<Trip>>(
        success: response.data['success'],
        data: paginatedResponse,
      );
    } on DioException catch (e) {
      return ApiResponse<PaginatedResponse<Trip>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<List<User>>> getFollowers(String userId,
      {int page = 1, int limit = 20}) async {
    try {
      final response =
          await _dio.get('/users/$userId/followers', queryParameters: {
        'page': page,
        'limit': limit,
      });

      final followers = (response.data['data']['followers'] as List)
          .map((json) => User.fromJson(json))
          .toList();

      return ApiResponse<List<User>>(
        success: response.data['success'],
        data: followers,
      );
    } on DioException catch (e) {
      return ApiResponse<List<User>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<List<User>>> getFollowing(String userId,
      {int page = 1, int limit = 20}) async {
    try {
      final response =
          await _dio.get('/users/$userId/following', queryParameters: {
        'page': page,
        'limit': limit,
      });

      final following = (response.data['data']['following'] as List)
          .map((json) => User.fromJson(json))
          .toList();

      return ApiResponse<List<User>>(
        success: response.data['success'],
        data: following,
      );
    } on DioException catch (e) {
      return ApiResponse<List<User>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<bool>> getFollowStatus(String userId) async {
    try {
      final response = await _dio.get('/follow/$userId');

      return ApiResponse<bool>(
        success: response.data['success'],
        data: (response.data['data'] != null)
            ? (response.data['data']['isFollowing'] ?? false)
            : false,
      );
    } on DioException catch (e) {
      return ApiResponse<bool>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
        data: false, // Default to not following on error
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> searchUsers({
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final response = await _dio.get('/users', queryParameters: queryParams);

      return ApiResponse<Map<String, dynamic>>(
        success: response.data['success'],
        data: response.data['data'],
      );
    } on DioException catch (e) {
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  // Trip endpoints
  Future<ApiResponse<Trip>> createTrip(CreateTripRequest request) async {
    try {
      final response = await _dio.post('/trips', data: request.toJson());

      return ApiResponse<Trip>.fromJson(
        response.data,
        (json) => Trip.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<List<Trip>>> getTrips({String? status}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null) {
        queryParams['status'] = status;
      }

      final response = await _dio.get('/trips', queryParameters: queryParams);

      final trips = (response.data['data'] as List)
          .map((json) => Trip.fromJson(json))
          .toList();

      return ApiResponse<List<Trip>>(
        success: response.data['success'],
        data: trips,
      );
    } on DioException catch (e) {
      return ApiResponse<List<Trip>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<Trip>> getTrip(String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId');

      return ApiResponse<Trip>.fromJson(
        response.data,
        (json) => Trip.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<Trip?>> getCurrentTrip() async {
    try {
      final response = await _dio.get('/trips/status');

      if (response.data['data'] == null) {
        return ApiResponse<Trip?>(
          success: true,
          data: null,
          message: response.data['message'],
        );
      }

      return ApiResponse<Trip?>.fromJson(
        response.data,
        (json) => json != null ? Trip.fromJson(json as Map<String, dynamic>) : null,
      );
    } on DioException catch (e) {
      return ApiResponse<Trip?>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<Trip>> endTrip(String tripId) async {
    try {
      final response = await _dio.post('/trips/$tripId/end');

      return ApiResponse<Trip>.fromJson(
        response.data,
        (json) => Trip.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // Thread entries
  Future<ApiResponse<TripThreadEntry>> createThreadEntry(
    String tripId,
    CreateThreadEntryRequest request,
  ) async {
    try {
      final response = await _dio.post('/trips/$tripId/entries', data: request.toJson());

      return ApiResponse<TripThreadEntry>.fromJson(
        response.data,
        (json) => TripThreadEntry.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<TripThreadEntry>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripThreadEntry>>> getThreadEntries(String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId/entries');

      final entries = (response.data['data'] as List)
          .map((json) => TripThreadEntry.fromJson(json))
          .toList();

      return ApiResponse<List<TripThreadEntry>>(
        success: response.data['success'],
        data: entries,
      );
    } on DioException catch (e) {
      return ApiResponse<List<TripThreadEntry>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }
  // Add this method for manual refresh
  Future<ApiResponse<Map<String, dynamic>>> refreshAccessToken(
      String refreshToken) async {
    try {
      final response = await _dio.post('/auth/refresh-token', data: {
        'refreshToken': refreshToken,
      });
      if (response.statusCode == 200 && response.data['success'] == true) {
        return ApiResponse<Map<String, dynamic>>(
          success: true,
          data: Map<String, dynamic>.from(response.data['data']),
        );
      } else {
        return ApiResponse<Map<String, dynamic>>(
          success: false,
          error: response.data['error'] ?? 'Failed to refresh token',
        );
      }
    } on DioException catch (e) {
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      return ApiResponse<Map<String, dynamic>>(
        success: false,
        error: 'Unknown error occurred',
      );
    }
  }
}

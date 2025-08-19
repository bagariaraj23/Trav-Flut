import 'package:dio/dio.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/storage_service.dart';
import 'dart:convert'; // Added for jsonEncode

class TripService {
  // static const String baseUrl = 'http://localhost:3000/api';
  // static const String baseUrl = 'http://10.61.114.100:3000/api';
  static const String baseUrl = 'http://192.168.0.110:3000/api';
  // static const String baseUrl = 'http://192.168.0.111:3000/api';

  late final Dio _dio;
  StorageService? _storageService;

  TripService() {
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

              if (response.statusCode == 200) {
                final newToken = response.data['data']['accessToken'];
                await _storageService!.saveAccessToken(newToken);

                // Retry original request
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final cloneReq = await _dio.fetch(opts);
                return handler.resolve(cloneReq);
              }
            } catch (e) {
              // Refresh failed, clear tokens
              await _storageService!.clearTokens();
            }
          }
        }
        handler.next(error);
      },
    ));
  }

  // Trip CRUD operations
  Future<ApiResponse<Trip>> createTrip(CreateTripRequest request) async {
    try {
      print('[DEBUG] TripService.createTrip called');
      print('[DEBUG] Request data: ${request.toJson()}');
      print('[DEBUG] Request JSON: ${jsonEncode(request.toJson())}');

      final response = await _dio.post('/trips', data: request.toJson());

      print('[DEBUG] HTTP response received:');
      print('[DEBUG] Status code: ${response.statusCode}');
      print('[DEBUG] Response data: ${response.data}');

      return ApiResponse<Trip>.fromJson(
        response.data,
        (json) => Trip.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      print('[DEBUG] DioException in createTrip:');
      print('[DEBUG] Error type: ${e.type}');
      print('[DEBUG] Error message: ${e.message}');
      print('[DEBUG] Response status: ${e.response?.statusCode}');
      print('[DEBUG] Response data: ${e.response?.data}');

      return ApiResponse<Trip>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    } catch (e) {
      print('[DEBUG] Unexpected error in createTrip: $e');
      return ApiResponse<Trip>(
        success: false,
        error: 'An unexpected error occurred',
      );
    }
  }

  Future<ApiResponse<List<Trip>>> getTrips({TripStatus? status}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (status != null) {
        queryParams['status'] = status.name.toUpperCase();
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
        (json) =>
            json != null ? Trip.fromJson(json as Map<String, dynamic>) : null,
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
      final response =
          await _dio.post('/trips/$tripId/entries', data: request.toJson());

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

  Future<ApiResponse<List<TripThreadEntry>>> getThreadEntries(
      String tripId) async {
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

  // Participants
  Future<ApiResponse<TripParticipant>> addParticipant(
    String tripId,
    String userId, {
    String? role,
  }) async {
    try {
      final response = await _dio.post('/trips/$tripId/participants', data: {
        'userId': userId,
        if (role != null) 'role': role,
      });

      return ApiResponse<TripParticipant>.fromJson(
        response.data,
        (json) => TripParticipant.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<TripParticipant>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<List<TripParticipant>>> getParticipants(
      String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId/participants');

      final participants = (response.data['data'] as List)
          .map((json) => TripParticipant.fromJson(json))
          .toList();

      return ApiResponse<List<TripParticipant>>(
        success: response.data['success'],
        data: participants,
      );
    } on DioException catch (e) {
      return ApiResponse<List<TripParticipant>>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  // Final post
  Future<ApiResponse<TripFinalPost>> getFinalPost(String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId/final-post');

      return ApiResponse<TripFinalPost>.fromJson(
        response.data,
        (json) => TripFinalPost.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<TripFinalPost>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<TripFinalPost>> updateFinalPost(
    String tripId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response =
          await _dio.put('/trips/$tripId/final-post', data: updates);

      return ApiResponse<TripFinalPost>.fromJson(
        response.data,
        (json) => TripFinalPost.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse<TripFinalPost>(
        success: false,
        error: e.response?.data['error'] ?? 'Network error occurred',
      );
    }
  }

  Future<ApiResponse<void>> publishFinalPost(String tripId) async {
    try {
      final response = await _dio.post('/trips/$tripId/publish');

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
}

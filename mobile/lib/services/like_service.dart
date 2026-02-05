import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/token_refresh_manager.dart';
import 'package:tripthread/config/app_config.dart';

class LikeService {
  late final Dio _dio;
  late final Dio _refreshDio;
  StorageService? _storageService;

  LikeService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: AppConfig.defaultHeaders,
      ),
    );
    _refreshDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: AppConfig.defaultHeaders,
      ),
    );
    _setupInterceptors();
  }

  void setStorageService(StorageService storageService) {
    _storageService = storageService;
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
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
          if (error.response?.statusCode == 401 &&
              _storageService != null &&
              error.requestOptions.extra['retried'] != true) {
            try {
              final newToken = await TokenRefreshManager.instance.refresh(
                storage: _storageService!,
                refreshClient: _refreshDio,
              );
              if (newToken != null && newToken.isNotEmpty) {
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                opts.extra['retried'] = true;
                final cloneReq = await _dio.fetch(opts);
                return handler.resolve(cloneReq);
              }
              await _storageService!.clearTokens();
              return handler.next(error);
            } catch (e) {
              await _storageService!.clearTokens();
              return handler.next(error);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<void> toggleLike(String entityType, String entityId) async {
    try {
      final dio = _dio;

      final currentStatus = await checkLikeStatus([entityId], entityType);
      final isLiked = currentStatus[entityId] ?? false;

      if (isLiked) {
        final response = await dio.delete('/likes/$entityType/$entityId');

        if (response.statusCode != 200) {
          throw AppException('Failed to unlike');
        }
      } else {
        final response = await dio.post(
          '/likes',
          data: {'entityType': entityType, 'entityId': entityId},
        );

        if (response.statusCode != 200) {
          throw AppException('Failed to like');
        }
      }
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[LikeService] toggleLike error: $e');
      throw AppException('Failed to toggle like: ${e.toString()}');
    }
  }

  Future<List<User>> getLikeUsers(
    String entityType,
    String entityId,
    int page,
  ) async {
    try {
      final dio = _dio;

      final response = await dio.get(
        '/likes/$entityType/$entityId/users',
        queryParameters: {'page': page.toString(), 'limit': '20'},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final responseData = data['data'] as Map<String, dynamic>;
          final items = responseData['items'] as List<dynamic>? ?? [];

          final users = <User>[];
          for (final item in items) {
            try {
              final itemMap = item is Map<String, dynamic> ? item : null;
              if (itemMap == null) continue;
              final userData = itemMap['user'] as Map<String, dynamic>?;
              if (userData == null) {
                debugPrint(
                  '[LikeService] User data is null for like item: $item',
                );
                continue;
              }
              if (userData['id'] == null || userData['email'] == null) {
                debugPrint(
                  '[LikeService] Missing required user fields: $userData',
                );
                continue;
              }
              users.add(User.fromJson(userData));
            } catch (e) {
              debugPrint('[LikeService] Error parsing user data: $e');
            }
          }
          return users;
        }
      }

      throw AppException('Failed to get like users');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[LikeService] getLikeUsers error: $e');
      throw AppException('Failed to get like users: ${e.toString()}');
    }
  }

  Future<Map<String, bool>> checkLikeStatus(
    List<String> entityIds,
    String entityType,
  ) async {
    try {
      final dio = _dio;

      final response = await dio.get(
        '/likes/status',
        queryParameters: {
          'entityType': entityType,
          'entityIds': entityIds.join(','),
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final statusMap = data['data'] as Map<String, dynamic>;
          return statusMap.map((key, value) => MapEntry(key, value as bool));
        }
      }

      return {for (var id in entityIds) id: false};
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[LikeService] checkLikeStatus error: $e');
      return {for (var id in entityIds) id: false};
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/token_refresh_manager.dart';
import 'package:tripthread/config/app_config.dart';

class CommentService {
  late final Dio _dio;
  late final Dio _refreshDio;
  StorageService? _storageService;

  static int _parseLikeCount(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  CommentService() {
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

  Future<Comment> createComment(
    String entityType,
    String entityId,
    String text,
    String? parentId,
  ) async {
    try {
      final dio = _dio;

      final response = await dio.post(
        '/comments',
        data: {
          'entityType': entityType,
          'entityId': entityId,
          'contentText': text,
          if (parentId != null) 'parentCommentId': parentId,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final commentData = data['data'] as Map<String, dynamic>;
          return Comment.fromJson(commentData);
        }
      }

      throw AppException('Failed to create comment');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[CommentService] createComment error: $e');
      throw AppException('Failed to create comment: ${e.toString()}');
    }
  }

  Future<PaginatedResponse<Comment>> getComments(
    String entityType,
    String entityId,
    int page,
  ) async {
    try {
      final dio = _dio;

      final response = await dio.get(
        '/comments/entity/$entityType/$entityId',
        queryParameters: {'page': page.toString(), 'limit': '20'},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final responseData = data['data'] as Map<String, dynamic>;
          final items = responseData['items'] as List<dynamic>?;
          final nextCursor = responseData['nextCursor'] as String?;

          final comments =
              items?.map((item) {
                final commentData = item as Map<String, dynamic>;

                if (commentData['entityType'] == null) {
                  commentData['entityType'] = entityType;
                }
                if (commentData['entityId'] == null) {
                  commentData['entityId'] = entityId;
                }
                commentData['likeCount'] = _parseLikeCount(commentData['likeCount']);

                return Comment.fromJson(commentData);
              }).toList() ??
              [];

          return PaginatedResponse<Comment>(
            data: comments,
            pagination: PaginationInfo(
              page: page,
              limit: 20,
              total: comments.length,
              totalPages: nextCursor != null ? page + 1 : page,
            ),
          );
        }
      }

      throw AppException('Failed to get comments');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[CommentService] getComments error: $e');
      throw AppException('Failed to get comments: ${e.toString()}');
    }
  }

  Future<Comment> updateComment(String commentId, String newText) async {
    try {
      final dio = _dio;

      final response = await dio.put(
        '/comments/$commentId',
        data: {'contentText': newText},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final commentData = data['data'] as Map<String, dynamic>;
          return Comment.fromJson(commentData);
        }
      }

      throw AppException('Failed to update comment');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[CommentService] updateComment error: $e');
      throw AppException('Failed to update comment: ${e.toString()}');
    }
  }

  Future<void> deleteComment(String commentId) async {
    try {
      final dio = _dio;

      final response = await dio.delete('/comments/$commentId');

      if (response.statusCode != 200) {
        throw AppException('Failed to delete comment');
      }
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[CommentService] deleteComment error: $e');
      throw AppException('Failed to delete comment: ${e.toString()}');
    }
  }

  Future<PaginatedResponse<Comment>> getReplies(
    String commentId,
    int page,
  ) async {
    try {
      final dio = _dio;

      final response = await dio.get(
        '/comments/$commentId/replies',
        queryParameters: {'page': page.toString(), 'limit': '20'},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final responseData = data['data'] as Map<String, dynamic>;
          final items = responseData['items'] as List<dynamic>?;
          final nextCursor = responseData['nextCursor'] as String?;

          final replies =
              items?.map((item) {
                final commentData = item as Map<String, dynamic>;

                if (commentData['entityType'] == null ||
                    commentData['entityId'] == null) {
                  debugPrint(
                    '[CommentService] Warning: Reply missing entityType or entityId',
                  );
                }
                commentData['likeCount'] = _parseLikeCount(commentData['likeCount']);

                return Comment.fromJson(commentData);
              }).toList() ??
              [];

          return PaginatedResponse<Comment>(
            data: replies,
            pagination: PaginationInfo(
              page: page,
              limit: 20,
              total: replies.length,
              totalPages: nextCursor != null ? page + 1 : page,
            ),
          );
        }
      }

      throw AppException('Failed to get replies');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[CommentService] getReplies error: $e');
      throw AppException('Failed to get replies: ${e.toString()}');
    }
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/token_refresh_manager.dart';
import 'package:tripthread/config/app_config.dart';

class ShareLinkResult {
  final String webUrl;
  final String shareToken;

  const ShareLinkResult({
    required this.webUrl,
    required this.shareToken,
  });

  String get primaryAppDeepLink => 'tripthread://share/$shareToken';
}

class SharedEntity {
  final String entityType;
  final String entityId;
  final Map<String, dynamic> entityData;
  final Map<String, dynamic> shareData;

  const SharedEntity({
    required this.entityType,
    required this.entityId,
    required this.entityData,
    required this.shareData,
  });

  factory SharedEntity.fromJson(Map<String, dynamic> json) {
    final share = json['share'];
    if (share is! Map<String, dynamic>) {
      throw AppException('Share data missing or invalid');
    }
    final entityType = share['entityType'] as String?;
    final entityId = share['entityId'] as String?;
    if (entityType == null ||
        entityType.isEmpty ||
        entityId == null ||
        entityId.isEmpty) {
      throw AppException('Share target is missing');
    }
    final entity = json['entity'];
    final entityData = entity is Map<String, dynamic>
        ? entity
        : <String, dynamic>{};
    return SharedEntity(
      entityType: entityType,
      entityId: entityId,
      entityData: entityData,
      shareData: share,
    );
  }
}

class ShareService {
  late final Dio _dio;
  late final Dio _refreshDio;
  StorageService? _storageService;

  ShareService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: AppConfig.defaultHeaders,
    ));
    _refreshDio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: AppConfig.defaultHeaders,
    ));
    _setupInterceptors();
  }

  void setStorageService(StorageService storageService) {
    _storageService = storageService;
  }

  void _setupInterceptors() {
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
    ));
  }

  Future<ShareLinkResult> createShare(
    String entityType,
    String entityId,
  ) async {
    try {
      final response = await _dio.post(
        '/shares',
        data: {
          'entityType': entityType,
          'entityId': entityId,
          'shareType': 'DEEP_LINK',
          'shareSource': 'SYSTEM_SHEET',
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final shareData = data['data'] as Map<String, dynamic>;
          final shareToken = shareData['shareToken'] as String;
          final origin = AppConfig.effectiveShareLinkOrigin;
          final webUrl = '$origin/share/$shareToken';
          return ShareLinkResult(webUrl: webUrl, shareToken: shareToken);
        }
      }

      throw AppException('Failed to create share');
    } on DioException catch (e) {
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[ShareService] createShare error: $e');
      throw AppException('Failed to create share: ${e.toString()}');
    }
  }

  Future<SharedEntity> resolveShare(String shareToken) async {
    try {
      final response = await _dio.get('/shares/$shareToken');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          return SharedEntity.fromJson(data['data'] as Map<String, dynamic>);
        }
      }

      throw AppException('Failed to resolve share');
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) {
        throw AppException('Share token expired');
      }
      throw ErrorHandler.handleError(e);
    } catch (e) {
      debugPrint('[ShareService] resolveShare error: $e');
      throw AppException('Failed to resolve share: ${e.toString()}');
    }
  }
}


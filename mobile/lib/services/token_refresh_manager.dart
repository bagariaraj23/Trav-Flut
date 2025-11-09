import 'package:dio/dio.dart';

import 'storage_service.dart';

class TokenRefreshManager {
  TokenRefreshManager._();

  static final TokenRefreshManager instance = TokenRefreshManager._();

  bool _isRefreshing = false;
  Future<void>? _refreshFuture;
  int _lastFailureAtMs = 0;

  Future<String?> refresh({
    required StorageService storage,
    required Dio refreshClient,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastFailureAtMs < 5000) {
      await storage.clearTokens();
      return null;
    }

    try {
      if (!_isRefreshing) {
        _isRefreshing = true;
        _refreshFuture = () async {
          final refreshToken = await storage.getRefreshToken();
          if (refreshToken == null || refreshToken.isEmpty) {
            throw DioException(
              requestOptions: RequestOptions(path: '/auth/refresh-token'),
              type: DioExceptionType.cancel,
              error: 'Missing refresh token',
            );
          }

          final response = await refreshClient.post(
            '/auth/refresh-token',
            data: {'refreshToken': refreshToken},
          );

          if (response.statusCode == 200 &&
              response.data is Map<String, dynamic> &&
              response.data['success'] == true) {
            final data = response.data['data'];
            if (data is! Map<String, dynamic>) {
              throw DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: 'Malformed refresh response payload',
              );
            }

            final newAccessToken = data['accessToken'] as String?;
            final newRefreshToken = data['refreshToken'] as String?;

            if (newAccessToken == null ||
                newAccessToken.isEmpty ||
                newRefreshToken == null ||
                newRefreshToken.isEmpty) {
              throw DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: 'Refresh response missing tokens',
              );
            }

            final userId = await storage.getUserId();
            if (userId != null && userId.isNotEmpty) {
              await storage.saveTokens(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
                userId: userId,
              );
            } else {
              await storage.saveAccessToken(newAccessToken);
              await storage.saveRefreshToken(newRefreshToken);
            }
          } else {
            throw DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: 'Refresh request failed',
            );
          }
        }();

        await _refreshFuture;
      } else if (_refreshFuture != null) {
        await _refreshFuture;
      }

      return await storage.getAccessToken();
    } catch (error) {
      _lastFailureAtMs = now;
      await storage.clearTokens();
      rethrow;
    } finally {
      _isRefreshing = false;
      _refreshFuture = null;
    }
  }
}


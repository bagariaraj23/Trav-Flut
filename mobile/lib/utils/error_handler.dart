import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class AppException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  AppException(this.message, {this.code, this.statusCode});

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  NetworkException(String message) : super(message, code: 'NETWORK_ERROR');
}

class ValidationException extends AppException {
  ValidationException(String message) : super(message, code: 'VALIDATION_ERROR');
}

class AuthenticationException extends AppException {
  AuthenticationException(String message) : super(message, code: 'AUTH_ERROR');
}

class ServerException extends AppException {
  ServerException(String message, {int? statusCode}) 
    : super(message, code: 'SERVER_ERROR', statusCode: statusCode);
}

class ErrorHandler {
  static AppException handleError(dynamic error) {
    if (error is DioException) {
      return _handleDioError(error);
    }
    
    if (error is AppException) {
      return error;
    }
    
    debugPrint('Unexpected error: $error');
    return AppException('An unexpected error occurred');
  }

  static AppException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException('Connection timeout. Please check your internet connection.');
      
      case DioExceptionType.connectionError:
        return NetworkException('Unable to connect to server. Please check your internet connection.');
      
      case DioExceptionType.badResponse:
        return _handleResponseError(error);
      
      case DioExceptionType.cancel:
        return NetworkException('Request was cancelled');
      
      default:
        return NetworkException('Network error occurred');
    }
  }

  static AppException _handleResponseError(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    
    String message = 'An error occurred';
    
    if (data is Map<String, dynamic> && data['error'] != null) {
      message = data['error'];
    }
    
    switch (statusCode) {
      case 400:
        return ValidationException(message);
      case 401:
        return AuthenticationException('Authentication required. Please log in again.');
      case 403:
        return AuthenticationException('Access denied. You don\'t have permission to perform this action.');
      case 404:
        return AppException('The requested resource was not found.');
      case 409:
        return ValidationException(message);
      case 429:
        return AppException('Too many requests. Please try again later.');
      case 500:
      case 502:
      case 503:
      case 504:
        return ServerException('Server error. Please try again later.', statusCode: statusCode);
      default:
        return ServerException(message, statusCode: statusCode);
    }
  }

  static void logError(dynamic error, {String? context, Map<String, dynamic>? additionalData}) {
    if (kDebugMode) {
      debugPrint('Error in $context: $error');
      if (additionalData != null) {
        debugPrint('Additional data: $additionalData');
      }
    }
    
    // In production, send to crash reporting service
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, context: context);
  }
}

// Retry mechanism for network requests
class RetryHandler {
  static Future<T> retry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
    bool Function(dynamic error)? retryIf,
  }) async {
    int attempts = 0;
    
    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (error) {
        attempts++;
        
        if (attempts >= maxRetries || (retryIf != null && !retryIf(error))) {
          rethrow;
        }
        
        await Future.delayed(delay * attempts); // Exponential backoff
      }
    }
    
    throw Exception('Max retries exceeded');
  }
}

// Network connectivity checker
class ConnectivityChecker {
  static Future<bool> hasConnection() async {
    try {
      // Simple connectivity check
      // In production, use connectivity_plus package
      return true;
    } catch (e) {
      return false;
    }
  }
}
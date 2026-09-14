import 'package:dio/dio.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/services/storage_service.dart';
import 'package:tripthread/services/token_refresh_manager.dart';

class ExpenseService {
  late final Dio _dio;
  late final Dio _refreshDio;
  StorageService? _storageService;

  ExpenseService() {
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
            } catch (_) {
              await _storageService!.clearTokens();
              return handler.next(error);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  String _errorFrom(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) return data['error'] as String;
    return fallback;
  }

  Future<ApiResponse<ExpenseListPage>> listExpenses(String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId/expenses');
      return ApiResponse<ExpenseListPage>.fromJson(
        response.data,
        (json) => ExpenseListPage.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to load expenses'));
    }
  }

  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    try {
      final response = await _dio.get('/trips/$tripId/expenses/summary');
      return ApiResponse<ExpenseSummary>.fromJson(
        response.data,
        (json) => ExpenseSummary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to load summary'));
    }
  }

  Future<ApiResponse<TripExpense>> createExpense(
    String tripId,
    CreateExpenseRequest request,
  ) async {
    try {
      final response = await _dio.post(
        '/trips/$tripId/expenses',
        data: request.toJson(),
      );
      return ApiResponse<TripExpense>.fromJson(
        response.data,
        (json) => TripExpense.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to add expense'));
    }
  }

  Future<ApiResponse<void>> deleteExpense(String tripId, String expenseId) async {
    try {
      await _dio.delete('/trips/$tripId/expenses/$expenseId');
      return const ApiResponse(success: true);
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to delete expense'));
    }
  }

  Future<ApiResponse<RecordedSettlement>> markPaid({
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required int amountMinor,
  }) async {
    try {
      final response = await _dio.post(
        '/trips/$tripId/settlements',
        data: {
          'fromUserId': fromUserId,
          'toUserId': toUserId,
          'amountMinor': amountMinor,
        },
      );
      return ApiResponse<RecordedSettlement>.fromJson(
        response.data,
        (json) => RecordedSettlement.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to mark paid'));
    }
  }

  Future<ApiResponse<void>> undoSettlement(String tripId, String settlementId) async {
    try {
      await _dio.delete('/trips/$tripId/settlements/$settlementId');
      return const ApiResponse(success: true);
    } on DioException catch (e) {
      return ApiResponse(success: false, error: _errorFrom(e, 'Failed to undo settlement'));
    }
  }
}

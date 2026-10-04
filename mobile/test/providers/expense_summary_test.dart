import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/providers/expense_provider.dart';
import 'package:tripthread/services/expense_service.dart';
import 'package:tripthread/utils/money.dart';
import 'package:tripthread/utils/unsettled_balance.dart';

class MockExpenseService extends ExpenseService {
  @override
  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    return ApiResponse(
      success: true,
      data: ExpenseSummary.fromJson({
        'currency': 'INR',
        'totalSpendMinor': 30000,
        'myNetMinor': 15000,
        'members': [],
        'openTransfers': [],
        'recordedSettlements': [],
        'pairwise': [],
      }),
    );
  }

  @override
  Future<ApiResponse<ExpenseListPage>> listExpenses(
    String tripId, {
    int page = 1,
    int limit = 100,
  }) async {
    return const ApiResponse(
      success: true,
      data: ExpenseListPage(
        items: [],
        page: 1,
        limit: 20,
        total: 0,
        hasNext: false,
      ),
    );
  }
}

void main() {
  test('formatMoneyMinor uses rupee grouping', () {
    expect(formatMoneyMinor(150000), contains('1,500'));
    expect(formatMoneyMinor(5154), contains('51.54'));
  });

  test('ExpenseSummary.fromJson parses settle-up payload', () {
    final summary = ExpenseSummary.fromJson({
      'currency': 'INR',
      'totalSpendMinor': 30000,
      'myNetMinor': 15000,
      'members': [
        {
          'userId': 'a',
          'name': 'Alice',
          'username': 'alice',
          'avatarUrl': null,
          'netMinor': 15000,
          'paidMinor': 30000,
          'owedMinor': 15000,
        },
      ],
      'openTransfers': [
        {
          'fromUserId': 'b',
          'toUserId': 'a',
          'amountMinor': 15000,
          'canMarkPaid': true,
        },
      ],
      'recordedSettlements': [],
      'pairwise': [],
    });

    expect(summary.totalSpendMinor, 30000);
    expect(summary.openTransfers.single.canMarkPaid, isTrue);
    expect(summary.members.single.username, 'alice');
  });

  test('ExpenseProvider.load stores summary for the money pane', () async {
    final provider = ExpenseProvider(expenseService: MockExpenseService());
    await provider.load('trip-1');
    expect(provider.summary?.myNetMinor, 15000);
    expect(provider.error, isNull);
  });

  test('ExpenseProvider.load follows later expense pages', () async {
    final provider = ExpenseProvider(expenseService: _PagingExpenseService());
    await provider.load('trip-1');
    expect(provider.expenses.map((e) => e.id), ['e1', 'e2']);
    expect(provider.error, isNull);
  });

  test('a newer load wins over an in-flight load for another trip', () async {
    final service = _GatedExpenseService();
    final provider = ExpenseProvider(expenseService: service);
    final first = provider.load('trip-a');
    final second = provider.load('trip-b');
    expect(provider.summary, isNull);
    service.release('trip-b');
    await second;
    expect(provider.summary?.myNetMinor, 200);
    service.release('trip-a');
    await first;
    expect(provider.summary?.myNetMinor, 200);
  });

  test('clear drops state even if an older load completes later', () async {
    final service = _GatedExpenseService();
    final provider = ExpenseProvider(expenseService: service);
    final pending = provider.load('trip-a');
    provider.clear();
    service.release('trip-a');
    await pending;
    expect(provider.summary, isNull);
    expect(provider.expenses, isEmpty);
  });

  test('leaveErrorFrom maps UNSETTLED_BALANCE to money-pane copy', () {
    expect(
      leaveErrorFrom(
        {
          'error':
              'Settle your trip balance before leaving or deleting your account',
          'meta': {'code': 'UNSETTLED_BALANCE', 'netMinor': -15000},
        },
        'fallback',
      ),
      unsettledBalanceLeaveMessage,
    );
  });
}

class _PagingExpenseService extends ExpenseService {
  @override
  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    return const ApiResponse(
      success: true,
      data: ExpenseSummary(
        currency: 'INR',
        totalSpendMinor: 0,
        myNetMinor: 0,
        members: [],
        openTransfers: [],
        recordedSettlements: [],
        pairwise: [],
      ),
    );
  }

  @override
  Future<ApiResponse<ExpenseListPage>> listExpenses(
    String tripId, {
    int page = 1,
    int limit = 100,
  }) async {
    TripExpense item(String id) {
      return TripExpense(
        id: id,
        tripId: tripId,
        createdById: 'u',
        payerId: 'u',
        title: id,
        category: 'FOOD',
        amountMinor: 100,
        currency: 'INR',
        splitMethod: 'EQUAL',
        createdAt: DateTime.utc(2026, 1, 1),
      );
    }

    if (page == 1) {
      return ApiResponse(
        success: true,
        data: ExpenseListPage(
          items: [item('e1')],
          page: 1,
          limit: limit,
          total: 2,
          hasNext: true,
        ),
      );
    }
    return ApiResponse(
      success: true,
      data: ExpenseListPage(
        items: [item('e2')],
        page: page,
        limit: limit,
        total: 2,
        hasNext: false,
      ),
    );
  }
}

class _GatedExpenseService extends ExpenseService {
  final Map<String, Completer<void>> _gates = {};

  Completer<void> _gate(String tripId) => _gates.putIfAbsent(tripId, Completer.new);

  void release(String tripId) {
    final gate = _gate(tripId);
    if (!gate.isCompleted) gate.complete();
  }

  ExpenseSummary _summary(String tripId) {
    return ExpenseSummary(
      currency: 'INR',
      totalSpendMinor: 0,
      myNetMinor: tripId == 'trip-b' ? 200 : 100,
      members: const [],
      openTransfers: const [],
      recordedSettlements: const [],
      pairwise: const [],
    );
  }

  @override
  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    await _gate(tripId).future;
    return ApiResponse(success: true, data: _summary(tripId));
  }

  @override
  Future<ApiResponse<ExpenseListPage>> listExpenses(
    String tripId, {
    int page = 1,
    int limit = 100,
  }) async {
    await _gate(tripId).future;
    return ApiResponse(
      success: true,
      data: ExpenseListPage(
        items: const [],
        page: page,
        limit: limit,
        total: 0,
        hasNext: false,
      ),
    );
  }
}

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
  Future<ApiResponse<ExpenseListPage>> listExpenses(String tripId) async {
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

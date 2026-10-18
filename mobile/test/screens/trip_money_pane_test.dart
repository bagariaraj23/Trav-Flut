import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/expense_provider.dart';
import 'package:tripthread/screens/trip/trip_money_pane.dart';
import 'package:tripthread/services/expense_service.dart';

class MockExpenseService extends ExpenseService {
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

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  User? get currentUser => User(
        id: 'me',
        email: 'me@test.com',
        name: 'Me',
        username: 'me',
        isPrivate: false,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('Money pane shows settled summary and add-expense action',
      (tester) async {
    final expenseProvider = ExpenseProvider(
      expenseService: MockExpenseService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: MockAuthProvider(),
            ),
            ChangeNotifierProvider<ExpenseProvider>.value(
              value: expenseProvider,
            ),
          ],
          child: const Scaffold(
            body: TripMoneyPane(tripId: 'trip-1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('All settled'), findsOneWidget);
    expect(find.text('No open payments.'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
  });

  testWidgets('Mark as paid failure is shown when a summary is already loaded',
      (tester) async {
    final expenseProvider = ExpenseProvider(
      expenseService: _FailingSettlementService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: MockAuthProvider(),
            ),
            ChangeNotifierProvider<ExpenseProvider>.value(
              value: expenseProvider,
            ),
          ],
          child: const Scaffold(
            body: TripMoneyPane(tripId: 'trip-1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as paid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('This transfer is no longer valid'), findsOneWidget);
  });

  testWidgets('paid settlements show without undo and lock expense deletes',
      (tester) async {
    final expenseProvider = ExpenseProvider(
      expenseService: _PaidSettlementService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: MockAuthProvider(),
            ),
            ChangeNotifierProvider<ExpenseProvider>.value(
              value: expenseProvider,
            ),
          ],
          child: const Scaffold(
            body: TripMoneyPane(tripId: 'trip-1'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Already paid'), findsOneWidget);
    expect(find.textContaining('Them paid Me'), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsNothing);
    expect(find.textContaining('Pay in GPay'), findsNothing);
    expect(find.textContaining('tap for shares'), findsNothing);
    expect(
      find.text('Splits are locked after a settlement is recorded.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('You and others (raw bills)'), findsNothing);
  });
}

class _FailingSettlementService extends MockExpenseService {
  @override
  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    return const ApiResponse(
      success: true,
      data: ExpenseSummary(
        currency: 'INR',
        totalSpendMinor: 10000,
        myNetMinor: 10000,
        members: [],
        openTransfers: [
          OpenTransfer(
            fromUserId: 'them',
            toUserId: 'me',
            amountMinor: 10000,
            canMarkPaid: true,
          ),
        ],
        recordedSettlements: [],
        pairwise: [],
      ),
    );
  }

  @override
  Future<ApiResponse<RecordedSettlement>> markPaid({
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required int amountMinor,
  }) async {
    return const ApiResponse(
      success: false,
      error: 'This transfer is no longer valid',
    );
  }
}

class _PaidSettlementService extends MockExpenseService {
  @override
  Future<ApiResponse<ExpenseSummary>> getSummary(String tripId) async {
    return ApiResponse(
      success: true,
      data: ExpenseSummary(
        currency: 'INR',
        totalSpendMinor: 10000,
        myNetMinor: 0,
        members: const [
          ExpenseMemberBalance(
            userId: 'me',
            name: 'Me',
            username: 'me',
            netMinor: 0,
            paidMinor: 0,
            owedMinor: 5000,
          ),
          ExpenseMemberBalance(
            userId: 'them',
            name: 'Them',
            username: 'them',
            netMinor: 0,
            paidMinor: 10000,
            owedMinor: 5000,
          ),
        ],
        openTransfers: const [],
        recordedSettlements: [
          RecordedSettlement(
            id: 's1',
            fromUserId: 'them',
            toUserId: 'me',
            amountMinor: 5000,
            status: 'PAID',
            createdAt: DateTime.utc(2026, 1, 1),
            canUndo: false,
          ),
        ],
        pairwise: const [],
      ),
    );
  }

  @override
  Future<ApiResponse<ExpenseListPage>> listExpenses(
    String tripId, {
    int page = 1,
    int limit = 100,
  }) async {
    return ApiResponse(
      success: true,
      data: ExpenseListPage(
        items: [
          TripExpense(
            id: 'e1',
            tripId: tripId,
            createdById: 'me',
            payerId: 'me',
            title: 'Dinner',
            category: 'FOOD',
            amountMinor: 10000,
            currency: 'INR',
            splitMethod: 'EXACT',
            createdAt: DateTime.utc(2026, 1, 1),
            shares: const [
              ExpenseShare(userId: 'me', shareMinor: 4000),
              ExpenseShare(userId: 'them', shareMinor: 6000),
            ],
          ),
        ],
        page: 1,
        limit: limit,
        total: 1,
        hasNext: false,
      ),
    );
  }
}

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
}

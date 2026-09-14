import 'package:flutter/foundation.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/services/expense_service.dart';

class ExpenseProvider extends ChangeNotifier {
  final ExpenseService _service;

  ExpenseProvider({required ExpenseService expenseService})
      : _service = expenseService;

  String? _tripId;
  ExpenseSummary? _summary;
  List<TripExpense> _expenses = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  ExpenseSummary? get summary => _summary;
  List<TripExpense> get expenses => List.unmodifiable(_expenses);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> load(String tripId) async {
    _tripId = tripId;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final summaryRes = await _service.getSummary(tripId);
      final listRes = await _service.listExpenses(tripId);
      if (!summaryRes.success || summaryRes.data == null) {
        _error = summaryRes.error ?? 'Failed to load money summary';
      } else if (!listRes.success || listRes.data == null) {
        _error = listRes.error ?? 'Failed to load expenses';
      } else {
        _summary = summaryRes.data;
        _expenses = listRes.data!.items;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addExpense(CreateExpenseRequest request) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    _isSaving = true;
    _error = null;
    notifyListeners();
    final res = await _service.createExpense(tripId, request);
    _isSaving = false;
    if (!res.success) {
      _error = res.error ?? 'Failed to add expense';
      notifyListeners();
      return false;
    }
    await load(tripId);
    return true;
  }

  Future<bool> deleteExpense(String expenseId) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    final res = await _service.deleteExpense(tripId, expenseId);
    if (!res.success) {
      _error = res.error;
      notifyListeners();
      return false;
    }
    await load(tripId);
    return true;
  }

  Future<bool> markPaid(OpenTransfer transfer) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    final res = await _service.markPaid(
      tripId: tripId,
      fromUserId: transfer.fromUserId,
      toUserId: transfer.toUserId,
      amountMinor: transfer.amountMinor,
    );
    if (!res.success) {
      _error = res.error;
      notifyListeners();
      return false;
    }
    await load(tripId);
    return true;
  }

  Future<bool> undoSettlement(String settlementId) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    final res = await _service.undoSettlement(tripId, settlementId);
    if (!res.success) {
      _error = res.error;
      notifyListeners();
      return false;
    }
    await load(tripId);
    return true;
  }

  void clear() {
    _tripId = null;
    _summary = null;
    _expenses = [];
    _error = null;
    notifyListeners();
  }
}

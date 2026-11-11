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
  int _loadGeneration = 0;

  ExpenseSummary? get summary => _summary;
  List<TripExpense> get expenses => List.unmodifiable(_expenses);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<bool> load(String tripId) async {
    final generation = ++_loadGeneration;
    final tripChanged = _tripId != tripId;
    _tripId = tripId;
    if (tripChanged) {
      _summary = null;
      _expenses = [];
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final summaryFuture = _service.getSummary(tripId);
      final firstPageFuture = _service.listExpenses(tripId, page: 1);
      final summaryRes = await summaryFuture;
      final firstPage = await firstPageFuture;
      if (!_isCurrentLoad(generation)) return true;

      if (!summaryRes.success || summaryRes.data == null) {
        _failLoad(
          tripChanged: tripChanged,
          message: summaryRes.error ?? 'Failed to load money summary',
        );
        return false;
      }
      if (!firstPage.success || firstPage.data == null) {
        _failLoad(
          tripChanged: tripChanged,
          message: firstPage.error ?? 'Failed to load expenses',
        );
        return false;
      }

      final items = <TripExpense>[...firstPage.data!.items];
      var page = 1;
      var hasNext = firstPage.data!.hasNext && firstPage.data!.items.isNotEmpty;
      while (hasNext && page < 100) {
        page += 1;
        final listRes = await _service.listExpenses(tripId, page: page);
        if (!_isCurrentLoad(generation)) return true;
        if (!listRes.success || listRes.data == null) {
          _failLoad(
            tripChanged: tripChanged,
            message: listRes.error ?? 'Failed to load expenses',
          );
          return false;
        }
        items.addAll(listRes.data!.items);
        hasNext = listRes.data!.hasNext && listRes.data!.items.isNotEmpty;
      }

      if (!_isCurrentLoad(generation)) return true;
      _summary = summaryRes.data;
      _expenses = items;
      _error = null;
      return true;
    } catch (e) {
      if (!_isCurrentLoad(generation)) return true;
      _failLoad(tripChanged: tripChanged, message: e.toString());
      return false;
    } finally {
      if (_isCurrentLoad(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentLoad(int generation) => generation == _loadGeneration;

  void _failLoad({required bool tripChanged, required String message}) {
    _error = message;
    if (tripChanged) {
      _summary = null;
      _expenses = [];
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
    if (_tripId != tripId) {
      notifyListeners();
      return res.success;
    }
    if (!res.success) {
      _error = res.error ?? 'Failed to add expense';
      notifyListeners();
      return false;
    }
    return load(tripId);
  }

  Future<bool> deleteExpense(String expenseId) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    final res = await _service.deleteExpense(tripId, expenseId);
    if (_tripId != tripId) return res.success;
    if (!res.success) {
      _error = res.error ?? 'Failed to delete expense';
      notifyListeners();
      return false;
    }
    return load(tripId);
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
    if (_tripId != tripId) return res.success;
    if (!res.success) {
      _error = res.error ?? 'Failed to mark as paid';
      notifyListeners();
      return false;
    }
    return load(tripId);
  }

  Future<bool> undoSettlement(String settlementId) async {
    final tripId = _tripId;
    if (tripId == null) return false;
    final res = await _service.undoSettlement(tripId, settlementId);
    if (_tripId != tripId) return res.success;
    if (!res.success) {
      _error = res.error ?? 'Failed to undo settlement';
      notifyListeners();
      return false;
    }
    return load(tripId);
  }

  void clear() {
    _loadGeneration++;
    _tripId = null;
    _summary = null;
    _expenses = [];
    _isLoading = false;
    _isSaving = false;
    _error = null;
    notifyListeners();
  }
}

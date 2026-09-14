import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/expense_provider.dart';
import 'package:tripthread/utils/money.dart';
import 'package:tripthread/utils/user_display_labels.dart';

const _categories = [
  'FOOD',
  'STAY',
  'TRANSPORT',
  'ACTIVITIES',
  'SHOPPING',
  'OTHER',
];

const _methods = ['EQUAL', 'EXACT', 'PERCENT', 'SHARES'];

class AddExpenseSheet extends StatefulWidget {
  final ExpenseSummary summary;

  const AddExpenseSheet({super.key, required this.summary});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _category = 'FOOD';
  String _splitMethod = 'EQUAL';
  late String _payerId;
  late Set<String> _selectedIds;
  final Map<String, TextEditingController> _exactControllers = {};
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, TextEditingController> _weightControllers = {};

  @override
  void initState() {
    super.initState();
    final me = context.read<AuthProvider>().currentUser?.id;
    _payerId = me != null && widget.summary.members.any((m) => m.userId == me)
        ? me
        : widget.summary.members.first.userId;
    _selectedIds = widget.summary.members.map((m) => m.userId).toSet();
    for (final m in widget.summary.members) {
      _exactControllers[m.userId] = TextEditingController();
      _percentControllers[m.userId] = TextEditingController();
      _weightControllers[m.userId] = TextEditingController(text: '1');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    for (final c in _exactControllers.values) {
      c.dispose();
    }
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    for (final c in _weightControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<ExpenseMemberBalance> get _selectedMembers =>
      widget.summary.members.where((m) => _selectedIds.contains(m.userId)).toList();

  String _label(ExpenseMemberBalance m) =>
      userPrimaryLabel(id: m.userId, username: m.username, name: m.name);

  String? _validate() {
    if (_titleController.text.trim().isEmpty) return 'Add a title';
    final amount = parseRupees(_amountController.text);
    if (amount == null || amount <= 0) return 'Enter a valid amount';
    if (_selectedIds.isEmpty) return 'Select at least one person';
    final minor = rupeesToMinor(amount);
    if (_splitMethod == 'EXACT') {
      var sum = 0;
      for (final m in _selectedMembers) {
        final v = parseRupees(_exactControllers[m.userId]!.text);
        if (v == null) return 'Fill every exact share';
        sum += rupeesToMinor(v);
      }
      if (sum != minor) {
        return 'Exact shares must add up to ${formatMoneyMinor(minor, currency: widget.summary.currency)}';
      }
    }
    if (_splitMethod == 'PERCENT') {
      var bps = 0;
      for (final m in _selectedMembers) {
        final v = double.tryParse(_percentControllers[m.userId]!.text.trim());
        if (v == null) return 'Fill every percentage';
        bps += (v * 100).round();
      }
      if (bps != 10000) return 'Percentages must add up to 100';
    }
    if (_splitMethod == 'SHARES') {
      var w = 0;
      for (final m in _selectedMembers) {
        final v = int.tryParse(_weightControllers[m.userId]!.text.trim());
        if (v == null || v < 0) return 'Fill every share weight';
        w += v;
      }
      if (w <= 0) return 'Total shares must be greater than zero';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final amount = parseRupees(_amountController.text)!;
    final minor = rupeesToMinor(amount);
    final ids = _selectedMembers.map((m) => m.userId).toList();
    List<Map<String, dynamic>>? shares;
    List<Map<String, dynamic>>? percentBps;
    List<Map<String, dynamic>>? weights;
    if (_splitMethod == 'EXACT') {
      shares = _selectedMembers
          .map(
            (m) => {
              'userId': m.userId,
              'shareMinor': rupeesToMinor(parseRupees(_exactControllers[m.userId]!.text)!),
            },
          )
          .toList();
    } else if (_splitMethod == 'PERCENT') {
      percentBps = _selectedMembers
          .map(
            (m) => {
              'userId': m.userId,
              'bps': (double.parse(_percentControllers[m.userId]!.text.trim()) * 100)
                  .round(),
            },
          )
          .toList();
    } else if (_splitMethod == 'SHARES') {
      weights = _selectedMembers
          .map(
            (m) => {
              'userId': m.userId,
              'weight': int.parse(_weightControllers[m.userId]!.text.trim()),
            },
          )
          .toList();
    }

    final ok = await context.read<ExpenseProvider>().addExpense(
          CreateExpenseRequest(
            title: _titleController.text.trim(),
            category: _category,
            amountMinor: minor,
            payerId: _payerId,
            splitMethod: _splitMethod,
            memberIds: ids,
            shares: shares,
            percentBps: percentBps,
            weights: weights,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
          ),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      final err = context.read<ExpenseProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Could not save expense')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.summary.currency;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text('Add expense', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Car rental, Airbnb, dinner…',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${currencySymbol(currency).trim()})',
                  hintText: '1500 or 51.54',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(categoryLabel(c))))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _payerId,
                decoration: const InputDecoration(labelText: 'Who paid'),
                items: widget.summary.members
                    .map((m) => DropdownMenuItem(value: m.userId, child: Text(_label(m))))
                    .toList(),
                onChanged: (v) => setState(() => _payerId = v ?? _payerId),
              ),
              const SizedBox(height: 12),
              Text('Split among', style: Theme.of(context).textTheme.titleSmall),
              Wrap(
                spacing: 8,
                children: widget.summary.members.map((m) {
                  final selected = _selectedIds.contains(m.userId);
                  return FilterChip(
                    label: Text(_label(m)),
                    selected: selected,
                    onSelected: (on) {
                      setState(() {
                        if (on) {
                          _selectedIds.add(m.userId);
                        } else {
                          _selectedIds.remove(m.userId);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _methods.map((method) {
                  return ChoiceChip(
                    label: Text(method == 'EQUAL'
                        ? 'Equal'
                        : method == 'EXACT'
                            ? 'Exact'
                            : method == 'PERCENT'
                                ? '%'
                                : 'Shares'),
                    selected: _splitMethod == method,
                    onSelected: (_) => setState(() => _splitMethod = method),
                  );
                }).toList(),
              ),
              if (_splitMethod == 'EXACT') ...[
                const SizedBox(height: 8),
                ..._selectedMembers.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _exactControllers[m.userId],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: _label(m)),
                    ),
                  ),
                ),
              ],
              if (_splitMethod == 'PERCENT') ...[
                const SizedBox(height: 8),
                ..._selectedMembers.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _percentControllers[m.userId],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: '${_label(m)} %'),
                    ),
                  ),
                ),
              ],
              if (_splitMethod == 'SHARES') ...[
                const SizedBox(height: 8),
                ..._selectedMembers.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _weightControllers[m.userId],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: '${_label(m)} shares'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 16),
              Consumer<ExpenseProvider>(
                builder: (context, provider, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: provider.isSaving ? null : _submit,
                      child: provider.isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save expense'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

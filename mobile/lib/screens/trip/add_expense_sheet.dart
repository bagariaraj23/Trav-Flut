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
  String? _formError;

  @override
  void initState() {
    super.initState();
    final me = context.read<AuthProvider>().currentUser?.id;
    _payerId = me != null && widget.summary.members.any((m) => m.userId == me)
        ? me
        : widget.summary.members.first.userId;
    _selectedIds = widget.summary.members.map((m) => m.userId).toSet();
    for (final m in widget.summary.members) {
      _exactControllers[m.userId] = TextEditingController()
        ..addListener(_onSplitInputsChanged);
      _percentControllers[m.userId] = TextEditingController()
        ..addListener(_onSplitInputsChanged);
      _weightControllers[m.userId] = TextEditingController(text: '1')
        ..addListener(_onSplitInputsChanged);
    }
    _amountController.addListener(_onSplitInputsChanged);
  }

  void _onSplitInputsChanged() {
    if (!mounted) return;
    setState(() {
      _formError = _splitBalanceError();
    });
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

  String _money(int minor) =>
      formatMoneyMinor(minor, currency: widget.summary.currency);

  /// Live split balance hint (null when balanced / not applicable yet).
  String? _splitBalanceError() {
    final amount = parseRupees(_amountController.text);
    if (amount == null || amount <= 0) return null;
    if (_selectedIds.isEmpty) return null;
    final minor = rupeesToMinor(amount);

    if (_splitMethod == 'EXACT') {
      var sum = 0;
      var filled = 0;
      for (final m in _selectedMembers) {
        final v = parseRupees(_exactControllers[m.userId]!.text);
        if (v == null) continue;
        filled++;
        sum += rupeesToMinor(v);
      }
      if (filled == 0) return null;
      final diff = sum - minor;
      if (diff == 0) return null;
      if (diff < 0) {
        return 'Shares are short by ${_money(-diff)}. '
            'Entered ${_money(sum)} of ${_money(minor)}.';
      }
      return 'Shares exceed the total by ${_money(diff)}. '
          'Entered ${_money(sum)} of ${_money(minor)}.';
    }

    if (_splitMethod == 'PERCENT') {
      var bps = 0;
      var filled = 0;
      for (final m in _selectedMembers) {
        final v = double.tryParse(_percentControllers[m.userId]!.text.trim());
        if (v == null) continue;
        filled++;
        bps += (v * 100).round();
      }
      if (filled == 0) return null;
      final entered = bps / 100.0;
      final diffBps = bps - 10000;
      if (diffBps == 0) return null;
      if (diffBps < 0) {
        final short = (-diffBps / 100.0).toStringAsFixed(
          (-diffBps) % 100 == 0 ? 0 : 2,
        );
        return 'Percentages are short by $short%. '
            'Entered ${entered.toStringAsFixed(entered % 1 == 0 ? 0 : 2)}% of 100%.';
      }
      final over = (diffBps / 100.0).toStringAsFixed(
        diffBps % 100 == 0 ? 0 : 2,
      );
      return 'Percentages exceed 100% by $over%. '
          'Entered ${entered.toStringAsFixed(entered % 1 == 0 ? 0 : 2)}%.';
    }

    if (_splitMethod == 'SHARES') {
      var w = 0;
      var filled = 0;
      for (final m in _selectedMembers) {
        final v = int.tryParse(_weightControllers[m.userId]!.text.trim());
        if (v == null) continue;
        filled++;
        if (v < 0) {
          return 'Share weights cannot be negative.';
        }
        w += v;
      }
      if (filled == 0) return null;
      if (w <= 0) return 'Total shares must be greater than zero.';
    }

    return null;
  }

  String? _validate() {
    if (_amountController.text.trim().isEmpty) return 'Enter an amount';
    final amount = parseRupees(_amountController.text);
    if (amount == null || amount <= 0) return 'Enter a valid amount';
    if (_titleController.text.trim().isEmpty) return 'Add a reason / title';
    if (_selectedIds.isEmpty) return 'Select at least one person';

    if (_splitMethod == 'EXACT') {
      for (final m in _selectedMembers) {
        if (parseRupees(_exactControllers[m.userId]!.text) == null) {
          return 'Fill every exact share';
        }
      }
    }
    if (_splitMethod == 'PERCENT') {
      for (final m in _selectedMembers) {
        if (double.tryParse(_percentControllers[m.userId]!.text.trim()) == null) {
          return 'Fill every percentage';
        }
      }
    }
    if (_splitMethod == 'SHARES') {
      for (final m in _selectedMembers) {
        final v = int.tryParse(_weightControllers[m.userId]!.text.trim());
        if (v == null || v < 0) return 'Fill every share weight';
      }
    }

    return _splitBalanceError();
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      setState(() => _formError = error);
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
              'shareMinor':
                  rupeesToMinor(parseRupees(_exactControllers[m.userId]!.text)!),
            },
          )
          .toList();
    } else if (_splitMethod == 'PERCENT') {
      percentBps = _selectedMembers
          .map(
            (m) => {
              'userId': m.userId,
              'bps': (double.parse(_percentControllers[m.userId]!.text.trim()) *
                      100)
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
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          ),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      final err = context.read<ExpenseProvider>().error;
      setState(() => _formError = err ?? 'Could not save expense');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Could not save expense')),
      );
    }
  }

  Widget _sheetHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.secondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    if (_formError == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formError!,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.summary.currency;
    final canSave = _formError == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(context),
              Row(
                children: [
                  Icon(Icons.receipt_long_outlined,
                      color: Theme.of(context).colorScheme.secondary, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add expense',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _errorBanner(context),
              // 1. Amount
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${currencySymbol(currency).trim()})',
                  hintText: '1500 or 51.54',
                ),
              ),
              const SizedBox(height: 8),
              // 2. Reason / title
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Car rental, Airbnb, dinner…',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              // 3. Category
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(categoryLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 8),
              // 4. Rest
              DropdownButtonFormField<String>(
                value: _payerId,
                decoration: const InputDecoration(labelText: 'Who paid'),
                items: widget.summary.members
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.userId,
                        child: Text(_label(m)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _payerId = v ?? _payerId),
              ),
              const SizedBox(height: 12),
              _sectionLabel(context, 'Split among'),
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
                        _formError = _splitBalanceError();
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
                    onSelected: (_) => setState(() {
                      _splitMethod = method;
                      _formError = _splitBalanceError();
                    }),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                      decoration:
                          InputDecoration(labelText: '${_label(m)} shares'),
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
                      onPressed:
                          provider.isSaving || !canSave ? null : _submit,
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

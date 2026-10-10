import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/expense_provider.dart';
import 'package:tripthread/screens/trip/add_expense_sheet.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';
import 'package:tripthread/utils/money.dart';
import 'package:tripthread/utils/user_display_labels.dart';

class TripMoneyPane extends StatefulWidget {
  final String tripId;

  const TripMoneyPane({super.key, required this.tripId});

  @override
  State<TripMoneyPane> createState() => _TripMoneyPaneState();
}

class _TripMoneyPaneState extends State<TripMoneyPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
    });
  }

  Future<void> _reload() async {
    final provider = context.read<ExpenseProvider>();
    final ok = await provider.load(widget.tripId);
    if (!mounted || ok || provider.summary == null) return;
    _showError(provider.error);
  }

  Future<void> _runAction(Future<bool> Function() action) async {
    final ok = await action();
    if (!mounted || ok) return;
    _showError(context.read<ExpenseProvider>().error);
  }

  void _showError(String? message) {
    final text = (message == null || message.isEmpty) ? 'Something went wrong' : message;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _name(ExpenseSummary summary, String userId) {
    final m = _member(summary, userId);
    if (m == null) return userId;
    return userPrimaryLabel(id: m.userId, username: m.username, name: m.name);
  }

  Widget _avatar(ExpenseMemberBalance? member) {
    return ChatAvatar(
      radius: 16,
      avatarUrl: member?.avatarUrl,
      username: member?.username,
      name: member?.name,
    );
  }

  Color _warmSurfaceHighlight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkMuted
        : AppTheme.accentSoft;
  }

  ExpenseMemberBalance? _member(ExpenseSummary summary, String id) {
    for (final m in summary.members) {
      if (m.userId == id) return m;
    }
    return null;
  }

  Future<void> _openAdd(ExpenseSummary summary) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ExpenseProvider>(),
        child: AddExpenseSheet(summary: summary),
      ),
    );
  }

  String _shareLabel(ExpenseSummary summary, ExpenseShare share) {
    final fromSummary = _member(summary, share.userId);
    if (fromSummary != null) {
      return userPrimaryLabel(
        id: fromSummary.userId,
        username: fromSummary.username,
        name: fromSummary.name,
      );
    }
    final u = share.user;
    return userPrimaryLabel(
      id: share.userId,
      username: u?.username,
      name: u?.name,
    );
  }

  Future<void> _openExpenseDetail(
    ExpenseSummary summary,
    TripExpense expense,
  ) async {
    final currency = expense.currency;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Text(
                    expense.title,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                const SizedBox(height: 4),
                Text(
                  '${categoryLabel(expense.category)} · '
                  '${formatMoneyMinor(expense.amountMinor, currency: currency)} · '
                  '${expense.splitMethod == 'EQUAL' ? 'Equal split' : expense.splitMethod.toLowerCase()}',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (expense.payer != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Paid by ${userPrimaryLabel(id: expense.payer!.id, username: expense.payer!.username, name: expense.payer!.name)}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
                if (expense.note != null && expense.note!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(expense.note!),
                ],
                const SizedBox(height: 16),
                Text(
                  'Each person\'s share',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (expense.shares.isEmpty)
                  const Text('No share details available.')
                else
                  ...expense.shares.map((share) {
                    final name = _shareLabel(summary, share);
                    final pct = expense.amountMinor > 0
                        ? (share.shareMinor * 100 / expense.amountMinor)
                        : 0.0;
                    final weightNote = share.weight != null
                        ? ' · ${share.weight} share${share.weight == 1 ? '' : 's'}'
                        : '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ChatAvatar(
                        radius: 16,
                        avatarUrl: share.user?.avatarUrl,
                        username: share.user?.username,
                        name: share.user?.name ?? name,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '${pct.toStringAsFixed(pct % 1 == 0 ? 0 : 1)}%$weightNote',
                      ),
                      trailing: Text(
                        formatMoneyMinor(share.shareMinor, currency: currency),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    return AppLayout.reading(
      context: context,
      child: Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.error != null && provider.summary == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(provider.error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => provider.load(widget.tripId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final summary = provider.summary;
        if (summary == null) {
          return const Center(child: Text('No money data yet'));
        }
        final currency = summary.currency;
        String headline;
        if (summary.myNetMinor > 0) {
          headline = 'You are owed ${formatMoneyMinor(summary.myNetMinor, currency: currency)}';
        } else if (summary.myNetMinor < 0) {
          headline = 'You owe ${formatMoneyMinor(-summary.myNetMinor, currency: currency)}';
        } else {
          headline = 'All settled';
        }

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Card(
                    color: _warmSurfaceHighlight(context),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headline,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Trip total ${formatMoneyMinor(summary.totalSpendMinor, currency: currency)} · $currency',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Optimized so fewer payments settle the group.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Who pays whom', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (summary.openTransfers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('No open payments.'),
                    )
                  else
                    ...summary.openTransfers.map((t) {
                      return Card(
                        child: ListTile(
                          leading: _avatar(_member(summary, t.fromUserId)),
                          title: Text(
                            '${_name(summary, t.fromUserId)} → ${_name(summary, t.toUserId)}',
                          ),
                          subtitle: Text(
                            formatMoneyMinor(t.amountMinor, currency: currency),
                          ),
                          trailing: t.canMarkPaid
                              ? FilledButton(
                                  onPressed: () => _runAction(() => provider.markPaid(t)),
                                  child: const Text('Mark as paid'),
                                )
                              : null,
                        ),
                      );
                    }),
                  if (summary.recordedSettlements.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Already paid', style: Theme.of(context).textTheme.titleSmall),
                    ...summary.recordedSettlements.map((s) {
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${_name(summary, s.fromUserId)} paid ${_name(summary, s.toUserId)} ${formatMoneyMinor(s.amountMinor, currency: currency)}',
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  Text('Expenses', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (summary.recordedSettlements.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: _warmSurfaceHighlight(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Splits are locked after a settlement is recorded.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (provider.expenses.isEmpty)
                    const Text('No expenses yet. Log what you spent.')
                  else
                    ...provider.expenses.map((e) {
                      final payer = e.payer;
                      final splitsLocked = summary.recordedSettlements.isNotEmpty;
                      final canDelete =
                          !splitsLocked && e.createdById == currentUserId;
                      final isUnequal = e.splitMethod != 'EQUAL';
                      return Card(
                        child: ListTile(
                          onTap: () => _openExpenseDetail(summary, e),
                          leading: ChatAvatar(
                            radius: 20,
                            avatarUrl: payer?.avatarUrl,
                            username: payer?.username,
                            name: payer?.name,
                          ),
                          title: Text(e.title),
                          subtitle: Text(
                            '${categoryLabel(e.category)} · ${payer != null ? userPrimaryLabel(id: payer.id, username: payer.username, name: payer.name) : 'Someone'} paid · ${e.splitMethod == 'EQUAL' ? 'split ${e.shares.length} ways' : 'unequal'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatMoneyMinor(e.amountMinor, currency: e.currency),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (isUnequal)
                                Icon(
                                  Icons.chevron_right,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              if (canDelete)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete expense?'),
                                        content: const Text(
                                          'This removes the split. You can add a new one after.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && context.mounted) {
                                      await _runAction(() => provider.deleteExpense(e.id));
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openAdd(summary),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
            ),
          ],
        );
      },
      ),
    );
  }
}

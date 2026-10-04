import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/expense.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/expense_provider.dart';
import 'package:tripthread/screens/trip/add_expense_sheet.dart';
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
    final initial = userAvatarInitial(
      username: member?.username,
      name: member?.name,
    );
    final url = member?.avatarUrl;
    return CircleAvatar(
      radius: 16,
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty ? Text(initial) : null,
    );
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

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().currentUser?.id;
    return Consumer<ExpenseProvider>(
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
                      final fromMe = t.fromUserId == currentUserId;
                      return Card(
                        child: ListTile(
                          leading: _avatar(_member(summary, t.fromUserId)),
                          title: Text(
                            '${_name(summary, t.fromUserId)} → ${_name(summary, t.toUserId)}',
                          ),
                          subtitle: Text(
                            fromMe
                                ? 'Pay in GPay/UPI, then ${_name(summary, t.toUserId)} can mark received'
                                : formatMoneyMinor(t.amountMinor, currency: currency),
                          ),
                          trailing: t.canMarkPaid
                              ? FilledButton(
                                  onPressed: () => _runAction(() => provider.markPaid(t)),
                                  child: const Text('Mark as paid'),
                                )
                              : Text(
                                  formatMoneyMinor(t.amountMinor, currency: currency),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
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
                        trailing: s.canUndo
                            ? IconButton(
                                icon: const Icon(Icons.undo, size: 20),
                                onPressed: () => _runAction(
                                  () => provider.undoSettlement(s.id),
                                ),
                              )
                            : null,
                      );
                    }),
                  ],
                  if (summary.pairwise.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: const Text('You and others (raw bills)'),
                      children: summary.pairwise.map((p) {
                        final line = p.youOweMinor > 0
                            ? 'You owe ${formatMoneyMinor(p.youOweMinor, currency: currency)}'
                            : p.theyOweMinor > 0
                                ? 'They owe you ${formatMoneyMinor(p.theyOweMinor, currency: currency)}'
                                : 'Settled between you';
                        return ListTile(
                          dense: true,
                          title: Text(_name(summary, p.otherUserId)),
                          subtitle: Text('${p.sharedCount} shared bills · $line'),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('Expenses', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (provider.expenses.isEmpty)
                    const Text('No expenses yet. Log what you spent.')
                  else
                    ...provider.expenses.map((e) {
                      final payer = e.payer;
                      final canDelete = e.createdById == currentUserId;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: payer?.avatarUrl != null
                                ? NetworkImage(payer!.avatarUrl!)
                                : null,
                            child: payer?.avatarUrl == null
                                ? Text(userAvatarInitial(
                                    username: payer?.username,
                                    name: payer?.name,
                                  ))
                                : null,
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
    );
  }
}

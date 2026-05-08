import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final expensesQueryProvider = StateProvider.autoDispose<_ExpensesQuery>((ref) {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, 1);
  return _ExpensesQuery(
    q: '',
    category: '',
    from: DateFormat('yyyy-MM-dd').format(from),
    to: DateFormat('yyyy-MM-dd').format(today),
  );
});

final expensesControllerProvider =
    StateNotifierProvider.autoDispose<_ExpensesController, AsyncValue<List<Expense>>>((ref) {
  return _ExpensesController(ref)..load();
});

final expensesSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  return api.getJson('/expenses/summary', token: token);
});

class _ExpensesQuery {
  const _ExpensesQuery({
    required this.q,
    required this.category,
    required this.from,
    required this.to,
  });

  final String q;
  final String category;
  final String from;
  final String to;

  Map<String, String> toQuery() {
    final map = <String, String>{'limit': '200'};
    if (q.trim().isNotEmpty) map['q'] = q.trim();
    if (category.trim().isNotEmpty) map['category'] = category.trim();
    if (from.trim().isNotEmpty) map['from'] = from.trim();
    if (to.trim().isNotEmpty) map['to'] = to.trim();
    return map;
  }

  _ExpensesQuery copyWith({
    String? q,
    String? category,
    String? from,
    String? to,
  }) {
    return _ExpensesQuery(
      q: q ?? this.q,
      category: category ?? this.category,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

class _ExpensesController extends StateNotifier<AsyncValue<List<Expense>>> {
  _ExpensesController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final q = ref.read(expensesQueryProvider);
      final res = await api.getJson('/expenses', token: token, query: q.toQuery());
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Expense.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('expenses_load_failed', st);
    }
  }

  Future<void> addExpense({
    required String category,
    required double amount,
    required String expenseDate,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/expenses', token: token, body: {
      'category': category.trim(),
      'amount': amount,
      'expenseDate': expenseDate,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
    await load();
    ref.invalidate(expensesSummaryProvider);
  }

  Future<void> deleteExpense(int id) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/expenses/$id', token: token);
    await load();
    ref.invalidate(expensesSummaryProvider);
  }

  Future<void> updateExpense({
    required int expenseId,
    required String category,
    required double amount,
    required String expenseDate,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.patchJson('/expenses/$expenseId', token: token, body: {
      'category': category.trim(),
      'amount': amount,
      'expenseDate': expenseDate,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
    await load();
    ref.invalidate(expensesSummaryProvider);
  }
}

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final query = ref.watch(expensesQueryProvider);
    final itemsAsync = ref.watch(expensesControllerProvider);
    final summaryAsync = ref.watch(expensesSummaryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('Expenses', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => _openAddExpense(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.read(expensesControllerProvider.notifier).load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search (category / notes)',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => ref.read(expensesQueryProvider.notifier).state = query.copyWith(q: v),
                      onSubmitted: (_) => ref.read(expensesControllerProvider.notifier).load(),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Category (exact)',
                        prefixIcon: Icon(Icons.label),
                      ),
                      onChanged: (v) =>
                          ref.read(expensesQueryProvider.notifier).state = query.copyWith(category: v),
                      onSubmitted: (_) => ref.read(expensesControllerProvider.notifier).load(),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final start = DateTime.tryParse(query.from) ?? DateTime(now.year, now.month, 1);
                      final end = DateTime.tryParse(query.to) ?? now;
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(now.year + 1),
                        initialDateRange: DateTimeRange(start: start, end: end),
                      );
                      if (picked == null) return;
                      final f = DateFormat('yyyy-MM-dd').format(picked.start);
                      final t = DateFormat('yyyy-MM-dd').format(picked.end);
                      ref.read(expensesQueryProvider.notifier).state = query.copyWith(from: f, to: t);
                      await ref.read(expensesControllerProvider.notifier).load();
                      ref.invalidate(expensesSummaryProvider);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text('${query.from} → ${query.to}'),
                  ),
                  FilledButton(
                    onPressed: () {
                      ref.read(expensesControllerProvider.notifier).load();
                      ref.invalidate(expensesSummaryProvider);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: summaryAsync.when(
            data: (s) {
              final todayTotal = (s['today'] as Map?)?['total'] as num? ?? 0;
              final todayCount = (s['today'] as Map?)?['count'] as num? ?? 0;
              final monthTotal = (s['thisMonth'] as Map?)?['total'] as num? ?? 0;
              final monthCount = (s['thisMonth'] as Map?)?['count'] as num? ?? 0;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    title: 'Today',
                    value: number.format(todayTotal),
                    subtitle: '${todayCount.toInt()} entries',
                  ),
                  _MetricCard(
                    title: 'This Month',
                    value: number.format(monthTotal),
                    subtitle: '${monthCount.toInt()} entries',
                  ),
                ],
              );
            },
            error: (e, _) => Text(e.toString()),
            loading: () => const LinearProgressIndicator(),
          ),
        ),
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _EmptyState(
                    title: 'No expenses found',
                    subtitle: 'Add an expense or change filters.',
                    icon: Icons.account_balance_wallet,
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Category')),
                            DataColumn(label: Text('Amount')),
                            DataColumn(label: Text('Notes')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: [
                            for (final e in items)
                              DataRow(
                                cells: [
                                  DataCell(Text(e.expenseDate)),
                                  DataCell(Text(e.category)),
                                  DataCell(Text(number.format(e.amount))),
                                  DataCell(Text(e.notes ?? '-')),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'View',
                                          onPressed: () => _openViewExpense(context, e),
                                          icon: const Icon(Icons.visibility),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit',
                                          onPressed: () => _openEditExpense(context, ref, e),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        if (canDelete)
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: () => _confirmDelete(context, ref, e.id),
                                            icon: const Icon(Icons.delete_outline),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return ListTile(
                        leading: const Icon(Icons.account_balance_wallet),
                        title: Text('${e.category} • ${e.expenseDate}'),
                        subtitle: Text('Amount: ${number.format(e.amount)}${e.notes != null ? ' • ${e.notes}' : ''}'),
                        trailing: IconButton(
                          tooltip: 'Actions',
                          onPressed: () => _openExpenseActions(context, ref, e),
                          icon: const Icon(Icons.more_vert),
                        ),
                      );
                    },
                  );
                },
              );
            },
            error: (e, _) => Center(child: Text(e.toString())),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }

  Future<void> _openAddExpense(BuildContext context, WidgetRef ref) async {
    final categoryCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.add,
      title: 'Add Expense',
      subtitle: 'Record an expense entry',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 680;
          final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
          Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expense Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  field(TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category'))),
                  field(
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                  ),
                  field(
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(labelText: 'Expense Date (YYYY-MM-DD)'),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final category = categoryCtrl.text.trim();
            final amount = double.tryParse(amountCtrl.text.trim());
            final date = dateCtrl.text.trim();
            if (category.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category required')));
              return;
            }
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid amount')));
              return;
            }
            try {
              await ref.read(expensesControllerProvider.notifier).addExpense(
                    category: category,
                    amount: amount,
                    expenseDate: date,
                    notes: notesCtrl.text,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense added')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    categoryCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
    dateCtrl.dispose();
  }

  void _openViewExpense(BuildContext context, Expense e) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Expense'),
          content: Text(
            [
              'Date: ${e.expenseDate}',
              'Category: ${e.category}',
              'Amount: ${e.amount}',
              if (e.notes != null) 'Notes: ${e.notes}',
            ].join('\n'),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _openEditExpense(BuildContext context, WidgetRef ref, Expense e) async {
    final categoryCtrl = TextEditingController(text: e.category);
    final amountCtrl = TextEditingController(text: e.amount.toString());
    final notesCtrl = TextEditingController(text: e.notes ?? '');
    final dateCtrl = TextEditingController(text: e.expenseDate);

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.edit_outlined,
      title: 'Edit Expense',
      subtitle: '${e.category} • ${e.expenseDate}',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 680;
          final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
          Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expense Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  field(TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Category'))),
                  field(
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                  ),
                  field(
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(labelText: 'Expense Date (YYYY-MM-DD)'),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () async {
            final amount = double.tryParse(amountCtrl.text.trim());
            if (categoryCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category required')));
              return;
            }
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid amount')));
              return;
            }
            try {
              await ref.read(expensesControllerProvider.notifier).updateExpense(
                    expenseId: e.id,
                    category: categoryCtrl.text,
                    amount: amount,
                    expenseDate: dateCtrl.text.trim(),
                    notes: notesCtrl.text,
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
            } on ApiException catch (er) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(er.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );

    categoryCtrl.dispose();
    amountCtrl.dispose();
    notesCtrl.dispose();
    dateCtrl.dispose();
  }

  void _openExpenseActions(BuildContext context, WidgetRef ref, Expense e) {
    final roles = ref.read(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View'),
                onTap: () => Navigator.of(context).pop('view'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
            ],
          ),
        );
      },
    ).then((selected) {
      if (!context.mounted) return;
      if (selected == 'view') _openViewExpense(context, e);
      if (selected == 'edit') _openEditExpense(context, ref, e);
      if (selected == 'delete' && canDelete) _confirmDelete(context, ref, e.id);
    });
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, int expenseId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete expense?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(expensesControllerProvider.notifier).deleteExpense(expenseId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }
}

class _MetricCard extends StatefulWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: _hover ? 1.015 : 1,
          child: Card(
            elevation: _hover ? 6 : 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _hover
                    ? [
                        BoxShadow(
                          color: const Color(0xFFD4AF37).withAlpha(28),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        )
                      ]
                    : const [],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.value, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(icon, size: 28),
                ),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

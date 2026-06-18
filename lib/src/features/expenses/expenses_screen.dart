import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/form_dialog.dart';
import '../../core/in_app_pdf.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
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
    state = const AsyncLoading<List<Expense>>().copyWithPrevious(state);
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
    String? paymentSource,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/expenses', token: token, body: {
      'category': category.trim(),
      'amount': amount,
      'expenseDate': expenseDate,
      'paymentSource': paymentSource?.trim().isEmpty == true ? null : paymentSource?.trim(),
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

  String _fmtDateOnly(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '-';
    final m = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(s);
    if (m != null) return m.group(0)!;
    final d = DateTime.tryParse(s);
    if (d == null) return s;
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  Future<void> _openExpensesPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Expenses PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runExpensesPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runExpensesPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runExpensesPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/expenses.pdf', token: token);
      final name = 'expenses_$today.pdf';
      if (!context.mounted) return;
      // In-app preview (no external launcher); download saves to disk.
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Expenses Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Global "+" Quick Action → open Add Expense modal once on arrival.
    // Self-guarding via the provider value (this is a stateless ConsumerWidget).
    if (ref.watch(pendingQuickActionProvider) == QuickAction.recordExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (ref.read(pendingQuickActionProvider) != QuickAction.recordExpense) return;
        ref.read(pendingQuickActionProvider.notifier).state = null;
        _openAddExpense(context, ref);
      });
    }
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final query = ref.watch(expensesQueryProvider);
    final itemsAsync = ref.watch(expensesControllerProvider);
    final summaryAsync = ref.watch(expensesSummaryProvider);
    final isDark = theme.brightness == Brightness.dark;

    // ── Left: expense ledger track (table or dashed empty state) ───────────
    Widget ledgerTrack() {
      return itemsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 360),
              child: AppDashedPanel(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 52,
                          width: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFE06C6C).withAlpha(22),
                          ),
                          child: const Icon(Icons.account_balance_wallet_outlined, size: 26, color: Color(0xFFE06C6C)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No expenses found',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add an expense or change the filters above.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          // Bordered table panel — Inter typography + faint dividers.
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surface,
              border: Border.all(
                color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant,
                width: 0.8,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: theme.copyWith(
                  dividerColor: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                  dataTableTheme: DataTableThemeData(
                    dividerThickness: 1,
                    headingTextStyle: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    dataTextStyle: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    headingRowColor: WidgetStatePropertyAll(
                      isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
                    ),
                  ),
                ),
                child: DataTable(
                  headingRowHeight: 48,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 58,
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
                          DataCell(Text(_fmtDateOnly(e.expenseDate))),
                          DataCell(Text(e.category)),
                          DataCell(Text(
                            number.format(e.amount),
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          )),
                          DataCell(Text(e.notes ?? '-')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppTableActionButton(
                                  icon: Icons.visibility_outlined,
                                  tooltip: 'View',
                                  onPressed: () => _openViewExpense(context, e),
                                ),
                                const SizedBox(width: 2),
                                AppTableActionButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Edit',
                                  onPressed: () => _openEditExpense(context, ref, e),
                                ),
                                if (canDelete) ...[
                                  const SizedBox(width: 2),
                                  AppTableActionButton(
                                    icon: Icons.delete_outline,
                                    tooltip: 'Delete',
                                    danger: true,
                                    onPressed: () => _confirmDelete(context, ref, e.id),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        error: (e, _) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 360),
          child: Center(child: Text(e.toString())),
        ),
        loading: () => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 360),
          child: const Center(child: SizedBox.square(dimension: 32, child: CircularProgressIndicator())),
        ),
      );
    }

    // ── Right: financial summary sidebar (Today + This Month stacked) ──────
    Widget metricsSidebar() {
      return summaryAsync.when(
        data: (s) {
          final todayTotal = (s['today'] as Map?)?['total'] as num? ?? 0;
          final todayCount = (s['today'] as Map?)?['count'] as num? ?? 0;
          final monthTotal = (s['thisMonth'] as Map?)?['total'] as num? ?? 0;
          final monthCount = (s['thisMonth'] as Map?)?['count'] as num? ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetricCard(
                title: 'Today',
                value: number.format(todayTotal),
                subtitle: '${todayCount.toInt()} entries',
                icon: Icons.today_outlined,
                accent: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'This Month',
                value: number.format(monthTotal),
                subtitle: '${monthCount.toInt()} entries',
                icon: Icons.calendar_month_outlined,
                accent: const Color(0xFFF59E0B),
              ),
            ],
          );
        },
        error: (e, _) => Text(e.toString()),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
      );
    }

    return ListView(
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
                tooltip: 'PDF',
                onPressed: () => _openExpensesPdfActions(context, ref),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.read(expensesControllerProvider.notifier).load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        // ── Streamlined filter bar (controls locked to 40px) ──────────────
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
                    width: 300,
                    height: 40,
                    child: TextField(
                      style: GoogleFonts.inter(fontSize: 13.5),
                      decoration: appDenseInputDecoration(
                        context,
                        hint: 'Search category / notes',
                        prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      onChanged: (v) => ref.read(expensesQueryProvider.notifier).state = query.copyWith(q: v),
                      onSubmitted: (_) => ref.read(expensesControllerProvider.notifier).load(),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    height: 40,
                    child: TextField(
                      style: GoogleFonts.inter(fontSize: 13.5),
                      decoration: appDenseInputDecoration(
                        context,
                        hint: 'Category (exact)',
                        prefixIcon: Icon(Icons.label_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      onChanged: (v) =>
                          ref.read(expensesQueryProvider.notifier).state = query.copyWith(category: v),
                      onSubmitted: (_) => ref.read(expensesControllerProvider.notifier).load(),
                    ),
                  ),
                  // Date range builder — same 40px height.
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
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
                      icon: Icon(Icons.calendar_today_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                      label: Text(
                        '${query.from} → ${query.to}',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(
                          color: isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(28),
                          width: 0.8,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: FilledButton(
                      onPressed: () {
                        ref.read(expensesControllerProvider.notifier).load();
                        ref.invalidate(expensesSummaryProvider);
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        textStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Split console: Ledger (75%) + Summary sidebar (25%) ────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth >= 980) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: ledgerTrack()),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: metricsSidebar()),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  metricsSidebar(),
                  const SizedBox(height: 16),
                  ledgerTrack(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openAddExpense(BuildContext context, WidgetRef ref) async {
    final items = ref.read(expensesControllerProvider).valueOrNull ?? const <Expense>[];
    final categoryOptions = <String>{
      'Rent',
      'Electricity',
      'Internet',
      'Cleaning',
      'Supplies',
      'Equipment Repair',
      'Maintenance',
      'Salaries',
      'Other',
      for (final e in items) e.category.trim(),
    }.where((e) => e.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    TextEditingController? categoryAutoCtrl;
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final formKey = GlobalKey<FormState>();
    const paymentSourceOptions = <String>[
      'Petty Cash',
      'Main Bank Account',
      'Owner\'s Wallet',
      'Card',
    ];
    String paymentSource = paymentSourceOptions.first;
    String? receiptName;

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.add,
      title: 'Add Expense',
      subtitle: 'Record an expense entry',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Form(
            key: formKey,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormSectionLabel(
                'Expense Details',
                hint: 'Logged to the cash book for clean, audit-ready bookkeeping.',
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 16),
              // Category | Amount
              FormRow([
                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (q.isEmpty) return categoryOptions.take(8);
                    return categoryOptions.where((o) => o.toLowerCase().contains(q)).take(8);
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final theme = Theme.of(context);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(14),
                        color: theme.colorScheme.surface,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 460),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: Icon(_expenseCategoryIcon(option), size: 18),
                                title: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (v) => categoryAutoCtrl?.text = v,
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    categoryAutoCtrl ??= textEditingController;
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        hintText: 'Rent, Electricity, Supplies...',
                      ),
                    );
                  },
                ),
                _ExpenseAmountField(controller: amountCtrl),
              ]),
              const SizedBox(height: 16),
              // Expense Date | Payment Source
              FormRow([
                TextField(
                  controller: dateCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Expense Date',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: () async {
                    final current = DateTime.tryParse(dateCtrl.text.trim());
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: current ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: paymentSource,
                  decoration: const InputDecoration(
                    labelText: 'Payment Source',
                    helperText: 'Which account funded this',
                  ),
                  items: [
                    for (final s in paymentSourceOptions)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setModalState(() => paymentSource = v ?? paymentSourceOptions.first),
                ),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Vendor, bill reference, or reason for the expense.',
                  alignLabelWithHint: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 18),
              const FormSectionLabel('Receipt Voucher', icon: Icons.attach_file_outlined),
              const SizedBox(height: 12),
              _ReceiptDropZone(
                fileName: receiptName,
                onPick: () => setModalState(
                  () => receiptName = receiptName == null ? 'receipt_voucher.pdf' : null,
                ),
              ),
            ],
          ),
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
            // Close any open Autocomplete overlay / keyboard before the dialog
            // pops, so the options overlay disposes cleanly (prevents the
            // framework "_dependents.isEmpty" assertion on dismiss).
            FocusScope.of(context).unfocus();
            final category = categoryAutoCtrl?.text.trim() ?? '';
            final date = dateCtrl.text.trim();
            if (category.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category required')));
              return;
            }
            // TextFormField validator drives the amount check inline.
            if (!(formKey.currentState?.validate() ?? false)) return;
            final amount = double.parse(amountCtrl.text.trim());
            try {
              await ref.read(expensesControllerProvider.notifier).addExpense(
                    category: category,
                    amount: amount,
                    expenseDate: date,
                    paymentSource: paymentSource,
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
              'Date: ${_fmtDateOnly(e.expenseDate)}',
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
    final items = ref.read(expensesControllerProvider).valueOrNull ?? const <Expense>[];
    final categoryOptions = <String>{
      'Rent',
      'Electricity',
      'Internet',
      'Cleaning',
      'Supplies',
      'Equipment Repair',
      'Maintenance',
      'Salaries',
      'Other',
      for (final x in items) x.category.trim(),
    }.where((x) => x.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    TextEditingController? categoryAutoCtrl;
    final amountCtrl = TextEditingController(text: e.amount.toString());
    final notesCtrl = TextEditingController(text: e.notes ?? '');
    final dateCtrl = TextEditingController(text: _fmtDateOnly(e.expenseDate));
    final formKey = GlobalKey<FormState>();

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.edit_outlined,
      title: 'Edit Expense',
      subtitle: '${e.category} • ${_fmtDateOnly(e.expenseDate)}',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= 680;
          final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
          Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

          return Form(
            key: formKey,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expense Details', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  field(
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: e.category),
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return categoryOptions.take(8);
                        return categoryOptions.where((o) => o.toLowerCase().contains(q)).take(8);
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final theme = Theme.of(context);
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 10,
                            borderRadius: BorderRadius.circular(14),
                            color: theme.colorScheme.surface,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 460),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(_expenseCategoryIcon(option), size: 18),
                                    title: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                      onSelected: (v) => categoryAutoCtrl?.text = v,
                      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                        categoryAutoCtrl ??= textEditingController;
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: const InputDecoration(labelText: 'Category'),
                        );
                      },
                    ),
                  ),
                  field(_ExpenseAmountField(controller: amountCtrl)),
                  field(
                    TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Expense Date', suffixIcon: Icon(Icons.calendar_today_outlined)),
                      onTap: () async {
                        final current = DateTime.tryParse(dateCtrl.text.trim());
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: current ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked == null) return;
                        dateCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                      },
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
          ),
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
            FocusScope.of(context).unfocus();
            final category = categoryAutoCtrl?.text.trim() ?? '';
            if (category.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category required')));
              return;
            }
            if (!(formKey.currentState?.validate() ?? false)) return;
            final amount = double.parse(amountCtrl.text.trim());
            try {
              await ref.read(expensesControllerProvider.notifier).updateExpense(
                    expenseId: e.id,
                    category: category,
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

    amountCtrl.dispose();
    notesCtrl.dispose();
    dateCtrl.dispose();
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

IconData _expenseCategoryIcon(String raw) {
  final v = raw.trim().toLowerCase();
  if (v.contains('rent')) return Icons.apartment;
  if (v.contains('electric')) return Icons.bolt;
  if (v.contains('internet') || v.contains('wifi')) return Icons.wifi;
  if (v.contains('clean')) return Icons.cleaning_services;
  if (v.contains('supply')) return Icons.inventory_2;
  if (v.contains('equip') || v.contains('repair')) return Icons.build_circle_outlined;
  if (v.contains('maint')) return Icons.handyman_outlined;
  if (v.contains('salary') || v.contains('staff')) return Icons.badge_outlined;
  if (v.contains('water')) return Icons.water_drop_outlined;
  if (v.contains('marketing') || v.contains('ads')) return Icons.campaign_outlined;
  if (v.contains('other') || v.contains('misc')) return Icons.more_horiz;
  return Icons.category_outlined;
}

/// Dashed "upload receipt" drop-zone shown in the Add Expense form. A clean
/// corporate placeholder for attaching the scanned invoice/voucher to the
/// expense record for the audit trail.
class _ReceiptDropZone extends StatelessWidget {
  const _ReceiptDropZone({required this.fileName, required this.onPick});

  final String? fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasFile = fileName != null && fileName!.trim().isNotEmpty;

    if (hasFile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.primary.withAlpha(18),
          border: Border.all(color: cs.primary.withAlpha(90)),
        ),
        child: Row(
          children: [
            Icon(Icons.description_outlined, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Attached • ready to upload on save',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onPick,
              icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return AppDashedPanel(
      radius: 14,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: cs.primary.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cloud_upload_outlined, color: cs.primary),
            ),
            const SizedBox(height: 10),
            Text(
              'Attach receipt voucher',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'PDF, JPG or PNG — keeps your expense audit clean',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Upload Invoice File'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Premium currency amount field for the expense modals. Numeric-only with a
/// decimal keyboard, an allow-list formatter that blocks non-numeric input at
/// the keystroke level, a floating label, brand-accent wallet glyph, and an
/// inline validator. Borders/fill come from the global InputDecorationTheme so
/// it stays pixel-consistent with the "Category" field and respects the live
/// brand colour.
class _ExpenseAmountField extends StatelessWidget {
  const _ExpenseAmountField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final brand = Theme.of(context).colorScheme.primary;
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      decoration: InputDecoration(
        labelText: 'Expense Amount (Rs.)',
        hintText: '0.00',
        prefixIcon: Icon(Icons.account_balance_wallet_rounded, color: brand),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter the expense amount';
        }
        final parsed = double.tryParse(value.trim());
        if (parsed == null || parsed <= 0) {
          return 'Please enter a valid numeric amount';
        }
        return null;
      },
    );
  }
}

/// Financial summary card for the right-hand sidebar. Fills its parent width
/// and renders the accumulation figure in Bebas Neue.
class _MetricCard extends StatefulWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
          border: Border.all(
            color: _hover
                ? widget.accent.withAlpha(90)
                : (isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant),
            width: _hover ? 1.0 : 0.8,
          ),
          boxShadow: _hover
              ? [BoxShadow(color: widget.accent.withAlpha(40), blurRadius: 26, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withAlpha(isDark ? 55 : 12), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: widget.accent.withAlpha(28),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: widget.accent.withAlpha(60), width: 0.8),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.value,
                  maxLines: 1,
                  style: GoogleFonts.bebasNeue(
                    fontSize: 38,
                    height: 1.0,
                    letterSpacing: 1.5,
                    color: widget.accent,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


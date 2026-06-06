import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/in_app_pdf.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final paymentsQueryProvider = StateProvider.autoDispose<_PaymentsQuery>((ref) {
  final today = DateTime.now();
  final from = DateTime(today.year, today.month, 1);
  return _PaymentsQuery(
    q: '',
    method: '',
    from: DateFormat('yyyy-MM-dd').format(from),
    to: DateFormat('yyyy-MM-dd').format(today),
    limit: 50,
    offset: 0,
    sort: 'newest',
  );
});

final paymentsControllerProvider =
    StateNotifierProvider.autoDispose<_PaymentsController, AsyncValue<_PaymentsPage>>((ref) {
  return _PaymentsController(ref)..load();
});

final paymentsSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  return api.getJson('/payments/summary', token: token);
});

/// Searches unpaid + partially-paid invoices for the Record Payment picker.
/// Query is debounced in the modal; this provider just holds the result list.
final unpaidInvoiceSearchProvider =
    StateNotifierProvider.autoDispose<_UnpaidInvoiceSearch, AsyncValue<List<Invoice>>>((ref) {
  return _UnpaidInvoiceSearch(ref)..load('');
});

class _UnpaidInvoiceSearch extends StateNotifier<AsyncValue<List<Invoice>>> {
  _UnpaidInvoiceSearch(this.ref) : super(const AsyncValue.data([]));

  final Ref ref;

  Future<void> load(String q) async {
    state = const AsyncLoading<List<Invoice>>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final query = <String, String>{'status': 'unpaid,partial', 'limit': '40'};
      if (q.trim().isNotEmpty) query['q'] = q.trim();
      final res = await api.getJson('/invoices', token: token, query: query);
      final raw = res['items'] as List<dynamic>? ?? [];
      // Accept both 'unpaid' and 'partial'/'partially_paid' statuses.
      final items = raw
          .whereType<Map>()
          .map((e) => Invoice.fromJson(e.cast<String, dynamic>()))
          .where((inv) =>
              inv.status == 'unpaid' ||
              inv.status == 'partial' ||
              inv.status == 'partially_paid')
          .toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

class _PaymentsQuery {
  const _PaymentsQuery({
    required this.q,
    required this.method,
    required this.from,
    required this.to,
    required this.limit,
    required this.offset,
    required this.sort,
  });

  final String q;
  final String method;
  final String from;
  final String to;
  final int limit;
  final int offset;
  final String sort;

  Map<String, String> toQuery() {
    final map = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      'sort': sort,
    };
    if (q.trim().isNotEmpty) map['q'] = q.trim();
    if (method.trim().isNotEmpty) map['method'] = method.trim();
    if (from.trim().isNotEmpty) map['from'] = from.trim();
    if (to.trim().isNotEmpty) map['to'] = to.trim();
    return map;
  }

  _PaymentsQuery copyWith({
    String? q,
    String? method,
    String? from,
    String? to,
    int? limit,
    int? offset,
    String? sort,
  }) {
    return _PaymentsQuery(
      q: q ?? this.q,
      method: method ?? this.method,
      from: from ?? this.from,
      to: to ?? this.to,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sort: sort ?? this.sort,
    );
  }
}

class _PaymentsPage {
  const _PaymentsPage({required this.items, required this.total, required this.limit, required this.offset});

  final List<Payment> items;
  final int total;
  final int limit;
  final int offset;
}

class _PaymentsController extends StateNotifier<AsyncValue<_PaymentsPage>> {
  _PaymentsController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncLoading<_PaymentsPage>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final q = ref.read(paymentsQueryProvider);
      final res = await api.getJson('/payments', token: token, query: q.toQuery());
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Payment.fromJson(e.cast<String, dynamic>()))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      state = AsyncValue.data(_PaymentsPage(items: items, total: total, limit: q.limit, offset: q.offset));
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('payments_load_failed', st);
    }
  }

  Future<void> nextPage() async {
    final page = state.valueOrNull;
    if (page == null) return;
    final next = page.offset + page.limit;
    if (next >= page.total) return;
    final q = ref.read(paymentsQueryProvider);
    ref.read(paymentsQueryProvider.notifier).state = q.copyWith(offset: next);
    await load();
  }

  Future<void> prevPage() async {
    final q = ref.read(paymentsQueryProvider);
    final prev = max(0, q.offset - q.limit);
    ref.read(paymentsQueryProvider.notifier).state = q.copyWith(offset: prev);
    await load();
  }

  /// Records a manual payment against an invoice.
  ///
  /// Ledger re-evaluation:
  /// - A new payment row is created via POST /payments.
  /// - If [amount] ≥ invoice [balance], the invoice is marked `paid`.
  /// - If [amount] < invoice [balance], it is marked `partial` / `partially_paid`.
  /// Both mutations are handled server-side by the `/payments/record` endpoint;
  /// we only need to send [invoiceId], [amount], [method], and [reference].
  Future<void> recordPayment({
    required int invoiceId,
    required double amount,
    required String method,
    String? reference,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await api.postJson('/payments/record', token: token, body: {
      'invoiceId': invoiceId,
      'amount': amount,
      'method': method,
      'reference': clean(reference),
    });
    await load();
    ref.invalidate(paymentsSummaryProvider);
  }

  Future<void> updatePayment({
    required int paymentId,
    required String method,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.patchJson('/payments/$paymentId', token: token, body: {'method': method});
    await load();
    ref.invalidate(paymentsSummaryProvider);
  }

  Future<void> deletePayment(int paymentId) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/payments/$paymentId', token: token);
    await load();
    ref.invalidate(paymentsSummaryProvider);
  }
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();

  Future<void> _openPaymentsPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Payments PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPaymentsPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPaymentsPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runPaymentsPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/payments.pdf', token: token);
      final name = 'payments_$today.pdf';
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Payments Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(paymentsControllerProvider.notifier).load();
    });
  }

  Future<void> _openRecordPayment(BuildContext context, WidgetRef ref) async {
    final pretty = DateFormat('dd MMM yyyy');
    final searchCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final referenceCtrl = TextEditingController();
    Timer? searchDebounce;

    Invoice? selectedInvoice;
    String paymentMethod = 'cash';

    final formKey = GlobalKey<FormState>();

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.payments_outlined,
      title: 'Record Manual Payment',
      subtitle: 'Log a partial or full payment against an open invoice',
      maxWidth: 820,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final invoicesAsync = r.watch(unpaidInvoiceSearchProvider);

              void onInvoiceSelected(Invoice inv) {
                setModalState(() {
                  selectedInvoice = inv;
                  amountCtrl.text = inv.balance.toStringAsFixed(2);
                });
              }

              return Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── SECTION 1: Invoice Picker ─────────────────────────
                    const FormSectionLabel(
                      'Invoice',
                      hint: 'Search by invoice number, member name, or code. Only open (unpaid / partially paid) invoices appear.',
                      icon: Icons.receipt_long_outlined,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Search Invoice',
                        hintText: 'Invoice no., member name or code…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        searchDebounce?.cancel();
                        searchDebounce = Timer(const Duration(milliseconds: 320), () {
                          r.read(unpaidInvoiceSearchProvider.notifier).load(v);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    // Results list
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: invoicesAsync.when(
                        data: (invoices) {
                          if (invoices.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  searchCtrl.text.isEmpty
                                      ? 'All invoices are settled — no open balances.'
                                      : 'No matching unpaid invoices.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: invoices.length,
                            separatorBuilder: (_, si) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final inv = invoices[i];
                              final isSelected = selectedInvoice?.id == inv.id;
                              final accent = Theme.of(context).colorScheme.primary;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: accent.withAlpha(22),
                                leading: Icon(
                                  Icons.receipt_outlined,
                                  size: 18,
                                  color: isSelected ? accent : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                title: Text(
                                  '${inv.invoiceNo} — ${inv.memberName}',
                                  style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                                ),
                                subtitle: Text(
                                  'Due: ${inv.balance.toStringAsFixed(2)}  •  Total: ${inv.total.toStringAsFixed(2)}  •  ${pretty.format(DateTime.tryParse(inv.createdAt) ?? DateTime.now())}',
                                ),
                                trailing: _InvoiceStatusPill(status: inv.status),
                                onTap: () => onInvoiceSelected(inv),
                              );
                            },
                          );
                        },
                        error: (e, _) => Center(child: Text(e.toString())),
                        loading: () => const Center(child: CircularProgressIndicator()),
                      ),
                    ),

                    // Selected invoice summary card
                    if (selectedInvoice != null) ...[
                      const SizedBox(height: 10),
                      _SelectedInvoiceBanner(invoice: selectedInvoice!),
                    ],

                    const SizedBox(height: 18),
                    // ── SECTION 2: Amount ─────────────────────────────────
                    const FormSectionLabel(
                      'Payment Details',
                      hint: 'Amount auto-fills to the outstanding balance. Edit for partial payments.',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    const SizedBox(height: 12),
                    // Amount input — full width
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount Received',
                        hintText: selectedInvoice == null
                            ? 'Select an invoice first'
                            : 'Balance due: ${selectedInvoice!.balance.toStringAsFixed(2)}',
                        prefixIcon: const Icon(Icons.currency_rupee),
                      ),
                      validator: (v) {
                        if (selectedInvoice == null) return 'Select an invoice first';
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Enter a valid amount';
                        if (n > selectedInvoice!.total) return 'Cannot exceed invoice total';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // ── SECTION 3: Method | Reference (2-column row) ──────
                    FormRow([
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        decoration: const InputDecoration(labelText: 'Payment Mode'),
                        items: const [
                          DropdownMenuItem(value: 'cash',
                              child: Row(children: [Icon(Icons.money, size: 18), SizedBox(width: 8), Text('Cash')])),
                          DropdownMenuItem(value: 'card',
                              child: Row(children: [Icon(Icons.credit_card, size: 18), SizedBox(width: 8), Text('Card')])),
                          DropdownMenuItem(value: 'bank',
                              child: Row(children: [Icon(Icons.account_balance, size: 18), SizedBox(width: 8), Text('Bank Transfer')])),
                          DropdownMenuItem(value: 'online',
                              child: Row(children: [Icon(Icons.smartphone, size: 18), SizedBox(width: 8), Text('Online (JazzCash/EasyPaisa)')])),
                        ],
                        onChanged: (v) => setModalState(() => paymentMethod = v ?? 'cash'),
                      ),
                      TextFormField(
                        controller: referenceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Transaction / Reference ID',
                          hintText: 'Optional — cheque no., TRX ID…',
                        ),
                      ),
                    ]),

                    // Ledger preview: show what status the invoice will become
                    if (selectedInvoice != null)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: amountCtrl,
                        builder: (context, val, _) {
                          final entered = double.tryParse(val.text.trim());
                          if (entered == null || entered <= 0) return const SizedBox.shrink();
                          final inv = selectedInvoice!;
                          final willFullySettle = entered >= inv.balance;
                          final remaining = (inv.balance - entered).clamp(0, double.infinity);
                          return Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _LedgerPreviewBanner(
                              amountEntered: entered,
                              balance: inv.balance.toDouble(),
                              remaining: remaining.toDouble(),
                              willFullySettle: willFullySettle,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final amount = double.tryParse(amountCtrl.text.trim());
            if (amount == null || amount <= 0 || selectedInvoice == null) return;
            try {
              await ref.read(paymentsControllerProvider.notifier).recordPayment(
                    invoiceId: selectedInvoice!.id,
                    amount: amount,
                    method: paymentMethod,
                    reference: referenceCtrl.text,
                  );
              // Also refresh the invoices list so status badges update globally.
              ref.invalidate(unpaidInvoiceSearchProvider);
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              final settled = amount >= selectedInvoice!.balance;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    settled
                        ? 'Payment recorded — invoice marked Paid ✓'
                        : 'Partial payment recorded — invoice marked Partially Paid',
                  ),
                  backgroundColor: settled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              );
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to record payment')));
            }
          },
          label: const Text('Record Payment'),
        ),
      ],
    ).whenComplete(() {
      searchCtrl.dispose();
      amountCtrl.dispose();
      referenceCtrl.dispose();
      searchDebounce?.cancel();
    });
  }

  void _applyQuery(_PaymentsQuery query, {String? q, String? method, String? from, String? to, bool load = false}) {
    ref.read(paymentsQueryProvider.notifier).state = query.copyWith(
      q: q,
      method: method,
      from: from,
      to: to,
      offset: 0,
    );
    if (load) {
      ref.read(paymentsControllerProvider.notifier).load();
    }
  }

  Widget _build(BuildContext context, WidgetRef ref, _PaymentsScreenState state) {
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final dt = DateFormat('yyyy-MM-dd HH:mm');
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final query = ref.watch(paymentsQueryProvider);
    final itemsAsync = ref.watch(paymentsControllerProvider);
    // Pagination is computed page-locally in the footer (see ledgerTrack).
    final summaryAsync = ref.watch(paymentsSummaryProvider);

    if (_searchCtrl.text != query.q && !_searchFocus.hasFocus) {
      _searchCtrl.text = query.q;
    }

    String fmtDateTime(String raw) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return raw;
      return dt.format(parsed);
    }

    Future<void> openEdit(Payment p) async {
      var method = p.method;

      await showAppFormDialog<void>(
        context: context,
        icon: Icons.edit_outlined,
        title: 'Edit Payment',
        subtitle: '${p.invoiceNo} • ${p.memberName}',
        body: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(method),
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'online', child: Text('Online')),
                  ],
                  onChanged: (v) => setModalState(() => method = v ?? method),
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
              try {
                await ref.read(paymentsControllerProvider.notifier).updatePayment(paymentId: p.id, method: method);
                if (!context.mounted) return;
                Navigator.of(context, rootNavigator: true).maybePop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment updated')));
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
    }

    Future<void> confirmDelete(Payment p) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Delete payment?'),
            content: Text(
              'Delete payment for ${p.invoiceNo}?\nThis may revert invoice status to Unpaid.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
            ],
          );
        },
      );
      if (ok != true) return;
      try {
        await ref.read(paymentsControllerProvider.notifier).deletePayment(p.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment deleted')));
      } on ApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
      }
    }

    final isDark = theme.brightness == Brightness.dark;

    // Pagination footer attached under the ledger table.
    Widget paginationFooter(_PaymentsPage page) {
      final items = page.items;
      final f = page.total == 0 ? 0 : page.offset + 1;
      final t = min(page.offset + items.length, page.total);
      final cp = page.offset > 0;
      final cn = page.offset + items.length < page.total;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            Text(
              page.total == 0
                  ? 'No payments'
                  : 'Showing ${number.format(f)}-${number.format(t)} of ${number.format(page.total)}',
              style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Previous',
              visualDensity: VisualDensity.compact,
              onPressed: cp ? () => ref.read(paymentsControllerProvider.notifier).prevPage() : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Next',
              visualDensity: VisualDensity.compact,
              onPressed: cn ? () => ref.read(paymentsControllerProvider.notifier).nextPage() : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
    }

    // ── Left: Main Ledger track (table or dashed empty state) ──────────────
    Widget ledgerTrack() {
      return itemsAsync.when(
        data: (page) {
          final items = page.items;
          if (items.isEmpty) {
            // Full-width dashed outer-bound empty panel.
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
                          child: const Icon(Icons.payments_outlined, size: 26, color: Color(0xFFE06C6C)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No payments found',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Try changing the date range or search above.',
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

          // Bordered table panel with a seamlessly attached footer.
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
            child: Column(
              children: [
                SingleChildScrollView(
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
                        DataColumn(label: Text('Invoice')),
                        DataColumn(label: Text('Member')),
                        DataColumn(label: Text('Amount')),
                        DataColumn(label: Text('Method')),
                        DataColumn(label: Text('Paid At')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: [
                        for (final p in items)
                          DataRow(
                            cells: [
                              DataCell(Text(p.invoiceNo)),
                              DataCell(Text('${p.memberName} (${p.memberCode})')),
                              DataCell(Text(
                                number.format(p.amount),
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              )),
                              DataCell(_MethodChip(method: p.method)),
                              DataCell(Text(fmtDateTime(p.paidAt))),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppTableActionButton(
                                      icon: Icons.visibility_outlined,
                                      tooltip: 'View',
                                      onPressed: () => _openView(context, p),
                                    ),
                                    const SizedBox(width: 2),
                                    AppTableActionButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Edit',
                                      onPressed: () => openEdit(p),
                                    ),
                                    if (canDelete) ...[
                                      const SizedBox(width: 2),
                                      AppTableActionButton(
                                        icon: Icons.delete_outline,
                                        tooltip: 'Delete',
                                        danger: true,
                                        onPressed: () => confirmDelete(p),
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
                paginationFooter(page),
              ],
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

    // ── Right: Metrics sidebar (3 stacked collection cards) ────────────────
    Widget metricsSidebar() {
      return summaryAsync.when(
        data: (s) {
          final todayTotal = (s['today'] as Map?)?['total'] as num? ?? 0;
          final todayCount = (s['today'] as Map?)?['count'] as num? ?? 0;
          final last7Total = (s['last7Days'] as Map?)?['total'] as num? ?? 0;
          final last30Total = (s['last30Days'] as Map?)?['total'] as num? ?? 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetricCard(
                title: 'Today',
                value: number.format(todayTotal),
                subtitle: '${todayCount.toInt()} payments',
                icon: Icons.today_outlined,
                accent: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Last 7 days',
                value: number.format(last7Total),
                subtitle: 'Collection',
                icon: Icons.calendar_view_week_outlined,
                accent: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'Last 30 days',
                value: number.format(last30Total),
                subtitle: 'Collection',
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
              Expanded(child: Text('Payments', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => _openRecordPayment(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Record'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'PDF',
                onPressed: () => widget._openPaymentsPdfActions(context, ref),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.read(paymentsControllerProvider.notifier).load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        // ── Streamlined filter bar (40px controls; pagination decoupled) ──
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
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      style: GoogleFonts.inter(fontSize: 13.5),
                      decoration: appDenseInputDecoration(
                        context,
                        hint: 'Search invoice / member / code',
                        prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      onChanged: (v) {
                        _applyQuery(query, q: v);
                        _scheduleReload();
                      },
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        ref.read(paymentsControllerProvider.notifier).load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    height: 40,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(query.method),
                      initialValue: query.method,
                      isDense: true,
                      isExpanded: true,
                      style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                      decoration: appDenseInputDecoration(context),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Methods')),
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank')),
                        DropdownMenuItem(value: 'online', child: Text('Online')),
                      ],
                      onChanged: (v) => _applyQuery(query, method: v ?? '', load: true),
                    ),
                  ),
                  // Date range builder — locked to the same 40px height.
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
                        _applyQuery(query, from: f, to: t);
                        await ref.read(paymentsControllerProvider.notifier).load();
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
                      onPressed: () => ref.read(paymentsControllerProvider.notifier).load(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        textStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                  AppFilterPill(
                    label: 'Reset',
                    icon: Icons.restart_alt_rounded,
                    selected: false,
                    onTap: () {
                      final today = DateTime.now();
                      final from = DateTime(today.year, today.month, 1);
                      final next = _PaymentsQuery(
                        q: '',
                        method: '',
                        from: DateFormat('yyyy-MM-dd').format(from),
                        to: DateFormat('yyyy-MM-dd').format(today),
                        limit: 50,
                        offset: 0,
                        sort: 'newest',
                      );
                      ref.read(paymentsQueryProvider.notifier).state = next;
                      _debounce?.cancel();
                      _searchCtrl.clear();
                      ref.read(paymentsControllerProvider.notifier).load();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Split console: Main Ledger (75%) + Metrics sidebar (25%) ───────
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
              // Narrow: metrics on top, ledger below.
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

  @override
  Widget build(BuildContext context) {
    return _build(context, ref, this);
  }
}

void _openView(BuildContext context, Payment p) {
  String fmt(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm').format(d);
  }

  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Payment'),
        content: Text(
          [
            'Invoice: ${p.invoiceNo} (#${p.invoiceId})',
            'Member: ${p.memberName} (${p.memberCode})',
            'Amount: ${p.amount}',
            'Method: ${p.method}',
            'Paid At: ${fmt(p.paidAt)}',
          ].join('\n'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      );
    },
  );
}

/// Collection stat card for the right-hand metrics sidebar. Fills its parent
/// width (no fixed size) and renders the financial figure in Bebas Neue.
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.brightness == Brightness.dark ? AppTheme.charcoal : theme.colorScheme.surface,
          border: Border.all(
            color: _hover
                ? widget.accent.withAlpha(90)
                : (theme.brightness == Brightness.dark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant),
            width: _hover ? 1.0 : 0.8,
          ),
          boxShadow: _hover
              ? [BoxShadow(color: widget.accent.withAlpha(40), blurRadius: 26, offset: const Offset(0, 12))]
              : [BoxShadow(color: Colors.black.withAlpha(theme.brightness == Brightness.dark ? 55 : 12), blurRadius: 14, offset: const Offset(0, 6))],
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
              // Bebas Neue accumulation figure — scales down if very large.
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

/// Flat payment-method pill — Inter, colour-coded by channel.
/// Small status pill inside the invoice picker list.
class _InvoiceStatusPill extends StatelessWidget {
  const _InvoiceStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (status == 'unpaid') {
      color = const Color(0xFFDC2626);
      label = 'Unpaid';
    } else if (status == 'partial' || status == 'partially_paid') {
      color = const Color(0xFFF59E0B);
      label = 'Partial';
    } else {
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(70), width: 0.8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.2),
      ),
    );
  }
}

/// Compact summary card shown after an invoice is selected — member, totals.
class _SelectedInvoiceBanner extends StatelessWidget {
  const _SelectedInvoiceBanner({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    final num = NumberFormat.decimalPattern();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${invoice.invoiceNo} — ${invoice.memberName}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total: ${num.format(invoice.total)}  •  Paid: ${num.format(invoice.amountPaid)}  •  Balance due: ${num.format(invoice.balance)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _InvoiceStatusPill(status: invoice.status),
        ],
      ),
    );
  }
}

/// Live ledger preview banner — shows what the invoice status will become once
/// this payment is saved, calculated entirely from client-side state.
class _LedgerPreviewBanner extends StatelessWidget {
  const _LedgerPreviewBanner({
    required this.amountEntered,
    required this.balance,
    required this.remaining,
    required this.willFullySettle,
  });

  final double amountEntered;
  final double balance;
  final double remaining;
  final bool willFullySettle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accent = willFullySettle ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final IconData icon = willFullySettle ? Icons.check_circle_outline : Icons.timelapse;
    final String message = willFullySettle
        ? 'Invoice will be marked Paid ✓'
        : 'Invoice will be marked Partially Paid — ${NumberFormat.decimalPattern().format(remaining)} still outstanding.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = method.trim().isEmpty ? 'unknown' : method;
    final accent = m == 'cash'
        ? const Color(0xFF10B981)
        : m == 'card'
            ? const Color(0xFF3B82F6)
            : m == 'bank'
                ? const Color(0xFFF59E0B)
                : m == 'online'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(70), width: 0.8),
      ),
      child: Text(
        m,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.1),
      ),
    );
  }
}


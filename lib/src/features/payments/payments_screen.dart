import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
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
  );
});

final paymentsControllerProvider =
    StateNotifierProvider.autoDispose<_PaymentsController, AsyncValue<List<Payment>>>((ref) {
  return _PaymentsController(ref)..load();
});

final paymentsSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  return api.getJson('/payments/summary', token: token);
});

class _PaymentsQuery {
  const _PaymentsQuery({
    required this.q,
    required this.method,
    required this.from,
    required this.to,
  });

  final String q;
  final String method;
  final String from;
  final String to;

  Map<String, String> toQuery() {
    final map = <String, String>{'limit': '200'};
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
  }) {
    return _PaymentsQuery(
      q: q ?? this.q,
      method: method ?? this.method,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

class _PaymentsController extends StateNotifier<AsyncValue<List<Payment>>> {
  _PaymentsController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
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
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('payments_load_failed', st);
    }
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

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

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
      final savedPath = preview
          ? previewBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf')
          : downloadBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf');
      if (!context.mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savedPath')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(preview ? 'Opening PDF…' : 'Download started')));
      }
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
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final dt = DateFormat('yyyy-MM-dd HH:mm');
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final query = ref.watch(paymentsQueryProvider);
    final itemsAsync = ref.watch(paymentsControllerProvider);
    final summaryAsync = ref.watch(paymentsSummaryProvider);

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text('Payments', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payments auto-create when invoice is marked Paid')),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Record'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'PDF',
                onPressed: () => _openPaymentsPdfActions(context, ref),
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
                        labelText: 'Search (invoice / member / code / phone)',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => ref.read(paymentsQueryProvider.notifier).state = query.copyWith(q: v),
                      onSubmitted: (_) => ref.read(paymentsControllerProvider.notifier).load(),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(query.method),
                      initialValue: query.method.isEmpty ? null : query.method,
                      decoration: const InputDecoration(labelText: 'Method'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank')),
                        DropdownMenuItem(value: 'online', child: Text('Online')),
                      ],
                      onChanged: (v) =>
                          ref.read(paymentsQueryProvider.notifier).state = query.copyWith(method: v ?? ''),
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
                      ref.read(paymentsQueryProvider.notifier).state = query.copyWith(from: f, to: t);
                      await ref.read(paymentsControllerProvider.notifier).load();
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text('${query.from} → ${query.to}'),
                  ),
                  FilledButton(
                    onPressed: () => ref.read(paymentsControllerProvider.notifier).load(),
                    child: const Text('Apply'),
                  ),
                  TextButton(
                    onPressed: () {
                      final today = DateTime.now();
                      final from = DateTime(today.year, today.month, 1);
                      final next = _PaymentsQuery(
                        q: '',
                        method: '',
                        from: DateFormat('yyyy-MM-dd').format(from),
                        to: DateFormat('yyyy-MM-dd').format(today),
                      );
                      ref.read(paymentsQueryProvider.notifier).state = next;
                      ref.read(paymentsControllerProvider.notifier).load();
                    },
                    child: const Text('Reset'),
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
              final last7Total = (s['last7Days'] as Map?)?['total'] as num? ?? 0;
              final last30Total = (s['last30Days'] as Map?)?['total'] as num? ?? 0;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(title: 'Today', value: number.format(todayTotal), subtitle: '${todayCount.toInt()} payments'),
                  _MetricCard(title: 'Last 7 days', value: number.format(last7Total), subtitle: 'Collection'),
                  _MetricCard(title: 'Last 30 days', value: number.format(last30Total), subtitle: 'Collection'),
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
                return const _EmptyState(
                  title: 'No payments found',
                  subtitle: 'Try changing date range or search.',
                  icon: Icons.payments,
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
                                  DataCell(Text(number.format(p.amount))),
                                  DataCell(_MethodChip(method: p.method)),
                                  DataCell(Text(fmtDateTime(p.paidAt))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'View',
                                          onPressed: () => _openView(context, p),
                                          icon: const Icon(Icons.visibility),
                                        ),
                                        IconButton(
                                          tooltip: 'Edit',
                                          onPressed: () => openEdit(p),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                        if (canDelete)
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: () => confirmDelete(p),
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
                      final p = items[i];
                      return ListTile(
                        leading: const Icon(Icons.payments),
                        title: Text('${p.memberName} • ${p.invoiceNo}'),
                        subtitle: Text('Amount: ${number.format(p.amount)} • ${fmtDateTime(p.paidAt)}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Actions',
                          onSelected: (v) {
                            if (v == 'view') _openView(context, p);
                            if (v == 'edit') openEdit(p);
                            if (v == 'delete' && canDelete) confirmDelete(p);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'view', child: Text('View')),
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                          child: const Icon(Icons.more_vert),
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
}

void _openView(BuildContext context, Payment p) {
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
            'Paid At: ${p.paidAt}',
          ].join('\n'),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      );
    },
  );
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

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = method.trim().isEmpty ? 'unknown' : method;
    final bg = m == 'cash'
        ? theme.colorScheme.primaryContainer
        : m == 'card'
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = m == 'cash'
        ? theme.colorScheme.onPrimaryContainer
        : m == 'card'
            ? theme.colorScheme.onTertiaryContainer
            : theme.colorScheme.onSurfaceVariant;
    return Chip(
      label: Text(m),
      backgroundColor: bg,
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

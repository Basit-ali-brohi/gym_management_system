import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/whatsapp.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final invoicesControllerProvider =
    StateNotifierProvider.autoDispose<InvoicesController, AsyncValue<_InvoicesPage>>((ref) {
  return InvoicesController(ref)..load();
});

final billingPlansProvider = FutureProvider.autoDispose<List<Plan>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/plans', token: token);
  return (res['items'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => Plan.fromJson(e.cast<String, dynamic>()))
      .toList();
});

final invoiceMemberSearchProvider =
    StateNotifierProvider.autoDispose<_InvoiceMemberSearch, AsyncValue<List<Member>>>((ref) {
  return _InvoiceMemberSearch(ref);
});

class _InvoicesPage {
  const _InvoicesPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.q,
    required this.status,
    required this.sort,
  });

  const _InvoicesPage.empty()
      : items = const [],
        total = 0,
        limit = 50,
        offset = 0,
        q = '',
        status = 'all',
        sort = 'newest';

  final List<Invoice> items;
  final int total;
  final int limit;
  final int offset;
  final String q;
  final String status;
  final String sort;
}

class InvoicesController extends StateNotifier<AsyncValue<_InvoicesPage>> {
  InvoicesController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;
  String _q = '';
  String _status = 'all';
  String _sort = 'newest';
  final int _limit = 50;
  int _offset = 0;

  Future<void> setFilters({String? q, String? status, String? sort, bool resetOffset = true}) async {
    if (q != null) _q = q.trim();
    if (status != null) _status = status.trim();
    if (sort != null) _sort = sort.trim();
    if (resetOffset) _offset = 0;
    await load();
  }

  Future<void> nextPage() async {
    final page = state.valueOrNull;
    final total = page?.total ?? 0;
    final next = _offset + _limit;
    if (next >= total) return;
    _offset = next;
    await load();
  }

  Future<void> prevPage() async {
    _offset = max(0, _offset - _limit);
    await load();
  }

  Future<void> load() async {
    state = const AsyncLoading<_InvoicesPage>().copyWithPrevious(state);
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final query = <String, String>{
        'limit': _limit.toString(),
        'offset': _offset.toString(),
        'sort': _sort,
      };
      if (_q.isNotEmpty) query['q'] = _q;
      if (_status.isNotEmpty) query['status'] = _status;
      final res = await api.getJson('/invoices', token: token, query: query);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Invoice.fromJson(e.cast<String, dynamic>()))
          .toList();
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      state = AsyncValue.data(
        _InvoicesPage(
          items: items,
          total: total,
          limit: _limit,
          offset: _offset,
          q: _q,
          status: _status,
          sort: _sort,
        ),
      );
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('invoices_load_failed', st);
    }
  }

  Future<void> markPaid(int invoiceId) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.postJson('/invoices/mark-paid', token: token, body: {'invoiceId': invoiceId, 'method': 'cash'});
    await load();
  }

  Future<void> voidInvoice(int invoiceId) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.patchJson('/invoices/$invoiceId', token: token, body: {'status': 'void'});
    await load();
  }
}

class _InvoiceMemberSearch extends StateNotifier<AsyncValue<List<Member>>> {
  _InvoiceMemberSearch(this.ref) : super(const AsyncValue.data([]));

  final Ref ref;

  Future<void> search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/members', token: token, query: {'q': query, 'limit': '20'});
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Member.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('search_failed', st);
    }
  }
}

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();

  Widget _build(BuildContext context, WidgetRef ref, _InvoicesScreenState state) {
    final invoicesAsync = ref.watch(invoicesControllerProvider);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final dt = DateFormat('yyyy-MM-dd HH:mm');
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final pagePreview = invoicesAsync.valueOrNull ?? const _InvoicesPage.empty();
    final itemsPreview = pagePreview.items;
    final total = pagePreview.total;
    final loaded = itemsPreview.length;
    final paid = itemsPreview.where((i) => i.status == 'paid').length;
    final unpaid = itemsPreview.where((i) => i.status == 'unpaid').length;
    final voided = itemsPreview.where((i) => i.status == 'void').length;
    final fromN = total == 0 ? 0 : pagePreview.offset + 1;
    final toN = total == 0 ? 0 : min(pagePreview.offset + loaded, total);
    final canPrev = pagePreview.offset > 0;
    final canNext = pagePreview.offset + loaded < total;

    Widget metricCard({
      required String title,
      required String value,
      required String subtitle,
      required IconData icon,
    }) {
      return SizedBox(
        width: 260,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Invoices', style: theme.textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: () => _openAutoInvoice(context, ref),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _sendAllInvoiceReminders(context, ref),
              icon: const Icon(Icons.done_all),
              label: const Text('Send All'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'PDF',
              onPressed: () => _openInvoicesListPdfActions(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(invoicesControllerProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metricCard(
              title: 'Total invoices',
              value: '$total',
              subtitle: 'Filtered total',
              icon: Icons.receipt_long,
            ),
            metricCard(
              title: 'Paid',
              value: '$paid',
              subtitle: 'This page',
              icon: Icons.verified_outlined,
            ),
            metricCard(
              title: 'Unpaid',
              value: '$unpaid',
              subtitle: 'This page',
              icon: Icons.pending_actions_outlined,
            ),
            metricCard(
              title: 'Voided',
              value: '$voided',
              subtitle: 'This page',
              icon: Icons.block_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(state._statusFilter),
                    initialValue: state._statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'void', child: Text('Voided')),
                    ],
                    onChanged: (v) => state._setStatusFilter(v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(state._sort),
                    initialValue: state._sort,
                    decoration: const InputDecoration(labelText: 'Sort'),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                      DropdownMenuItem(value: 'total_desc', child: Text('Total high–low')),
                    ],
                    onChanged: (v) => state._setSort(v ?? 'newest'),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: state._searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search invoice, member, code',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => state._scheduleApplyFilters(),
                  ),
                ),
                Text(
                  total == 0
                      ? '—'
                      : 'Showing ${number.format(fromN)}–${number.format(toN)} of ${number.format(total)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                IconButton(
                  tooltip: 'Previous',
                  onPressed: canPrev ? () => ref.read(invoicesControllerProvider.notifier).prevPage() : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next',
                  onPressed: canNext ? () => ref.read(invoicesControllerProvider.notifier).nextPage() : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                OutlinedButton(
                  onPressed: state._clearFilters,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        invoicesAsync.when(
          data: (page) {
            if (page.total == 0) return const _EmptyState();
            final items = page.items;
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No results', style: theme.textTheme.bodySmall)),
              );
            }

            String formatDate(String raw) {
              final parsed = DateTime.tryParse(raw);
              if (parsed == null) return raw;
              return dt.format(parsed);
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Invoice')),
                            DataColumn(label: Text('Member')),
                            DataColumn(label: Text('Total')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Created')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: [
                            for (final inv in items)
                              DataRow(
                                cells: [
                                  DataCell(Text(inv.invoiceNo)),
                                  DataCell(Text(inv.memberName)),
                                  DataCell(Text(number.format(inv.total))),
                                  DataCell(_StatusChip(status: inv.status)),
                                  DataCell(Text(formatDate(inv.createdAt))),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _CompactIconButton(
                                          tooltip: 'View',
                                          onPressed: () => _openInvoiceView(context, ref, inv.id),
                                          icon: Icons.visibility,
                                        ),
                                        _CompactIconButton(
                                          tooltip: 'Edit',
                                          onPressed: inv.status == 'paid'
                                              ? null
                                              : () => _openInvoiceEdit(context, ref, inv.id),
                                          icon: Icons.edit_outlined,
                                        ),
                                        _CompactIconButton(
                                          tooltip: 'PDF',
                                          onPressed: () => _openInvoicePdfActions(context, ref, inv),
                                          icon: Icons.picture_as_pdf_outlined,
                                        ),
                                        if (canDelete)
                                          _CompactIconButton(
                                            tooltip: 'Void',
                                            onPressed: inv.status == 'paid' ? null : () => _confirmVoid(context, ref, inv),
                                            icon: Icons.delete_outline,
                                          ),
                                        if (inv.status == 'unpaid') ...[
                                          const SizedBox(width: 6),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              minimumSize: const Size(0, 32),
                                            ),
                                            onPressed: () => ref
                                                .read(invoicesControllerProvider.notifier)
                                                .markPaid(inv.id),
                                            child: const Text('Paid'),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final inv = items[i];
                    return ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text('${inv.invoiceNo} • ${inv.memberName}'),
                        subtitle: Text('Total: ${number.format(inv.total)} • ${formatDate(inv.createdAt)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusChip(status: inv.status),
                            const SizedBox(width: 6),
                            _CompactIconButton(
                              tooltip: 'View',
                              onPressed: () => _openInvoiceView(context, ref, inv.id),
                              icon: Icons.visibility,
                            ),
                            _CompactIconButton(
                              tooltip: 'Edit',
                              onPressed: inv.status == 'paid' ? null : () => _openInvoiceEdit(context, ref, inv.id),
                              icon: Icons.edit_outlined,
                            ),
                            _CompactIconButton(
                              tooltip: 'PDF',
                              onPressed: () => _openInvoicePdfActions(context, ref, inv),
                              icon: Icons.picture_as_pdf_outlined,
                            ),
                            if (canDelete)
                              _CompactIconButton(
                                tooltip: 'Void',
                                onPressed: inv.status == 'paid' ? null : () => _confirmVoid(context, ref, inv),
                                icon: Icons.delete_outline,
                              ),
                            if (inv.status == 'unpaid') ...[
                              const SizedBox(width: 6),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  minimumSize: const Size(0, 32),
                                ),
                                onPressed: () => ref.read(invoicesControllerProvider.notifier).markPaid(inv.id),
                                child: const Text('Paid'),
                              ),
                            ],
                          ],
                        ),
                      );
                  },
                );
              },
            );
          },
          error: (e, _) => Center(child: Text(e.toString())),
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _openAutoInvoice(BuildContext context, WidgetRef ref) async {
    final searchCtrl = TextEditingController();
    final taxCtrl = TextEditingController(text: '0');
    Member? selectedMember;
    int? selectedPlanId;

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.auto_awesome,
      title: 'Auto Invoice',
      subtitle: 'Generate invoice from member + plan',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final memberAsync = r.watch(invoiceMemberSearchProvider);
              final plansAsync = r.watch(billingPlansProvider);

              if (plansAsync is AsyncData<List<Plan>> && selectedPlanId == null && plansAsync.value.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  setModalState(() => selectedPlanId = plansAsync.value.first.id);
                });
              }

              Plan? selectedPlan;
              if (plansAsync is AsyncData<List<Plan>> && selectedPlanId != null) {
                final plans = plansAsync.value;
                for (final p in plans) {
                  if (p.id == selectedPlanId) {
                    selectedPlan = p;
                    break;
                  }
                }
              }
              final taxPercent = double.tryParse(taxCtrl.text.trim()) ?? 0;
              final p = selectedPlan;
              final subtotal = p == null ? null : (p.price + p.admissionFee);
              final tax = subtotal == null ? null : (subtotal * taxPercent / 100);
              final total = (subtotal == null || tax == null) ? null : (subtotal + tax);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Member', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search member (code / name / phone)',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => r.read(invoiceMemberSearchProvider.notifier).search(v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 220,
                    child: memberAsync.when(
                      data: (items) {
                        if (searchCtrl.text.trim().isEmpty) {
                          return const Center(child: Text('Type to search members'));
                        }
                        if (items.isEmpty) return const Center(child: Text('No results'));
                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = items[i];
                            final selected = selectedMember?.id == m.id;
                            return ListTile(
                              selected: selected,
                              title: Text('${m.fullName} (${m.memberCode})'),
                              subtitle: Text('ID: ${m.id}${m.phone != null ? ' • ${m.phone}' : ''}'),
                              onTap: () => setModalState(() => selectedMember = m),
                            );
                          },
                        );
                      },
                      error: (e, _) => Center(child: Text(e.toString())),
                      loading: () => const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Plan & totals', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  plansAsync.when(
                    data: (plans) {
                      if (plans.isEmpty) return const Text('No plans found. Create a plan first.');
                      selectedPlanId ??= plans.first.id;
                      return DropdownButtonFormField<int>(
                        key: ValueKey(selectedPlanId),
                        initialValue: selectedPlanId,
                        decoration: const InputDecoration(labelText: 'Plan'),
                        items: [
                          for (final p in plans)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.name} • ${p.price}'),
                            ),
                        ],
                        onChanged: (v) => setModalState(() => selectedPlanId = v),
                      );
                    },
                    error: (e, _) => Text(e.toString()),
                    loading: () => const LinearProgressIndicator(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Subtotal (auto)'),
                          child: Text(subtotal == null ? '-' : subtotal.toStringAsFixed(2)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: taxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Tax %'),
                          onChanged: (_) => setModalState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Tax Amount (auto)'),
                    child: Text(tax == null ? '-' : tax.toStringAsFixed(2)),
                  ),
                  const SizedBox(height: 10),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Total Amount (auto)'),
                    child: Text(total == null ? '-' : total.toStringAsFixed(2)),
                  ),
                ],
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
        FilledButton(
          onPressed: () async {
            final taxPercent = double.tryParse(taxCtrl.text.trim()) ?? 0;
            if (selectedMember == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a member')));
              return;
            }
            if (selectedPlanId == null) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a plan')));
              return;
            }
            try {
              final token = ref.read(authControllerProvider).token;
              final api = ref.read(apiClientProvider);
              final res = await api.postJson(
                '/billing/auto-invoice',
                token: token,
                body: {
                  'memberId': selectedMember!.id,
                  'planId': selectedPlanId,
                  'taxPercent': taxPercent,
                },
              );
              if (!context.mounted) return;
              ref.read(invoicesControllerProvider.notifier).load();
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Invoice created: ${res['invoiceNo']}')),
              );
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Generate'),
        ),
      ],
      maxWidth: 820,
    );

    searchCtrl.dispose();
    taxCtrl.dispose();
  }

  Future<void> _openInvoicePdfActions(BuildContext context, WidgetRef ref, Invoice inv) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${inv.invoiceNo}.pdf'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicePdf(context, ref, inv, preview: true);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicePdf(context, ref, inv, preview: false);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runInvoicePdf(BuildContext context, WidgetRef ref, Invoice inv, {required bool preview}) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');

      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/invoices/${inv.id}/pdf', token: token);
      final name = '${inv.invoiceNo}.pdf';
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to download PDF')));
    }
  }

  Future<void> _openInvoicesListPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Invoices PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicesListPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicesListPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runInvoicesListPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/invoices.pdf', token: token);
      final name = 'invoices_$today.pdf';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to export PDF')));
    }
  }

  Future<void> _sendAllInvoiceReminders(BuildContext context, WidgetRef ref) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/invoices', token: token, query: {'status': 'unpaid', 'limit': '200', 'sort': 'newest'});
      final raw = (res['items'] as List<dynamic>? ?? []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      final items = raw
          .map(
            (e) => (
              invoiceNo: e['invoice_no']?.toString() ?? '',
              total: (e['total'] is num) ? (e['total'] as num) : (num.tryParse(e['total']?.toString() ?? '') ?? 0),
              memberName: e['full_name']?.toString() ?? '',
              memberCode: e['member_code']?.toString() ?? '',
              phone: e['phone']?.toString(),
            ),
          )
          .where((i) => normalizeWhatsAppPhone(i.phone).isNotEmpty)
          .toList();

      if (!context.mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No reminders ready to send')));
        return;
      }

      final slug = ref.read(authControllerProvider).user?.tenantSlug ?? '';
      final tenantLabel = slug.trim().isEmpty ? 'Gym' : 'Gym ($slug)';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening WhatsApp for ${items.length} reminders…')));

      var okCount = 0;
      var failCount = 0;
      for (final i in items) {
        final msg =
            'Assalam o Alaikum ${i.memberName}, apka pending bill ${i.invoiceNo} (Rs ${i.total}) clear kar dein. Shukriya. $tenantLabel';
        final ok = await openWhatsAppMessage(phone: i.phone ?? '', message: msg);
        if (ok) {
          okCount += 1;
        } else {
          failCount += 1;
        }
        await Future<void>.delayed(const Duration(milliseconds: 240));
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reminders: sent $okCount, failed $failCount')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Send reminders failed')));
    }
  }

  Future<void> _openInvoiceView(BuildContext context, WidgetRef ref, int invoiceId) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/invoices/$invoiceId', token: token);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          final member = res['member'] is Map ? (res['member'] as Map).cast<String, dynamic>() : null;
          return AlertDialog(
            title: Text(res['invoiceNo']?.toString() ?? 'Invoice'),
            content: Text(
              [
                if (member != null) 'Member: ${member['name']} (${member['code']})',
                'Status: ${res['status']}',
                'Subtotal: ${res['subtotal']}',
                'Discount: ${res['discount']}',
                'Tax: ${res['tax']}',
                'Total: ${res['total']}',
                if (res['dueDate'] != null) 'Due: ${res['dueDate']}',
                'Created: ${res['createdAt']}',
              ].join('\n'),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          );
        },
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load invoice')));
    }
  }

  Future<void> _openInvoiceEdit(BuildContext context, WidgetRef ref, int invoiceId) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/invoices/$invoiceId', token: token);

      final discountCtrl = TextEditingController(text: (res['discount'] ?? 0).toString());
      final taxCtrl = TextEditingController(text: (res['tax'] ?? 0).toString());
      final dueCtrl = TextEditingController(text: (res['dueDate'] ?? '').toString());

      if (!context.mounted) return;
      await showAppFormDialog<void>(
        context: context,
        icon: Icons.edit_outlined,
        title: 'Edit Invoice',
        subtitle: res['invoiceNo']?.toString() ?? '',
        body: LayoutBuilder(
          builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 680;
            final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
            Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    field(
                      TextField(
                        controller: discountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Discount'),
                      ),
                    ),
                    field(
                      TextField(
                        controller: taxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Tax'),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: TextField(
                        controller: dueCtrl,
                        decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD)'),
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
              final discount = double.tryParse(discountCtrl.text.trim());
              final tax = double.tryParse(taxCtrl.text.trim());
              try {
                await api.patchJson('/invoices/$invoiceId', token: token, body: {
                  'discount': discount ?? 0,
                  'tax': tax ?? 0,
                  'dueDate': dueCtrl.text.trim().isEmpty ? null : dueCtrl.text.trim(),
                });
                ref.read(invoicesControllerProvider.notifier).load();
                if (!context.mounted) return;
                Navigator.of(context, rootNavigator: true).maybePop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
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

      discountCtrl.dispose();
      taxCtrl.dispose();
      dueCtrl.dispose();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref, Invoice inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Void invoice?'),
          content: Text('Void ${inv.invoiceNo}?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Void')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(invoicesControllerProvider.notifier).voidInvoice(inv.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voided')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _hydratedFromRoute = false;
  String _statusFilter = 'all';
  String _sort = 'newest';

  void _setStatusFilter(String v) {
    setState(() => _statusFilter = v);
    ref.read(invoicesControllerProvider.notifier).setFilters(status: _statusFilter);
  }

  void _setSort(String v) {
    setState(() => _sort = v);
    ref.read(invoicesControllerProvider.notifier).setFilters(sort: _sort);
  }

  void _scheduleApplyFilters() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      ref.read(invoicesControllerProvider.notifier).setFilters(q: _searchCtrl.text, resetOffset: true);
    });
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _statusFilter = 'all';
      _sort = 'newest';
    });
    _debounce?.cancel();
    ref.read(invoicesControllerProvider.notifier).setFilters(q: '', status: 'all', sort: 'newest', resetOffset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hydratedFromRoute) {
      _hydratedFromRoute = true;
      final q = GoRouterState.of(context).uri.queryParameters['q']?.trim();
      if (q != null && q.isNotEmpty) {
        _searchCtrl.text = q;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(invoicesControllerProvider.notifier).setFilters(
                q: _searchCtrl.text,
                status: _statusFilter,
                sort: _sort,
                resetOffset: true,
              );
        });
      }
    }
    return widget._build(context, ref, this);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                  child: const Icon(Icons.receipt_long, size: 28),
                ),
                const SizedBox(height: 12),
                Text('No invoices yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Invoices will appear here once billing is used.', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid = status == 'paid';
    final isUnpaid = status == 'unpaid';
    final accent = isPaid
        ? const Color(0xFF36D27E)
        : isUnpaid
            ? const Color(0xFFFFC857)
            : theme.colorScheme.primary;
    final label = (status.isEmpty ? '—' : status).toUpperCase();

    final bgA = theme.colorScheme.surface.withAlpha(theme.brightness == Brightness.dark ? 72 : 140);
    final bgB = theme.colorScheme.surfaceContainerHighest.withAlpha(theme.brightness == Brightness.dark ? 52 : 120);
    final border = accent.withAlpha(theme.brightness == Brightness.dark ? 150 : 130);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                bgA,
                bgB,
              ],
            ),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(isPaid ? 46 : isUnpaid ? 44 : 24),
                blurRadius: 16,
                spreadRadius: 0,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}

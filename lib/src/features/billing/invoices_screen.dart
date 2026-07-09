import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart'; // AppTheme + AppTypography + StatCategory
import '../../core/form_dialog.dart';
import '../../core/gym_floor_components.dart'; // CategoryStatCard
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/whatsapp.dart';
import '../../core/in_app_pdf.dart';
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
    // Global "+" Quick Action → open Auto Invoice modal once on arrival.
    final pendingAction = ref.watch(pendingQuickActionProvider);
    if (pendingAction == null) {
      state.quickActionHandled = false;
    } else if (pendingAction == QuickAction.quickInvoice && !state.quickActionHandled) {
      state.quickActionHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!state.mounted) return;
        ref.read(pendingQuickActionProvider.notifier).state = null;
        _openAutoInvoice(context, ref);
      });
    }
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final dt = DateFormat('yyyy-MM-dd HH:mm');
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final pagePreview = invoicesAsync.valueOrNull ?? const _InvoicesPage.empty();
    final itemsPreview = pagePreview.items;
    final total = pagePreview.total;
    final paid = itemsPreview.where((i) => i.status == 'paid').length;
    final unpaid = itemsPreview.where((i) => i.status == 'unpaid').length;
    final voided = itemsPreview.where((i) => i.status == 'void').length;
    // Pagination is computed page-locally inside the data branch (see footer).

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final actionList = <Widget>[
              FilledButton.icon(
                onPressed: () => _openAutoInvoice(context, ref),
                icon: const Icon(PhosphorIconsRegular.sparkle),
                label: const Text('Generate'),
              ),
              OutlinedButton.icon(
                onPressed: () => _sendAllInvoiceReminders(context, ref),
                icon: const Icon(PhosphorIconsRegular.checks),
                label: const Text('Send All'),
              ),
              IconButton(
                tooltip: 'PDF',
                onPressed: () => _openInvoicesListPdfActions(context, ref),
                icon: const Icon(PhosphorIconsRegular.filePdf),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref.read(invoicesControllerProvider.notifier).load(),
                icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              ),
            ];
            if (c.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppPageTitle('Invoices'),
                  const SizedBox(height: 12),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actionList),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: const AppPageTitle('Invoices')),
                for (var k = 0; k < actionList.length; k++) ...[
                  if (k > 0) const SizedBox(width: 8),
                  actionList[k],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        // ── Single-row 4-up ledger summary ───────────────────────────────
        // 4 cols on desktop (span edge-to-edge via Expanded), 2 on tablet,
        // 1 stacked on mobile. "Voided" never drops to an isolated row.
        LayoutBuilder(
          builder: (context, c) {
            final tiles = <Widget>[
              CategoryStatCard(
                category: StatCategory.financial,
                label: 'Total invoices',
                value: '$total',
                footnote: 'FILTERED TOTAL',
              ),
              CategoryStatCard(
                category: StatCategory.membership,
                label: 'Paid',
                value: '$paid',
                footnote: 'THIS PAGE',
              ),
              CategoryStatCard(
                category: StatCategory.atRisk,
                label: 'Unpaid',
                value: '$unpaid',
                footnote: 'THIS PAGE',
              ),
              CategoryStatCard(
                category: StatCategory.operational,
                label: 'Voided',
                value: '$voided',
                footnote: 'THIS PAGE',
              ),
            ];
            final cols = c.maxWidth >= 900
                ? 4
                : c.maxWidth >= 520
                    ? 2
                    : 1;
            const gap = 12.0;
            return Column(
              children: [
                for (var i = 0; i < tiles.length; i += cols)
                  Padding(
                    padding: EdgeInsets.only(bottom: i + cols < tiles.length ? gap : 0),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var j = 0; j < cols; j++) ...[
                            if (j > 0) const SizedBox(width: gap),
                            Expanded(
                              child: (i + j) < tiles.length ? tiles[i + j] : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        // ── Filter deck (dense 40px controls; pagination decoupled below) ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(state._statusFilter),
                    initialValue: state._statusFilter,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.archivo(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: appDenseInputDecoration(context),
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
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(state._sort),
                    initialValue: state._sort,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.archivo(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: appDenseInputDecoration(context),
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                      DropdownMenuItem(value: 'total_desc', child: Text('Total high-low')),
                    ],
                    onChanged: (v) => state._setSort(v ?? 'newest'),
                  ),
                ),
                SizedBox(
                  width: 320,
                  height: 40,
                  child: TextField(
                    controller: state._searchCtrl,
                    style: GoogleFonts.archivo(fontSize: 13.5),
                    decoration: appDenseInputDecoration(
                      context,
                      hint: 'Search invoice, member, code',
                      prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    onChanged: (_) => state._scheduleApplyFilters(),
                  ),
                ),
                AppFilterPill(
                  label: 'Clear',
                  icon: PhosphorIconsRegular.x,
                  selected: false,
                  onTap: state._clearFilters,
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

            // Pagination values for the decoupled footer (uses live page data).
            final fFromN = page.total == 0 ? 0 : page.offset + 1;
            final fToN = min(page.offset + items.length, page.total);
            final fCanPrev = page.offset > 0;
            final fCanNext = page.offset + items.length < page.total;

            // Footer bar attached seamlessly under the table pane.
            Widget paginationFooter() {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.brightness == Brightness.dark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      page.total == 0
                          ? 'No invoices'
                          : 'Showing ${number.format(fFromN)}-${number.format(fToN)} of ${number.format(page.total)}',
                      style: GoogleFonts.archivo(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: fCanPrev ? () => ref.read(invoicesControllerProvider.notifier).prevPage() : null,
                      icon: const Icon(PhosphorIconsRegular.caretLeft),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: fCanNext ? () => ref.read(invoicesControllerProvider.notifier).nextPage() : null,
                      icon: const Icon(PhosphorIconsRegular.caretRight),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  // Unified table panel: bordered window with the table on top
                  // and the pagination footer seamlessly attached below.
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.brightness == Brightness.dark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant,
                        width: 0.8,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          // Scoped Theme: Inter typography + faint dividers.
                          child: Theme(
                            data: theme.copyWith(
                              dividerColor: theme.brightness == Brightness.dark
                                  ? Colors.white.withAlpha(15)
                                  : Colors.grey.shade200,
                              dataTableTheme: DataTableThemeData(
                                dividerThickness: 1,
                                headingTextStyle: GoogleFonts.archivo(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                dataTextStyle: GoogleFonts.archivo(fontSize: 13.5, color: theme.colorScheme.onSurface),
                                headingRowColor: WidgetStatePropertyAll(
                                  theme.brightness == Brightness.dark
                                      ? Colors.white.withAlpha(8)
                                      : Colors.black.withAlpha(5),
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
                                      // Monetary figure in tabular Inter.
                                      DataCell(Text(
                                        number.format(inv.total),
                                        style: GoogleFonts.archivo(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      )),
                                      DataCell(_StatusChip(status: inv.status)),
                                      DataCell(Text(formatDate(inv.createdAt))),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // High-frequency read actions stay exposed.
                                            AppTableActionButton(
                                              icon: PhosphorIconsRegular.eye,
                                              tooltip: 'View',
                                              onPressed: () => _openInvoiceView(context, ref, inv.id),
                                            ),
                                            const SizedBox(width: 2),
                                            AppTableActionButton(
                                              icon: PhosphorIconsRegular.filePdf,
                                              tooltip: 'Export PDF',
                                              onPressed: () => _openInvoicePdfActions(context, ref, inv),
                                            ),
                                            const SizedBox(width: 2),
                                            // Status-altering workflows live in the overflow menu.
                                            _InvoiceActionsMenu(
                                              status: inv.status,
                                              canDelete: canDelete,
                                              onMarkPaid: () =>
                                                  ref.read(invoicesControllerProvider.notifier).markPaid(inv.id),
                                              onEdit: () => _openInvoiceEdit(context, ref, inv.id),
                                              onVoid: () => _confirmVoid(context, ref, inv),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        paginationFooter(),
                      ],
                    ),
                  );
                }

                // Narrow: stacked list with the same footer attached below.
                return Column(
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final inv = items[i];
                        return Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withAlpha(40),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      inv.invoiceNo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.archivo(fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusChip(status: inv.status),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${inv.memberName}  •  ${number.format(inv.total)}  •  ${formatDate(inv.createdAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.archivo(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  AppTableActionButton(
                                    icon: PhosphorIconsRegular.eye,
                                    tooltip: 'View',
                                    onPressed: () => _openInvoiceView(context, ref, inv.id),
                                  ),
                                  const SizedBox(width: 2),
                                  AppTableActionButton(
                                    icon: PhosphorIconsRegular.filePdf,
                                    tooltip: 'Export PDF',
                                    onPressed: () => _openInvoicePdfActions(context, ref, inv),
                                  ),
                                  const Spacer(),
                                  _InvoiceActionsMenu(
                                    status: inv.status,
                                    canDelete: canDelete,
                                    onMarkPaid: () => ref.read(invoicesControllerProvider.notifier).markPaid(inv.id),
                                    onEdit: () => _openInvoiceEdit(context, ref, inv.id),
                                    onVoid: () => _confirmVoid(context, ref, inv),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    paginationFooter(),
                  ],
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
    final discountCtrl = TextEditingController(text: '0');
    Member? selectedMember;
    int? selectedPlanId;
    String discountType = 'percentage';
    String paymentMethod = 'cash';
    String paymentStatus = 'paid';

    await showAppFormDialog<void>(
      context: context,
      icon: PhosphorIconsRegular.sparkle,
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
              final discountValue = double.tryParse(discountCtrl.text.trim()) ?? 0;
              final p = selectedPlan;
              final subtotal = p == null ? null : (p.price + p.admissionFee);
              // Inline financial engine: Subtotal − Discount, then Tax on the
              // discounted (taxable) amount, then Total.
              double? discountAmount;
              double? taxable;
              double? tax;
              double? total;
              if (subtotal != null) {
                discountAmount = discountType == 'percentage'
                    ? subtotal * discountValue / 100
                    : discountValue;
                discountAmount = discountAmount.clamp(0, subtotal).toDouble();
                taxable = subtotal - discountAmount;
                tax = taxable * taxPercent / 100;
                total = taxable + tax;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Member', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search member (code / name / phone)',
                      prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
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
                  const FormSectionLabel(
                    'Plan & Billing',
                    hint: 'Discount applies before tax. Totals recalculate live as you type.',
                    icon: PhosphorIconsRegular.receipt,
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  // Subtotal (auto) | Payment Method
                  FormRow([
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Subtotal (auto)'),
                      child: Text(subtotal == null ? '-' : subtotal.toStringAsFixed(2)),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: paymentMethod,
                      decoration: const InputDecoration(labelText: 'Payment Method'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'online', child: Text('Online (JazzCash/EasyPaisa)')),
                      ],
                      onChanged: (v) => setModalState(() => paymentMethod = v ?? 'cash'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Discount Type | Discount Value
                  FormRow([
                    FormSegmented<String>(
                      label: 'Discount Type',
                      value: discountType,
                      onChanged: (v) => setModalState(() => discountType = v),
                      segments: const [
                        FormSegment('percentage', 'Percentage', icon: PhosphorIconsRegular.percent),
                        FormSegment('fixed', 'Fixed', icon: PhosphorIconsRegular.wallet),
                      ],
                    ),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Discount Value',
                        hintText: discountType == 'percentage' ? 'e.g. 10 (%)' : 'e.g. 500 (flat)',
                        suffixText: discountType == 'percentage' ? '%' : null,
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Tax % | Tax Amount (auto)
                  FormRow([
                    TextField(
                      controller: taxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tax %', suffixText: '%'),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tax Amount (auto)'),
                      child: Text(tax == null ? '-' : tax.toStringAsFixed(2)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FormSegmented<String>(
                    label: 'Payment Status',
                    value: paymentStatus,
                    onChanged: (v) => setModalState(() => paymentStatus = v),
                    segments: const [
                      FormSegment('paid', 'Paid', icon: PhosphorIconsRegular.checkCircle, color: AppTheme.emerald),
                      FormSegment('partial', 'Partially Paid', icon: PhosphorIconsRegular.timer, color: AppTheme.iron),
                      FormSegment('unpaid', 'Unpaid', icon: PhosphorIconsRegular.warningCircle, color: AppTheme.danger),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _InvoiceTotalsCard(
                    subtotal: subtotal,
                    discount: discountAmount,
                    tax: tax,
                    total: total,
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
            final discountValue = double.tryParse(discountCtrl.text.trim()) ?? 0;
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
                  'discountType': discountType,
                  'discountValue': discountValue,
                  'paymentMethod': paymentMethod,
                  'paymentStatus': paymentStatus,
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
    discountCtrl.dispose();
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
              icon: const Icon(PhosphorIconsRegular.eye),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicePdf(context, ref, inv, preview: false);
              },
              icon: const Icon(PhosphorIconsRegular.downloadSimple),
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
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Invoice ${inv.invoiceNo}');
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
              icon: const Icon(PhosphorIconsRegular.eye),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runInvoicesListPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(PhosphorIconsRegular.downloadSimple),
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
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Invoices Report Preview');
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
            'Hello ${i.memberName}, your pending bill ${i.invoiceNo} (Rs ${i.total}) is due. Please clear it. Thank you. $tenantLabel';
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
        icon: PhosphorIconsRegular.pencilSimple,
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
  bool quickActionHandled = false;
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
                  child: const Icon(PhosphorIconsRegular.receipt, size: 28),
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

/// Flat status pill — Inter, colour-coded: paid → emerald, unpaid → amber,
/// void → muted grey.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    // paid = membership (positive), unpaid = at-risk (same meaning as
    // "unpaid/overdue" everywhere else), void = neutral operational.
    final isPaid = status == 'paid';
    final isUnpaid = status == 'unpaid';
    final category = isPaid
        ? StatCategory.membership
        : isUnpaid
            ? StatCategory.atRisk
            : StatCategory.operational;
    final label = (status.isEmpty ? '-' : status).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: category.soft,
        borderRadius: AppRadius.smallAll,
      ),
      child: Text(
        label,
        style: AppTypography.uiLabel(color: category.color, fontSize: 11.5, weight: FontWeight.w700, letterSpacing: 0.15),
      ),
    );
  }
}

/// Overflow menu for status-altering invoice workflows.
/// Keeps the row clean: View + Export PDF stay exposed; Edit, Mark as Paid,
/// and Void live behind a single more_vert button.
class _InvoiceActionsMenu extends StatelessWidget {
  const _InvoiceActionsMenu({
    required this.status,
    required this.canDelete,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onVoid,
  });

  final String status;
  final bool canDelete;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onVoid;

  static const Color _mutedRed = Color(0xFFE06C6C);

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool danger = false,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.colorScheme.onSurfaceVariant.withAlpha(110)
        : danger
            ? _mutedRed
            : theme.colorScheme.onSurface;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18, color: !enabled ? color : (danger ? _mutedRed : theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.archivo(fontSize: 13.5, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaid = status == 'paid';

    return PopupMenuButton<String>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      elevation: 10,
      color: isDark ? AppTheme.charcoalHigh : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smallAll,
        side: BorderSide(
          color: isDark ? AppTheme.borderHover : AppTheme.line,
          width: 0.8,
        ),
      ),
      icon: Icon(PhosphorIconsRegular.dotsThreeVertical, size: 18, color: theme.colorScheme.onSurfaceVariant),
      onSelected: (v) {
        switch (v) {
          case 'paid':
            onMarkPaid();
            break;
          case 'edit':
            onEdit();
            break;
          case 'void':
            onVoid();
            break;
        }
      },
      itemBuilder: (context) => [
        if (status == 'unpaid') _item(context, 'paid', PhosphorIconsRegular.checkCircle, 'Mark as paid'),
        _item(context, 'edit', PhosphorIconsRegular.pencilSimple, 'Edit invoice', enabled: !isPaid),
        if (canDelete) const PopupMenuDivider(),
        if (canDelete) _item(context, 'void', PhosphorIconsRegular.prohibit, 'Void invoice', danger: true, enabled: !isPaid),
      ],
    );
  }
}

/// Live billing summary surfaced beneath the Auto Invoice inputs. Shows the
/// Subtotal − Discount + Tax → Total breakdown computed in the form controller.
class _InvoiceTotalsCard extends StatelessWidget {
  const _InvoiceTotalsCard({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
  });

  final num? subtotal;
  final num? discount;
  final num? tax;
  final num? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String fmt(num? v) => v == null ? '-' : v.toStringAsFixed(2);

    Widget line(String label, String value, {bool negative = false, Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            Text(
              negative && value != '-' ? '− $value' : value,
              style: AppTypography.mono(color: color ?? cs.onSurface, fontSize: 14, weight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest.withAlpha(90),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          line('Subtotal', fmt(subtotal)),
          line('Discount', fmt(discount), negative: true, color: AppTheme.danger),
          line('Tax', fmt(tax)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: theme.dividerColor),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Due',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                fmt(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

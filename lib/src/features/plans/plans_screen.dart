import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/in_app_pdf.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final plansControllerProvider =
    StateNotifierProvider.autoDispose<PlansController, AsyncValue<List<Plan>>>((ref) {
  return PlansController(ref)..load();
});

/// Capitalises the first letter of each word, leaving the rest untouched so
/// acronyms survive: "abc" -> "Abc", "monthly plan" -> "Monthly Plan",
/// "VIP" -> "VIP". Used to sanitise free-typed plan names in the table.
String _titleCase(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  return s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class PlansController extends StateNotifier<AsyncValue<List<Plan>>> {
  PlansController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    final hadData = state.valueOrNull != null;
    if (!hadData) state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/plans', token: token);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Plan.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      if (!hadData) state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      if (!hadData) state = AsyncValue.error('plans_load_failed', st);
    }
  }

  Future<void> createPlan({
    required String name,
    required int durationDays,
    required double price,
    required double admissionFee,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.postJson('/plans', token: token, body: {
      'name': name.trim(),
      'durationDays': durationDays,
      'price': price,
      'admissionFee': admissionFee,
    });
    await load();
  }

  Future<void> updatePlan({
    required int planId,
    required String name,
    required int durationDays,
    required double price,
    required double admissionFee,
    required String status,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.patchJson('/plans/$planId', token: token, body: {
      'name': name.trim(),
      'durationDays': durationDays,
      'price': price,
      'admissionFee': admissionFee,
      'status': status,
    });
    await load();
  }

  Future<void> deactivatePlan({required int planId}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/plans/$planId', token: token);
    await load();
  }

  Future<void> deletePlan({required int planId}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/plans/$planId/hard', token: token);
    await load();
  }
}

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();

  Future<void> _openPlansPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Plans PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPlansPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runPlansPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runPlansPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/plans.pdf', token: token);
      final name = 'plans_$today.pdf';
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Plans Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  Widget _build(BuildContext context, WidgetRef ref, _PlansScreenState state) {
    final plansAsync = ref.watch(plansControllerProvider);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern();
    final roles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final canManage = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final itemsPreview = plansAsync.valueOrNull ?? const <Plan>[];
    final total = itemsPreview.length;
    final active = itemsPreview.where((p) => p.status == 'active').length;
    final inactive = itemsPreview.where((p) => p.status != 'active').length;
    final avgDays = itemsPreview.isEmpty
        ? 0
        : (itemsPreview.map((p) => p.durationDays).reduce((a, b) => a + b) / itemsPreview.length).round();
    final filteredPreview = state._applyPlanUiFilters(itemsPreview);

    // Flex metric tile — no fixed width. The parent grid wraps each in an
    // Expanded so 4 tiles span the container edge-to-edge.
    Widget metricCard({
      required String title,
      required String value,
      required String subtitle,
      required IconData icon,
      required Color accent,
    }) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withAlpha(60), width: 0.8),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Plans', style: theme.textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: () => _openAddPlan(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Plan'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'PDF',
              onPressed: () => _openPlansPdfActions(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(plansControllerProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Single-row 4-up metric grid ──────────────────────────────────
        // 4 cols on desktop (span edge-to-edge via Expanded), 2 cols on tablet,
        // 1 col stacked on mobile. "Avg Duration" never gets isolated.
        LayoutBuilder(
          builder: (context, c) {
            final tiles = <Widget>[
              metricCard(
                title: 'Total Plans',
                value: '$total',
                subtitle: 'In your gym',
                icon: Icons.card_membership_outlined,
                accent: theme.colorScheme.primary,
              ),
              metricCard(
                title: 'Active',
                value: '$active',
                subtitle: 'Ready for production',
                icon: Icons.verified_outlined,
                accent: theme.colorScheme.tertiary,
              ),
              metricCard(
                title: 'Inactive',
                value: '$inactive',
                subtitle: 'Archived / disabled',
                icon: Icons.block_outlined,
                accent: theme.colorScheme.onSurfaceVariant,
              ),
              metricCard(
                title: 'Avg Duration',
                value: '$avgDays days',
                subtitle: 'Across plans',
                icon: Icons.timelapse_outlined,
                accent: const Color(0xFFF59E0B),
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
        // ── Compact single-line filter bar (all controls locked to 40px) ──
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
                    style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: appDenseInputDecoration(context),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (v) => state._setStatusFilter(v ?? 'all'),
                  ),
                ),
                SizedBox(
                  width: 170,
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(state._sort),
                    initialValue: state._sort,
                    isDense: true,
                    isExpanded: true,
                    style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                    decoration: appDenseInputDecoration(context),
                    items: const [
                      DropdownMenuItem(value: 'name_asc', child: Text('Name A-Z')),
                      DropdownMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                    ],
                    onChanged: (v) => state._setSort(v ?? 'name_asc'),
                  ),
                ),
                SizedBox(
                  width: 340,
                  height: 40,
                  child: TextField(
                    controller: state._searchCtrl,
                    style: GoogleFonts.inter(fontSize: 13.5),
                    decoration: appDenseInputDecoration(
                      context,
                      hint: 'Search plan',
                      prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    onChanged: (_) => state._touchFilters(),
                  ),
                ),
                Text(
                  'Showing ${number.format(filteredPreview.length)} of ${number.format(total)}',
                  style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                AppFilterPill(
                  label: 'Clear',
                  icon: Icons.close_rounded,
                  selected: false,
                  onTap: () => state._clearFilters(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        plansAsync.when(
          data: (items) {
            if (items.isEmpty) return _EmptyState(onAdd: () => _openAddPlan(context, ref));

            final filtered = state._applyPlanUiFilters(items);
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No results', style: theme.textTheme.bodySmall)),
              );
            }

            Future<void> toggleStatus(Plan p) async {
              if (!canManage) return;
              final next = p.status == 'active' ? 'inactive' : 'active';
              try {
                await ref.read(plansControllerProvider.notifier).updatePlan(
                      planId: p.id,
                      name: p.name,
                      durationDays: p.durationDays,
                      price: p.price.toDouble(),
                      admissionFee: p.admissionFee.toDouble(),
                      status: next,
                    );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked $next')));
              } on ApiException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
              }
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    // Scoped Theme: Inter typography + faint dividers for the table only.
                    child: Theme(
                      data: theme.copyWith(
                        dividerColor: theme.brightness == Brightness.dark
                            ? Colors.white.withAlpha(15)
                            : Colors.grey.shade200,
                        dataTableTheme: DataTableThemeData(
                          dividerThickness: 1,
                          headingTextStyle: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          dataTextStyle: GoogleFonts.inter(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurface,
                          ),
                          headingRowColor: WidgetStatePropertyAll(
                            theme.brightness == Brightness.dark
                                ? Colors.white.withAlpha(8)
                                : Colors.black.withAlpha(5),
                          ),
                        ),
                      ),
                      child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 12,
                      headingRowHeight: 46,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 58,
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Duration')),
                        DataColumn(label: Text('Price')),
                        DataColumn(label: Text('Admission')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: [
                        for (final p in filtered)
                          DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  // Title-case so messy entries ("abc") read as "Abc".
                                  child: Text(_titleCase(p.name), overflow: TextOverflow.ellipsis),
                                ),
                              ),
                              DataCell(SizedBox(width: 110, child: Text('${p.durationDays} days'))),
                              DataCell(SizedBox(width: 110, child: Text(number.format(p.price)))),
                              DataCell(SizedBox(width: 110, child: Text(number.format(p.admissionFee)))),
                              DataCell(
                                SizedBox(
                                  width: 140,
                                  child: canManage
                                      ? _StatusToggleButton(
                                          status: p.status,
                                          onPressed: () => toggleStatus(p),
                                        )
                                      : _StatusChip(status: p.status),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppTableActionButton(
                                      icon: Icons.visibility_outlined,
                                      tooltip: 'View',
                                      onPressed: () => _openViewPlan(context, p),
                                    ),
                                    const SizedBox(width: 2),
                                    AppTableActionButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Edit',
                                      onPressed: () => _openEditPlan(context, ref, p),
                                    ),
                                    if (canManage) ...[
                                      const SizedBox(width: 2),
                                      AppTableActionButton(
                                        icon: Icons.delete_outline,
                                        tooltip: 'Delete',
                                        danger: true,
                                        onPressed: () => _confirmDelete(context, ref, p),
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
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.card_membership),
                      title: Text(_titleCase(p.name)),
                      subtitle: Text(
                        '${p.durationDays} days • Price: ${number.format(p.price)} • Admission: ${number.format(p.admissionFee)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          canManage
                              ? _StatusToggleButton(
                                  status: p.status,
                                  onPressed: () => toggleStatus(p),
                                )
                              : _StatusChip(status: p.status),
                          IconButton(
                            tooltip: 'View',
                            onPressed: () => _openViewPlan(context, p),
                            icon: const Icon(Icons.visibility),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _openEditPlan(context, ref, p),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          if (canManage)
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(context, ref, p),
                              icon: const Icon(Icons.delete_outline),
                            ),
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

  void _openViewPlan(BuildContext context, Plan plan) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(plan.name),
          content: Text(
            [
              'Duration: ${plan.durationDays} days',
              'Price: ${plan.price}',
              'Admission Fee: ${plan.admissionFee}',
              'Status: ${plan.status}',
            ].join('\n'),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _openEditPlan(BuildContext context, WidgetRef ref, Plan plan) async {
    final nameCtrl = TextEditingController(text: plan.name);
    final durationCtrl = TextEditingController(text: plan.durationDays.toString());
    final priceCtrl = TextEditingController(text: plan.price.toString());
    final admissionCtrl = TextEditingController(text: plan.admissionFee.toString());
    var status = plan.status;

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.edit_outlined,
      title: 'Edit Plan',
      subtitle: plan.name,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 680;
              final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
              Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name'))),
                      field(
                        TextField(
                          controller: durationCtrl,
                          decoration: const InputDecoration(labelText: 'Duration (days)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      field(
                        TextField(
                          controller: priceCtrl,
                          decoration: const InputDecoration(labelText: 'Price'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      field(
                        TextField(
                          controller: admissionCtrl,
                          decoration: const InputDecoration(labelText: 'Admission Fee'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      field(
                        DropdownButtonFormField<String>(
                          key: ValueKey(status),
                          initialValue: status,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                            DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          ],
                          onChanged: (v) => setModalState(() => status = v ?? 'active'),
                        ),
                      ),
                    ],
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
            final duration = int.tryParse(durationCtrl.text.trim());
            final price = double.tryParse(priceCtrl.text.trim());
            final admission = double.tryParse(admissionCtrl.text.trim()) ?? 0;
            if (duration == null || duration <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid duration')));
              return;
            }
            if (price == null || price < 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid price')));
              return;
            }
            try {
              await ref.read(plansControllerProvider.notifier).updatePlan(
                    planId: plan.id,
                    name: nameCtrl.text,
                    durationDays: duration,
                    price: price,
                    admissionFee: admission,
                    status: status,
                  );
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

    nameCtrl.dispose();
    durationCtrl.dispose();
    priceCtrl.dispose();
    admissionCtrl.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Plan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete plan?'),
          content: Text('Delete ${plan.name}? This action cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(plansControllerProvider.notifier).deletePlan(planId: plan.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final msg = e.message == 'plan_in_use' ? 'Plan is in use. Deactivate instead.' : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  Future<void> _openAddPlan(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');
    final priceCtrl = TextEditingController(text: '3000');
    final admissionCtrl = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      try {
        await ref.read(plansControllerProvider.notifier).createPlan(
              name: nameCtrl.text,
              durationDays: int.parse(durationCtrl.text),
              price: double.parse(priceCtrl.text),
              admissionFee: double.parse(admissionCtrl.text),
            );
        if (context.mounted) Navigator.of(context, rootNavigator: true).maybePop();
      } on ApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create failed')));
      }
    }

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.add,
      title: 'Add Plan',
      subtitle: 'Create membership plan details',
      body: Form(
        key: formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 680;
            final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
            Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plan Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    field(
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Plan Name'),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'Name required' : null,
                      ),
                    ),
                    field(
                      TextFormField(
                        controller: durationCtrl,
                        decoration: const InputDecoration(labelText: 'Duration (days)'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Valid days required';
                          return null;
                        },
                      ),
                    ),
                    field(
                      TextFormField(
                        controller: priceCtrl,
                        decoration: const InputDecoration(labelText: 'Price'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Valid price required';
                          return null;
                        },
                      ),
                    ),
                    field(
                      TextFormField(
                        controller: admissionCtrl,
                        decoration: const InputDecoration(labelText: 'Admission Fee'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n < 0) return 'Valid fee required';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: submit, child: const Text('Save')),
      ],
    );

    nameCtrl.dispose();
    durationCtrl.dispose();
    priceCtrl.dispose();
    admissionCtrl.dispose();
  }
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  String _sort = 'name_asc';

  void _setStatusFilter(String v) => setState(() => _statusFilter = v);
  void _setSort(String v) => setState(() => _sort = v);
  void _touchFilters() => setState(() {});
  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _statusFilter = 'all';
      _sort = 'name_asc';
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Plan> _applyPlanUiFilters(List<Plan> items) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = items.where((p) {
      if (_statusFilter != 'all' && p.status != _statusFilter) return false;
      if (q.isNotEmpty) {
        final hay = '${p.name} ${p.durationDays} ${p.price} ${p.admissionFee} ${p.status}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    if (_sort == 'name_desc') {
      filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    } else if (_sort == 'newest') {
      filtered.sort((a, b) => b.id.compareTo(a.id));
    } else {
      filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return widget._build(context, ref, this);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

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
                  child: const Icon(Icons.card_membership, size: 28),
                ),
                const SizedBox(height: 12),
                Text('No plans yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Create membership plans for your gym.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Plan')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat read-only status pill — Inter, emerald for active, grey otherwise.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = status == 'active';
    final accent = isActive ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(70), width: 0.8),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.1),
      ),
    );
  }
}

/// Interactive status pill — same flat look, with an unfold cue to signal that
/// tapping toggles active/inactive. Inter typography throughout.
class _StatusToggleButton extends StatelessWidget {
  const _StatusToggleButton({required this.status, required this.onPressed});

  final String status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = status == 'active';
    final accent = isActive ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withAlpha(28),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withAlpha(70), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.1),
              ),
              const SizedBox(width: 4),
              Icon(Icons.unfold_more, size: 14, color: accent.withAlpha(180)),
            ],
          ),
        ),
      ),
    );
  }
}

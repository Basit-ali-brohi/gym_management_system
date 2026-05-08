import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final plansControllerProvider =
    StateNotifierProvider.autoDispose<PlansController, AsyncValue<List<Plan>>>((ref) {
  return PlansController(ref)..load();
});

class PlansController extends StateNotifier<AsyncValue<List<Plan>>> {
  PlansController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
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
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('plans_load_failed', st);
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

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Expanded(child: Text('Plans', style: theme.textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: () => _openAddPlan(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Plan'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(plansControllerProvider.notifier).load(),
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
              title: 'Total Plans',
              value: '$total',
              subtitle: 'In your gym',
              icon: Icons.card_membership_outlined,
            ),
            metricCard(
              title: 'Active',
              value: '$active',
              subtitle: 'Ready for production',
              icon: Icons.verified_outlined,
            ),
            metricCard(
              title: 'Inactive',
              value: '$inactive',
              subtitle: 'Archived / disabled',
              icon: Icons.block_outlined,
            ),
            metricCard(
              title: 'Avg Lead Time',
              value: '$avgDays days',
              subtitle: 'Production estimate',
              icon: Icons.timelapse_outlined,
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
                    initialValue: 'all',
                    decoration: const InputDecoration(labelText: 'All Statuses'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: 'name_asc',
                    decoration: const InputDecoration(labelText: 'Name A–Z'),
                    items: const [
                      DropdownMenuItem(value: 'name_asc', child: Text('Name A–Z')),
                      DropdownMenuItem(value: 'name_desc', child: Text('Name Z–A')),
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search plan',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Text(
                  'Showing $total of $total',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('Clear')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        plansAsync.when(
          data: (items) {
            if (items.isEmpty) return _EmptyState(onAdd: () => _openAddPlan(context, ref));

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
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Duration')),
                            DataColumn(label: Text('Price')),
                            DataColumn(label: Text('Admission')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: [
                            for (final p in items)
                              DataRow(
                                cells: [
                                  DataCell(Text(p.name)),
                                  DataCell(Text('${p.durationDays} days')),
                                  DataCell(Text(number.format(p.price))),
                                  DataCell(Text(number.format(p.admissionFee))),
                                  DataCell(
                                    canManage
                                        ? _StatusToggleButton(
                                            status: p.status,
                                            onPressed: () => toggleStatus(p),
                                          )
                                        : _StatusChip(status: p.status),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
                    final p = items[i];
                    return ListTile(
                      leading: const Icon(Icons.card_membership),
                      title: Text(p.name),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = status == 'active';
    final bg = isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;
    final fg = isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant;
    return Chip(
      label: Text(status),
      backgroundColor: bg,
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StatusToggleButton extends StatelessWidget {
  const _StatusToggleButton({required this.status, required this.onPressed});

  final String status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = status == 'active';
    final bg = isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;
    final fg = isActive ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: bg,
        foregroundColor: fg,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        shape: const StadiumBorder(),
      ),
      child: Text(status),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final staffControllerProvider =
    StateNotifierProvider.autoDispose<_StaffController, AsyncValue<List<StaffUser>>>((ref) {
  return _StaffController(ref)..load();
});

class _StaffController extends StateNotifier<AsyncValue<List<StaffUser>>> {
  _StaffController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final res = await api.getJson('/staff', token: token);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => StaffUser.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('staff_load_failed', st);
    }
  }

  Future<void> invite({
    required String email,
    required String fullName,
    required String password,
    required List<String> roles,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.postJson('/staff', token: token, body: {
      'email': email.trim(),
      'fullName': fullName.trim(),
      'password': password,
      'roles': roles,
    });
    await load();
  }

  Future<void> updateRoles({
    required int userId,
    required List<String> roles,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.putJson('/staff/$userId/roles', token: token, body: {'roles': roles});
    await load();
  }

  Future<void> setStatus({
    required int userId,
    required String status,
  }) async {
    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) throw ApiException('unauthorized');
    final api = ref.read(apiClientProvider);
    await api.patchJson('/staff/$userId/status', token: token, body: {'status': status});
    await load();
  }
}

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dt = DateFormat('yyyy-MM-dd');
    final staffAsync = ref.watch(staffControllerProvider);
    final itemsPreview = staffAsync.valueOrNull ?? const <StaffUser>[];
    final total = itemsPreview.length;
    final active = itemsPreview.where((u) => u.status == 'active').length;
    final disabled = itemsPreview.where((u) => u.status != 'active').length;
    final admins = itemsPreview.where((u) => u.roles.contains('admin')).length;

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

    String fmtDate(String raw) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return raw;
      return dt.format(parsed);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Staff', style: theme.textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: () => _openInvite(context, ref),
              icon: const Icon(Icons.person_add),
              label: const Text('Invite'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(staffControllerProvider.notifier).load(),
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
              title: 'Total users',
              value: '$total',
              subtitle: 'Team members',
              icon: Icons.groups_outlined,
            ),
            metricCard(
              title: 'Active',
              value: '$active',
              subtitle: 'Can login',
              icon: Icons.verified_outlined,
            ),
            metricCard(
              title: 'Disabled',
              value: '$disabled',
              subtitle: 'Blocked',
              icon: Icons.block_outlined,
            ),
            metricCard(
              title: 'Admins',
              value: '$admins',
              subtitle: 'Has admin role',
              icon: Icons.admin_panel_settings_outlined,
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
                      DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: 'name_asc',
                    decoration: const InputDecoration(labelText: 'Sort'),
                    items: const [
                      DropdownMenuItem(value: 'name_asc', child: Text('Name A–Z')),
                      DropdownMenuItem(value: 'name_desc', child: Text('Name Z–A')),
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(
                  width: 360,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search staff, role, status',
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
        staffAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyState(
                title: 'No staff users',
                subtitle: 'Invite staff to control access and audit activity.',
                icon: Icons.badge,
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Roles')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Created')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: [
                        for (final u in items)
                          DataRow(
                            cells: [
                              DataCell(Text(u.fullName)),
                              DataCell(Text(u.email)),
                              DataCell(Wrap(spacing: 6, children: [for (final r in u.roles) _RoleChip(role: r)])),
                              DataCell(_StatusChip(status: u.status)),
                              DataCell(Text(fmtDate(u.createdAt))),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'View',
                                      onPressed: () => _openView(context, u),
                                      icon: const Icon(Icons.visibility),
                                    ),
                                    IconButton(
                                      tooltip: 'Edit roles',
                                      onPressed: () => _openRoles(context, ref, u),
                                      icon: const Icon(Icons.manage_accounts),
                                    ),
                                    IconButton(
                                      tooltip: u.status == 'active' ? 'Disable' : 'Enable',
                                      onPressed: () => _confirmToggleStatus(context, ref, u),
                                      icon: Icon(u.status == 'active' ? Icons.block : Icons.check_circle_outline),
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
                  separatorBuilder: (context, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = items[i];
                    return ListTile(
                      leading: const Icon(Icons.badge),
                      title: Text(u.fullName),
                      subtitle: Text('${u.email} • ${u.roles.join(', ')}'),
                      trailing: IconButton(
                        tooltip: 'Actions',
                        onPressed: () => _openActions(context, ref, u),
                        icon: const Icon(Icons.more_vert),
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

  Future<void> _openInvite(BuildContext context, WidgetRef ref) async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var roles = <String>{'staff'};

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.person_add_alt_1_outlined,
      title: 'Invite Staff',
      subtitle: 'Create staff user and assign roles',
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
                  Text('Staff Details', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      field(TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name'))),
                      field(TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'))),
                      field(
                        TextField(
                          controller: passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Password'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Roles', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilterChip(
                        label: const Text('staff'),
                        selected: roles.contains('staff'),
                        onSelected: (v) => setModalState(() {
                          if (v) roles.add('staff');
                          if (!v && roles.length > 1) roles.remove('staff');
                        }),
                      ),
                      FilterChip(
                        label: const Text('admin'),
                        selected: roles.contains('admin'),
                        onSelected: (v) => setModalState(() {
                          if (v) roles.add('admin');
                          if (!v) roles.remove('admin');
                        }),
                      ),
                      FilterChip(
                        label: const Text('owner'),
                        selected: roles.contains('owner'),
                        onSelected: (v) => setModalState(() {
                          if (v) roles.add('owner');
                          if (!v) roles.remove('owner');
                        }),
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
            if (nameCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name required')));
              return;
            }
            if (!emailCtrl.text.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valid email required')));
              return;
            }
            if (passCtrl.text.length < 6) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password min 6 chars')));
              return;
            }
            try {
              await ref.read(staffControllerProvider.notifier).invite(
                    email: emailCtrl.text,
                    fullName: nameCtrl.text,
                    password: passCtrl.text,
                    roles: roles.toList(),
                  );
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff created')));
            } on ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
            } catch (_) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
            }
          },
          child: const Text('Create'),
        ),
      ],
    );

    emailCtrl.dispose();
    nameCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _openRoles(BuildContext context, WidgetRef ref, StaffUser user) async {
    var roles = user.roles.toSet();
    await showAppFormDialog<void>(
      context: context,
      icon: Icons.manage_accounts_outlined,
      title: 'Edit Roles',
      subtitle: user.email,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Roles', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilterChip(
                    label: const Text('staff'),
                    selected: roles.contains('staff'),
                    onSelected: (v) => setModalState(() {
                      if (v) roles.add('staff');
                      if (!v && roles.length > 1) roles.remove('staff');
                    }),
                  ),
                  FilterChip(
                    label: const Text('admin'),
                    selected: roles.contains('admin'),
                    onSelected: (v) => setModalState(() {
                      if (v) roles.add('admin');
                      if (!v) roles.remove('admin');
                    }),
                  ),
                  FilterChip(
                    label: const Text('owner'),
                    selected: roles.contains('owner'),
                    onSelected: (v) => setModalState(() {
                      if (v) roles.add('owner');
                      if (!v) roles.remove('owner');
                    }),
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
            try {
              await ref.read(staffControllerProvider.notifier).updateRoles(userId: user.id, roles: roles.toList());
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: true).maybePop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Roles updated')));
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

  void _openView(BuildContext context, StaffUser user) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(user.fullName),
          content: Text(
            [
              'Email: ${user.email}',
              'Roles: ${user.roles.join(', ')}',
              'Status: ${user.status}',
              'Created: ${user.createdAt}',
            ].join('\n'),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _confirmToggleStatus(BuildContext context, WidgetRef ref, StaffUser user) async {
    final next = user.status == 'active' ? 'disabled' : 'active';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(next == 'disabled' ? 'Disable user?' : 'Enable user?'),
          content: Text('${user.fullName} (${user.email})'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(staffControllerProvider.notifier).setStatus(userId: user.id, status: next);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  }

  void _openActions(BuildContext context, WidgetRef ref, StaffUser user) {
    showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final next = user.status == 'active' ? 'disabled' : 'active';
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
                leading: const Icon(Icons.manage_accounts),
                title: const Text('Edit roles'),
                onTap: () => Navigator.of(context).pop('roles'),
              ),
              ListTile(
                leading: Icon(next == 'disabled' ? Icons.block : Icons.check_circle_outline),
                title: Text(next == 'disabled' ? 'Disable' : 'Enable'),
                onTap: () => Navigator.of(context).pop('status'),
              ),
            ],
          ),
        );
      },
    ).then((selected) {
      if (!context.mounted) return;
      if (selected == 'view') _openView(context, user);
      if (selected == 'roles') _openRoles(context, ref, user);
      if (selected == 'status') _confirmToggleStatus(context, ref, user);
    });
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = role == 'owner'
        ? theme.colorScheme.primaryContainer
        : role == 'admin'
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    final fg = role == 'owner'
        ? theme.colorScheme.onPrimaryContainer
        : role == 'admin'
            ? theme.colorScheme.onTertiaryContainer
            : theme.colorScheme.onSurfaceVariant;
    return Chip(
      label: Text(role),
      backgroundColor: bg,
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

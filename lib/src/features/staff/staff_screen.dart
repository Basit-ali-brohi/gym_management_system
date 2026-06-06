import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/in_app_pdf.dart';
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
    state = const AsyncLoading<List<StaffUser>>().copyWithPrevious(state);
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

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();

  Future<void> _openStaffPdfActions(BuildContext context, WidgetRef ref) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Staff PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runStaffPdf(context, ref, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runStaffPdf(context, ref, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runStaffPdf(
    BuildContext context,
    WidgetRef ref, {
    required bool preview,
    required String today,
  }) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/staff.pdf', token: token);
      final name = 'staff_$today.pdf';
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Staff Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  Widget _build(BuildContext context, WidgetRef ref, _StaffScreenState state) {
    final theme = Theme.of(context);
    final dt = DateFormat('yyyy-MM-dd');
    final number = NumberFormat.decimalPattern();
    final staffAsync = ref.watch(staffControllerProvider);
    final itemsPreview = staffAsync.valueOrNull ?? const <StaffUser>[];
    final total = itemsPreview.length;
    final active = itemsPreview.where((u) => u.status == 'active').length;
    final disabled = itemsPreview.where((u) => u.status != 'active').length;
    final admins = itemsPreview.where((u) => u.roles.contains('admin')).length;

    // Flex team metric tile — fills its parent (no fixed width) so 4 tiles
    // span edge-to-edge. Count rendered in Bebas Neue.
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
                    Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: accent)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
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
              tooltip: 'PDF',
              onPressed: () => _openStaffPdfActions(context, ref),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => ref.read(staffControllerProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // ── Edge-to-edge 4-up team metric grid ───────────────────────────
        LayoutBuilder(
          builder: (context, c) {
            final tiles = <Widget>[
              metricCard(
                title: 'Total users',
                value: '$total',
                subtitle: 'Team members',
                icon: Icons.groups_outlined,
                accent: theme.colorScheme.primary,
              ),
              metricCard(
                title: 'Active',
                value: '$active',
                subtitle: 'Can login',
                icon: Icons.verified_outlined,
                accent: theme.colorScheme.tertiary,
              ),
              metricCard(
                title: 'Disabled',
                value: '$disabled',
                subtitle: 'Blocked',
                icon: Icons.block_outlined,
                accent: const Color(0xFFE06C6C),
              ),
              metricCard(
                title: 'Admins',
                value: '$admins',
                subtitle: 'Has admin role',
                icon: Icons.admin_panel_settings_outlined,
                accent: const Color(0xFF3B82F6),
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
        // ── Filter bar (40px controls; counter decoupled to table footer) ──
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
                      DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
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
                  width: 320,
                  height: 40,
                  child: TextField(
                    controller: state._searchCtrl,
                    style: GoogleFonts.inter(fontSize: 13.5),
                    decoration: appDenseInputDecoration(
                      context,
                      hint: 'Search staff, role, status',
                      prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    onChanged: (_) => state._touchFilters(),
                  ),
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
        staffAsync.when(
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyState(
                title: 'No staff users',
                subtitle: 'Invite staff to control access and audit activity.',
                icon: Icons.badge,
              );
            }

            final filtered = state._applyStaffUiFilters(items);
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('No results', style: theme.textTheme.bodySmall)),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  final isDark = theme.brightness == Brightness.dark;
                  // Unified ledger panel: table on top, footer counter below.
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
                              dataRowMinHeight: 54,
                              dataRowMaxHeight: 60,
                              columns: const [
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('Roles')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Created')),
                                DataColumn(label: Text('Action')),
                              ],
                              rows: [
                                for (final u in filtered)
                                  DataRow(
                                    cells: [
                                      DataCell(Text(
                                        u.fullName,
                                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600),
                                      )),
                                      // Email in Inter, muted, for a technical look.
                                      DataCell(Text(
                                        u.email,
                                        style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                                      )),
                                      DataCell(Wrap(spacing: 6, children: [for (final r in u.roles) _RoleChip(role: r)])),
                                      DataCell(_StatusChip(status: u.status)),
                                      DataCell(Text(
                                        fmtDate(u.createdAt),
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      )),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Hover-circle actions with a wider gap to avoid misclicks.
                                            AppTableActionButton(
                                              icon: Icons.visibility_outlined,
                                              tooltip: 'View',
                                              onPressed: () => _openView(context, u),
                                            ),
                                            const SizedBox(width: 8),
                                            AppTableActionButton(
                                              icon: Icons.manage_accounts_outlined,
                                              tooltip: 'Manage roles',
                                              onPressed: () => _openRoles(context, ref, u),
                                            ),
                                            const SizedBox(width: 8),
                                            AppTableActionButton(
                                              icon: u.status == 'active' ? Icons.block : Icons.check_circle_outline,
                                              tooltip: u.status == 'active' ? 'Disable' : 'Enable',
                                              danger: u.status == 'active',
                                              onPressed: () => _confirmToggleStatus(context, ref, u),
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
                        // Decoupled footer counter, lower-right.
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Spacer(),
                              Text(
                                'Showing ${number.format(filtered.length)} of ${number.format(items.length)}',
                                style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = filtered[i];
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
    final rand = Random.secure();
    String genPassword() {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
      final buf = StringBuffer();
      for (var i = 0; i < 12; i += 1) {
        buf.write(chars[rand.nextInt(chars.length)]);
      }
      return buf.toString();
    }
    var showPass = false;

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
                          obscureText: !showPass,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Generate',
                                  onPressed: () => setModalState(() => passCtrl.text = genPassword()),
                                  icon: const Icon(Icons.auto_fix_high),
                                ),
                                IconButton(
                                  tooltip: showPass ? 'Hide' : 'Show',
                                  onPressed: () => setModalState(() => showPass = !showPass),
                                  icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                ),
                              ],
                            ),
                          ),
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
                        label: const Text('receptionist'),
                        selected: roles.contains('receptionist'),
                        onSelected: (v) => setModalState(() {
                          if (v) roles.add('receptionist');
                          if (!v) roles.remove('receptionist');
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
                    label: const Text('receptionist'),
                    selected: roles.contains('receptionist'),
                    onSelected: (v) => setModalState(() {
                      if (v) roles.add('receptionist');
                      if (!v) roles.remove('receptionist');
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

/// Flat role pill — Inter, subtle tinted fill: owner → primary, admin →
/// blue, staff/other → muted grey.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = role == 'owner'
        ? theme.colorScheme.primary
        : role == 'admin'
            ? const Color(0xFF3B82F6)
            : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(64), width: 0.8),
      ),
      child: Text(
        role,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.1),
      ),
    );
  }
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
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

  List<StaffUser> _applyStaffUiFilters(List<StaffUser> items) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final filtered = items.where((u) {
      if (_statusFilter != 'all' && u.status != _statusFilter) return false;
      if (q.isNotEmpty) {
        final hay = '${u.fullName} ${u.email} ${u.status} ${u.roles.join(' ')}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    DateTime? parse(String raw) => DateTime.tryParse(raw);

    if (_sort == 'name_desc') {
      filtered.sort((a, b) => b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase()));
    } else if (_sort == 'newest') {
      filtered.sort((a, b) {
        final ad = parse(a.createdAt);
        final bd = parse(b.createdAt);
        if (ad == null && bd == null) return b.id.compareTo(a.id);
        if (ad == null) return 1;
        if (bd == null) return -1;
        final c = bd.compareTo(ad);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
    } else {
      filtered.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return widget._build(context, ref, this);
  }
}

/// Flat status pill — Inter, emerald for active, muted grey otherwise.
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

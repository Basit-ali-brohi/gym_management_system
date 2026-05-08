import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
import '../../models/models.dart';
import '../auth/auth_controller.dart';

final membersControllerProvider =
    StateNotifierProvider.autoDispose<MembersController, AsyncValue<List<Member>>>((ref) {
  return MembersController(ref)..load();
});

final plansLookupProvider = FutureProvider.autoDispose<List<Plan>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/plans', token: token);
  return (res['items'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => Plan.fromJson(e.cast<String, dynamic>()))
      .toList();
});

class MembersController extends StateNotifier<AsyncValue<List<Member>>> {
  MembersController(this.ref) : super(const AsyncValue.loading());

  final Ref ref;
  String _lastQuery = '';
  String _lastStatus = '';
  String _lastFrom = '';
  String _lastTo = '';

  Future<void> load({String q = '', String status = '', String from = '', String to = ''}) async {
    _lastQuery = q;
    _lastStatus = status;
    _lastFrom = from;
    _lastTo = to;
    state = const AsyncValue.loading();
    try {
      final token = ref.read(authControllerProvider).token;
      final api = ref.read(apiClientProvider);
      final query = <String, String>{'limit': '200'};
      if (q.trim().isNotEmpty) query['q'] = q.trim();
      if (status.trim().isNotEmpty) query['status'] = status.trim();
      if (from.trim().isNotEmpty) query['from'] = from.trim();
      if (to.trim().isNotEmpty) query['to'] = to.trim();
      final res = await api.getJson('/members', token: token, query: query);
      final items = (res['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Member.fromJson(e.cast<String, dynamic>()))
          .toList();
      state = AsyncValue.data(items);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error('members_load_failed', st);
    }
  }

  Future<void> createMember({
    required String memberCode,
    required String fullName,
    String? phone,
    required int planId,
    required String joinDate,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.postJson('/members/register', token: token, body: {
      'memberCode': memberCode.trim(),
      'fullName': fullName.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'planId': planId,
      'joinDate': joinDate,
      'startDate': joinDate,
      'createInvoice': true,
    });
    await load(q: _lastQuery, status: _lastStatus, from: _lastFrom, to: _lastTo);
  }

  Future<void> updateMember({
    required int memberId,
    required String fullName,
    String? phone,
    required String status,
    String? notes,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.patchJson('/members/$memberId', token: token, body: {
      'fullName': fullName.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'status': status,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
    });
    await load(q: _lastQuery, status: _lastStatus, from: _lastFrom, to: _lastTo);
  }

  Future<void> deleteMember({required int memberId}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/members/$memberId', token: token);
    await load(q: _lastQuery, status: _lastStatus, from: _lastFrom, to: _lastTo);
  }

  Future<void> changeMembership({
    required int memberId,
    required int planId,
    required String startDate,
    required bool createInvoice,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.postJson('/members/$memberId/change-membership', token: token, body: {
      'planId': planId,
      'startDate': startDate,
      'createInvoice': createInvoice,
    });
    await load(q: _lastQuery, status: _lastStatus, from: _lastFrom, to: _lastTo);
  }
}

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _hydratedFromRoute = false;
  bool _openedPrefill = false;
  String _statusFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;

  final _date = DateFormat('yyyy-MM-dd');
  final _pretty = DateFormat('dd MMM yyyy');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _csvEscape(String value) {
    final v = value.replaceAll('"', '""');
    return '"$v"';
  }

  Future<void> _exportMembersCsv(BuildContext context, List<Member> items) async {
    final now = DateTime.now();
    final name = 'members_${_date.format(now)}.csv';
    final lines = <String>[
      ['id', 'member_code', 'full_name', 'phone', 'status', 'join_date', 'branch_name'].map(_csvEscape).join(','),
      ...items.map((m) {
        return [
          m.id.toString(),
          m.memberCode,
          m.fullName,
          m.phone ?? '',
          m.status,
          m.joinDate,
          m.branchName ?? '',
        ].map(_csvEscape).join(',');
      }),
    ];
    final bytes = utf8.encode('${lines.join('\r\n')}\r\n');
    final path = downloadBytes(fileName: name, bytes: bytes, mimeType: 'text/csv');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(path == null ? 'Exported' : 'Exported: $path')),
    );
  }

  Future<void> _openMembersPdfActions(BuildContext context) async {
    final today = _date.format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Members PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runMembersPdf(context, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runMembersPdf(context, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runMembersPdf(BuildContext context, {required bool preview, required String today}) async {
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/members.pdf', token: token);
      final name = 'members_$today.pdf';
      final savedPath = preview
          ? previewBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf')
          : downloadBytes(fileName: name, bytes: bytes, mimeType: 'application/pdf');
      if (!context.mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $savedPath')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(preview ? 'Opening PDF…' : 'Download started')));
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
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(membersControllerProvider);
    final theme = Theme.of(context);
    final rawRoles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final roles = rawRoles
        .map((r) => r.trim().toLowerCase().replaceAll(' ', '_'))
        .where((r) => r.isNotEmpty)
        .toSet();
    final canDelete = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final qp = GoRouterState.of(context).uri.queryParameters;
    final q = qp['q']?.trim();
    if (!_hydratedFromRoute && q != null && q.isNotEmpty) {
      _hydratedFromRoute = true;
      _searchCtrl.text = q;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(membersControllerProvider.notifier).load(q: q);
      });
    }
    final prefill = qp['prefill']?.trim();
    final prefillName = qp['fullName']?.trim();
    final prefillPhone = qp['phone']?.trim();
    if (!_openedPrefill && prefill == 'lead' && (prefillName?.isNotEmpty ?? false)) {
      _openedPrefill = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openAddMember(context, prefillFullName: prefillName, prefillPhone: prefillPhone);
      });
    }
    final fromStr = _fromDate == null ? '' : _date.format(_fromDate!);
    final toStr = _toDate == null ? '' : _date.format(_toDate!);
    final statusStr = _statusFilter == 'all' ? '' : _statusFilter;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 700;
            final items = membersAsync.valueOrNull ?? const <Member>[];
            final total = items.length;
            final active = items.where((m) => m.status == 'active').length;
            final expired = items.where((m) => m.status == 'expired').length;
            final inactive = items.where((m) => m.status == 'inactive').length;

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

            final search = TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search (code / name / phone)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 220), () {
                  ref
                      .read(membersControllerProvider.notifier)
                      .load(q: v.trim(), status: statusStr, from: fromStr, to: toStr);
                });
              },
            );

            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HoverScaleButton(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty ? null : () => _exportMembersCsv(context, items),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'PDF',
                  onPressed: () => _openMembersPdfActions(context),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                const SizedBox(width: 6),
                _HoverScaleButton(
                  child: FilledButton.icon(
                    onPressed: () => _openAddMember(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Member'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh',
                    onPressed: () => ref
                        .read(membersControllerProvider.notifier)
                        .load(q: _searchCtrl.text.trim(), status: statusStr, from: fromStr, to: toStr),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            );

            final headerRow = stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Members', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Text('Members', style: theme.textTheme.headlineSmall)),
                      actions,
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerRow,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    metricCard(
                      title: 'Total Members',
                      value: '$total',
                      subtitle: 'In your gym',
                      icon: Icons.groups_outlined,
                    ),
                    metricCard(
                      title: 'Active',
                      value: '$active',
                      subtitle: 'Membership active',
                      icon: Icons.verified_outlined,
                    ),
                    metricCard(
                      title: 'Expired',
                      value: '$expired',
                      subtitle: 'Past end-date',
                      icon: Icons.schedule_outlined,
                    ),
                    metricCard(
                      title: 'Inactive',
                      value: '$inactive',
                      subtitle: 'Disabled / archived',
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
                            initialValue: _statusFilter,
                            decoration: const InputDecoration(labelText: 'All Statuses'),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                              DropdownMenuItem(value: 'active', child: Text('Active')),
                              DropdownMenuItem(value: 'expired', child: Text('Expired')),
                              DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                            ],
                            onChanged: (v) async {
                              final next = v ?? 'all';
                              setState(() => _statusFilter = next);
                              await ref.read(membersControllerProvider.notifier).load(
                                    q: _searchCtrl.text.trim(),
                                    status: next == 'all' ? '' : next,
                                    from: fromStr,
                                    to: toStr,
                                  );
                            },
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
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _fromDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) return;
                            setState(() => _fromDate = picked);
                            await ref.read(membersControllerProvider.notifier).load(
                                  q: _searchCtrl.text.trim(),
                                  status: statusStr,
                                  from: _date.format(picked),
                                  to: toStr,
                                );
                          },
                          icon: const Icon(Icons.date_range),
                          label: Text(_fromDate == null ? 'From' : _date.format(_fromDate!)),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _toDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked == null) return;
                            setState(() => _toDate = picked);
                            await ref.read(membersControllerProvider.notifier).load(
                                  q: _searchCtrl.text.trim(),
                                  status: statusStr,
                                  from: fromStr,
                                  to: _date.format(picked),
                                );
                          },
                          icon: const Icon(Icons.date_range),
                          label: Text(_toDate == null ? 'To' : _date.format(_toDate!)),
                        ),
                        SizedBox(width: stacked ? double.infinity : 360, child: search),
                        Text(
                          'Showing $total of $total',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            _searchCtrl.clear();
                              setState(() {
                                _statusFilter = 'all';
                                _fromDate = null;
                                _toDate = null;
                              });
                              ref.read(membersControllerProvider.notifier).load(q: '');
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        membersAsync.when(
          data: (items) {
            if (items.isEmpty) return _EmptyState(onAdd: () => _openAddMember(context));

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: DataTable(
                        columnSpacing: 18,
                        horizontalMargin: 12,
                          columns: const [
                            DataColumn(label: Text('ID')),
                            DataColumn(label: Text('Code')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Phone')),
                            DataColumn(label: Text('Joined')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: [
                            for (final m in items)
                              DataRow(
                                cells: [
                                  DataCell(SizedBox(width: 46, child: Text(m.id.toString()))),
                                  DataCell(SizedBox(width: 92, child: Text(m.memberCode, overflow: TextOverflow.ellipsis))),
                                  DataCell(SizedBox(width: 220, child: Text(m.fullName, overflow: TextOverflow.ellipsis))),
                                  DataCell(SizedBox(width: 150, child: Text(m.phone ?? '-', overflow: TextOverflow.ellipsis))),
                                  DataCell(SizedBox(width: 110, child: Text(_formatDate(m.joinDate)))),
                                  DataCell(_StatusChip(status: m.status)),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          onPressed: () => _openEditMember(context, m),
                                          icon: const Icon(Icons.edit_outlined),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                          iconSize: 20,
                                        ),
                                        const SizedBox(width: 2),
                                        IconButton(
                                          tooltip: 'View',
                                          onPressed: () => _openMemberDetail(context, m),
                                          icon: const Icon(Icons.visibility),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                          iconSize: 20,
                                        ),
                                        if (canDelete) ...[
                                          const SizedBox(width: 2),
                                          IconButton(
                                            tooltip: 'Delete',
                                            onPressed: () => _confirmDelete(context, m),
                                            icon: const Icon(Icons.delete_outline),
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                            iconSize: 20,
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
                    final m = items[i];
                    return ListTile(
                      title: Text('${m.fullName} (${m.memberCode})'),
                      subtitle: Text([
                        'ID: ${m.id}',
                        if (m.phone != null && m.phone!.isNotEmpty) m.phone!,
                        if (m.branchName != null && m.branchName!.isNotEmpty) m.branchName!,
                      ].join(' • ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusChip(status: m.status),
                          IconButton(
                            tooltip: 'View',
                            onPressed: () => _openMemberDetail(context, m),
                            icon: const Icon(Icons.visibility),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _openEditMember(context, m),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          if (canDelete)
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(context, m),
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

  Future<void> _openMemberDetail(BuildContext context, Member member) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    final future = api.getJson('/members/${member.id}/detail', token: token);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context);
        final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: viewInsets.bottom + 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(snap.error.toString()));
                }

                final data = snap.data ?? <String, dynamic>{};
                final m = (data['member'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                final sub = (data['subscription'] as Map?)?.cast<String, dynamic>();
                final invoices = (data['invoices'] as List<dynamic>? ?? [])
                    .whereType<Map>()
                    .map((e) => e.cast<String, dynamic>())
                    .toList();
                final checkinsTotal = (data['checkinsTotal'] as num?)?.toInt() ?? 0;
                final lastCheckinAt = data['lastCheckinAt']?.toString();
                final planName = sub?['planName']?.toString();
                final endDate = sub?['endDate']?.toString();

                final fullName = m['fullName']?.toString() ?? member.fullName;
                final initials = fullName
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((s) => s.isNotEmpty)
                    .take(2)
                    .map((s) => s[0].toUpperCase())
                    .join();

                String prettyDate(String raw) {
                  final parsed = DateTime.tryParse(raw);
                  if (parsed == null) return raw;
                  return _pretty.format(parsed);
                }

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(radius: 24, child: Text(initials.isEmpty ? 'M' : initials)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fullName, style: Theme.of(context).textTheme.titleLarge),
                                Text('Code: ${m['memberCode'] ?? member.memberCode} • ID: ${m['id'] ?? member.id}'),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Membership', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text('Plan: ${planName ?? '-'}'),
                              Text('Expiry: ${endDate ?? '-'}'),
                              const SizedBox(height: 10),
                              Text('History', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text('Total check-ins: $checkinsTotal'),
                              Text('Last check-in: ${lastCheckinAt == null ? '-' : prettyDate(lastCheckinAt)}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Last Invoices', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (invoices.isEmpty)
                        Text('No invoices', style: Theme.of(context).textTheme.bodySmall)
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: invoices.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final inv = invoices[i];
                            return ListTile(
                              dense: true,
                              title: Text(inv['invoiceNo']?.toString() ?? ''),
                              subtitle: Text('Total: ${inv['total']} • ${inv['status']}'),
                              trailing: Text(prettyDate(inv['createdAt']?.toString() ?? '')),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _date.format(parsed);
  }

  Future<void> _openAddMember(
    BuildContext context, {
    String? prefillFullName,
    String? prefillPhone,
  }) async {
    final memberCodeCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController(text: prefillFullName?.trim() ?? '');
    final phoneCtrl = TextEditingController(text: prefillPhone?.trim() ?? '');
    final formKey = GlobalKey<FormState>();
    DateTime joinDate = DateTime.now();
    int? selectedPlanId;
    int selectedDurationDays = 30;

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      if (selectedPlanId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a plan')));
        return;
      }
      try {
        await ref.read(membersControllerProvider.notifier).createMember(
              memberCode: memberCodeCtrl.text,
              fullName: fullNameCtrl.text,
              phone: phoneCtrl.text,
              planId: selectedPlanId!,
              joinDate: _date.format(joinDate),
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
      icon: Icons.person_add_alt_1_outlined,
      title: 'Add Member',
      subtitle: 'Create member and assign membership plan',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final plansAsync = r.watch(plansLookupProvider);
              final expiryDate = joinDate.add(Duration(days: selectedDurationDays));

              return Form(
                key: formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 680;
                    final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                    Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Member Details', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            field(
                              TextFormField(
                                controller: memberCodeCtrl,
                                decoration: const InputDecoration(labelText: 'Member Code'),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Code required' : null,
                              ),
                            ),
                            field(
                              TextFormField(
                                controller: fullNameCtrl,
                                decoration: const InputDecoration(labelText: 'Full Name'),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Name required' : null,
                              ),
                            ),
                            field(
                              TextFormField(
                                controller: phoneCtrl,
                                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text('Membership', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        plansAsync.when(
                          data: (plans) {
                            if (plans.isEmpty) {
                              return InputDecorator(
                                decoration: const InputDecoration(labelText: 'Membership Plan'),
                                child: Row(
                                  children: const [
                                    Icon(Icons.info_outline),
                                    SizedBox(width: 8),
                                    Expanded(child: Text('No plans found. Create a plan first.')),
                                  ],
                                ),
                              );
                            }
                            selectedPlanId ??= plans.first.id;
                            final selectedPlan =
                                plans.firstWhere((p) => p.id == selectedPlanId, orElse: () => plans.first);
                            selectedDurationDays = selectedPlan.durationDays;
                            return DropdownButtonFormField<int>(
                              key: ValueKey(selectedPlanId),
                              initialValue: selectedPlanId,
                              decoration: const InputDecoration(labelText: 'Membership Plan'),
                              items: [
                                for (final p in plans)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text('${p.name} (${p.durationDays} days)'),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                final plan = plans.firstWhere((p) => p.id == v, orElse: () => plans.first);
                                setModalState(() {
                                  selectedPlanId = v;
                                  selectedDurationDays = plan.durationDays;
                                });
                              },
                            );
                          },
                          error: (e, _) {
                            return InputDecorator(
                              decoration: const InputDecoration(labelText: 'Membership Plan'),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(e.toString())),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Retry',
                                    onPressed: () => r.invalidate(plansLookupProvider),
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                            );
                          },
                          loading: () => const InputDecorator(
                            decoration: InputDecoration(labelText: 'Membership Plan'),
                            child: Row(
                              children: [
                                SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('Loading plans...'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            field(
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: joinDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked == null) return;
                                  setModalState(() => joinDate = picked);
                                },
                                child: InputDecorator(
                                  decoration: const InputDecoration(labelText: 'Joining Date'),
                                  child: Text(_pretty.format(joinDate)),
                                ),
                              ),
                            ),
                            field(
                              InputDecorator(
                                decoration: const InputDecoration(labelText: 'Expiry Date (auto)'),
                                child: Text(_pretty.format(expiryDate)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
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
        FilledButton(onPressed: submit, child: const Text('Save')),
      ],
      maxWidth: 860,
    );

    memberCodeCtrl.dispose();
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
  }

  Future<void> _openEditMember(BuildContext context, Member member) async {
    final fullNameCtrl = TextEditingController(text: member.fullName);
    final phoneCtrl = TextEditingController(text: member.phone ?? '');
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var status = member.status;
    bool changeMembership = false;
    bool createInvoice = true;
    int? selectedPlanId;
    DateTime startDate = DateTime.now();
    int selectedDurationDays = 30;

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.edit_outlined,
      title: 'Edit Member',
      subtitle: '${member.fullName} (${member.memberCode})',
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final plansAsync = r.watch(plansLookupProvider);
              final expiryDate = startDate.add(Duration(days: selectedDurationDays));

              return Form(
                key: formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 680;
                    final fieldWidth = twoCol ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                    Widget field(Widget child) => SizedBox(width: fieldWidth, child: child);

                    Widget membershipSection() {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 14),
                          Text('Membership', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: changeMembership,
                            title: const Text('Change membership plan'),
                            subtitle: const Text('Creates a new subscription and keeps history'),
                            onChanged: (v) => setModalState(() => changeMembership = v),
                          ),
                          if (changeMembership)
                            plansAsync.when(
                              data: (plans) {
                                if (plans.isEmpty) {
                                  return InputDecorator(
                                    decoration: const InputDecoration(labelText: 'Membership Plan'),
                                    child: Row(
                                      children: const [
                                        Icon(Icons.info_outline),
                                        SizedBox(width: 8),
                                        Expanded(child: Text('No plans found. Create a plan first.')),
                                      ],
                                    ),
                                  );
                                }
                                selectedPlanId ??= plans.first.id;
                                final selectedPlan =
                                    plans.firstWhere((p) => p.id == selectedPlanId, orElse: () => plans.first);
                                selectedDurationDays = selectedPlan.durationDays;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: constraints.maxWidth,
                                      child: DropdownButtonFormField<int>(
                                        key: ValueKey(selectedPlanId),
                                        initialValue: selectedPlanId,
                                        decoration: const InputDecoration(labelText: 'Membership Plan'),
                                        items: [
                                          for (final p in plans)
                                            DropdownMenuItem(
                                              value: p.id,
                                              child: Text('${p.name} (${p.durationDays} days)'),
                                            ),
                                        ],
                                        onChanged: (v) => setModalState(() => selectedPlanId = v),
                                      ),
                                    ),
                                    field(
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: startDate,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                          );
                                          if (picked == null) return;
                                          setModalState(() => startDate = picked);
                                        },
                                        icon: const Icon(Icons.date_range),
                                        label: Text(_pretty.format(startDate)),
                                      ),
                                    ),
                                    field(
                                      InputDecorator(
                                        decoration: const InputDecoration(labelText: 'Expiry Date (auto)'),
                                        child: Text(_pretty.format(expiryDate)),
                                      ),
                                    ),
                                    SizedBox(
                                      width: constraints.maxWidth,
                                      child: CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        value: createInvoice,
                                        title: const Text('Create invoice'),
                                        onChanged: (v) => setModalState(() => createInvoice = v ?? true),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              error: (e, _) => Text(e.toString()),
                              loading: () => const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Member Details', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            field(
                              TextFormField(
                                controller: fullNameCtrl,
                                decoration: const InputDecoration(labelText: 'Full Name'),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Name required' : null,
                              ),
                            ),
                            field(
                              TextFormField(
                                controller: phoneCtrl,
                                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            field(
                              DropdownButtonFormField<String>(
                                key: ValueKey(status),
                                initialValue: status,
                                decoration: const InputDecoration(labelText: 'Status'),
                                items: const [
                                  DropdownMenuItem(value: 'active', child: Text('Active')),
                                  DropdownMenuItem(value: 'expired', child: Text('Expired')),
                                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                                ],
                                onChanged: (v) => setModalState(() => status = v ?? 'active'),
                              ),
                            ),
                            SizedBox(
                              width: constraints.maxWidth,
                              child: TextFormField(
                                controller: notesCtrl,
                                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        membershipSection(),
                      ],
                    );
                  },
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
        FilledButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            try {
              if (changeMembership) {
                if (selectedPlanId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a plan')));
                  return;
                }
                await ref.read(membersControllerProvider.notifier).changeMembership(
                      memberId: member.id,
                      planId: selectedPlanId!,
                      startDate: _date.format(startDate),
                      createInvoice: createInvoice,
                    );
              }
              await ref.read(membersControllerProvider.notifier).updateMember(
                    memberId: member.id,
                    fullName: fullNameCtrl.text,
                    phone: phoneCtrl.text,
                    status: status,
                    notes: notesCtrl.text,
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
      maxWidth: 860,
    );

    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, Member member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete member?'),
          content: Text('Delete ${member.fullName} (${member.memberCode})?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await ref.read(membersControllerProvider.notifier).deleteMember(memberId: member.id);
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
                  child: const Icon(Icons.people, size: 28),
                ),
                const SizedBox(height: 12),
                Text('No members yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Add your first member to start attendance & billing.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Member')),
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
    final isExpired = status == 'expired';
    final bg = isActive
        ? theme.colorScheme.primaryContainer
        : isExpired
            ? const Color(0xFFD4AF37).withValues(alpha: 0.18)
            : theme.colorScheme.surfaceContainerHighest;
    final fg = isActive
        ? theme.colorScheme.onPrimaryContainer
        : isExpired
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant;
    return Chip(
      label: Text(status),
      backgroundColor: bg,
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _HoverScaleButton extends StatefulWidget {
  const _HoverScaleButton({required this.child});

  final Widget child;

  @override
  State<_HoverScaleButton> createState() => _HoverScaleButtonState();
}

class _HoverScaleButtonState extends State<_HoverScaleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: _hover ? 1.03 : 1,
        child: widget.child,
      ),
    );
  }
}

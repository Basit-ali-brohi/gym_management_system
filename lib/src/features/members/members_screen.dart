import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../../core/form_dialog.dart';
import '../../core/providers.dart';
import '../../core/ui_kit.dart';
import '../../core/in_app_pdf.dart';
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
    final hadData = state.valueOrNull != null;
    if (!hadData) state = const AsyncValue.loading();
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
      if (!hadData) state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      if (!hadData) state = AsyncValue.error('members_load_failed', st);
    }
  }

  void applyMembershipSnapshot({
    required int memberId,
    String? membershipPlanName,
    String? membershipEndDate,
  }) {
    final items = state.valueOrNull;
    if (items == null) return;
    final plan = (membershipPlanName ?? '').trim();
    final end = (membershipEndDate ?? '').trim();
    if (plan.isEmpty && end.isEmpty) return;
    state = AsyncValue.data([
      for (final m in items)
        if (m.id == memberId)
          m.copyWith(
            status: m.status == 'inactive' ? m.status : 'active',
            membershipPlanName: plan.isEmpty ? null : plan,
            membershipEndDate: end.isEmpty ? null : end,
          )
        else
          m
    ]);
  }

  void clearMembershipSnapshot({required int memberId}) {
    final items = state.valueOrNull;
    if (items == null) return;
    state = AsyncValue.data([
      for (final m in items)
        if (m.id == memberId)
          Member(
            id: m.id,
            memberCode: m.memberCode,
            fullName: m.fullName,
            phone: m.phone,
            email: m.email,
            status: m.status,
            joinDate: m.joinDate,
            branchName: m.branchName,
            membershipEndDate: null,
            membershipPlanName: null,
            frozenUntil: m.frozenUntil,
          )
        else
          m
    ]);
  }

  void applyFreezeSnapshot({required int memberId, required String? frozenUntil}) {
    final items = state.valueOrNull;
    if (items == null) return;
    state = AsyncValue.data([
      for (final m in items)
        if (m.id == memberId)
          Member(
            id: m.id,
            memberCode: m.memberCode,
            fullName: m.fullName,
            phone: m.phone,
            email: m.email,
            status: m.status,
            joinDate: m.joinDate,
            branchName: m.branchName,
            membershipEndDate: m.membershipEndDate,
            membershipPlanName: m.membershipPlanName,
            frozenUntil: frozenUntil,
          )
        else
          m
    ]);
  }

  Future<void> createMember({
    String? memberCode,
    required String fullName,
    String? phone,
    String? email,
    String? cnic,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? dob,
    String? medicalConditions,
    required int planId,
    required String joinDate,
    int? leadId,
  }) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    await api.postJson('/members/register', token: token, body: {
      'memberCode': clean(memberCode),
      'fullName': fullName.trim(),
      'phone': clean(phone),
      'email': clean(email),
      'cnic': clean(cnic),
      'emergencyContactName': clean(emergencyContactName),
      'emergencyContactPhone': clean(emergencyContactPhone),
      'dob': clean(dob),
      'medicalConditions': clean(medicalConditions),
      'planId': planId,
      'joinDate': joinDate,
      'startDate': joinDate,
      'createInvoice': true,
    });
    if (leadId != null && leadId > 0) {
      await api.postJson('/leads/$leadId/convert', token: token);
    }
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
    final items = state.valueOrNull;
    if (items != null) {
      state = AsyncValue.data([
        for (final m in items)
          if (m.id == memberId)
            m.copyWith(
              fullName: fullName.trim(),
              phone: phone?.trim().isEmpty == true ? null : phone?.trim(),
              status: status,
            )
          else
            m
      ]);
    }
    await load(q: _lastQuery, status: _lastStatus, from: _lastFrom, to: _lastTo);
  }

  Future<void> deleteMember({required int memberId}) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    await api.deleteJson('/members/$memberId', token: token);
    final items = state.valueOrNull;
    if (items != null) {
      state = AsyncValue.data([for (final m in items) if (m.id != memberId) m]);
    }
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
  final _tableHScroll = ScrollController();
  Timer? _debounce;
  bool _hydratedFromRoute = false;
  bool _openedPrefill = false;
  bool _quickActionHandled = false;
  String _statusFilter = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _pendingLeadId;
  String _planFilter = 'all';
  bool _frozenOnly = false;
  bool _expiringOnly = false;
  String _sort = 'name_asc';

  final _date = DateFormat('yyyy-MM-dd');
  final _pretty = DateFormat('dd MMM yyyy');

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _tableHScroll.dispose();
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
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Members Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    }
  }

  List<Member> _applyMemberUiFilters(List<Member> items) {
    DateTime? parseDateOnly(String? raw) {
      final s = raw?.trim();
      if (s == null || s.isEmpty) return null;
      final m = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(s);
      final d = DateTime.tryParse(m?.group(0) ?? s);
      if (d == null) return null;
      return DateTime(d.year, d.month, d.day);
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    final from = _fromDate == null ? null : DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
    final to = _toDate == null ? null : DateTime(_toDate!.year, _toDate!.month, _toDate!.day);

    final filtered = items.where((m) {
      if (_statusFilter != 'all' && m.status != _statusFilter) return false;
      if (_frozenOnly && !_isFrozenUntil(m.frozenUntil)) return false;
      if (_expiringOnly) {
        final left = _daysLeft(m.membershipEndDate);
        if (left == null || left < 0 || left > 7) return false;
      }
      if (from != null || to != null) {
        final jd = parseDateOnly(m.joinDate);
        if (jd == null) return false;
        if (from != null && jd.isBefore(from)) return false;
        if (to != null && jd.isAfter(to)) return false;
      }
      if (_planFilter == 'all') return true;
      if (_planFilter == 'none') {
        final hasPlan = (m.membershipPlanName?.trim().isNotEmpty ?? false) || (m.membershipEndDate?.trim().isNotEmpty ?? false);
        if (hasPlan) return false;
      } else {
        if ((m.membershipPlanName?.trim() ?? '') != _planFilter) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${m.memberCode} ${m.fullName} ${(m.phone ?? '')} ${(m.membershipPlanName ?? '')}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    int nameCmp(Member a, Member b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());

    if (_sort == 'name_asc') {
      filtered.sort(nameCmp);
    } else if (_sort == 'name_desc') {
      filtered.sort((a, b) => nameCmp(b, a));
    } else if (_sort == 'newest') {
      filtered.sort((a, b) {
        final ad = parseDateOnly(a.joinDate);
        final bd = parseDateOnly(b.joinDate);
        if (ad == null && bd == null) return b.id.compareTo(a.id);
        if (ad == null) return 1;
        if (bd == null) return -1;
        final d = bd.compareTo(ad);
        return d != 0 ? d : b.id.compareTo(a.id);
      });
    }

    return filtered;
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
    final canManageMembership = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
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
    final leadIdRaw = qp['leadId']?.trim();
    final leadId = leadIdRaw == null ? null : int.tryParse(leadIdRaw);
    if (!_openedPrefill && prefill == 'lead' && (prefillName?.isNotEmpty ?? false)) {
      _openedPrefill = true;
      _pendingLeadId = leadId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openAddMember(context, prefillFullName: prefillName, prefillPhone: prefillPhone);
      });
    }
    // Global "+" Quick Action → open Add Member modal once on arrival.
    final pendingAction = ref.watch(pendingQuickActionProvider);
    if (pendingAction == null) {
      _quickActionHandled = false;
    } else if (pendingAction == QuickAction.addMember && !_quickActionHandled) {
      _quickActionHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(pendingQuickActionProvider.notifier).state = null;
        await _openAddMember(context);
      });
    }
    final fromStr = _fromDate == null ? '' : _date.format(_fromDate!);
    final toStr = _toDate == null ? '' : _date.format(_toDate!);
    final statusStr = _statusFilter == 'all' ? '' : _statusFilter;
    final plansAsync = ref.watch(plansLookupProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 700;
            final items = membersAsync.valueOrNull ?? const <Member>[];
            final filteredPreview = _applyMemberUiFilters(items);
            final total = items.length;
            final active = items.where((m) => m.status == 'active').length;
            final expired = items.where((m) => m.status == 'expired').length;
            final inactive = items.where((m) => m.status == 'inactive').length;

            // Flex metric tile — no fixed width. The parent grid wraps each in
            // an Expanded so 4 tiles span the container edge-to-edge.
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

            final search = TextField(
              controller: _searchCtrl,
              style: GoogleFonts.inter(fontSize: 13.5),
              decoration: appDenseInputDecoration(
                context,
                hint: 'Search code / name / phone',
                prefixIcon: Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
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

            final actionButtons = <Widget>[
              _HoverScaleButton(
                child: OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : () => _exportMembersCsv(context, items),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export'),
                ),
              ),
              IconButton(
                tooltip: 'PDF',
                onPressed: () => _openMembersPdfActions(context),
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
              _HoverScaleButton(
                child: FilledButton.icon(
                  onPressed: () => _openAddMember(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Member'),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => ref
                    .read(membersControllerProvider.notifier)
                    .load(q: _searchCtrl.text.trim(), status: statusStr, from: fromStr, to: toStr),
                icon: const Icon(Icons.refresh),
              ),
            ];

            final headerRow = stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Members', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      // Wrap so buttons flow to a second line instead of overflowing.
                      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actionButtons),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Text('Members', style: theme.textTheme.headlineSmall)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var k = 0; k < actionButtons.length; k++) ...[
                            if (k > 0) const SizedBox(width: 8),
                            actionButtons[k],
                          ],
                        ],
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerRow,
                const SizedBox(height: 12),
                // ── Single-row 4-up metric grid ────────────────────────────
                // 4 cols on desktop (span edge-to-edge via Expanded), 2 cols on
                // tablet, 1 col stacked on mobile. No card ever sits isolated.
                Builder(
                  builder: (context) {
                    final tiles = <Widget>[
                      metricCard(
                        title: 'Total Members',
                        value: '$total',
                        subtitle: 'In your gym',
                        icon: Icons.groups_outlined,
                        accent: theme.colorScheme.primary,
                      ),
                      metricCard(
                        title: 'Active',
                        value: '$active',
                        subtitle: 'Membership active',
                        icon: Icons.verified_outlined,
                        accent: theme.colorScheme.tertiary,
                      ),
                      metricCard(
                        title: 'Expired',
                        value: '$expired',
                        subtitle: 'Past end-date',
                        icon: Icons.schedule_outlined,
                        accent: const Color(0xFFF59E0B),
                      ),
                      metricCard(
                        title: 'Inactive',
                        value: '$inactive',
                        subtitle: 'Disabled / archived',
                        icon: Icons.block_outlined,
                        accent: theme.colorScheme.onSurfaceVariant,
                      ),
                    ];
                    final cols = stacked
                        ? 1
                        : constraints.maxWidth >= 900
                            ? 4
                            : 2;
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
                                      child: (i + j) < tiles.length
                                          ? tiles[i + j]
                                          : const SizedBox.shrink(),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Builder(
                      builder: (context) {
                        // Dense, fixed-height dropdown shared by all primary filters.
                        Widget denseDropdown({
                          required Key? dropKey,
                          required String value,
                          required List<DropdownMenuItem<String>> items,
                          required ValueChanged<String?> onChanged,
                          double width = 180,
                        }) {
                          return SizedBox(
                            width: stacked ? double.infinity : width,
                            height: 38,
                            child: DropdownButtonFormField<String>(
                              key: dropKey,
                              initialValue: value,
                              isDense: true,
                              isExpanded: true,
                              style: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurface),
                              decoration: appDenseInputDecoration(context),
                              items: items,
                              onChanged: onChanged,
                            ),
                          );
                        }

                        // Date filter rendered as a 38px pill-button to match height.
                        Widget dateButton({
                          required String fallback,
                          required DateTime? value,
                          required ValueChanged<DateTime> onPick,
                        }) {
                          final isSet = value != null;
                          final accent = theme.colorScheme.primary;
                          final isDark = theme.brightness == Brightness.dark;
                          return SizedBox(
                            height: 38,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: value ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked == null) return;
                                onPick(picked);
                              },
                              icon: Icon(Icons.calendar_today_outlined, size: 15, color: isSet ? accent : theme.colorScheme.onSurfaceVariant),
                              label: Text(
                                isSet ? _date.format(value) : fallback,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: isSet ? FontWeight.w600 : FontWeight.w500,
                                  color: isSet ? accent : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                side: BorderSide(
                                  color: isSet
                                      ? accent.withAlpha(95)
                                      : (isDark ? Colors.white.withAlpha(33) : Colors.black.withAlpha(33)),
                                  width: 1,
                                ),
                                backgroundColor: isSet ? accent.withAlpha(isDark ? 30 : 22) : Colors.transparent,
                              ),
                            ),
                          );
                        }

                        final planDropdown = plansAsync.when(
                          data: (plans) {
                            final names = <String>{
                              for (final p in plans) p.name.trim(),
                            }.where((e) => e.isNotEmpty).toList()
                              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            return denseDropdown(
                              dropKey: ValueKey(_planFilter),
                              value: _planFilter,
                              width: 190,
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('All Plans')),
                                const DropdownMenuItem(value: 'none', child: Text('No Plan')),
                                for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
                              ],
                              onChanged: (v) => setState(() => _planFilter = v ?? 'all'),
                            );
                          },
                          error: (e, st) => denseDropdown(
                            dropKey: ValueKey(_planFilter),
                            value: _planFilter,
                            width: 190,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Plans')),
                              DropdownMenuItem(value: 'none', child: Text('No Plan')),
                            ],
                            onChanged: (v) => setState(() => _planFilter = v ?? 'all'),
                          ),
                          loading: () => denseDropdown(
                            dropKey: const ValueKey('plan-loading'),
                            value: _planFilter,
                            width: 190,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Plans')),
                              DropdownMenuItem(value: 'none', child: Text('No Plan')),
                            ],
                            onChanged: (v) => setState(() => _planFilter = v ?? 'all'),
                          ),
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Primary row: Status / Sort / Plan + Search ───────
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                denseDropdown(
                                  dropKey: const ValueKey('status'),
                                  value: _statusFilter,
                                  width: 170,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                                    DropdownMenuItem(value: 'active', child: Text('Active')),
                                    DropdownMenuItem(value: 'expired', child: Text('Expired')),
                                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                                  ],
                                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                                ),
                                denseDropdown(
                                  dropKey: ValueKey(_sort),
                                  value: _sort,
                                  width: 160,
                                  items: const [
                                    DropdownMenuItem(value: 'name_asc', child: Text('Name A-Z')),
                                    DropdownMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                                    DropdownMenuItem(value: 'newest', child: Text('Newest')),
                                  ],
                                  onChanged: (v) => setState(() => _sort = v ?? 'name_asc'),
                                ),
                                planDropdown,
                                SizedBox(
                                  width: stacked ? double.infinity : 320,
                                  height: 38,
                                  child: search,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            // ── Secondary row: tags + date range + count + clear ─
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                AppFilterPill(
                                  label: 'Frozen',
                                  icon: Icons.ac_unit_rounded,
                                  selected: _frozenOnly,
                                  onTap: () => setState(() => _frozenOnly = !_frozenOnly),
                                ),
                                AppFilterPill(
                                  label: 'Expiring (<=7d)',
                                  icon: Icons.timelapse_rounded,
                                  selected: _expiringOnly,
                                  accentOverride: const Color(0xFFF59E0B),
                                  onTap: () => setState(() => _expiringOnly = !_expiringOnly),
                                ),
                                dateButton(
                                  fallback: 'From',
                                  value: _fromDate,
                                  onPick: (d) => setState(() => _fromDate = d),
                                ),
                                dateButton(
                                  fallback: 'To',
                                  value: _toDate,
                                  onPick: (d) => setState(() => _toDate = d),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Showing ${filteredPreview.length} of $total',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                AppFilterPill(
                                  label: 'Clear',
                                  icon: Icons.close_rounded,
                                  selected: false,
                                  onTap: () {
                                    _searchCtrl.clear();
                                    setState(() {
                                      _statusFilter = 'all';
                                      _fromDate = null;
                                      _toDate = null;
                                      _planFilter = 'all';
                                      _frozenOnly = false;
                                      _expiringOnly = false;
                                    });
                                    ref.read(membersControllerProvider.notifier).load(q: '');
                                  },
                                ),
                              ],
                            ),
                          ],
                        );
                      },
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
            final filtered = _applyMemberUiFilters(items);
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt_off_outlined, size: 44, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 10),
                      Text('No members match filters', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing filters',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _planFilter = 'all';
                            _frozenOnly = false;
                            _expiringOnly = false;
                          });
                        },
                        child: const Text('Clear Filters'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: ScrollConfiguration(
                      behavior: const MaterialScrollBehavior().copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.unknown,
                        },
                      ),
                      child: Scrollbar(
                      thumbVisibility: true,
                      interactive: true,
                      controller: _tableHScroll,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _tableHScroll,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                            columns: const [
                              DataColumn(label: Text('ID')),
                              DataColumn(label: Text('Code')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Phone')),
                              DataColumn(label: Text('Plan')),
                              DataColumn(label: Text('Joined')),
                              DataColumn(label: Text('Expiry')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: [
                              for (final m in filtered)
                                DataRow(
                                  cells: [
                                    DataCell(SizedBox(width: 46, child: Text(m.id.toString()))),
                                    DataCell(SizedBox(width: 92, child: Text(m.memberCode, overflow: TextOverflow.ellipsis))),
                                    DataCell(SizedBox(width: 220, child: Text(m.fullName, overflow: TextOverflow.ellipsis))),
                                    DataCell(SizedBox(width: 150, child: Text(m.phone ?? '-', overflow: TextOverflow.ellipsis))),
                                    DataCell(SizedBox(
                                      width: 160,
                                      child: Text(
                                        m.membershipPlanName?.trim().isNotEmpty == true ? m.membershipPlanName! : '-',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(width: 110, child: Text(_formatDate(m.joinDate)))),
                                    DataCell(
                                      SizedBox(
                                        width: 140,
                                        child: Builder(
                                          builder: (context) {
                                            final daysLeft = _daysLeft(m.membershipEndDate);
                                            final dateText = m.membershipEndDate?.trim().isNotEmpty == true
                                                ? _formatDate(m.membershipEndDate!)
                                                : '-';
                                            if (daysLeft == null) return Text(dateText, overflow: TextOverflow.ellipsis);
                                            final theme = Theme.of(context);
                                            final urgent = daysLeft <= 3;
                                            // Red only when urgent (emergency); emerald otherwise.
                                            final accent = urgent ? theme.colorScheme.error : theme.colorScheme.tertiary;
                                            return Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Expanded(child: Text(dateText, overflow: TextOverflow.ellipsis)),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: accent.withAlpha(28),
                                                    borderRadius: BorderRadius.circular(999),
                                                    border: Border.all(color: accent.withAlpha(60), width: 0.8),
                                                  ),
                                                  child: Text(
                                                    daysLeft <= 0 ? 'Today' : '${daysLeft}d',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: accent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    DataCell(_StatusChip(status: m.status, frozen: _isFrozenUntil(m.frozenUntil))),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Two high-frequency actions stay exposed.
                                          AppTableActionButton(
                                            icon: Icons.visibility_outlined,
                                            tooltip: 'View',
                                            onPressed: () => _openMemberDetail(context, m),
                                          ),
                                          const SizedBox(width: 2),
                                          AppTableActionButton(
                                            icon: Icons.edit_outlined,
                                            tooltip: 'Edit',
                                            onPressed: () => _openEditMember(context, m),
                                          ),
                                          const SizedBox(width: 2),
                                          // Everything else lives in a tidy overflow menu.
                                          _MemberActionsMenu(
                                            frozen: _isFrozenUntil(m.frozenUntil),
                                            hasPlan: (m.membershipPlanName?.trim().isNotEmpty ?? false) ||
                                                (m.membershipEndDate?.trim().isNotEmpty ?? false),
                                            canManageMembership: canManageMembership,
                                            canDelete: canDelete,
                                            onRenew: () => _openRenewMembership(context, m),
                                            onToggleFreeze: () => _toggleFreeze(context, m),
                                            onRemovePlan: () => _removeMembership(context, m),
                                            onQr: () => _openMemberQrDialog(context, memberCode: m.memberCode, fullName: m.fullName),
                                            onDelete: () => _confirmDelete(context, m),
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
                      ),
                      ),
                    ),
                  );
                }

                // ── Mobile: stacked card per member (no cramped trailing row) ──
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = filtered[i];
                    final theme = Theme.of(context);
                    final daysLeft = _daysLeft(m.membershipEndDate);
                    final meta = <String>[
                      m.memberCode,
                      'ID ${m.id}',
                      if (m.phone != null && m.phone!.trim().isNotEmpty) m.phone!.trim(),
                      if (m.branchName != null && m.branchName!.trim().isNotEmpty) m.branchName!.trim(),
                    ].join('  •  ');
                    final planLine = <String>[
                      if (m.membershipPlanName?.trim().isNotEmpty == true) m.membershipPlanName!.trim(),
                      if (m.membershipEndDate?.trim().isNotEmpty == true)
                        'Expiry ${_formatDate(m.membershipEndDate!)}'
                            '${daysLeft != null ? ' (${daysLeft <= 0 ? 'today' : '${daysLeft}d'})' : ''}',
                    ].join('  •  ');
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
                                  m.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(status: m.status, frozen: _isFrozenUntil(m.frozenUntil)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (planLine.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              planLine,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              AppTableActionButton(
                                icon: Icons.visibility_outlined,
                                tooltip: 'View',
                                onPressed: () => _openMemberDetail(context, m),
                              ),
                              const SizedBox(width: 2),
                              AppTableActionButton(
                                icon: Icons.edit_outlined,
                                tooltip: 'Edit',
                                onPressed: () => _openEditMember(context, m),
                              ),
                              const Spacer(),
                              _MemberActionsMenu(
                                frozen: _isFrozenUntil(m.frozenUntil),
                                hasPlan: (m.membershipPlanName?.trim().isNotEmpty ?? false) ||
                                    (m.membershipEndDate?.trim().isNotEmpty ?? false),
                                canManageMembership: canManageMembership,
                                canDelete: canDelete,
                                onRenew: () => _openRenewMembership(context, m),
                                onToggleFreeze: () => _toggleFreeze(context, m),
                                onRemovePlan: () => _removeMembership(context, m),
                                onQr: () => _openMemberQrDialog(context, memberCode: m.memberCode, fullName: m.fullName),
                                onDelete: () => _confirmDelete(context, m),
                              ),
                            ],
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
                final frozenUntil = m['frozenUntil']?.toString();

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
                            tooltip: 'QR',
                            onPressed: () => _openMemberQrDialog(
                              context,
                              memberCode: (m['memberCode']?.toString() ?? member.memberCode),
                              fullName: fullName,
                            ),
                            icon: const Icon(Icons.qr_code_2),
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
                              if (_isFrozenUntil(frozenUntil)) Text('Frozen until: ${_formatDate(frozenUntil ?? '')}'),
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

  Future<void> _openMemberQrDialog(BuildContext context, {required String memberCode, required String fullName}) async {
    final code = memberCode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member code missing')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Member QR'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(fullName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Code: $code', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Center(
                  child: QrImageView(
                    data: code,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
              },
              child: const Text('Copy Code'),
            ),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Future<void> _openRenewMembership(BuildContext context, Member member) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    final formKey = GlobalKey<FormState>();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentEnd = DateTime.tryParse((member.membershipEndDate ?? '').trim());
    final defaultStart = (currentEnd != null && !DateTime(currentEnd.year, currentEnd.month, currentEnd.day).isBefore(today))
        ? DateTime(currentEnd.year, currentEnd.month, currentEnd.day).add(const Duration(days: 1))
        : today;
    DateTime startDate = defaultStart;
    int? selectedPlanId;
    var payNow = true;
    var payMethod = 'cash';

    Future<void> submit(List<Plan> plans) async {
      if (!formKey.currentState!.validate()) return;
      selectedPlanId ??= plans.first.id;
      try {
        final selected = plans.firstWhere((p) => p.id == selectedPlanId, orElse: () => plans.first);
        final res = await api.postJson(
          '/members/${member.id}/change-membership',
          token: token,
          body: {
            'planId': selectedPlanId!,
            'startDate': DateFormat('yyyy-MM-dd').format(startDate),
            'createInvoice': true,
          },
        );
        final invoiceId = (res['invoiceId'] as num?)?.toInt();
        final invoiceNo = res['invoiceNo']?.toString();
        if (payNow && invoiceId != null && invoiceId > 0) {
          await api.postJson('/invoices/mark-paid', token: token, body: {'invoiceId': invoiceId, 'method': payMethod});
        }
        if (!context.mounted) return;
        final endDate = res['endDate']?.toString();
        ref.read(membersControllerProvider.notifier).applyMembershipSnapshot(
              memberId: member.id,
              membershipPlanName: selected.name,
              membershipEndDate: endDate,
            );
        ref.read(membersControllerProvider.notifier).load(q: _searchCtrl.text.trim());
        Future<void> openReceipt() async {
          if (invoiceId == null || invoiceId <= 0) return;
          final bytes = await api.getBytes('/pdf/invoice/$invoiceId.pdf', token: token);
          final name = 'invoice_${invoiceNo ?? invoiceId}.pdf';
          if (!context.mounted) return;
          await showInAppPdfPreview(context, bytes: bytes, title: 'Invoice ${invoiceNo ?? invoiceId}', fileName: name);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Renewed till ${endDate ?? '-'}'
              '${invoiceNo != null && invoiceNo.isNotEmpty ? ' • Invoice $invoiceNo' : ''}'
              '${payNow ? ' • Paid' : ''}',
            ),
            action: (payNow && invoiceId != null && invoiceId > 0)
                ? SnackBarAction(
                    label: 'Receipt',
                    onPressed: () {
                      unawaited(openReceipt());
                    },
                  )
                : null,
          ),
        );
        Navigator.of(context, rootNavigator: true).maybePop();
      } on ApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Renew failed')));
      }
    }

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.autorenew,
      title: 'Renew Membership',
      subtitle: member.fullName,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Consumer(
            builder: (context, r, _) {
              final plansAsync = r.watch(plansLookupProvider);
              return plansAsync.when(
                data: (plans) {
                  if (plans.isEmpty) return const Text('No plans available');
                  selectedPlanId ??= plans.firstWhere(
                        (p) => (member.membershipPlanName ?? '').trim().isNotEmpty && p.name == member.membershipPlanName,
                        orElse: () => plans.first,
                      ).id;
                  return Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<int>(
                          key: ValueKey(selectedPlanId),
                          initialValue: selectedPlanId,
                          decoration: const InputDecoration(labelText: 'Membership Plan'),
                          items: [
                            for (final p in plans)
                              DropdownMenuItem<int>(
                                value: p.id,
                                child: Text('${p.name} • ${p.durationDays} days • ${p.price.toString()}'),
                              ),
                          ],
                          onChanged: (v) => setModalState(() => selectedPlanId = v),
                          validator: (v) => v == null ? 'Select plan' : null,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(today.year - 1),
                              lastDate: DateTime(today.year + 3),
                            );
                            if (picked == null) return;
                            setModalState(() => startDate = picked);
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text('Start: ${DateFormat('yyyy-MM-dd').format(startDate)}'),
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: payNow,
                          onChanged: (v) => setModalState(() => payNow = v ?? true),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mark Paid Now'),
                          subtitle: const Text('Creates payment entry and clears dues'),
                        ),
                        if (payNow) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey(payMethod),
                            initialValue: payMethod,
                            decoration: const InputDecoration(labelText: 'Payment Method'),
                            items: const [
                              DropdownMenuItem(value: 'cash', child: Text('Cash')),
                              DropdownMenuItem(value: 'card', child: Text('Card')),
                              DropdownMenuItem(value: 'bank', child: Text('Bank')),
                              DropdownMenuItem(value: 'online', child: Text('Online')),
                            ],
                            onChanged: (v) => setModalState(() => payMethod = v ?? 'cash'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => submit(plans),
                          child: Text(payNow ? 'Renew & Pay' : 'Renew & Create Invoice'),
                        ),
                      ],
                    ),
                  );
                },
                error: (e, _) => Text(e.toString()),
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleFreeze(BuildContext context, Member member) async {
    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    final isFrozen = _isFrozenUntil(member.frozenUntil);

    if (isFrozen) {
      try {
        await api.postJson('/members/${member.id}/unfreeze', token: token);
        if (!context.mounted) return;
        ref.read(membersControllerProvider.notifier).applyFreezeSnapshot(memberId: member.id, frozenUntil: null);
        ref.read(membersControllerProvider.notifier).load(q: _searchCtrl.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member unfrozen')));
      } on ApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unfreeze failed')));
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime until = today.add(const Duration(days: 7));
    final reasonCtrl = TextEditingController();

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      try {
        await api.postJson(
          '/members/${member.id}/freeze',
          token: token,
          body: {
            'untilDate': DateFormat('yyyy-MM-dd').format(until),
            'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          },
        );
        if (!context.mounted) return;
        final untilStr = DateFormat('yyyy-MM-dd').format(until);
        ref.read(membersControllerProvider.notifier).applyFreezeSnapshot(memberId: member.id, frozenUntil: untilStr);
        ref.read(membersControllerProvider.notifier).load(q: _searchCtrl.text.trim());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Member frozen till $untilStr')),
        );
        Navigator.of(context, rootNavigator: true).maybePop();
      } on ApiException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Freeze failed')));
      }
    }

    await showAppFormDialog<void>(
      context: context,
      icon: Icons.ac_unit_outlined,
      title: 'Freeze Member',
      subtitle: member.fullName,
      body: StatefulBuilder(
        builder: (context, setModalState) {
          return Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: until,
                      firstDate: today,
                      lastDate: DateTime(today.year + 3),
                    );
                    if (picked == null) return;
                    setModalState(() => until = picked);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Freeze until: ${DateFormat('yyyy-MM-dd').format(until)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Reason (optional)'),
                  maxLength: 191,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Freeze'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeMembership(BuildContext context, Member member) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Remove membership?',
      message: "This will remove the member's current plan and block check-ins.",
      confirmLabel: 'Remove',
      cancelLabel: 'Cancel',
      danger: true,
    );
    if (!ok) return;

    final token = ref.read(authControllerProvider).token;
    final api = ref.read(apiClientProvider);
    try {
      await api.postJson('/members/${member.id}/remove-membership', token: token);
      if (!context.mounted) return;
      ref.read(membersControllerProvider.notifier).clearMembershipSnapshot(memberId: member.id);
      ref.read(membersControllerProvider.notifier).load(q: _searchCtrl.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Membership removed')));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remove failed')));
    }
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return _date.format(parsed);
  }

  bool _isFrozenUntil(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty) return false;
    final until = DateTime.tryParse(v);
    if (until == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(until.year, until.month, until.day);
    return !d.isBefore(today);
  }

  int? _daysLeft(String? rawEndDate) {
    final v = rawEndDate?.trim();
    if (v == null || v.isEmpty) return null;
    final end = DateTime.tryParse(v);
    if (end == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(end.year, end.month, end.day);
    return d.difference(today).inDays;
  }

  Future<void> _openAddMember(
    BuildContext context, {
    String? prefillFullName,
    String? prefillPhone,
  }) async {
    final memberCodeCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController(text: prefillFullName?.trim() ?? '');
    final phoneCtrl = TextEditingController(text: prefillPhone?.trim() ?? '');
    final emailCtrl = TextEditingController();
    final cnicCtrl = TextEditingController();
    final emergencyNameCtrl = TextEditingController();
    final emergencyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime joinDate = DateTime.now();
    DateTime? dob;
    int? selectedPlanId;
    int selectedDurationDays = 30;
    const medicalOptions = <String>[
      'None',
      'Asthma',
      'Hypertension',
      'Diabetes',
      'Heart Condition',
      'Back / Joint Injury',
      'Pregnancy',
    ];
    final medicalConditions = <String>{};

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
              email: emailCtrl.text,
              cnic: cnicCtrl.text,
              emergencyContactName: emergencyNameCtrl.text,
              emergencyContactPhone: emergencyCtrl.text,
              dob: dob == null ? null : _date.format(dob!),
              medicalConditions: medicalConditions.join(', '),
              planId: selectedPlanId!,
              joinDate: _date.format(joinDate),
              leadId: _pendingLeadId,
            );
        _pendingLeadId = null;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FormSectionLabel(
                      'Member Details',
                      hint: 'Identity & contact info for billing, contracts and birthday loyalty campaigns.',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 16),
                    // Row 1 — Member Code | Full Name
                    FormRow([
                      TextFormField(
                        controller: memberCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Member Code',
                          hintText: 'Leave blank to auto-generate',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          return v.trim().length < 2 ? 'Invalid code' : null;
                        },
                      ),
                      TextFormField(
                        controller: fullNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'As per CNIC / ID',
                        ),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'Name required' : null,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    // Row 2 — Phone | Email
                    FormRow([
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          hintText: 'Primary mobile number',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'For receipts & marketing',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return null;
                          return s.contains('@') ? null : 'Invalid email';
                        },
                      ),
                    ]),
                    const SizedBox(height: 16),
                    // Row 3 — CNIC | Date of Birth
                    FormRow([
                      TextFormField(
                        controller: cnicCtrl,
                        decoration: const InputDecoration(
                          labelText: 'CNIC / National ID',
                          hintText: 'For contract enforcement',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dob ?? DateTime(2000, 1, 1),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now(),
                          );
                          if (picked == null) return;
                          setModalState(() => dob = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date of Birth',
                            hintText: 'Triggers birthday discounts',
                          ),
                          child: Text(
                            dob == null ? 'Select date' : _pretty.format(dob!),
                            style: dob == null
                                ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
                                : null,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    const FormSectionLabel(
                      'Emergency & Safety',
                      hint: 'Captured for medical liability and rapid response during training.',
                      icon: Icons.health_and_safety_outlined,
                    ),
                    const SizedBox(height: 16),
                    // Emergency Contact Name | Emergency Phone
                    FormRow([
                      TextFormField(
                        controller: emergencyNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Emergency Contact Name',
                          hintText: 'Next of kin / guardian',
                        ),
                      ),
                      TextFormField(
                        controller: emergencyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Emergency Phone',
                          hintText: 'Reachable in an emergency',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    FormMultiChips(
                      label: 'Medical Conditions / Injuries',
                      hint: 'Flag anything that affects high-intensity training. Select "None" if not applicable.',
                      options: medicalOptions,
                      selected: medicalConditions,
                      accent: const Color(0xFFDC2626),
                      onToggle: (m) => setModalState(() {
                        if (m == 'None') {
                          medicalConditions
                            ..clear()
                            ..add('None');
                        } else {
                          medicalConditions.remove('None');
                          if (medicalConditions.contains(m)) {
                            medicalConditions.remove(m);
                          } else {
                            medicalConditions.add(m);
                          }
                        }
                      }),
                    ),
                    const SizedBox(height: 18),
                    const FormSectionLabel('Membership', icon: Icons.card_membership_outlined),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    // Row — Joining Date | Expiry Date (auto)
                    FormRow([
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
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Expiry Date (auto)'),
                        child: Text(_pretty.format(expiryDate)),
                      ),
                    ]),
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
        FilledButton(onPressed: submit, child: const Text('Save')),
      ],
      maxWidth: 860,
    );

    memberCodeCtrl.dispose();
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    cnicCtrl.dispose();
    emergencyNameCtrl.dispose();
    emergencyCtrl.dispose();
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
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Delete member?',
      message: 'Delete ${member.fullName} (${member.memberCode})?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
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

/// Flat status pill — Inter typography, colour-coded by membership state.
/// active → emerald, expired → amber, inactive → muted grey, frozen → blue.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.frozen = false});

  final String status;
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    late final Color accent;
    late final String label;
    if (frozen) {
      accent = const Color(0xFF3B82F6); // blue — paused, not failed
      label = 'frozen';
    } else if (status == 'active') {
      accent = theme.colorScheme.tertiary; // emerald
      label = 'active';
    } else if (status == 'expired') {
      accent = const Color(0xFFF59E0B); // amber
      label = 'expired';
    } else {
      accent = theme.colorScheme.onSurfaceVariant; // muted grey
      label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withAlpha(70), width: 0.8),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: accent,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Overflow menu for low-frequency member operations.
/// Keeps the table row clean: only View + Edit stay exposed; the rest
/// (Renew, Freeze, Remove Plan, QR, Delete) live behind a more_vert button.
class _MemberActionsMenu extends StatelessWidget {
  const _MemberActionsMenu({
    required this.frozen,
    required this.hasPlan,
    required this.canManageMembership,
    required this.canDelete,
    required this.onRenew,
    required this.onToggleFreeze,
    required this.onRemovePlan,
    required this.onQr,
    required this.onDelete,
  });

  final bool frozen;
  final bool hasPlan;
  final bool canManageMembership;
  final bool canDelete;
  final VoidCallback onRenew;
  final VoidCallback onToggleFreeze;
  final VoidCallback onRemovePlan;
  final VoidCallback onQr;
  final VoidCallback onDelete;

  static const Color _mutedRed = Color(0xFFE06C6C);

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger ? _mutedRed : theme.colorScheme.onSurface;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? _mutedRed : theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<String>(
      tooltip: 'More actions',
      position: PopupMenuPosition.under,
      elevation: 10,
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(22) : Colors.black.withAlpha(16),
          width: 0.8,
        ),
      ),
      icon: Icon(Icons.more_vert, size: 18, color: theme.colorScheme.onSurfaceVariant),
      onSelected: (v) {
        switch (v) {
          case 'renew':
            onRenew();
            break;
          case 'freeze':
            onToggleFreeze();
            break;
          case 'removePlan':
            onRemovePlan();
            break;
          case 'qr':
            onQr();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        if (canManageMembership) _item(context, 'renew', Icons.autorenew, 'Renew membership'),
        if (canManageMembership)
          _item(context, 'freeze', frozen ? Icons.play_circle_outline : Icons.ac_unit_outlined,
              frozen ? 'Unfreeze member' : 'Freeze member'),
        if (canManageMembership && hasPlan) _item(context, 'removePlan', Icons.link_off, 'Remove plan'),
        _item(context, 'qr', Icons.qr_code_2, 'Show QR code'),
        if (canDelete) const PopupMenuDivider(),
        if (canDelete) _item(context, 'delete', Icons.delete_outline, 'Delete member', danger: true),
      ],
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

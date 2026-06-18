import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart'; // AppTheme + AppTypography
import '../../core/providers.dart';
import '../../core/whatsapp.dart';
import '../../core/in_app_pdf.dart';
import '../auth/auth_controller.dart';

final dashboardSummaryProvider = FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/dashboard/summary', token: token);
  return DashboardSummary.fromJson(res);
});

class DashboardActivityItem {
  const DashboardActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.at,
    required this.amount,
    required this.invoiceNo,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String at;
  final num? amount;
  final String? invoiceNo;

  factory DashboardActivityItem.fromJson(Map<String, dynamic> json) {
    num? parseNum(dynamic v) {
      if (v == null) return null;
      if (v is num) return v;
      return num.tryParse(v.toString());
    }

    return DashboardActivityItem(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      at: json['at']?.toString() ?? '',
      amount: parseNum(json['amount']),
      invoiceNo: json['invoiceNo']?.toString(),
    );
  }
}

final dashboardActivityProvider = FutureProvider.autoDispose<List<DashboardActivityItem>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/dashboard/activity', token: token, query: const {'limit': '20'});
  return (res['items'] as List<dynamic>? ?? [])
      .whereType<Map>()
      .map((e) => DashboardActivityItem.fromJson(e.cast<String, dynamic>()))
      .where((i) => i.id.trim().isNotEmpty)
      .toList();
});

final dashboardActivityPanelCollapsedProvider = StateProvider.autoDispose<bool>((ref) => true);

class AtRiskMember {
  const AtRiskMember({
    required this.memberId,
    required this.fullName,
    required this.memberCode,
    required this.phone,
    required this.lastCheckinAt,
  });

  final int memberId;
  final String fullName;
  final String memberCode;
  final String? phone;
  final String? lastCheckinAt;

  factory AtRiskMember.fromJson(Map<String, dynamic> json) {
    return AtRiskMember(
      memberId: (json['memberId'] as num?)?.toInt() ?? 0,
      fullName: json['fullName']?.toString() ?? '',
      memberCode: json['memberCode']?.toString() ?? '',
      phone: json['phone']?.toString(),
      lastCheckinAt: json['lastCheckinAt']?.toString(),
    );
  }
}

class AtRiskMembersPayload {
  const AtRiskMembersPayload({
    required this.days,
    required this.template,
    required this.gymName,
    required this.items,
  });

  final int days;
  final String template;
  final String? gymName;
  final List<AtRiskMember> items;

  factory AtRiskMembersPayload.fromJson(Map<String, dynamic> json) {
    return AtRiskMembersPayload(
      days: (json['days'] as num?)?.toInt() ?? 3,
      template: json['template']?.toString() ??
          'Hello {name}, you have not visited the gym for {days} days. Please visit soon. {gym}',
      gymName: json['gymName']?.toString(),
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => AtRiskMember.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.memberId > 0)
          .toList(),
    );
  }
}

final atRiskMembersProvider = FutureProvider.autoDispose<AtRiskMembersPayload>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) throw ApiException('unauthorized');
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/dashboard/at-risk-members', token: token, query: const {'limit': '10'});
  return AtRiskMembersPayload.fromJson(res);
});

class DashboardSummary {
  const DashboardSummary({
    required this.membersTotal,
    required this.activeMembers,
    required this.membershipActiveMembers,
    required this.membershipExpiredMembers,
    required this.frozenMembers,
    required this.plansTotal,
    required this.todayCheckins,
    required this.unpaidInvoices,
    required this.unpaidAmount,
    required this.revenueLast30Days,
    required this.revenueTotal,
    required this.revenue7d,
    required this.expiringMembers,
  });

  final int membersTotal;
  final int activeMembers;
  final int membershipActiveMembers;
  final int membershipExpiredMembers;
  final int? frozenMembers;
  final int plansTotal;
  final int todayCheckins;
  final int unpaidInvoices;
  final num unpaidAmount;
  final num revenueLast30Days;
  final num revenueTotal;
  final List<RevenuePoint> revenue7d;
  final List<ExpiringMember> expiringMembers;

  bool get hasExpiring => expiringMembers.isNotEmpty;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      membersTotal: (json['membersTotal'] as num?)?.toInt() ?? 0,
      activeMembers: (json['activeMembers'] as num?)?.toInt() ?? 0,
      membershipActiveMembers: (json['membershipActiveMembers'] as num?)?.toInt() ?? 0,
      membershipExpiredMembers: (json['membershipExpiredMembers'] as num?)?.toInt() ?? 0,
      frozenMembers: json.containsKey('frozenMembers') ? (json['frozenMembers'] as num?)?.toInt() ?? 0 : null,
      plansTotal: (json['plansTotal'] as num?)?.toInt() ?? 0,
      todayCheckins: (json['todayCheckins'] as num?)?.toInt() ?? 0,
      unpaidInvoices: (json['unpaidInvoices'] as num?)?.toInt() ?? 0,
      unpaidAmount: json['unpaidAmount'] as num? ?? 0,
      revenueLast30Days: json['revenueLast30Days'] as num? ?? 0,
      revenueTotal: json['revenueTotal'] as num? ?? 0,
      revenue7d: (json['revenue7d'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => RevenuePoint.fromJson(e.cast<String, dynamic>()))
          .toList(),
      expiringMembers: (json['expiringMembers'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => ExpiringMember.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class RevenuePoint {
  const RevenuePoint({required this.date, required this.amount});

  final String date;
  final num amount;

  factory RevenuePoint.fromJson(Map<String, dynamic> json) {
    return RevenuePoint(
      date: json['date']?.toString() ?? '',
      amount: json['amount'] as num? ?? 0,
    );
  }
}

class ExpiringMember {
  const ExpiringMember({
    required this.memberId,
    required this.memberCode,
    required this.fullName,
    required this.endDate,
    required this.daysLeft,
    this.frozenUntil,
  });

  final int memberId;
  final String memberCode;
  final String fullName;
  final String endDate;
  final int daysLeft;
  final String? frozenUntil;

  factory ExpiringMember.fromJson(Map<String, dynamic> json) {
    return ExpiringMember(
      memberId: (json['memberId'] as num?)?.toInt() ?? 0,
      memberCode: json['memberCode']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      endDate: json['endDate']?.toString() ?? '',
      daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
      frozenUntil: json['frozenUntil']?.toString(),
    );
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final number = NumberFormat.decimalPattern();
    final auth = ref.watch(authControllerProvider);
    final tenantSlug = auth.user?.tenantSlug ?? '';

    return _DashboardScaffold(
      tenantSlug: tenantSlug,
      summaryAsync: summaryAsync,
      number: number,
      onRefresh: () => ref.invalidate(dashboardSummaryProvider),
    );
  }
}

class _DashboardScaffold extends ConsumerStatefulWidget {
  const _DashboardScaffold({
    required this.tenantSlug,
    required this.summaryAsync,
    required this.number,
    required this.onRefresh,
  });

  final String tenantSlug;
  final AsyncValue<DashboardSummary> summaryAsync;
  final NumberFormat number;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_DashboardScaffold> createState() => _DashboardScaffoldState();
}

class _DashboardScaffoldState extends ConsumerState<_DashboardScaffold> {
  bool _exportingPdf = false;

  @override
  Widget build(BuildContext context) {
    final showFloatingFeed = MediaQuery.sizeOf(context).width >= 1150;
    final rawRoles = ref.watch(authControllerProvider).user?.roles ?? const <String>[];
    final roles = rawRoles
        .map((r) => r.trim().toLowerCase().replaceAll(' ', '_'))
        .where((r) => r.isNotEmpty)
        .toSet();
    final canSeeRevenue = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final activityCollapsed = ref.watch(dashboardActivityPanelCollapsedProvider);

    Widget mainList({
      required EdgeInsets padding,
      required bool includeInlineActivity,
    }) {
      return ListView(
        padding: padding,
        children: [
          _HeroBanner(
            tenantSlug: widget.tenantSlug,
            onRefresh: widget.onRefresh,
            onExportPdf: () => _openDashboardPdfActions(context),
            canSeeRevenue: canSeeRevenue,
          ),
          const SizedBox(height: 16),
          widget.summaryAsync.when(
            data: (s) {
              final frozen = s.frozenMembers;
              return LayoutBuilder(
                builder: (context, box) {
                  // ── Strict 3-column layout ────────────────────────────────
                  // Column count is fixed at 3 across all drawer states so the
                  // KPI grid always shares vertical alignment edges with the
                  // 3-column Quick Actions grid below.
                  // Card WIDTH (not column count) changes when the drawer opens
                  // or closes — the TweenAnimationBuilder handles that smoothly.
                  // Desktop (content area ≥ 480) keeps the premium 3-up grid,
                  // unchanged. Narrow phones drop straight to a single
                  // full-width column so card text ("Total Revenue") fits on one
                  // line instead of wrapping mid-word in a cramped 2-col squeeze.
                  final int cols = box.maxWidth >= 480 ? 3 : 1;

                  const double gap = 12;

                  // Exact card width: fills the row wall-to-wall.
                  // Same formula used by _QuickActionsSection → guarantees
                  // the right edge of row N aligns with the banner's right edge.
                  final double targetW =
                      (box.maxWidth - (cols - 1) * gap) / cols;

                  // AnimatedSize smooths the height change when the row count
                  // changes (e.g. 2 rows of 4 → 2 rows of 3 when drawer opens).
                  // TweenAnimationBuilder interpolates each card's width at
                  // 60 fps so the expansion/contraction is a true size morph,
                  // not an instant snap or a cross-fade.
                  return AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: targetW),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      builder: (context, animW, _) {
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            if (canSeeRevenue)
                              _MetricCard(
                                width: animW,
                                title: 'Total Revenue',
                                value: widget.number.format(s.revenueTotal),
                                subtitle: 'All-time paid',
                                icon: Icons.payments,
                                onTap: () => context.go('/invoices'),
                              ),
                            if (canSeeRevenue)
                              _MetricCard(
                                width: animW,
                                title: 'Revenue (30d)',
                                value: widget.number.format(s.revenueLast30Days),
                                subtitle: 'Last 30 days',
                                icon: Icons.show_chart,
                                onTap: () => context.go('/invoices'),
                              ),
                            _MetricCard(
                              width: animW,
                              title: 'Active Members',
                              value: widget.number.format(s.membershipActiveMembers),
                              subtitle: 'Membership active',
                              icon: Icons.people,
                              onTap: () => context.go('/members'),
                            ),
                            _MetricCard(
                              width: animW,
                              title: 'Frozen Members',
                              value: frozen == null ? '—' : widget.number.format(frozen),
                              subtitle: frozen == null ? 'Restart backend to enable' : 'Access blocked',
                              icon: Icons.ac_unit_outlined,
                              onTap: () => context.go('/members'),
                            ),
                            if (canSeeRevenue)
                              _MetricCard(
                                width: animW,
                                title: 'Unpaid Dues',
                                value: widget.number.format(s.unpaidAmount),
                                subtitle: '${widget.number.format(s.unpaidInvoices)} invoices',
                                icon: Icons.receipt_long,
                                onTap: () => context.go('/invoices'),
                              ),
                            _MetricCard(
                              width: animW,
                              title: "Today's Check-ins",
                              value: widget.number.format(s.todayCheckins),
                              subtitle: 'Attendance today',
                              icon: Icons.how_to_reg,
                              onTap: () => context.go('/attendance'),
                            ),
                            _MetricCard(
                              width: animW,
                              title: 'Plans',
                              value: widget.number.format(s.plansTotal),
                              subtitle: 'Membership plans',
                              icon: Icons.card_membership,
                              onTap: () => context.go('/plans'),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              );
            },
            error: (e, stackTrace) {
              String message = e.toString();
              if (e is ApiException) {
                if (e.statusCode == 404) {
                  message = 'Backend update not applied. Stop the server and start it again.';
                } else if (e.statusCode == 401) {
                  message = 'Session expired. Please log in again.';
                } else {
                  message = e.message;
                }
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber),
                      const SizedBox(width: 10),
                      Expanded(child: Text(message)),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () => ref.invalidate(dashboardSummaryProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 18),
          _QuickActionsSection(canSeeRevenue: canSeeRevenue),
          const SizedBox(height: 18),
          const _AtRiskMembersCard(),
          if (includeInlineActivity) ...[
            const SizedBox(height: 18),
            const _RecentActivityFeedCard(),
          ],
          const SizedBox(height: 18),
          widget.summaryAsync.when(
            data: (s) {
              final active = s.membershipActiveMembers;
              final expired = s.membershipExpiredMembers;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1100;
                  if (!canSeeRevenue) {
                    return _ActiveInactiveCard(active: active, expired: expired);
                  }
                  if (wide) {
                    final half = (constraints.maxWidth - 12) / 2;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: half, child: _Revenue7dCard(points: s.revenue7d)),
                        const SizedBox(width: 12),
                        SizedBox(width: half, child: _ActiveInactiveCard(active: active, expired: expired)),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _Revenue7dCard(points: s.revenue7d),
                      const SizedBox(height: 12),
                      _ActiveInactiveCard(active: active, expired: expired),
                    ],
                  );
                },
              );
            },
            error: (e, stackTrace) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 18),
          widget.summaryAsync.when(
            data: (s) => _InsightsCard(summary: s, canSeeRevenue: canSeeRevenue, number: widget.number),
            error: (e, _) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
          widget.summaryAsync.when(
            data: (s) => _ExpiringMembersCard(
              members: s.expiringMembers,
              onOpenMembers: () => context.go('/members'),
            ),
            error: (e, _) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ],
      );
    }

    if (!showFloatingFeed) {
      return mainList(padding: const EdgeInsets.all(20), includeInlineActivity: true);
    }

    final theme = Theme.of(context);
    final gold = theme.colorScheme.primary;
    final expandedW = 390.0;
    final tabW = 44.0;

    return Row(
      children: [
        Expanded(
          child: mainList(padding: const EdgeInsets.all(20), includeInlineActivity: false),
        ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          padding: EdgeInsets.fromLTRB(0, 20, activityCollapsed ? 0 : 20, 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            width: activityCollapsed ? tabW : expandedW,
            child: ClipRRect(
              clipBehavior: Clip.hardEdge,
              borderRadius: BorderRadius.circular(18),
              child: ClipRect(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: OverflowBox(
                        alignment: Alignment.centerRight,
                        minWidth: expandedW,
                        maxWidth: expandedW,
                        child: SizedBox(
                          width: expandedW,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeInOut,
                            opacity: activityCollapsed ? 0 : 1,
                            child: IgnorePointer(
                              ignoring: activityCollapsed,
                              child: _RecentActivityFeedDocked(
                                active: !activityCollapsed,
                                headerTrailing: IconButton(
                                  tooltip: 'Hide',
                                  onPressed: () => ref.read(dashboardActivityPanelCollapsedProvider.notifier).state = true,
                                  icon: const Icon(Icons.keyboard_double_arrow_right),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeInOut,
                      opacity: activityCollapsed ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !activityCollapsed,
                        child: _ActivityVerticalTab(
                          onTap: () => ref.read(dashboardActivityPanelCollapsedProvider.notifier).state = false,
                          glow: gold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDashboardPdfActions(BuildContext context) async {
    if (_exportingPdf) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dashboard PDF'),
          content: const Text('Preview ya download?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runDashboardPdf(context, preview: true, today: today);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _runDashboardPdf(context, preview: false, today: today);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runDashboardPdf(BuildContext context, {required bool preview, required String today}) async {
    setState(() => _exportingPdf = true);
    try {
      final token = ref.read(authControllerProvider).token;
      if (token == null || token.isEmpty) throw ApiException('unauthorized');
      final api = ref.read(apiClientProvider);
      final bytes = await api.getBytes('/pdf/dashboard.pdf', token: token);
      final name = 'dashboard_$today.pdf';
      if (!context.mounted) return;
      await presentPdf(context, preview: preview, bytes: bytes, fileName: name, title: 'Dashboard Report Preview');
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF failed')));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }
}

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.canSeeRevenue});

  final bool canSeeRevenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            // ── Strict 3-column layout ────────────────────────────────────
            // Matches the KPI card grid above: identical breakpoints so both
            // grids always have the same column count and shared vertical edges.
            // Width (not column count) adapts when the drawer opens / closes.
            // Desktop keeps the 3-up grid; phones (< 480) use one full-width
            // column so action labels don't wrap mid-word.
            final int cols = box.maxWidth >= 480 ? 3 : 1;

            const double gap = 12;

            // Exact card width: fills the row wall-to-wall, matching banner bounds.
            final double targetW =
                (box.maxWidth - (cols - 1) * gap) / cols;

            // ── Animation ─────────────────────────────────────────────────
            // AnimatedSize handles smooth height change when row count changes.
            // TweenAnimationBuilder interpolates each card's width at 60 fps,
            // giving the wall-to-wall expansion effect without snapping.
            return AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: targetW),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                builder: (context, animW, _) {
                  // Local helper keeps card list readable.
                  Widget card(
                    String title,
                    String subtitle,
                    IconData icon,
                    VoidCallback onTap,
                  ) =>
                      SizedBox(
                        width: animW,
                        child: _ActionCard(
                          title: title,
                          subtitle: subtitle,
                          icon: icon,
                          onTap: onTap,
                        ),
                      );

                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      card('Add Member', 'New registration', Icons.person_add_alt_1, () => context.go('/members')),
                      card('Add Plan', 'Pricing & duration', Icons.add_card, () => context.go('/plans')),
                      card('Check-in', 'Search member & check-in', Icons.qr_code_scanner, () => context.go('/attendance')),
                      card('Add Lead', 'New enquiry', Icons.person_search, () => context.go('/leads')),
                      if (canSeeRevenue) card('Invoices', 'Generate & track', Icons.receipt_long, () => context.go('/invoices')),
                      if (canSeeRevenue) card('Record Expense', 'Track costs', Icons.account_balance_wallet, () => context.go('/expenses')),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RecentActivityFeedFloating extends ConsumerStatefulWidget {
  const _RecentActivityFeedFloating();

  @override
  ConsumerState<_RecentActivityFeedFloating> createState() => _RecentActivityFeedFloatingState();
}

class _RecentActivityFeedFloatingState extends ConsumerState<_RecentActivityFeedFloating> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      ref.invalidate(dashboardActivityProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const _RecentActivityFeedCardBase(floating: true);
  }
}

class _RecentActivityFeedDocked extends ConsumerStatefulWidget {
  const _RecentActivityFeedDocked({required this.headerTrailing, required this.active});

  final Widget headerTrailing;
  final bool active;

  @override
  ConsumerState<_RecentActivityFeedDocked> createState() => _RecentActivityFeedDockedState();
}

class _RecentActivityFeedDockedState extends ConsumerState<_RecentActivityFeedDocked> {
  Timer? _timer;

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      ref.invalidate(dashboardActivityProvider);
    });
  }

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _RecentActivityFeedDocked oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RecentActivityFeedCardBase(
      floating: true,
      headerTrailing: widget.headerTrailing,
    );
  }
}

class _RecentActivityFeedCard extends StatelessWidget {
  const _RecentActivityFeedCard();

  @override
  Widget build(BuildContext context) {
    return const _RecentActivityFeedCardBase(floating: false);
  }
}

class _AtRiskMembersCard extends ConsumerWidget {
  const _AtRiskMembersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(atRiskMembersProvider);
    String formatError(Object e) {
      if (e is ApiException) {
        if (e.statusCode == 404) {
          return 'Backend update not applied. Stop the server and start it again.';
        }
        if (e.statusCode == 401) return 'Session expired. Please log in again.';
        return e.message;
      }
      return e.toString();
    }

    Future<void> openWhatsApp({required String? phone, required String message}) async {
      final digits = normalizeWhatsAppPhone(phone);
      if (digits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone missing')));
        return;
      }
      final ok = await openWhatsAppMessage(phone: digits, message: message);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    }

    String fmtDate(String? raw) {
      if (raw == null) return 'Never';
      final d = DateTime.tryParse(raw);
      if (d == null) return raw;
      return DateFormat('yyyy-MM-dd').format(d);
    }

    Widget header({required int days, required int count}) {
      // Follow the live brand accent chosen in Settings (was a fixed amber).
      final accent = theme.colorScheme.primary;
      return Row(
        children: [
          Container(
            height: 40, width: 40,
            decoration: AppTheme.iconBox(color: accent),
            child: Center(child: Icon(Icons.warning_amber_rounded, color: accent, size: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AT-RISK MEMBERS', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface)),
                Text(
                  'No check-in for $days+ days • $count',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(atRiskMembersProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: async.when(
          data: (payload) {
            if (payload.items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header(days: payload.days, count: 0),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'No at-risk members right now.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              );
            }

            String buildMessage(AtRiskMember m) {
              final gym = (payload.gymName ?? 'Gym').trim().isEmpty ? 'Gym' : (payload.gymName ?? 'Gym').trim();
              return payload.template
                  .replaceAll('{name}', m.fullName)
                  .replaceAll('{days}', payload.days.toString())
                  .replaceAll('{gym}', gym)
                  .replaceAll('{code}', m.memberCode);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(days: payload.days, count: payload.items.length),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: Scrollbar(
                    child: ListView.separated(
                      itemCount: payload.items.length,
                      separatorBuilder: (context, _) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
                      itemBuilder: (context, i) {
                        final m = payload.items[i];
                        final msg = buildMessage(m);
                        final phoneOk = normalizeWhatsAppPhone(m.phone).isNotEmpty;
                        final accent = theme.colorScheme.primary;
                        final initials = m.fullName.trim().isEmpty ? '?' : m.fullName.trim().substring(0, 1).toUpperCase();
                        return Container(
                          decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: accent.withAlpha(28),
                              child: Text(initials, style: theme.textTheme.labelMedium?.copyWith(color: accent, fontWeight: FontWeight.w700)),
                            ),
                            title: Text('${m.fullName} (${m.memberCode})', maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Last visit: ${fmtDate(m.lastCheckinAt)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: phoneOk ? 'Send WhatsApp' : 'Phone missing',
                              onPressed: phoneOk ? () => openWhatsApp(phone: m.phone, message: msg) : null,
                              icon: Icon(Icons.chat_bubble_outline, color: phoneOk ? AppTheme.emerald : theme.colorScheme.onSurfaceVariant),
                            ),
                            onTap: () => context.go('/members?q=${Uri.encodeComponent(m.memberCode)}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(days: 3, count: 0),
              const SizedBox(height: 10),
              Text(formatError(e), style: theme.textTheme.bodySmall),
            ],
          ),
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(days: 3, count: 0),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              const SizedBox(height: 320),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityFeedCardBase extends ConsumerWidget {
  const _RecentActivityFeedCardBase({required this.floating, this.headerTrailing});

  final bool floating;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(dashboardActivityProvider);
    final primary = theme.colorScheme.primary;
    String formatError(Object e) {
      if (e is ApiException) {
        if (e.statusCode == 404) {
          return 'Backend update not applied. Stop the server and start it again.';
        }
        if (e.statusCode == 401) return 'Session expired. Please log in again.';
        return e.message;
      }
      return e.toString();
    }

    String fmtTime(String raw) {
      final d = DateTime.tryParse(raw);
      if (d == null) return '';
      return DateFormat('HH:mm').format(d);
    }

    Widget header({required bool dense}) {
      return Row(
        children: [
          Container(
            height: dense ? 34 : 40,
            width: dense ? 34 : 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: primary.withValues(alpha: 0.12),
              border: Border.all(color: primary.withValues(alpha: 0.28)),
            ),
            child: Icon(Icons.bolt, color: primary, size: dense ? 18 : 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RECENT ACTIVITY', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface)),
                Text(
                  'Auto refresh • check-ins & payments',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(dashboardActivityProvider),
            icon: const Icon(Icons.refresh),
          ),
          ...(headerTrailing == null ? const <Widget>[] : <Widget>[headerTrailing!]),
        ],
      );
    }

    Widget body(List<DashboardActivityItem> items) {
      if (items.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_toggle_off, size: 42, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 10),
                Text('No activity yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'New check-ins and payments will show here.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }

      // Dynamic height: the card wraps exactly around the rows (no trailing
      // empty surface), but still caps + scrolls when the feed grows long.
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: floating ? 340 : 320),
        child: Scrollbar(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (context, _) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
            itemBuilder: (context, i) {
              final a = items[i];
              final isPayment = a.type == 'payment';
              final isAlert = a.type == 'alert';
              final icon = isPayment
                  ? Icons.payments_outlined
                  : isAlert
                      ? Icons.warning_amber_outlined
                      : Icons.how_to_reg;
              final chipColor = isPayment
                  ? theme.colorScheme.tertiary
                  : isAlert
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary;
              final route = isPayment
                  ? '/payments'
                  : isAlert
                      ? '/inventory'
                      : '/attendance';
              return Container(
                decoration: BoxDecoration(border: Border(left: BorderSide(color: chipColor, width: 3))),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: chipColor.withAlpha(32),
                    foregroundColor: chipColor,
                    child: Icon(icon, size: 17),
                  ),
                  title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(a.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(fmtTime(a.at), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  onTap: () => context.go(route),
                ),
              );
            },
          ),
        ),
      );
    }

    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: async.when(
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(dense: floating),
              const SizedBox(height: 10),
              body(items),
            ],
          ),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(dense: floating),
              const SizedBox(height: 10),
              Text(formatError(e), style: theme.textTheme.bodySmall),
            ],
          ),
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(dense: floating),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
              SizedBox(height: floating ? 340 : 320),
            ],
          ),
        ),
      ),
    );

    if (!floating) return card;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: primary.withValues(alpha: 0.28)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
                theme.colorScheme.surface.withValues(alpha: 0.86),
              ],
            ),
          ),
          child: card,
        ),
      ),
    );
  }
}

class _ActivityVerticalTab extends StatelessWidget {
  const _ActivityVerticalTab({required this.onTap, required this.glow});

  final VoidCallback onTap;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 44,
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
              border: Border.all(color: glow.withValues(alpha: 0.40)),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_active_outlined, size: 18, color: glow),
                    const SizedBox(width: 8),
                    Text(
                      'Activity',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: glow,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.keyboard_double_arrow_left, size: 18, color: glow),
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

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.tenantSlug,
    required this.onRefresh,
    required this.onExportPdf,
    required this.canSeeRevenue,
  });

  final String tenantSlug;
  final VoidCallback onRefresh;
  final VoidCallback onExportPdf;
  final bool canSeeRevenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gymName = tenantSlug
        .trim()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ')
        .trim();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final today = DateFormat('EEE, MMM d').format(DateTime.now());
    final gold = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    // Theme-aware banner tokens. Light mode abandons the dark charcoal gradient
    // for a clean white→cream surface so it no longer clashes with the canvas.
    final headingColor = isDark ? theme.colorScheme.onSurface : const Color(0xFF1E1E1E);
    final greetingColor = isDark ? gold.withAlpha(200) : const Color(0xFF475569);

    final BoxDecoration bannerDecoration = isDark
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: AppTheme.borderSubtle, width: 0.8),
            gradient: AppTheme.heroBannerGradient(primary: gold),
            boxShadow: [
              // Ambient accent glow lives OUTSIDE the card, not on the border.
              BoxShadow(color: gold.withAlpha(16), blurRadius: 56, spreadRadius: 0, offset: const Offset(0, 28)),
              BoxShadow(color: Colors.black.withAlpha(110), blurRadius: 30, offset: const Offset(0, 14)),
            ],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.large),
            // Razor-thin structural border + soft elevation per spec.
            border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 1),
            // Ultra-soft slate-white → muted premium cream.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFAFBFC), Color(0xFFFAF7F0)],
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: Container(
        decoration: bannerDecoration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Stack(
            children: [
              // Single decorative accent bloom — top-left corner only.
              // Very faint in light mode (premium cream tint, no contrast shock).
              Positioned(
                left: -60,
                top: -60,
                child: Container(
                  height: 260,
                  width: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [gold.withAlpha(isDark ? 32 : 12), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Builder(
                  builder: (context) {
                    final narrow = MediaQuery.sizeOf(context).width < 600;

                    final heroActionsRow = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: onRefresh,
                          icon: Icon(Icons.refresh, color: isDark ? gold.withAlpha(200) : theme.colorScheme.onSurfaceVariant),
                        ),
                        IconButton(
                          tooltip: 'PDF',
                          onPressed: onExportPdf,
                          icon: Icon(Icons.picture_as_pdf_outlined, color: isDark ? gold.withAlpha(200) : theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    );

                    final dumbbell = isDark
                        ? Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: AppTheme.charcoal.withAlpha(180),
                              border: Border.all(color: gold.withAlpha(80)),
                              boxShadow: AppTheme.neonGlow(gold, blur: 22),
                            ),
                            child: Icon(Icons.fitness_center_rounded, size: 44, color: gold),
                          )
                        : Container(
                            height: 72,
                            width: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.shade100,
                              border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 1),
                            ),
                            child: Icon(Icons.fitness_center_rounded, size: 34, color: Colors.grey.shade400),
                          );

                    final content = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting  $today',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: greetingColor,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gymName.isEmpty ? 'GYM DASHBOARD' : gymName.toUpperCase(),
                          style: theme.textTheme.headlineSmall?.copyWith(color: headingColor),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tenantSlug.trim().isEmpty
                              ? 'Performance overview'
                              : 'Gym: $tenantSlug  •  Performance overview',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const _TagChip(label: 'Members'),
                            const _TagChip(label: 'Attendance'),
                            if (canSeeRevenue) const _TagChip(label: 'Billing'),
                            const _TagChip(label: 'CRM'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, c) {
                            final heroActions = <Widget>[
                              FilledButton.icon(
                                onPressed: () => context.go('/members'),
                                icon: const Icon(Icons.person_add_alt_1_outlined),
                                label: const Text('Add member', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              _HeroBorderButton(label: 'Check-in', icon: Icons.qr_code_scanner, accent: gold, onTap: () => context.go('/attendance')),
                              if (canSeeRevenue)
                                _HeroBorderButton(label: 'Invoices', icon: Icons.receipt_long_outlined, accent: gold, onTap: () => context.go('/invoices')),
                              _HeroBorderButton(label: 'Leads', icon: Icons.person_search_outlined, accent: theme.colorScheme.tertiary, onTap: () => context.go('/leads')),
                            ];
                            // Mobile: clean 2-up grid (each button half-width).
                            if (c.maxWidth < 600) {
                              final half = (c.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final a in heroActions) SizedBox(width: half, child: a),
                                ],
                              );
                            }
                            return Wrap(spacing: 8, runSpacing: 8, children: heroActions);
                          },
                        ),
                      ],
                    );

                    // Mobile: actions pinned top-right, content full-width, no
                    // decorative dumbbell (so the 2×2 button grid has real room).
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(alignment: Alignment.centerRight, child: heroActionsRow),
                          content,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: content),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            heroActionsRow,
                            const SizedBox(height: 10),
                            dumbbell,
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        // Light: soft grey-100 pill; Dark: elevated charcoal.
        color: isDark ? AppTheme.charcoalHigh : Colors.grey.shade100,
        border: Border.all(
          color: isDark ? AppTheme.borderHover : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: isDark ? theme.colorScheme.onSurface.withAlpha(200) : const Color(0xFF374151),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HeroBorderButton extends StatefulWidget {
  const _HeroBorderButton({required this.label, required this.icon, required this.accent, required this.onTap});
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  @override
  State<_HeroBorderButton> createState() => _HeroBorderButtonState();
}

class _HeroBorderButtonState extends State<_HeroBorderButton> {
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
          borderRadius: BorderRadius.circular(12),
          color: _hover ? widget.accent.withAlpha(22) : Colors.transparent,
          border: Border.all(color: widget.accent.withAlpha(_hover ? 180 : 100), width: _hover ? 1.2 : 1.0),
          boxShadow: _hover ? AppTheme.neonGlow(widget.accent, blur: 14) : const [],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: widget.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: widget.accent, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatefulWidget {
  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final double width;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hover = _hover;
    final radius = AppRadius.largeAll;
    final accent = theme.colorScheme.primary;
    final accentLight = Color.lerp(accent, Colors.white, 0.40) ?? accent;
    final isDark = theme.brightness == Brightness.dark;
    final blurSigma = hover ? 30.0 : 24.0;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          scale: hover ? 1.018 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, hover ? -6 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: hover
                  ? [
                      BoxShadow(color: accent.withAlpha(62), blurRadius: 40, offset: const Offset(0, 20)),
                      BoxShadow(color: Colors.black.withAlpha(isDark ? 110 : 36), blurRadius: 28, offset: const Offset(0, 14)),
                    ]
                  : [BoxShadow(color: Colors.black.withAlpha(isDark ? 75 : 22), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: radius,
                    child: CustomPaint(
                      // At rest: barely-visible white shimmer — just shape, no colour.
                      // On hover: thin accent stroke signals interactivity.
                      foregroundPainter: _GradientStrokePainter(
                        radius: radius,
                        width: hover ? 1.1 : 0.8,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: hover
                              ? [accent.withAlpha(100), accentLight.withAlpha(60), accent.withAlpha(100)]
                              : [Colors.white.withAlpha(18), Colors.white.withAlpha(8), Colors.white.withAlpha(18)],
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          // Flat charcoal — no competing colour gradient in the background.
                          color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                height: 46,
                                width: 46,
                                decoration: AppTheme.iconBox(color: accent, hover: hover),
                                child: Center(child: Icon(widget.icon, color: accent, size: 22)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                    const SizedBox(height: 5),
                                    // headlineSmall is Bebas Neue via theme — preserve only colour.
                                    Text(
                                      widget.value,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        color: isDark ? accent : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(widget.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: accent.withAlpha(hover ? 200 : 100), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientStrokePainter extends CustomPainter {
  const _GradientStrokePainter({
    required this.radius,
    required this.width,
    required this.gradient,
  });

  final BorderRadius radius;
  final double width;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _GradientStrokePainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.width != width || oldDelegate.gradient != gradient;
  }
}

class _Revenue7dCard extends StatelessWidget {
  const _Revenue7dCard({required this.points});

  final List<RevenuePoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = NumberFormat.compact();

    String dateKey(DateTime d) {
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '$y-$m-$dd';
    }

    final rawMap = <String, double>{};
    for (final p in points) {
      final parsed = DateTime.tryParse(p.date);
      final key = parsed == null ? p.date : dateKey(parsed);
      rawMap[key] = (rawMap[key] ?? 0) + p.amount.toDouble();
    }

    final today = DateTime.now();
    final days = List<DateTime>.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });
    final normalized = [
      for (final d in days) RevenuePoint(date: dateKey(d), amount: rawMap[dateKey(d)] ?? 0),
    ];

    final total7d = normalized.fold<double>(0, (s, p) => s + p.amount.toDouble());
    final maxValue = normalized.isEmpty
        ? 0.0
        : normalized.map((p) => p.amount.toDouble()).reduce((a, b) => a > b ? a : b);

    String labelFor(String raw) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return raw;
      return DateFormat('E').format(parsed);
    }

    final isDark = theme.brightness == Brightness.dark;
    final gold = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
        border: Border.all(color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant, width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 70 : 16), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 38, width: 38,
                  decoration: AppTheme.iconBox(color: gold),
                  child: Center(child: Icon(Icons.show_chart_rounded, color: gold, size: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('REVENUE (7 DAYS)', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface)),
                      Text('Daily earnings trend', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // titleLarge = Bebas Neue — keep only colour; tracking comes from theme.
                    Text(number.format(total7d), style: theme.textTheme.titleLarge?.copyWith(color: gold)),
                    Text('7-day total', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _RevenueChartPainter(
                  points: normalized,
                  lineColor: gold,
                  gridColor: isDark ? AppTheme.borderHover : theme.colorScheme.outlineVariant,
                  dotColor: gold,
                ),
                size: Size.infinite,
              ),
            ),
            const SizedBox(height: 8),
            // Equal-width centered cells so every day label (Thu, Fri, …) stays
            // fully visible and aligned under its data point on any width.
            Row(
              children: [
                for (final p in normalized.take(7))
                  Expanded(
                    child: Text(
                      labelFor(p.date),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            if (maxValue <= 0) ...[
              const SizedBox(height: 8),
              Text('No revenue recorded in the last 7 days.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({
    required this.summary,
    required this.canSeeRevenue,
    required this.number,
  });

  final DashboardSummary summary;
  final bool canSeeRevenue;
  final NumberFormat number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiringSoon = summary.expiringMembers.where((m) => m.daysLeft >= 0 && m.daysLeft <= 3).length;
    final isDark = theme.brightness == Brightness.dark;
    final items = <({IconData icon, Color color, String title, String subtitle})>[];

    if (expiringSoon > 0) {
      items.add((
        icon: Icons.notifications_active_outlined,
        color: AppTheme.alertAmber,
        title: '$expiringSoon memberships expiring',
        subtitle: 'Due within 3 days - action needed',
      ));
    }

    if (summary.membershipExpiredMembers > 0) {
      items.add((
        icon: Icons.event_busy_outlined,
        color: theme.colorScheme.error,
        title: '${number.format(summary.membershipExpiredMembers)} expired members',
        subtitle: 'Renewal follow-ups needed',
      ));
    }

    if (canSeeRevenue && summary.unpaidAmount > 0) {
      items.add((
        icon: Icons.payments_outlined,
        color: theme.colorScheme.primary,
        title: '${number.format(summary.unpaidAmount)} unpaid dues',
        subtitle: '${number.format(summary.unpaidInvoices)} invoices pending',
      ));
    }

    if (summary.todayCheckins == 0) {
      items.add((
        icon: Icons.how_to_reg_outlined,
        color: theme.colorScheme.tertiary,
        title: 'No check-ins yet',
        subtitle: "Today's attendance is still zero",
      ));
    }

    if (items.isEmpty) {
      items.add((
        icon: Icons.check_circle_outline,
        color: AppTheme.emeraldNeon,
        title: 'All systems green',
        subtitle: 'No urgent actions required',
      ));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
        border: Border.all(color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant, width: 0.8),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 70 : 16), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('INSIGHTS', style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: isDark ? AppTheme.borderHover : theme.colorScheme.outlineVariant, width: 0.8),
                    color: isDark ? AppTheme.charcoalHigh : theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text('Today', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final it in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: AppTheme.iconBox(color: it.color, radius: 12),
                      child: Center(child: Icon(it.icon, color: it.color, size: 20)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(it.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: it.color,
                        boxShadow: AppTheme.neonGlow(it.color, blur: 6),
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
}

class _ExpiringMembersCard extends StatelessWidget {
  const _ExpiringMembersCard({
    required this.members,
    required this.onOpenMembers,
  });

  final List<ExpiringMember> members;
  final VoidCallback onOpenMembers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = members.where((m) => m.daysLeft >= 0 && m.daysLeft <= 7).toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    if (list.isEmpty) return const SizedBox.shrink();

    bool isFrozen(ExpiringMember m) {
      final raw = m.frozenUntil?.trim();
      if (raw == null || raw.isEmpty) return false;
      final until = DateTime.tryParse(raw);
      if (until == null) return false;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(until.year, until.month, until.day);
      return !d.isBefore(today);
    }

    String badge(int daysLeft) {
      if (daysLeft <= 0) return 'Today';
      if (daysLeft == 1) return '1 day';
      return '$daysLeft days';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Renewals', style: theme.textTheme.titleMedium)),
                OutlinedButton(
                  onPressed: onOpenMembers,
                  child: const Text('Open Members'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Expiring in the next 7 days',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final m in list.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.tertiaryContainer,
                      foregroundColor: theme.colorScheme.onTertiaryContainer,
                      child: Text(
                        m.fullName.trim().isEmpty ? '?' : m.fullName.trim().substring(0, 1).toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.fullName,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${m.memberCode} • Expiry: ${m.endDate}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isFrozen(m)) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: Text(
                          'Frozen',
                          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: (m.daysLeft <= 3
                                ? theme.colorScheme.errorContainer
                                : theme.colorScheme.primaryContainer)
                            .withAlpha(220),
                      ),
                      child: Text(
                        badge(m.daysLeft),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: m.daysLeft <= 3
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onPrimaryContainer,
                        ),
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
}

class _RevenueChartPainter extends CustomPainter {
  _RevenueChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    this.dotColor,
  });

  final List<RevenuePoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color? dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor;

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = gridColor;

    final padding = 8.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    final origin = Offset(padding, padding);

    for (int i = 1; i <= 3; i++) {
      final y = origin.dy + (h * i / 4);
      canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + w, y), grid);
    }

    if (points.isEmpty) return;
    final maxY = points.map((e) => e.amount.toDouble()).fold<double>(0, (m, v) => v > m ? v : m);
    final denom = maxY <= 0 ? 1 : maxY;

    final pts = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = origin.dx + (w * (points.length == 1 ? 0 : i / (points.length - 1)));
      final y = origin.dy + h - (h * (points[i].amount.toDouble() / denom));
      pts.add(Offset(x, y));
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts.last.dx, pts.last.dy);
    } else {
      for (int i = 0; i < pts.length - 1; i++) {
        final p0 = i == 0 ? pts[i] : pts[i - 1];
        final p1 = pts[i];
        final p2 = pts[i + 1];
        final p3 = i + 2 < pts.length ? pts[i + 2] : p2;

        final c1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
        );
        final c2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
        );
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
      }
    }

    final bottomY = origin.dy + h;
    final fill = Path()
      ..addPath(path, Offset.zero)
      ..lineTo(pts.last.dx, bottomY)
      ..lineTo(pts.first.dx, bottomY)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withAlpha(90),
          lineColor.withAlpha(38),
          lineColor.withAlpha(8),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(origin.dx, origin.dy, w, h));

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, p);

    // Neon glow data-point markers
    if (maxY > 0) {
      final dc = dotColor ?? lineColor;
      final dotGlow = Paint()..color = dc.withAlpha(38)..style = PaintingStyle.fill;
      final dotCore = Paint()..color = dc..style = PaintingStyle.fill;
      final dotRing = Paint()..color = dc.withAlpha(80)..style = PaintingStyle.stroke..strokeWidth = 1.2;
      for (final pt in pts) {
        canvas.drawCircle(pt, 6.0, dotGlow);
        canvas.drawCircle(pt, 3.5, dotCore);
        canvas.drawCircle(pt, 5.0, dotRing);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor || oldDelegate.gridColor != gridColor || oldDelegate.dotColor != dotColor;
  }
}

class _ActiveInactiveCard extends StatelessWidget {
  const _ActiveInactiveCard({required this.active, required this.expired});

  final int active;
  final int expired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = active + expired;
    final pct = total <= 0 ? 0.0 : (active / total).clamp(0.0, 1.0);
    final pctText = NumberFormat.percentPattern().format(pct);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 620;
            final donutSize = wide ? 150.0 : 132.0;
            // Slimmer rings for the sharp enterprise look (was 14/12).
            final ringW = wide ? 10.0 : 9.0;
            Widget donut() {
              return SizedBox(
                height: donutSize,
                width: donutSize,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return CustomPaint(
                      painter: _DonutPiePainter(
                        value: value,
                        activeColor: theme.colorScheme.tertiary,
                        expiredColor: theme.colorScheme.error,
                        trackColor: theme.colorScheme.outlineVariant,
                        glowColor: theme.colorScheme.tertiary,
                        ringWidth: ringW,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // titleMedium = Bebas Neue — percentage reads as a scoreboard digit.
                            Text(
                              pctText,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.tertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            // One clean legend row: [• label] ............ [count (pct%)]
            Widget legendRow(Color dot, String label, int count) {
              final pctInt = total <= 0 ? 0 : ((count * 100) / total).round();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      '$count ($pctInt%)',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget legend({required CrossAxisAlignment crossAxisAlignment}) {
              return Column(
                crossAxisAlignment: crossAxisAlignment,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Active vs Expired', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  legendRow(theme.colorScheme.tertiary, 'Active', active),
                  Divider(height: 1, color: theme.dividerColor),
                  legendRow(theme.colorScheme.error, 'Expired', expired),
                  const SizedBox(height: 10),
                  Text(
                    'Total: $total',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              );
            }

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(child: donut()),
                  const SizedBox(height: 12),
                  legend(crossAxisAlignment: CrossAxisAlignment.center),
                ],
              );
            }

            return SizedBox(
              height: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Center(child: donut())),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: legend(crossAxisAlignment: CrossAxisAlignment.start),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DonutPiePainter extends CustomPainter {
  _DonutPiePainter({
    required this.value,
    required this.activeColor,
    required this.expiredColor,
    required this.trackColor,
    required this.glowColor,
    this.ringWidth = 12.0,
  });

  final double value;
  final Color activeColor;
  final Color expiredColor;
  final Color trackColor;
  final Color glowColor;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide / 2) - 6;

    final start = -pi / 2;
    final full = 2 * pi;
    final activeSweep = (full * value).clamp(0.0, full);
    final gap = value <= 0 || value >= 1 ? 0.0 : 0.06;

    final track = Paint()
      ..color = trackColor.withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    final expiredPaint = Paint()
      ..color = expiredColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);

    final arcRect = Rect.fromCircle(center: center, radius: radius);

    if (activeSweep > 0) {
      final s = start + gap / 2;
      final sw = max(0.0, activeSweep - gap);
      if (sw > 0) {
        final glow = Paint()
          ..color = glowColor.withAlpha(55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth + 8
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(arcRect, s, sw, false, glow);
        canvas.drawArc(arcRect, s, sw, false, activePaint);
      }
    }

    final remaining = full - activeSweep;
    if (remaining > 0) {
      final s = start + activeSweep + gap / 2;
      final sw = max(0.0, remaining - gap);
      if (sw > 0) {
        canvas.drawArc(arcRect, s, sw, false, expiredPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPiePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.expiredColor != expiredColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.ringWidth != ringWidth;
  }
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hover = _hover;
    final accent = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final radius = AppRadius.largeAll;

    // Width is controlled by the SizedBox wrapper in _QuickActionsSection.
    // TweenAnimationBuilder there drives the smooth resize between column modes.
    return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          scale: hover ? 1.013 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, hover ? -5 : 0, 0),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: radius,
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  // Minimum height so cards never collapse on very narrow viewports.
                  constraints: const BoxConstraints(minHeight: 76),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: isDark
                        ? (hover ? AppTheme.charcoalHigh : AppTheme.charcoal)
                        : (hover ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surface),
                    // White-only border at rest; accent on hover — accent is earned.
                    border: Border.all(
                      color: hover
                          ? accent.withAlpha(90)
                          : (isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant),
                      width: hover ? 1.0 : 0.8,
                    ),
                    boxShadow: hover
                        ? [
                            BoxShadow(color: accent.withAlpha(45), blurRadius: 32, offset: const Offset(0, 16)),
                            BoxShadow(color: Colors.black.withAlpha(isDark ? 100 : 22), blurRadius: 20, offset: const Offset(0, 10)),
                          ]
                        : [BoxShadow(color: Colors.black.withAlpha(isDark ? 50 : 12), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 44,
                          width: 44,
                          decoration: AppTheme.iconBox(color: accent, hover: hover),
                          child: Center(child: Icon(widget.icon, size: 22, color: accent)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Bebas Neue for the action verb ("ADD MEMBER", "CHECK-IN")
                              Text(
                                widget.title.toUpperCase(),
                                style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface, fontSize: 15),
                              ),
                              const SizedBox(height: 3),
                              // Inter for the functional subtitle — stays legible at small size
                              Text(widget.subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: hover ? 1.0 : 0.4,
                          child: Icon(Icons.chevron_right, color: accent, size: 20),
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
}

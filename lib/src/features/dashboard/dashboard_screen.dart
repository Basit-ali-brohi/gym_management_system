import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/whatsapp.dart';
import '../../core/web_download_stub.dart' if (dart.library.html) '../../core/web_download_web.dart';
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
          'Assalam o Alaikum {name}, aap {days} din se gym nahi aaye. Please visit soon. {gym}',
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
    final tenantSlug = auth.user?.tenantSlug ?? 'demo';

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

    Widget mainList({required EdgeInsets padding, required bool includeInlineActivity}) {
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
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth >= 1200 ? 280.0 : 320.0;
                  final frozen = s.frozenMembers;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (canSeeRevenue)
                        _MetricCard(
                          width: cardWidth,
                          title: 'Total Revenue',
                          value: widget.number.format(s.revenueTotal),
                          subtitle: 'All-time paid',
                          icon: Icons.payments,
                          onTap: () => context.go('/invoices'),
                        ),
                      if (canSeeRevenue)
                        _MetricCard(
                          width: cardWidth,
                          title: 'Revenue (30d)',
                          value: widget.number.format(s.revenueLast30Days),
                          subtitle: 'Last 30 days',
                          icon: Icons.show_chart,
                          onTap: () => context.go('/invoices'),
                        ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Active Members',
                        value: widget.number.format(s.membershipActiveMembers),
                        subtitle: 'Membership active',
                        icon: Icons.people,
                        onTap: () => context.go('/members'),
                      ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Frozen Members',
                        value: frozen == null ? '—' : widget.number.format(frozen),
                        subtitle: frozen == null ? 'Restart backend to enable' : 'Access blocked',
                        icon: Icons.ac_unit_outlined,
                        onTap: () => context.go('/members'),
                      ),
                      if (canSeeRevenue)
                        _MetricCard(
                          width: cardWidth,
                          title: 'Unpaid Dues',
                          value: widget.number.format(s.unpaidAmount),
                          subtitle: '${widget.number.format(s.unpaidInvoices)} invoices',
                          icon: Icons.receipt_long,
                          onTap: () => context.go('/invoices'),
                        ),
                      _MetricCard(
                        width: cardWidth,
                        title: "Today's Check-ins",
                        value: widget.number.format(s.todayCheckins),
                        subtitle: 'Attendance today',
                        icon: Icons.how_to_reg,
                        onTap: () => context.go('/attendance'),
                      ),
                      _MetricCard(
                        width: cardWidth,
                        title: 'Plans',
                        value: widget.number.format(s.plansTotal),
                        subtitle: 'Membership plans',
                        icon: Icons.card_membership,
                        onTap: () => context.go('/plans'),
                      ),
                    ],
                  );
                },
              );
            },
            error: (e, stackTrace) {
              String message = e.toString();
              if (e is ApiException) {
                if (e.statusCode == 404) {
                  message = 'Backend update apply nahi hui. Server ko stop karke dobara start karo.';
                } else if (e.statusCode == 401) {
                  message = 'Session expired. Dobara login karo.';
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
        Expanded(child: mainList(padding: const EdgeInsets.all(20), includeInlineActivity: false)),
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
        Text('Quick Actions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ActionCard(
              title: 'Add Member',
              subtitle: 'New registration',
              icon: Icons.person_add_alt_1,
              onTap: () => context.go('/members'),
            ),
            _ActionCard(
              title: 'Add Plan',
              subtitle: 'Pricing & duration',
              icon: Icons.add_card,
              onTap: () => context.go('/plans'),
            ),
            _ActionCard(
              title: 'Check-in',
              subtitle: 'Search member & check-in',
              icon: Icons.qr_code_scanner,
              onTap: () => context.go('/attendance'),
            ),
            _ActionCard(
              title: 'Add Lead',
              subtitle: 'New enquiry',
              icon: Icons.person_search,
              onTap: () => context.go('/leads'),
            ),
            if (canSeeRevenue)
              _ActionCard(
                title: 'Invoices',
                subtitle: 'Generate & track',
                icon: Icons.receipt_long,
                onTap: () => context.go('/invoices'),
              ),
            if (canSeeRevenue)
              _ActionCard(
                title: 'Record Expense',
                subtitle: 'Track costs',
                icon: Icons.account_balance_wallet,
                onTap: () => context.go('/expenses'),
              ),
          ],
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
          return 'Backend update apply nahi hui. Server ko stop karke dobara start karo.';
        }
        if (e.statusCode == 401) return 'Session expired. Dobara login karo.';
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
      final primary = theme.colorScheme.primary;
      return Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: primary.withValues(alpha: 0.12),
              border: Border.all(color: primary.withValues(alpha: 0.28)),
            ),
            child: Icon(Icons.warning_amber_outlined, color: primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('At-Risk Members', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.people),
                          title: Text('${m.fullName} (${m.memberCode})', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Last: ${fmtDate(m.lastCheckinAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: phoneOk ? 'WhatsApp' : 'Phone missing',
                            onPressed: phoneOk ? () => openWhatsApp(phone: m.phone, message: msg) : null,
                            icon: const Icon(Icons.chat_bubble_outline),
                          ),
                          onTap: () => context.go('/members?q=${Uri.encodeComponent(m.memberCode)}'),
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
          return 'Backend update apply nahi hui. Server ko stop karke dobara start karo.';
        }
        if (e.statusCode == 401) return 'Session expired. Dobara login karo.';
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
                Text('Recent Activity', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
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

      return SizedBox(
        height: floating ? 340 : 320,
        child: Scrollbar(
          child: ListView.separated(
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
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: chipColor.withValues(alpha: 0.14),
                  foregroundColor: chipColor,
                  child: Icon(icon, size: 18),
                ),
                title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(fmtTime(a.at), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                onTap: () => context.go(route),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withAlpha(41),
              theme.colorScheme.tertiary.withAlpha(31),
              theme.colorScheme.surface.withAlpha(89),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                height: 190,
                width: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withAlpha(31),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -60,
              child: Container(
                height: 220,
                width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.tertiary.withAlpha(26),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting • $today',
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gymName.isEmpty ? 'Gym Dashboard' : gymName,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Gym: $tenantSlug • Performance overview',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => context.go('/members'),
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text('Add member'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/attendance'),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Check-in'),
                            ),
                            if (canSeeRevenue)
                              OutlinedButton.icon(
                                onPressed: () => context.go('/invoices'),
                                icon: const Icon(Icons.receipt_long_outlined),
                                label: const Text('Invoices'),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/leads'),
                              icon: const Icon(Icons.person_search_outlined),
                              label: const Text('Leads'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            tooltip: 'PDF',
                            onPressed: onExportPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: theme.colorScheme.surface.withAlpha(64),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Icon(Icons.apartment, size: 44, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surface.withAlpha(64),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
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
    final radius = BorderRadius.circular(16);
    final goldA = const Color(0xFFD4AF37);
    final goldB = const Color(0xFFFFE08A);
    final blurSigma = hover ? 22.0 : 18.0;
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: hover ? 1.015 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, hover ? -5 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: hover
                  ? [
                      BoxShadow(
                        color: goldA.withAlpha(52),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.black.withAlpha(theme.brightness == Brightness.dark ? 90 : 30),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withAlpha(theme.brightness == Brightness.dark ? 60 : 20),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
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
                      foregroundPainter: _GradientStrokePainter(
                        radius: radius,
                        width: 1,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            goldA.withAlpha(hover ? 220 : 160),
                            goldB.withAlpha(hover ? 170 : 110),
                            goldA.withAlpha(hover ? 220 : 160),
                          ],
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.surfaceContainerHighest.withAlpha(theme.brightness == Brightness.dark ? 70 : 120),
                              theme.colorScheme.surface.withAlpha(theme.brightness == Brightness.dark ? 58 : 110),
                            ],
                          ),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(hover ? 170 : 120)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: theme.colorScheme.primary.withAlpha(hover ? 52 : 38),
                                  border: Border.all(color: theme.colorScheme.primary.withAlpha(hover ? 130 : 90)),
                                ),
                                child: Icon(widget.icon, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.title, style: theme.textTheme.labelLarge),
                                    const SizedBox(height: 6),
                                    Text(
                                      widget.value,
                                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(widget.subtitle, style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Revenue (7 days)', style: theme.textTheme.titleMedium)),
                Text(number.format(total7d), style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _RevenueChartPainter(
                  points: normalized,
                  lineColor: theme.colorScheme.tertiary,
                  gridColor: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final p in normalized.take(7)) Text(labelFor(p.date), style: theme.textTheme.labelSmall),
              ],
            ),
            if (maxValue <= 0) ...[
              const SizedBox(height: 8),
              Text(
                'No revenue recorded in the last 7 days.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
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
    final items = <({IconData icon, String title, String subtitle})>[];

    if (expiringSoon > 0) {
      items.add((
        icon: Icons.notifications_active_outlined,
        title: '$expiringSoon memberships expiring',
        subtitle: 'Due within 3 days',
      ));
    }

    if (summary.membershipExpiredMembers > 0) {
      items.add((
        icon: Icons.event_busy_outlined,
        title: '${number.format(summary.membershipExpiredMembers)} expired members',
        subtitle: 'Renewal follow-ups needed',
      ));
    }

    if (canSeeRevenue && summary.unpaidAmount > 0) {
      items.add((
        icon: Icons.payments_outlined,
        title: '${number.format(summary.unpaidAmount)} unpaid dues',
        subtitle: '${number.format(summary.unpaidInvoices)} invoices pending',
      ));
    }

    if (summary.todayCheckins == 0) {
      items.add((
        icon: Icons.how_to_reg_outlined,
        title: 'No check-ins yet',
        subtitle: 'Today’s attendance is still zero',
      ));
    }

    if (items.isEmpty) {
      items.add((
        icon: Icons.check_circle_outline,
        title: 'All good',
        subtitle: 'No urgent actions right now',
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Insights', style: theme.textTheme.titleMedium)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    color: theme.colorScheme.surface.withAlpha(32),
                  ),
                  child: Text('Today', style: theme.textTheme.labelMedium),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final it in items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      height: 38,
                      width: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: theme.colorScheme.primary.withAlpha(24),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Icon(it.icon, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            it.subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
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
  });

  final List<RevenuePoint> points;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor;

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
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

    final gold = const Color(0xFFD4AF37);
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          gold.withAlpha(68),
          gold.withAlpha(18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(origin.dx, origin.dy, w, h));

    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, p);

    final dot = Paint()..color = lineColor;
    for (final pt in pts) {
      canvas.drawCircle(pt, 2.6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.lineColor != lineColor || oldDelegate.gridColor != gridColor;
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
            final ringW = wide ? 14.0 : 12.0;
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
                        ringWidth: ringW,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              pctText,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            Widget legend({required CrossAxisAlignment crossAxisAlignment}) {
              return Column(
                crossAxisAlignment: crossAxisAlignment,
                children: [
                  Text('Active vs Expired', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _LegendPill(
                        color: theme.colorScheme.tertiary,
                        label: 'Active',
                        value: active.toString(),
                      ),
                      _LegendPill(
                        color: theme.colorScheme.error,
                        label: 'Expired',
                        value: expired.toString(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Total: $total', style: theme.textTheme.bodySmall),
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

            final legendWidthCap = (constraints.maxWidth / 2) - 110;
            final legendWidth = min(320.0, max(220.0, legendWidthCap));
            return SizedBox(
              height: 168,
              child: Stack(
                children: [
                  Center(child: donut()),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(width: legendWidth, child: legend(crossAxisAlignment: CrossAxisAlignment.start)),
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

class _LegendPill extends StatelessWidget {
  const _LegendPill({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface.withAlpha(32),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(width: 8),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
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
    this.ringWidth = 12.0,
  });

  final double value;
  final Color activeColor;
  final Color expiredColor;
  final Color trackColor;
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
          ..color = const Color(0xFFD4AF37).withAlpha(24)
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth + 6
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
        oldDelegate.trackColor != trackColor;
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
    final gold = theme.colorScheme.primary;
    return SizedBox(
      width: 320,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          scale: hover ? 1.012 : 1,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: hover
                    ? [
                        BoxShadow(
                          color: gold.withValues(alpha: 0.16),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : const [],
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: gold.withValues(alpha: 0.12),
                          border: Border.all(color: gold.withValues(alpha: 0.28)),
                        ),
                        child: Icon(widget.icon, size: 22, color: gold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(widget.subtitle, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
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

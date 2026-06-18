import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_theme.dart'; // AppTheme + AppTypography
import '../../core/branding.dart';
import '../../core/providers.dart';
import '../../core/whatsapp.dart';
import '../auth/auth_controller.dart';

class ExpiringPreviewMember {
  const ExpiringPreviewMember({
    required this.memberId,
    required this.fullName,
    required this.memberCode,
    required this.endDate,
    required this.daysLeft,
  });

  final int memberId;
  final String fullName;
  final String memberCode;
  final String endDate;
  final int daysLeft;
}

class ExpiringMemberReminder {
  const ExpiringMemberReminder({
    required this.memberId,
    required this.fullName,
    required this.memberCode,
    required this.phone,
    required this.planName,
    required this.endDate,
    required this.daysLeft,
    required this.frozenUntil,
  });

  final int memberId;
  final String fullName;
  final String memberCode;
  final String? phone;
  final String planName;
  final String endDate;
  final int daysLeft;
  final String? frozenUntil;
}

class UnpaidInvoiceReminder {
  const UnpaidInvoiceReminder({
    required this.invoiceId,
    required this.invoiceNo,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.memberName,
    required this.memberCode,
    required this.phone,
  });

  final int invoiceId;
  final String invoiceNo;
  final num total;
  final String status;
  final String createdAt;
  final String memberName;
  final String memberCode;
  final String? phone;
}

String _dateOnly(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

final expiringPreviewProvider = FutureProvider.autoDispose<List<ExpiringPreviewMember>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) return const [];
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/dashboard/summary', token: token);
  final raw = (res['expiringMembers'] as List<dynamic>? ?? []).whereType<Map>().toList();
  return raw
      .map((e) => e.cast<String, dynamic>())
      .map(
        (e) => ExpiringPreviewMember(
          memberId: (e['memberId'] as num?)?.toInt() ?? 0,
          fullName: e['fullName']?.toString() ?? '',
          memberCode: e['memberCode']?.toString() ?? '',
          endDate: e['endDate']?.toString() ?? '',
          daysLeft: (e['daysLeft'] as num?)?.toInt() ?? 999,
        ),
      )
      .where((m) => m.daysLeft >= 0 && m.daysLeft <= 3)
      .toList();
});

final remindersDaysProvider = StateProvider.autoDispose<int>((ref) => 7);

final expiringMembersProvider =
    FutureProvider.autoDispose.family<List<ExpiringMemberReminder>, int>((ref, days) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) return const [];
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/members/expiring', token: token, query: {'days': days.toString()});
  final raw = (res['items'] as List<dynamic>? ?? []).whereType<Map>().toList();
  return raw
      .map((e) => e.cast<String, dynamic>())
      .map(
        (e) => ExpiringMemberReminder(
          memberId: (e['memberId'] as num?)?.toInt() ?? 0,
          fullName: e['fullName']?.toString() ?? '',
          memberCode: e['memberCode']?.toString() ?? '',
          phone: e['phone']?.toString(),
          planName: e['planName']?.toString() ?? '',
          endDate: e['endDate']?.toString() ?? '',
          daysLeft: (e['daysLeft'] as num?)?.toInt() ?? 999,
          frozenUntil: e['frozenUntil']?.toString(),
        ),
      )
      .where((m) => m.memberId > 0)
      .toList();
});

final unpaidInvoicesProvider = FutureProvider.autoDispose<List<UnpaidInvoiceReminder>>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) return const [];
  final api = ref.read(apiClientProvider);
  final res = await api.getJson('/invoices', token: token, query: {'status': 'unpaid', 'limit': '200'});
  final raw = (res['items'] as List<dynamic>? ?? []).whereType<Map>().toList();

  num parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  return raw
      .map((e) => e.cast<String, dynamic>())
      .map(
        (e) => UnpaidInvoiceReminder(
          invoiceId: (e['id'] as num?)?.toInt() ?? 0,
          invoiceNo: e['invoice_no']?.toString() ?? '',
          total: parseNum(e['total']),
          status: e['status']?.toString() ?? '',
          createdAt: e['created_at']?.toString() ?? '',
          memberName: e['full_name']?.toString() ?? '',
          memberCode: e['member_code']?.toString() ?? '',
          phone: e['phone']?.toString(),
        ),
      )
      .where((i) => i.invoiceId > 0)
      .toList();
});

final invoicesGeneratedTodayProvider = FutureProvider.autoDispose<int>((ref) async {
  final token = ref.read(authControllerProvider).token;
  if (token == null || token.isEmpty) return 0;
  final api = ref.read(apiClientProvider);
  final today = _dateOnly(DateTime.now());
  try {
    final res = await api.getJson('/invoices', token: token, query: {'from': today, 'to': today, 'limit': '1'});
    return (res['total'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
});

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final location = GoRouterState.of(context).matchedLocation;
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;
    final expiringAsync = ref.watch(expiringPreviewProvider);

    // Clean, title-cased gym name (no "(slug)" parenthetical). e.g. a slug of
    // "smartinn-fitness" → "Smartinn Fitness". Falls back to the product name.
    final rawSlug = (auth.user?.tenantSlug ?? '').trim();
    final tenantLabel = rawSlug.isEmpty
        ? 'Gym Management'
        : rawSlug
            .replaceAll(RegExp(r'[_-]+'), ' ')
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map((s) => s[0].toUpperCase() + s.substring(1))
            .join(' ');
    void toggleTheme() {
      ref.read(themeModeProvider.notifier).setMode(isDark ? ThemeMode.light : ThemeMode.dark);
    }
    Future<void> copyToClipboard(String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
    }

    Future<void> openWhatsApp({required String? phone, required String message}) async {
      final digits = normalizeWhatsAppPhone(phone);
      if (digits.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone missing')));
        return;
      }
      final ok = await openWhatsAppMessage(phone: digits, message: message);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    }

    void openExpiringDialog() {
      showDialog<void>(
        context: context,
        builder: (context) {
          final urgent = expiringAsync.valueOrNull ?? const <ExpiringPreviewMember>[];
          final urgentCount = urgent.length;

          Future<void> sendAllUnpaidInvoiceReminders(List<UnpaidInvoiceReminder> items) async {
            final eligible = items.where((i) => normalizeWhatsAppPhone(i.phone).isNotEmpty).toList();
            if (eligible.isEmpty) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No reminders ready')));
              return;
            }

            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Opening WhatsApp for ${eligible.length} reminders…')));

            var okCount = 0;
            var failCount = 0;
            for (final inv in eligible) {
              final msg =
                  'Hello ${inv.memberName}, your pending bill ${inv.invoiceNo} (Rs ${inv.total}) is due. Please clear it. Thank you. $tenantLabel';
              final ok = await openWhatsAppMessage(phone: inv.phone ?? '', message: msg);
              if (ok) {
                okCount += 1;
              } else {
                failCount += 1;
              }
              await Future<void>.delayed(const Duration(milliseconds: 240));
            }

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Reminders: sent $okCount, failed $failCount')),
            );
          }

          return AlertDialog(
            title: Text(urgentCount == 0 ? 'Reminder Center' : 'Reminder Center ($urgentCount urgent)'),
            content: SizedBox(
              width: 860,
              height: 520,
              child: DefaultTabController(
                length: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Daily Tasks'),
                        Tab(text: 'Expiring Members'),
                        Tab(text: 'Unpaid Invoices'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          Consumer(
                            builder: (context, r, _) {
                              final todayCount = r.watch(invoicesGeneratedTodayProvider);
                              final unpaid = r.watch(unpaidInvoicesProvider);
                              final unpaidList = unpaid.valueOrNull ?? const <UnpaidInvoiceReminder>[];
                              final ready = unpaidList.where((i) => normalizeWhatsAppPhone(i.phone).isNotEmpty).length;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Text('Daily Tasks', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 8),
                                          todayCount.when(
                                            data: (n) => Text('• $n Invoices generated today', style: theme.textTheme.bodyMedium),
                                            error: (e, _) => Text('• Invoices generated today: —', style: theme.textTheme.bodyMedium),
                                            loading: () => Text('• Invoices generated today: …', style: theme.textTheme.bodyMedium),
                                          ),
                                          const SizedBox(height: 6),
                                          Text('• $ready Reminders ready to send', style: theme.textTheme.bodyMedium),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: FilledButton.icon(
                                              onPressed: unpaid.valueOrNull == null ? null : () => sendAllUnpaidInvoiceReminders(unpaidList),
                                              icon: const Icon(Icons.done_all),
                                              label: const Text('Approve'),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Click Approve — the system will open WhatsApp reminders.',
                                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Note: Your browser popup blocker may block multiple WhatsApp tabs.',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              );
                            },
                          ),
                          Consumer(
                            builder: (context, r, _) {
                              final days = r.watch(remindersDaysProvider);
                              final expiring = r.watch(expiringMembersProvider(days));

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 160,
                                        child: DropdownButtonFormField<int>(
                                          key: ValueKey(days),
                                          initialValue: days,
                                          decoration: const InputDecoration(labelText: 'Days'),
                                          items: const [
                                            DropdownMenuItem(value: 3, child: Text('3 days')),
                                            DropdownMenuItem(value: 7, child: Text('7 days')),
                                            DropdownMenuItem(value: 14, child: Text('14 days')),
                                            DropdownMenuItem(value: 30, child: Text('30 days')),
                                          ],
                                          onChanged: (v) => r.read(remindersDaysProvider.notifier).state = v ?? 7,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Refresh',
                                        onPressed: () => r.refresh(expiringMembersProvider(days)),
                                        icon: const Icon(Icons.refresh),
                                      ),
                                      Text(
                                        urgentCount == 0 ? 'Urgent: 0' : 'Urgent: $urgentCount',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: expiring.when(
                                      data: (items) {
                                        if (items.isEmpty) return const Center(child: Text('No expiring members.'));
                                        return ListView.separated(
                                          itemCount: items.length,
                                          separatorBuilder: (context, _) => const Divider(height: 1),
                                          itemBuilder: (context, i) {
                                            final m = items[i];
                                            final msg =
                                                'Hello ${m.fullName}, your membership expires on ${m.endDate} (${m.daysLeft} days left). Please renew it. $tenantLabel';
                                            return ListTile(
                                              dense: true,
                                              title: Text('${m.fullName} (${m.memberCode})'),
                                              subtitle: Text('${m.planName} • Expiry: ${m.endDate} • ${m.daysLeft} days left'),
                                              trailing: Wrap(
                                                spacing: 6,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'WhatsApp',
                                                    onPressed: m.phone == null || m.phone!.trim().isEmpty
                                                        ? null
                                                        : () => openWhatsApp(phone: m.phone, message: msg),
                                                    icon: const Icon(Icons.chat_bubble_outline),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Copy message',
                                                    onPressed: () => copyToClipboard(msg),
                                                    icon: const Icon(Icons.content_copy_outlined),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Open member',
                                                    onPressed: () {
                                                      Navigator.of(context).pop();
                                                      context.go('/members?q=${Uri.encodeComponent(m.memberCode)}');
                                                    },
                                                    icon: const Icon(Icons.open_in_new),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                      error: (e, _) => Center(child: Text(e.toString())),
                                      loading: () => const Center(child: CircularProgressIndicator()),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          Consumer(
                            builder: (context, r, _) {
                              final unpaid = r.watch(unpaidInvoicesProvider);
                              final list = unpaid.valueOrNull ?? const <UnpaidInvoiceReminder>[];
                              final readyCount = list.where((i) => normalizeWhatsAppPhone(i.phone).isNotEmpty).length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: unpaid.valueOrNull == null ? null : () => sendAllUnpaidInvoiceReminders(list),
                                        icon: const Icon(Icons.done_all),
                                        label: Text('Send All ($readyCount)'),
                                      ),
                                      IconButton(
                                        tooltip: 'Refresh',
                                        onPressed: () => r.refresh(unpaidInvoicesProvider),
                                        icon: const Icon(Icons.refresh),
                                      ),
                                      Text(
                                        'Tip: open invoice page to mark Paid',
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: unpaid.when(
                                      data: (items) {
                                        if (items.isEmpty) return const Center(child: Text('No unpaid invoices.'));
                                        return ListView.separated(
                                          itemCount: items.length,
                                          separatorBuilder: (context, _) => const Divider(height: 1),
                                          itemBuilder: (context, i) {
                                            final inv = items[i];
                                            final msg =
                                                'Hello ${inv.memberName}, your pending bill ${inv.invoiceNo} (Rs ${inv.total}) is due. Please clear it. Thank you. $tenantLabel';
                                            return ListTile(
                                              dense: true,
                                              title: Text('${inv.invoiceNo} • ${inv.memberName} (${inv.memberCode})'),
                                              subtitle: Text('Total: Rs ${inv.total} • ${inv.createdAt}'),
                                              trailing: Wrap(
                                                spacing: 6,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'WhatsApp',
                                                    onPressed: inv.phone == null || inv.phone!.trim().isEmpty
                                                        ? null
                                                        : () => openWhatsApp(phone: inv.phone, message: msg),
                                                    icon: const Icon(Icons.chat_bubble_outline),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Copy message',
                                                    onPressed: () => copyToClipboard(msg),
                                                    icon: const Icon(Icons.content_copy_outlined),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Open invoices',
                                                    onPressed: () {
                                                      Navigator.of(context).pop();
                                                      context.go('/invoices');
                                                    },
                                                    icon: const Icon(Icons.open_in_new),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                      error: (e, _) => Center(child: Text(e.toString())),
                                      loading: () => const Center(child: CircularProgressIndicator()),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ],
          );
        },
      );
    }

    void openGlobalSearch() {
      final rootContext = context;
      showDialog<void>(
        context: context,
        builder: (_) => _MasterSearchDialog(rootContext: rootContext),
      );
    }

    // Global Quick Actions ("+"): flag the create intent, then route to the
    // owning screen which consumes the flag and opens its create modal.
    void runQuickAction(QuickAction action) {
      const routes = <QuickAction, String>{
        QuickAction.addMember: '/members',
        QuickAction.addLead: '/leads',
        QuickAction.quickInvoice: '/invoices',
        QuickAction.recordExpense: '/expenses',
      };
      ref.read(pendingQuickActionProvider.notifier).state = action;
      context.go(routes[action]!);
    }

    final roleList = auth.user?.roles ?? const <String>[];
    final roles = roleList
        .map((r) => r.trim().toLowerCase().replaceAll(' ', '_'))
        .where((r) => r.isNotEmpty)
        .toSet();
    final canSeeRevenue = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final canManageStaff = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final canSeeSettings = roles.contains('owner') || roles.contains('admin') || roles.contains('super_admin');
    final isReceptionistOnly = roles.contains('receptionist') && !canSeeRevenue;
    final canSeeInventory = !isReceptionistOnly;

    final destinations = <_NavDestination>[
      const _NavDestination.header('Overview'),
      const _NavDestination.item('Dashboard', Icons.dashboard, '/dashboard'),
      const _NavDestination.header('CRM'),
      const _NavDestination.item('Leads', Icons.person_search, '/leads'),
      const _NavDestination.header('Members'),
      const _NavDestination.item('Members', Icons.people, '/members'),
      const _NavDestination.item('Plans', Icons.card_membership, '/plans'),
      const _NavDestination.item('Attendance', Icons.how_to_reg, '/attendance'),
      if (canSeeRevenue) ...[
        const _NavDestination.header('Billing'),
        const _NavDestination.item('Invoices', Icons.receipt_long, '/invoices'),
        const _NavDestination.item('Payments', Icons.payments, '/payments'),
        const _NavDestination.header('Finance'),
        const _NavDestination.item('Expenses', Icons.account_balance_wallet, '/expenses'),
        const _NavDestination.item('Reports', Icons.bar_chart, '/reports'),
      ],
      if (canSeeInventory) ...[
        const _NavDestination.header('Operations'),
        const _NavDestination.item('Inventory', Icons.inventory_2, '/inventory'),
      ],
      if (canManageStaff || canSeeSettings) ...[
        const _NavDestination.header('Admin'),
        if (canManageStaff) const _NavDestination.item('Staff', Icons.badge, '/staff'),
        if (canSeeSettings) const _NavDestination.item('Settings', Icons.settings, '/settings'),
      ],
    ];

    _NavDestination? selected;
    for (final d in destinations) {
      if (d.isHeader) continue;
      if (d.route == location) {
        selected = d;
        break;
      }
    }
    final pageTitle = selected?.label ?? 'Dashboard';

    final userName = auth.user?.fullName ?? 'User';
    final initials = userName.trim().isEmpty
        ? 'U'
        : userName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
            .join();

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _OpenMasterSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _OpenMasterSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenMasterSearchIntent: CallbackAction<_OpenMasterSearchIntent>(
            onInvoke: (_) {
              openGlobalSearch();
              return null;
            },
          ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useRail = constraints.maxWidth >= 900;

            if (!useRail) {
              return Scaffold(
                appBar: AppBar(
                  // Just the page name (gym name lives in the drawer). FittedBox
                  // scales the title down to fit instead of ever truncating with
                  // an ellipsis on narrow phones.
                  titleSpacing: 4,
                  title: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        pageTitle,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  // Compact action density so 5 controls fit without overflow.
                  actionsIconTheme: const IconThemeData(size: 22),
                  actions: [
                    _IconBadgeButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_none),
                      badgeCount: expiringAsync.valueOrNull?.length ?? 0,
                      onPressed: openExpiringDialog,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: isDark ? 'Light theme' : 'Dark theme',
                      onPressed: toggleTheme,
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Search',
                      onPressed: openGlobalSearch,
                      icon: const Icon(Icons.search),
                    ),
                    _QuickActionsButton(onQuickAction: runQuickAction),
                    PopupMenuButton<String>(
                      tooltip: 'Account',
                      onSelected: (v) {
                        if (v == 'logout') ref.read(authControllerProvider.notifier).logout();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userName, style: theme.textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(auth.user?.email ?? '', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'logout', child: Text('Logout')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Text(initials),
                        ),
                      ),
                    ),
                  ],
                ),
                drawer: _AppDrawer(
                  tenantLabel: tenantLabel,
                  userName: userName,
                  email: auth.user?.email ?? '',
                  roles: (auth.user?.roles ?? const []).join(', '),
                  selectedRoute: location,
                  destinations: destinations,
                  onGo: (route) => context.go(route),
                ),
                body: child,
              );
            }

            return Scaffold(
              body: _DesktopFrame(
                tenantLabel: tenantLabel,
                userName: userName,
                email: auth.user?.email ?? '',
                initials: initials,
                pageTitle: pageTitle,
                selectedRoute: location,
                destinations: destinations,
                onGo: (route) => context.go(route),
                onLogout: () => ref.read(authControllerProvider.notifier).logout(),
                isDark: isDark,
                onToggleTheme: toggleTheme,
                expiringAsync: expiringAsync,
                onOpenNotifications: openExpiringDialog,
                onOpenSearch: openGlobalSearch,
                onQuickAction: runQuickAction,
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OpenMasterSearchIntent extends Intent {
  const _OpenMasterSearchIntent();
}

class _MasterSearchDialog extends ConsumerStatefulWidget {
  const _MasterSearchDialog({required this.rootContext});

  final BuildContext rootContext;

  @override
  ConsumerState<_MasterSearchDialog> createState() => _MasterSearchDialogState();
}

class _MasterSearchDialogState extends ConsumerState<_MasterSearchDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _requestId = 0;

  bool _loading = false;
  String? _error;
  String _q = '';
  _MasterSearchResponse _res = const _MasterSearchResponse.empty();
  final Map<String, _MasterSearchResponse> _cache = <String, _MasterSearchResponse>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setQuery(String raw) {
    final q = raw.trim();
    setState(() {
      _q = q;
      _error = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    if (q.length < 2) {
      setState(() {
        _loading = false;
        _res = const _MasterSearchResponse.empty();
      });
      return;
    }

    final cached = _cache[q.toLowerCase()];
    if (cached != null) {
      setState(() {
        _loading = false;
        _res = cached;
      });
      return;
    }

    final token = ref.read(authControllerProvider).token;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'unauthorized';
        _res = const _MasterSearchResponse.empty();
      });
      return;
    }

    final api = ref.read(apiClientProvider);
    final rid = ++_requestId;
    setState(() => _loading = true);
    try {
      final json = await api.getJson('/search', token: token, query: {'q': q, 'limit': '8'});
      if (!mounted || rid != _requestId) return;

      final res = _MasterSearchResponse.fromJson(json);
      _cache[q.toLowerCase()] = res;
      setState(() {
        _loading = false;
        _res = res;
      });
    } catch (e) {
      if (!mounted || rid != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'search_failed';
        _res = const _MasterSearchResponse.empty();
      });
    }
  }

  void _go(String route) {
    Navigator.of(context).pop();
    widget.rootContext.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface.withAlpha(theme.brightness == Brightness.dark ? 72 : 120);
    final border = theme.colorScheme.outlineVariant.withAlpha(theme.brightness == Brightness.dark ? 130 : 160);

    final hasResults = _res.members.isNotEmpty || _res.leads.isNotEmpty || _res.invoices.isNotEmpty;

    Widget glass({required Widget child, BorderRadius? radius}) {
      final r = radius ?? BorderRadius.circular(18);
      return ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface,
                  theme.colorScheme.surfaceContainerHighest.withAlpha(theme.brightness == Brightness.dark ? 40 : 70),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(theme.brightness == Brightness.dark ? 110 : 28),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }

    Widget section(String title, List<_MasterSearchTileData> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.9,
              ),
            ),
          ),
          for (final t in items)
            ListTile(
              dense: true,
              leading: Icon(t.icon, color: theme.colorScheme.tertiary),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: t.subtitle == null ? null : Text(t.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _go(t.route),
            ),
        ],
      );
    }

    final memberTiles = _res.members.map((m) {
      final target = (m.memberCode ?? '').trim().isNotEmpty ? m.memberCode!.trim() : m.fullName.trim();
      final q = Uri.encodeComponent(target);
      final subtitle = [m.phone, m.memberCode].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join(' • ');
      return _MasterSearchTileData(
        icon: Icons.people,
        title: m.fullName.trim().isEmpty ? target : '${m.fullName} (${m.memberCode ?? ''})'.replaceAll(' ()', ''),
        subtitle: subtitle.isEmpty ? null : subtitle,
        route: '/members?q=$q',
      );
    }).toList();

    final leadTiles = _res.leads.map((l) {
      final target = (l.phone ?? '').trim().isNotEmpty ? l.phone!.trim() : l.fullName.trim();
      final q = Uri.encodeComponent(target);
      final subtitle =
          [l.phone, l.status, l.source, l.interest].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join(' • ');
      return _MasterSearchTileData(
        icon: Icons.person_search,
        title: l.fullName,
        subtitle: subtitle.isEmpty ? null : subtitle,
        route: '/leads?q=$q',
      );
    }).toList();

    final invoiceTiles = _res.invoices.map((i) {
      final q = Uri.encodeComponent(i.invoiceNo);
      final subtitleParts = <String>[
        i.memberName,
        i.status,
        'Rs ${i.total}',
      ].where((s) => s.trim().isNotEmpty).toList();
      return _MasterSearchTileData(
        icon: Icons.receipt_long,
        title: i.invoiceNo,
        subtitle: subtitleParts.join(' • '),
        route: '/invoices?q=$q',
      );
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: glass(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search Members, Leads, Invoices…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _q.isEmpty
                              ? IconButton(
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close),
                                )
                              : IconButton(
                                  tooltip: 'Clear',
                                  onPressed: () {
                                    _ctrl.clear();
                                    _setQuery('');
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                        onChanged: _setQuery,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  ),
                if (!_loading && _error == null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: glass(
                      radius: BorderRadius.circular(16),
                      child: hasResults
                          ? SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  section('Members', memberTiles),
                                  section('Leads', leadTiles),
                                  section('Invoices', invoiceTiles),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                _q.length < 2 ? 'Type at least 2 characters…' : 'No results',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
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

class _MasterSearchTileData {
  const _MasterSearchTileData({
    required this.icon,
    required this.title,
    required this.route,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String route;
}

class _MasterSearchResponse {
  const _MasterSearchResponse({
    required this.members,
    required this.leads,
    required this.invoices,
  });

  const _MasterSearchResponse.empty() : this(members: const [], leads: const [], invoices: const []);

  final List<_MasterSearchMember> members;
  final List<_MasterSearchLead> leads;
  final List<_MasterSearchInvoice> invoices;

  factory _MasterSearchResponse.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v as List<dynamic>? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

    return _MasterSearchResponse(
      members: maps(json['members']).map(_MasterSearchMember.fromJson).toList(),
      leads: maps(json['leads']).map(_MasterSearchLead.fromJson).toList(),
      invoices: maps(json['invoices']).map(_MasterSearchInvoice.fromJson).toList(),
    );
  }
}

class _MasterSearchMember {
  const _MasterSearchMember({
    required this.id,
    required this.fullName,
    this.memberCode,
    this.phone,
  });

  final int id;
  final String fullName;
  final String? memberCode;
  final String? phone;

  factory _MasterSearchMember.fromJson(Map<String, dynamic> json) {
    return _MasterSearchMember(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: json['fullName']?.toString() ?? '',
      memberCode: json['memberCode']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

class _MasterSearchLead {
  const _MasterSearchLead({
    required this.id,
    required this.fullName,
    this.phone,
    this.status,
    this.source,
    this.interest,
  });

  final int id;
  final String fullName;
  final String? phone;
  final String? status;
  final String? source;
  final String? interest;

  factory _MasterSearchLead.fromJson(Map<String, dynamic> json) {
    return _MasterSearchLead(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString(),
      status: json['status']?.toString(),
      source: json['source']?.toString(),
      interest: json['interest']?.toString(),
    );
  }
}

class _MasterSearchInvoice {
  const _MasterSearchInvoice({
    required this.id,
    required this.invoiceNo,
    required this.total,
    required this.status,
    required this.memberName,
  });

  final int id;
  final String invoiceNo;
  final num total;
  final String status;
  final String memberName;

  factory _MasterSearchInvoice.fromJson(Map<String, dynamic> json) {
    num parseNum(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }

    return _MasterSearchInvoice(
      id: (json['id'] as num?)?.toInt() ?? 0,
      invoiceNo: json['invoiceNo']?.toString() ?? '',
      total: parseNum(json['total']),
      status: json['status']?.toString() ?? '',
      memberName: json['memberName']?.toString() ?? '',
    );
  }
}

class _NavDestination {
  const _NavDestination._(this.label, this.icon, this.route, this.isHeader);

  const _NavDestination.item(String label, IconData icon, String route) : this._(label, icon, route, false);

  const _NavDestination.header(String label) : this._(label, null, null, true);

  final String label;
  final IconData? icon;
  final String? route;
  final bool isHeader;
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.tenantLabel,
    required this.userName,
    required this.email,
    required this.roles,
    required this.selectedRoute,
    required this.destinations,
    required this.onGo,
  });

  final String tenantLabel;
  final String userName;
  final String email;
  final String roles;
  final String selectedRoute;
  final List<_NavDestination> destinations;
  final void Function(String route) onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tenantLabel, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(userName, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(email, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(roles, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final d in destinations)
                  if (d.isHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(
                        d.label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ListTile(
                      leading: Icon(d.icon),
                      selected: selectedRoute == d.route,
                      title: Text(d.label),
                      onTap: () {
                        Navigator.of(context).pop();
                        onGo(d.route!);
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopFrame extends StatelessWidget {
  const _DesktopFrame({
    required this.tenantLabel,
    required this.userName,
    required this.email,
    required this.initials,
    required this.pageTitle,
    required this.selectedRoute,
    required this.destinations,
    required this.onGo,
    required this.onLogout,
    required this.isDark,
    required this.onToggleTheme,
    required this.expiringAsync,
    required this.onOpenNotifications,
    required this.onOpenSearch,
    required this.onQuickAction,
    required this.child,
  });

  final String tenantLabel;
  final String userName;
  final String email;
  final String initials;
  final String pageTitle;
  final String selectedRoute;
  final List<_NavDestination> destinations;
  final void Function(String route) onGo;
  final VoidCallback onLogout;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final AsyncValue<List<ExpiringPreviewMember>> expiringAsync;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSearch;
  final void Function(QuickAction action) onQuickAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.obsidian : bg,
        gradient: isDark
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg, theme.colorScheme.surface],
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: isDark ? AppTheme.charcoal : theme.colorScheme.surface,
            // 5 % white border on the outer frame — shape only, no accent colour.
            border: Border.all(
              color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant,
              width: 0.8,
            ),
            boxShadow: isDark
                ? [
                    // Accent ambient glow stays in the shadow layer, not on the border.
                    BoxShadow(color: accent.withAlpha(12), blurRadius: 70, spreadRadius: 0, offset: const Offset(0, 24)),
                    BoxShadow(color: Colors.black.withAlpha(200), blurRadius: 44, spreadRadius: 0, offset: const Offset(0, 20)),
                  ]
                : [
                    BoxShadow(color: Colors.black.withAlpha(28), blurRadius: 40, spreadRadius: 0, offset: const Offset(0, 18)),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Row(
              children: [
                _Sidebar(
                  tenantLabel: tenantLabel,
                  userName: userName,
                  email: email,
                  initials: initials,
                  selectedRoute: selectedRoute,
                  destinations: destinations,
                  onGo: onGo,
                  onLogout: onLogout,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.obsidian.withAlpha(200)
                          : theme.colorScheme.surfaceContainerHighest.withAlpha(64),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          color: theme.scaffoldBackgroundColor,
                          child: Column(
                            children: [
                              _TopBar(
                                isDark: isDark,
                                onToggleTheme: onToggleTheme,
                                onOpenNotifications: onOpenNotifications,
                                onOpenSearch: onOpenSearch,
                                onQuickAction: onQuickAction,
                                expiringCount: expiringAsync.valueOrNull?.length ?? 0,
                              ),
                              Expanded(child: child),
                            ],
                          ),
                        ),
                      ),
                    ),
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tenantLabel,
    required this.userName,
    required this.email,
    required this.initials,
    required this.selectedRoute,
    required this.destinations,
    required this.onGo,
    required this.onLogout,
  });

  final String tenantLabel;
  final String userName;
  final String email;
  final String initials;
  final String selectedRoute;
  final List<_NavDestination> destinations;
  final void Function(String route) onGo;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.obsidian : theme.colorScheme.surfaceContainerHighest.withAlpha(77),
        border: Border(
          right: BorderSide(color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant, width: 0.8),
        ),
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D10), AppTheme.obsidian],
              )
            : null,
      ),
      child: Column(
        children: [
          // Premium brand header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: isDark ? AppTheme.borderSubtle : theme.colorScheme.outlineVariant, width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    // No border ring on the logo avatar — accent fill is enough.
                    // Neon glow removed; the avatar colour is the brand signal.
                  ),
                  child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bebas Neue lockup — "GYM MANAGEMENT" in brand tracking
                      Text(
                        'GYM MANAGEMENT',
                        style: AppTypography.brandTitle(color: theme.colorScheme.onSurface),
                      ),
                      // Inter for tenant slug — data text, must stay readable at 11 px
                      Text(
                        tenantLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.uiLabel(
                          color: isDark ? accent.withAlpha(160) : theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final d in destinations)
                  if (d.isHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                      child: Row(
                        children: [
                          Expanded(
                            // Nav group headers: Inter small-caps — legibility over brand.
                            child: Text(
                              d.label.toUpperCase(),
                              style: AppTypography.uiLabel(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                weight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _SidebarItem(
                      icon: d.icon!,
                      label: d.label,
                      selected: selectedRoute == d.route,
                      onTap: () => onGo(d.route!),
                    ),
              ],
            ),
          ),
          // User profile footer
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.charcoalHigh.withAlpha(200) : theme.colorScheme.surfaceContainerHighest.withAlpha(64),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.borderHover : theme.colorScheme.outlineVariant, width: 0.8),
                boxShadow: isDark ? [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 14, offset: const Offset(0, 6))] : [],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.withAlpha(isDark ? 40 : 30),
                  foregroundColor: accent,
                  child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: Text(userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Logout',
                  onPressed: onLogout,
                  icon: Icon(Icons.logout, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          // ── Corporate branding link, pinned to the sidebar base ──────────
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: PoweredByDeverosity(padding: EdgeInsets.symmetric(vertical: 8)),
          ),
        ],
      ),
    );
  }
}

// Sidebar item is stateful so it can track hover internally.
// No external wrapper needed — all hover logic lives here.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    // Only show hover state on non-selected items.
    final hover = _hover && !widget.selected;
    final iconColor = widget.selected ? accent : theme.colorScheme.onSurfaceVariant;
    final textColor = widget.selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
          // Suppress the default ink splash/highlight so the tile reads as
          // a flat solid fill, not a rippling Material surface.
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: isDark
                // Dark mode: white 5% tile on hover — no glow, no scale.
                ? AppTheme.sidebarItem(accent: accent, selected: widget.selected, hover: hover)
                // Light mode: black 4% tile on hover — matches Linear / Notion.
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
                    color: widget.selected
                        ? accent.withAlpha(22)
                        : hover
                            ? Colors.black.withAlpha(10) // ≈ black.withOpacity(0.04)
                            : Colors.transparent,
                    border: Border.all(
                      color: widget.selected ? accent.withAlpha(80) : Colors.transparent,
                      width: 0.8,
                    ),
                  ),
            child: Row(
              children: [
                // Selected-state accent pill (left edge).
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: widget.selected ? 20 : 0,
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: widget.selected && isDark
                        ? AppTheme.neonGlow(accent, blur: 8)
                        : const [],
                  ),
                ),
                SizedBox(width: widget.selected ? 10 : 14),
                Icon(widget.icon, color: iconColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: AppTypography.emphasisLabel(color: textColor).copyWith(
                      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: widget.selected ? 1.0 : 0.0,
                  child: Icon(Icons.chevron_right, color: iconColor, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isDark,
    required this.onToggleTheme,
    required this.onOpenNotifications,
    required this.onOpenSearch,
    required this.onQuickAction,
    required this.expiringCount,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSearch;
  final void Function(QuickAction action) onQuickAction;
  final int expiringCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark2 = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    return ClipRect(
      child: BackdropFilter(
        filter: isDark2 ? ImageFilter.blur(sigmaX: 12, sigmaY: 12) : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark2
                ? AppTheme.charcoal.withAlpha(220)
                : theme.colorScheme.surface.withAlpha(220),
            border: Border(
              bottom: BorderSide(
                color: isDark2 ? AppTheme.strokeSubtle : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshed')));
                },
                icon: Icon(Icons.refresh, color: theme.colorScheme.onSurfaceVariant),
              ),
              IconButton(
                tooltip: isDark ? 'Light theme' : 'Dark theme',
                onPressed: onToggleTheme,
                icon: Icon(
                  isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              _IconBadgeButton(
                tooltip: 'Notifications',
                icon: Icon(Icons.notifications_none, color: theme.colorScheme.onSurfaceVariant),
                badgeCount: expiringCount,
                onPressed: onOpenNotifications,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 260,
                child: TextField(
                  readOnly: true,
                  onTap: onOpenSearch,
                  decoration: InputDecoration(
                    hintText: 'Search members, leads…',
                    prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant, size: 20),
                    filled: true,
                    fillColor: isDark2 ? AppTheme.charcoalHigh.withAlpha(160) : null,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.mediumAll,
                      borderSide: BorderSide(color: isDark2 ? AppTheme.borderHover : theme.colorScheme.outlineVariant, width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.mediumAll,
                      borderSide: BorderSide(color: isDark2 ? AppTheme.borderHover : theme.colorScheme.outlineVariant, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppRadius.mediumAll,
                      borderSide: BorderSide(color: accent, width: 1.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _QuickActionsButton(onQuickAction: onQuickAction),
            ],
          ),
        ),
      ),
    );
  }
}

/// Global "+" Quick Actions popover — opens the four primary create modals from
/// anywhere in the app, matching the app design system (rounded 12px, line
/// icons, elegant separation).
class _QuickActionsButton extends StatelessWidget {
  const _QuickActionsButton({required this.onQuickAction});

  final void Function(QuickAction action) onQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    PopupMenuItem<QuickAction> row(
      QuickAction value,
      IconData icon,
      String title,
      String subtitle,
      Color tint,
    ) {
      return PopupMenuItem<QuickAction>(
        value: value,
        height: 56,
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: tint.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<QuickAction>(
      tooltip: 'Quick actions',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 12,
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.white.withAlpha(22) : Colors.black.withAlpha(16),
          width: 0.8,
        ),
      ),
      onSelected: onQuickAction,
      itemBuilder: (context) => [
        const PopupMenuItem<QuickAction>(
          enabled: false,
          height: 30,
          child: Text(
            'QUICK ACTIONS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
        ),
        row(QuickAction.addMember, Icons.person_add_alt_1_outlined, 'Add Member',
            'Register a new member', accent),
        row(QuickAction.addLead, Icons.person_search_outlined, 'Add Lead',
            'Capture a CRM enquiry', const Color(0xFF2563EB)),
        const PopupMenuDivider(),
        row(QuickAction.quickInvoice, Icons.receipt_long_outlined, 'Quick Invoice',
            'Auto-generate an invoice', const Color(0xFF10B981)),
        row(QuickAction.recordExpense, Icons.account_balance_wallet_outlined, 'Record Expense',
            'Log a business expense', const Color(0xFFF59E0B)),
      ],
      child: Container(
        height: 38,
        width: 38,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: accent.withAlpha(isDark ? 36 : 24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withAlpha(90)),
        ),
        child: Icon(Icons.add, size: 20, color: accent),
      ),
    );
  }
}

class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({
    required this.tooltip,
    required this.icon,
    required this.badgeCount,
    required this.onPressed,
  });

  final String tooltip;
  final Widget icon;
  final int badgeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
        ),
        if (badgeCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

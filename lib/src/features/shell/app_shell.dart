import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
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

    final tenantLabel = auth.user?.tenantSlug.isNotEmpty == true ? 'Gym (${auth.user!.tenantSlug})' : 'Gym';
    void toggleTheme() {
      ref.read(themeModeProvider.notifier).setMode(isDark ? ThemeMode.light : ThemeMode.dark);
    }
    void openExpiringDialog() {
      final items = expiringAsync.valueOrNull ?? const <ExpiringPreviewMember>[];
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Expiry Alerts (3 days)'),
            content: SizedBox(
              width: 420,
              child: items.isEmpty
                  ? const Text('No expiring memberships.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = items[i];
                        return ListTile(
                          dense: true,
                          title: Text('${m.fullName} (${m.memberCode})'),
                          subtitle: Text('Expiry: ${m.endDate} • ${m.daysLeft} days left'),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.go('/members');
                          },
                        );
                      },
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
      final ctrl = TextEditingController();
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Search'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search member (name / code / phone)',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (v) {
                Navigator.of(context).pop();
                final q = v.trim();
                if (q.isEmpty) return;
                context.go('/members?q=$q');
              },
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  final q = ctrl.text.trim();
                  if (q.isEmpty) return;
                  context.go('/members?q=$q');
                },
                child: const Text('Search'),
              ),
            ],
          );
        },
      ).whenComplete(ctrl.dispose);
    }

    final roleList = auth.user?.roles ?? const <String>[];
    final canSeeRevenue = roleList.contains('owner') || roleList.contains('admin') || roleList.contains('super_admin');
    final canManageStaff = roleList.contains('owner') || roleList.contains('admin') || roleList.contains('super_admin');
    final canSeeSettings = roleList.contains('owner') || roleList.contains('admin') || roleList.contains('super_admin');

    final destinations = <_NavDestination>[
      const _NavDestination('Dashboard', Icons.dashboard, '/dashboard'),
      const _NavDestination('Members', Icons.people, '/members'),
      const _NavDestination('Plans', Icons.card_membership, '/plans'),
      const _NavDestination('Attendance', Icons.how_to_reg, '/attendance'),
      if (canSeeRevenue) const _NavDestination('Invoices', Icons.receipt_long, '/invoices'),
      if (canSeeRevenue) const _NavDestination('Payments', Icons.payments, '/payments'),
      if (canSeeRevenue) const _NavDestination('Expenses', Icons.account_balance_wallet, '/expenses'),
      const _NavDestination('Inventory', Icons.inventory_2, '/inventory'),
      if (canSeeRevenue) const _NavDestination('Reports', Icons.bar_chart, '/reports'),
      if (canManageStaff) const _NavDestination('Staff', Icons.badge, '/staff'),
      if (canSeeSettings) const _NavDestination('Settings', Icons.settings, '/settings'),
    ];

    final selectedIndex = destinations.indexWhere((d) => d.route == location);
    final pageTitle = selectedIndex >= 0 ? destinations[selectedIndex].label : 'Dashboard';

    final userName = auth.user?.fullName ?? 'User';
    final initials = userName.trim().isEmpty
        ? 'U'
        : userName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
            .join();

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 900;

        if (!useRail) {
          return Scaffold(
            appBar: AppBar(
              title: Text('$tenantLabel — $pageTitle'),
              actions: [
                _IconBadgeButton(
                  tooltip: 'Notifications',
                  icon: const Icon(Icons.notifications_none),
                  badgeCount: expiringAsync.valueOrNull?.length ?? 0,
                  onPressed: openExpiringDialog,
                ),
                IconButton(
                  tooltip: isDark ? 'Light theme' : 'Dark theme',
                  onPressed: toggleTheme,
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                ),
                IconButton(
                  tooltip: 'Search',
                  onPressed: openGlobalSearch,
                  icon: const Icon(Icons.search),
                ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: CircleAvatar(
                      radius: 16,
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
            child: child,
          ),
        );
      },
    );
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
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
                  ListTile(
                    leading: Icon(d.icon),
                    selected: selectedRoute == d.route,
                    title: Text(d.label),
                    onTap: () {
                      Navigator.of(context).pop();
                      onGo(d.route);
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
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bg,
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: theme.brightness == Brightness.dark
                        ? Colors.black.withAlpha(115)
                        : Colors.black.withAlpha(30),
                    blurRadius: 40,
                    spreadRadius: 0,
                    offset: const Offset(0, 18),
                  ),
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
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(64),
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
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(77),
        border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: const Icon(Icons.fitness_center),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Gym Listing', style: theme.textTheme.titleMedium),
                      Text(
                        tenantLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final d in destinations)
                  _SidebarItem(
                    icon: d.icon,
                    label: d.label,
                    selected: selectedRoute == d.route,
                    onTap: () => onGo(d.route),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(64),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                leading: CircleAvatar(child: Text(initials)),
                title: Text(userName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Logout',
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected ? theme.colorScheme.tertiary.withAlpha(36) : theme.colorScheme.surface.withAlpha(28);
    final iconColor = selected ? theme.colorScheme.tertiary : theme.colorScheme.onSurfaceVariant;
    final textColor = selected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant;
    return _HoverScale(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                if (selected)
                  Container(
                    height: 18,
                    width: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  )
                else
                  const SizedBox(width: 4),
                const SizedBox(width: 10),
                Icon(icon, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                  ),
                ),
                if (selected) Icon(Icons.chevron_right, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({required this.child, required this.selected});

  final Widget child;
  final bool selected;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hover = _hover && !widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        scale: hover ? 1.02 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            boxShadow: hover
                ? [
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withAlpha(38),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : const [],
            borderRadius: BorderRadius.circular(14),
          ),
          child: widget.child,
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
    required this.expiringCount,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSearch;
  final int expiringCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(210),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshed')));
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: isDark ? 'Light theme' : 'Dark theme',
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
          ),
          _IconBadgeButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none),
            badgeCount: expiringCount,
            onPressed: onOpenNotifications,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 260,
            child: TextField(
              readOnly: true,
              onTap: onOpenSearch,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Add',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Use Add button inside Members/Plans/Invoices screens')),
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
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

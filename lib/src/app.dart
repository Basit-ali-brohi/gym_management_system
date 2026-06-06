import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/app_theme.dart';
import 'core/providers.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/billing/invoices_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/leads/leads_screen.dart';
import 'features/members/members_screen.dart';
import 'features/payments/payments_screen.dart';
import 'features/plans/plans_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/settings/settings_screen.dart';
import 'features/staff/staff_screen.dart';

final routerNotifierProvider = Provider<RouterNotifier>((ref) => RouterNotifier(ref));

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);
  return GoRouter(
    refreshListenable: notifier,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final isLoggingIn = state.matchedLocation == '/login';
      if (auth.isLoading) return null;
      if (!auth.isAuthenticated && !isLoggingIn) return '/login';
      if (auth.isAuthenticated && isLoggingIn) return '/dashboard';

      final location = state.matchedLocation;
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

      if (!canSeeRevenue && (location == '/invoices' || location == '/payments' || location == '/expenses' || location == '/reports')) {
        return '/dashboard';
      }
      if (!canSeeInventory && location == '/inventory') return '/dashboard';
      if (!canManageStaff && location == '/staff') return '/dashboard';
      if (!canSeeSettings && location == '/settings') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadePage(state, const LoginScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _fadePage(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/leads',
            pageBuilder: (context, state) => _fadePage(state, const LeadsScreen()),
          ),
          GoRoute(
            path: '/members',
            pageBuilder: (context, state) => _fadePage(state, const MembersScreen()),
          ),
          GoRoute(
            path: '/plans',
            pageBuilder: (context, state) => _fadePage(state, const PlansScreen()),
          ),
          GoRoute(
            path: '/attendance',
            pageBuilder: (context, state) => _fadePage(state, const AttendanceScreen()),
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) => _fadePage(state, const InvoicesScreen()),
          ),
          GoRoute(
            path: '/payments',
            pageBuilder: (context, state) => _fadePage(state, const PaymentsScreen()),
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (context, state) => _fadePage(state, const ExpensesScreen()),
          ),
          GoRoute(
            path: '/inventory',
            pageBuilder: (context, state) => _fadePage(state, const InventoryScreen()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => _fadePage(state, const ReportsScreen()),
          ),
          GoRoute(
            path: '/staff',
            pageBuilder: (context, state) => _fadePage(state, const StaffScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _fadePage(state, const SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Dual-font text theme
//
// Strategy — two-pass construction:
//   Pass 1: GoogleFonts.interTextTheme(base) — Inter owns every slot.
//   Pass 2: .copyWith() — Bebas Neue replaces the display / headline / title
//           roles that carry KPI numbers and section labels.
//
// Why Bebas Neue for headlineSmall?
//   The KPI metric values (revenue, check-ins) use headlineSmall in widget
//   code. Bebas Neue at that size with 2.0 tracking reads as a scoreboard
//   digit — immediately scannable from across a room, matching the gym brand.
//
// Why Inter for everything else?
//   Inter is a humanist sans designed for sub-16px legibility on screens.
//   Member names, dates, table rows, and form fields all stay readable in
//   the dark theme at their small sizes because Inter was built for it.
// ─────────────────────────────────────────────────────────────────────────────
TextTheme _buildMixedTextTheme(TextTheme base) {
  // Pass 1: Inter base — all slots get the screen-optimised humanist face.
  final inter = GoogleFonts.interTextTheme(base);

  // Pass 2: Bebas Neue overlay on heading and KPI-display slots only.
  return inter.copyWith(
    // ── Large display (hero numbers, future full-screen KPIs) ───────────────
    displayLarge:  GoogleFonts.bebasNeue(textStyle: inter.displayLarge,  letterSpacing: 2.0),
    displayMedium: GoogleFonts.bebasNeue(textStyle: inter.displayMedium, letterSpacing: 2.0),
    displaySmall:  GoogleFonts.bebasNeue(textStyle: inter.displaySmall,  letterSpacing: 1.8),
    // ── Headline (KPI values — revenue, member counts, check-ins) ───────────
    headlineLarge:  GoogleFonts.bebasNeue(textStyle: inter.headlineLarge,  letterSpacing: 2.0),
    headlineMedium: GoogleFonts.bebasNeue(textStyle: inter.headlineMedium, letterSpacing: 2.0),
    headlineSmall:  GoogleFonts.bebasNeue(textStyle: inter.headlineSmall,  letterSpacing: 2.0, height: 1.05),
    // ── Title (section labels and sidebar brand) ─────────────────────────────
    // titleLarge  → sidebar "GYM MANAGEMENT" lockup + chart primary headers
    titleLarge:  GoogleFonts.bebasNeue(textStyle: inter.titleLarge,  letterSpacing: 3.0),
    // titleMedium → section titles ("QUICK ACTIONS", "AT-RISK MEMBERS")
    titleMedium: GoogleFonts.bebasNeue(textStyle: inter.titleMedium, letterSpacing: 2.5),
    // titleSmall stays Inter — used for member names and list row titles
    // where legibility at 14 px matters more than brand presence.
    // ── Inter data labels (keep light weight contrast for hierarchy) ─────────
    labelLarge:  inter.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: inter.labelMedium?.copyWith(fontWeight: FontWeight.w500),
  );
}

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.ref) {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.isAuthenticated != next.isAuthenticated || prev?.isLoading != next.isLoading) {
        notifyListeners();
      }
    });
  }

  final Ref ref;
}

class GymSaasApp extends ConsumerWidget {
  const GymSaasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);
    final isAccentDark = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark;
    final onAccentDark = isAccentDark ? Colors.white : const Color(0xFF0B0F14);
    final onAccentLight = isAccentDark ? Colors.white : const Color(0xFF121212);
    const obsidian = Color(0xFF0B0B0C);   // deep obsidian black canvas
    const surface = Color(0xFF16161A);    // rich charcoal container surface
  
    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccentDark,
      secondary: accent,
      onSecondary: onAccentDark,
      error: Color(0xFFFF5C5C),
      onError: Color(0xFF0B0F14),
      surface: surface,
      onSurface: Color(0xFFEAECEF),
      surfaceContainerHighest: Color(0xFF1E1E24),
      onSurfaceVariant: Color(0xFFAAB4C8),
      outline: Color(0xFF2F2F3D),
      outlineVariant: Color(0xFF252530),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFEAECEF),
      onInverseSurface: Color(0xFF0B0B0C),
      inversePrimary: accent,
      tertiary: Color(0xFF10B981),      // electric emerald — health/active metrics
      onTertiary: Color(0xFF071F16),
    );

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: accent,
      onPrimary: onAccentLight,
      secondary: accent,
      onSecondary: onAccentLight,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF15181E),
      surfaceContainerHighest: Color(0xFFF4F5F7),
      onSurfaceVariant: Color(0xFF4B5563),
      outline: Color(0xFFE5E7EB),
      outlineVariant: Color(0xFFD1D5DB),
      shadow: Color(0x22000000),
      scrim: Colors.black,
      inverseSurface: Color(0xFF15181E),
      onInverseSurface: Colors.white,
      inversePrimary: accent,
      tertiary: Color(0xFF0F766E),
      onTertiary: Colors.white,
    );

    // Dual-font text themes: Bebas Neue for display/headline/title,
    // Inter for body/label/data. See _buildMixedTextTheme() above.
    final tunedLightText = _buildMixedTextTheme(
      ThemeData(useMaterial3: true, colorScheme: lightScheme).textTheme,
    );
    final tunedDarkText = _buildMixedTextTheme(
      ThemeData(useMaterial3: true, colorScheme: darkScheme).textTheme,
    );

    const darkCardColor = Color(0xFF16161A); // solid charcoal — opaque above obsidian canvas

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Gym Management',
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeAnimationCurve: Curves.easeInOut,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        textTheme: tunedLightText,
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        canvasColor: Colors.white,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 2,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: BorderSide(color: lightScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        shadowColor: Colors.black.withAlpha(30),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: BorderSide(color: lightScheme.outlineVariant),
          ),
        ),
        dividerTheme: DividerThemeData(color: lightScheme.outlineVariant),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F2F4),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: BorderSide(color: lightScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: BorderSide(color: lightScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: BorderSide(color: accent, width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 44),
            backgroundColor: accent,
            foregroundColor: onAccentLight,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: lightScheme.inverseSurface,
          contentTextStyle: tunedLightText.bodyMedium?.copyWith(color: lightScheme.onInverseSurface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dataTableTheme: const DataTableThemeData(
          headingRowHeight: 44,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: lightScheme.onSurface),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          backgroundColor: const Color(0xFFF1F2F4),
          side: BorderSide(color: lightScheme.outlineVariant),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        textTheme: tunedDarkText,
        scaffoldBackgroundColor: obsidian,
        canvasColor: obsidian,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          color: darkCardColor,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            // 5 % white border — gives shape without adding colour noise.
            side: const BorderSide(color: Color(0x0DFFFFFF), width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        shadowColor: Colors.black.withAlpha(140),
        dialogTheme: DialogThemeData(
          backgroundColor: surface.withAlpha(235),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: const BorderSide(color: Color(0x14FFFFFF), width: 0.8),
          ),
        ),
        dividerTheme: const DividerThemeData(color: Color(0x0DFFFFFF), thickness: 1, space: 1),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0x18FFFFFF),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: Color(0x14FFFFFF), width: 0.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: Color(0x14FFFFFF), width: 0.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: BorderSide(color: accent, width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 44),
            backgroundColor: accent,
            foregroundColor: onAccentDark,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkScheme.inverseSurface,
          contentTextStyle: tunedDarkText.bodyMedium?.copyWith(color: darkScheme.onInverseSurface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowHeight: 44,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFF1E1E24)),
          dividerThickness: 0.6,
          headingTextStyle: tunedDarkText.labelLarge?.copyWith(color: darkScheme.onSurfaceVariant),
          dataTextStyle: tunedDarkText.bodyMedium?.copyWith(color: darkScheme.onSurface),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: darkScheme.onSurface),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          backgroundColor: const Color(0xFF1E1E24),
          side: const BorderSide(color: Color(0x14FFFFFF), width: 0.8),
          labelStyle: tunedDarkText.labelMedium?.copyWith(color: darkScheme.onSurface),
          secondaryLabelStyle: tunedDarkText.labelMedium?.copyWith(color: darkScheme.onSurface),
        ),
      ),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

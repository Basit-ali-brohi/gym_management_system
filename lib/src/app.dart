import 'package:animations/animations.dart';
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
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Native-feeling fade-through between routes (Material motion).
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
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
// "Gym Floor" text theme
//
// Strategy — two-pass construction:
//   Pass 1: GoogleFonts.archivoTextTheme(base) — Archivo owns every slot; it's
//           the workhorse face for buttons, list rows, descriptions, labels.
//   Pass 2: .copyWith() — Oswald (condensed, uppercase-styled) replaces the
//           display / headline / title roles — page titles, section headers,
//           KPI headline text. Reads like gym signage / locker-room lettering.
//
// NOTE: the actual scoreboard NUMERALS (stat values, currency, dates, IDs,
// percentages) do not come from this text theme at all — they always render
// via [AppTypography.mono] (JetBrains Mono) at the call site, per the firm
// "every number is mono" rule. This theme only covers prose/label text.
// ─────────────────────────────────────────────────────────────────────────────
TextTheme _buildMixedTextTheme(TextTheme base) {
  // Pass 1: Archivo base — all slots get the workhorse UI face.
  final body = GoogleFonts.archivoTextTheme(base);

  // Pass 2: Oswald overlay on display / headline / title slots.
  TextStyle? oswald(TextStyle? s, {double ls = 0.3, double? height}) => s?.copyWith(
        fontFamily: AppTypography.displayFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: ls,
        height: height,
      );

  return body.copyWith(
    // ── Large display (hero numbers, full-screen KPIs) ──────────────────────
    displayLarge: oswald(body.displayLarge, ls: 0.4),
    displayMedium: oswald(body.displayMedium, ls: 0.4),
    displaySmall: oswald(body.displaySmall, ls: 0.3),
    // ── Headline (page titles, KPI headline text) ───────────────────────────
    headlineLarge: oswald(body.headlineLarge, ls: 0.3),
    headlineMedium: oswald(body.headlineMedium, ls: 0.3),
    headlineSmall: oswald(body.headlineSmall, ls: 0.3, height: 1.05),
    // ── Title (section labels and sidebar brand) ────────────────────────────
    titleLarge: oswald(body.titleLarge, ls: 0.4),
    titleMedium: oswald(body.titleMedium, ls: 0.3),
    // titleSmall stays Archivo — member names / list titles (legibility first).
    labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: body.labelMedium?.copyWith(fontWeight: FontWeight.w500),
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
    // Brief default: solid ember bg + dark (--charcoal) text. The dynamic
    // contrast check is kept so a user-picked custom accent colour never ends
    // up with unreadable text.
    final onAccentDark = isAccentDark ? Colors.white : AppTheme.obsidian;
    final onAccentLight = isAccentDark ? Colors.white : AppTheme.ink;
    const obsidian = AppTheme.obsidian; // dark chrome / canvas (#15171B)
    const surface = AppTheme.charcoal; // dark card surface (#1D2024)

    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccentDark,
      secondary: accent,
      onSecondary: onAccentDark,
      error: AppTheme.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: Color(0xFFECEDEE),
      surfaceContainerHighest: AppTheme.charcoalHigh,
      onSurfaceVariant: Color(0xFF9BA1A8),
      outline: AppTheme.borderHover,
      outlineVariant: AppTheme.borderSubtle,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFEAECEE),
      onInverseSurface: Color(0xFF0B0B0C),
      inversePrimary: accent,
      tertiary: Color(0xFF2F8F7E), // spotter teal, lifted for dark-bg legibility
      onTertiary: Color(0xFF07211C),
    );

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: accent,
      onPrimary: onAccentLight,
      secondary: accent,
      onSecondary: onAccentLight,
      error: AppTheme.danger,
      onError: Colors.white,
      surface: AppTheme.card,
      onSurface: AppTheme.ink,
      surfaceContainerHighest: AppTheme.ironSoft,
      onSurfaceVariant: AppTheme.muted,
      outline: AppTheme.line,
      outlineVariant: AppTheme.line,
      shadow: Color(0x14000000),
      scrim: Colors.black,
      inverseSurface: AppTheme.ink,
      onInverseSurface: Colors.white,
      inversePrimary: accent,
      tertiary: AppTheme.emerald, // spotter teal — membership/active category
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

    const darkCardColor = AppTheme.charcoal; // solid dark card surface above the obsidian canvas

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Gym Management',
      themeAnimationDuration: const Duration(milliseconds: 260),
      themeAnimationCurve: Curves.easeInOut,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        textTheme: tunedLightText,
        scaffoldBackgroundColor: AppTheme.canvas,
        canvasColor: AppTheme.canvas,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        appBarTheme: const AppBarTheme(centerTitle: false),
        // Flat and utilitarian, like gym equipment — no shadow, tight radius.
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppTheme.card,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: BorderSide(color: AppTheme.line),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        shadowColor: Colors.transparent,
        dialogTheme: DialogThemeData(
          backgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: BorderSide(color: AppTheme.line),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppTheme.line),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F7F3),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: AppTheme.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: AppTheme.line),
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
            textStyle: AppTypography.emphasisLabel(color: onAccentLight, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: lightScheme.inverseSurface,
          contentTextStyle: tunedLightText.bodyMedium?.copyWith(color: lightScheme.onInverseSurface),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
        ),
        dataTableTheme: const DataTableThemeData(
          headingRowHeight: 44,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: lightScheme.onSurface),
        ),
        // Tight radius everywhere, including "pill" chips — this system never
        // uses the soft 12px+ bubble radius of generic SaaS UI.
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
          backgroundColor: AppTheme.ironSoft,
          side: const BorderSide(color: AppTheme.line),
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
            side: const BorderSide(color: AppTheme.borderSubtle, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        shadowColor: Colors.transparent,
        dialogTheme: DialogThemeData(
          backgroundColor: surface.withAlpha(235),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.largeAll,
            side: const BorderSide(color: AppTheme.borderHover, width: 0.8),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppTheme.borderSubtle, thickness: 1, space: 1),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0x18FFFFFF),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: AppTheme.borderHover, width: 0.8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mediumAll,
            borderSide: const BorderSide(color: AppTheme.borderHover, width: 0.8),
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
            textStyle: AppTypography.emphasisLabel(color: onAccentDark, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkScheme.inverseSurface,
          contentTextStyle: tunedDarkText.bodyMedium?.copyWith(color: darkScheme.onInverseSurface),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
        ),
        dataTableTheme: DataTableThemeData(
          headingRowHeight: 44,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          headingRowColor: const WidgetStatePropertyAll(AppTheme.charcoalHigh),
          dividerThickness: 0.6,
          headingTextStyle: tunedDarkText.labelLarge?.copyWith(color: darkScheme.onSurfaceVariant),
          dataTextStyle: tunedDarkText.bodyMedium?.copyWith(color: darkScheme.onSurface),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: darkScheme.onSurface),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smallAll),
          backgroundColor: AppTheme.charcoalHigh,
          side: const BorderSide(color: AppTheme.borderHover, width: 0.8),
          labelStyle: tunedDarkText.labelMedium?.copyWith(color: darkScheme.onSurface),
          secondaryLabelStyle: tunedDarkText.labelMedium?.copyWith(color: darkScheme.onSurface),
        ),
      ),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

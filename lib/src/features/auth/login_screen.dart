import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/providers.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Debug-only auto-fill of the demo credentials so QA / dev can hit "Login"
  // directly. `kDebugMode` is a compile-time `false` in release builds, so the
  // literals below are tree-shaken away — production boots with empty, secure
  // fields. (kDebugMode comes from foundation.dart, re-exported by material.dart,
  // so no extra import is needed.)
  final _tenantCtrl = TextEditingController(text: kDebugMode ? 'demo' : '');
  final _emailCtrl = TextEditingController(text: kDebugMode ? 'admin@demo.com' : '');
  final _passCtrl = TextEditingController(text: kDebugMode ? 'admin123' : '');
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _tenantCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Safely launches the Deverosity branding site in the OS default browser,
  /// with fallback validation so a failed launch never crashes the login view.
  Future<void> _launchBrandingUrl() async {
    final Uri url = Uri.parse('https://deverosity.com/');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      debugPrint('URL Launch Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    final errorText = switch (auth.error) {
      null => null,
      'invalid_credentials' => 'Invalid tenant, email, or password',
      'unauthorized' => 'Login unauthorized',
      'login_failed' => 'Cannot connect to server ($apiBaseUrl). Check the API URL/port and ensure the backend is running.',
      _ => auth.error,
    };

    final accent = theme.colorScheme.primary;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    // Light-mode console palette — crisp professional slate.
    const lightPanelBg = Color(0xFFF4F6F8);
    const lightCard = Colors.white;
    const lightFieldFill = Color(0xFFEEF2F6);
    const lightBorder = Color(0xFFD7DEE7);

    // Shared Inter input decoration with an accent focus border (theme-aware).
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) {
      OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c, width: w),
          );
      final restBorder = isDark ? AppTheme.borderHover : lightBorder;
      return InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
        floatingLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: accent),
        prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        suffixIcon: suffix,
        filled: true,
        fillColor: isDark ? AppTheme.charcoalHigh.withAlpha(170) : lightFieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: b(restBorder, 0.8),
        enabledBorder: b(restBorder, 0.8),
        focusedBorder: b(accent, 1.4),
      );
    }

    Future<void> submit() async {
      if (auth.isLoading) return;
      if (!(_formKey.currentState?.validate() ?? false)) return;
      await ref.read(authControllerProvider.notifier).login(
            tenantSlug: _tenantCtrl.text,
            email: _emailCtrl.text,
            password: _passCtrl.text,
          );
    }

    Widget formCard() {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isDark ? AppTheme.charcoal : lightCard,
            border: Border.all(color: isDark ? AppTheme.borderSubtle : lightBorder, width: 0.8),
            boxShadow: isDark
                ? [
                    BoxShadow(color: Colors.black.withAlpha(130), blurRadius: 44, offset: const Offset(0, 22)),
                    BoxShadow(color: accent.withAlpha(14), blurRadius: 60, offset: const Offset(0, 24)),
                  ]
                : [
                    BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 32, offset: const Offset(0, 16)),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                          boxShadow: AppTheme.neonGlow(accent, blur: 14),
                        ),
                        child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GYM MANAGEMENT', style: AppTypography.brandTitle(color: theme.colorScheme.onSurface)),
                            const SizedBox(height: 2),
                            Text(
                              'Sign in to continue',
                              style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _GlowField(
                    child: TextFormField(
                      controller: _tenantCtrl,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: deco('Tenant / Gym Code', Icons.apartment_outlined),
                      validator: (v) => (v == null || v.trim().length < 2) ? 'Tenant required' : null,
                      enabled: !auth.isLoading,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GlowField(
                    child: TextFormField(
                      controller: _emailCtrl,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: deco('Email', Icons.alternate_email),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                      enabled: !auth.isLoading,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GlowField(
                    child: TextFormField(
                      controller: _passCtrl,
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: deco(
                        'Password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: auth.isLoading ? null : () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 20, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      obscureText: _obscure,
                      validator: (v) => (v == null || v.isEmpty) ? 'Password required' : null,
                      enabled: !auth.isLoading,
                      onFieldSubmitted: (_) => submit(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.error.withAlpha(70), width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(errorText, style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurface)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: auth.isLoading ? null : submit,
                      style: FilledButton.styleFrom(
                        textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Login'),
                    ),
                  ),
                  // ── Interactive "Powered by Deverosity" footer badge ──────
                  Center(
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _launchBrandingUrl,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              children: [
                                const TextSpan(text: 'Powered by '),
                                TextSpan(
                                  text: 'Deverosity',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFF7A00),
                                    decoration: TextDecoration.underline,
                                    decorationColor: const Color(0xFFFF7A00).withValues(alpha: 0.5),
                                  ),
                                ),
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

    // Smoky emerald bloom over obsidian for the left aesthetic panel.
    final smoky = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.45, 1.0],
      colors: [
        theme.colorScheme.tertiary.withAlpha(40),
        theme.colorScheme.tertiary.withAlpha(12),
        AppTheme.obsidian,
      ],
    );

    Widget brandPanel() {
      return Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: BoxDecoration(gradient: smoky)),
          // Soft emerald radial bloom, top-left.
          Positioned(
            left: -120,
            top: -80,
            child: Container(
              height: 360,
              width: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [theme.colorScheme.tertiary.withAlpha(38), Colors.transparent],
                ),
              ),
            ),
          ),
          // ── Seam fade: graphic dissolves into obsidian on the right edge ──
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x000B0B0C), AppTheme.obsidian],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display headline stays Bebas Neue (uppercase scoreboard feel).
                    // Always light — the left graphic stays dark in both themes.
                    Text(
                      'RUN YOUR GYM\nLIKE A BUSINESS',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.95),
                        height: 1.02,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Sub-headline: clean sentence case, Inter, dimmed for hierarchy.
                    Text(
                      'Members, leads, billing, attendance, inventory and reports — '
                      'all in one unified dashboard.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        height: 1.5,
                        letterSpacing: 0.3,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // ── Minimalist feature grid (2 rows × 3) ──────────────────
                    const _FeatureGrid(),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.obsidian,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 980;

          if (!wide) {
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(decoration: BoxDecoration(gradient: smoky)),
                Center(child: Padding(padding: const EdgeInsets.all(20), child: formCard())),
                // Global theme utility — top-right.
                const Positioned(top: 24, right: 24, child: _ThemeToggle()),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 7, child: brandPanel()),
              // Right console: obsidian in dark, crisp slate in light.
              SizedBox(
                width: 480,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: isDark ? AppTheme.obsidian : lightPanelBg),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: formCard()),
                    ),
                    // Theme toggle pinned to the absolute top-right of this panel.
                    const Positioned(top: 24, right: 24, child: _ThemeToggle()),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Minimalist floating theme toggle bound to [themeModeProvider].
/// Shows a moon in dark mode, a sun in light mode, with a soft hover glow.
class _ThemeToggle extends ConsumerStatefulWidget {
  const _ThemeToggle();

  @override
  ConsumerState<_ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends ConsumerState<_ThemeToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    // Warm amber glow for the moon; accent glow for the sun.
    final glow = isDark ? const Color(0xFFE5A93C) : const Color(0xFFF59E0B);
    final fg = isDark ? const Color(0xFFFFD8A0) : const Color(0xFFF59E0B);

    return Tooltip(
      message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => ref
              .read(themeModeProvider.notifier)
              .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withAlpha(_hover ? 20 : 10)
                  : Colors.black.withAlpha(_hover ? 12 : 6),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(_hover ? 45 : 22)
                    : Colors.black.withAlpha(_hover ? 32 : 18),
                width: 0.8,
              ),
              boxShadow: _hover ? AppTheme.neonGlow(glow, blur: 14) : const [],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.7, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                key: ValueKey<bool>(isDark),
                size: 20,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tracks descendant focus and adds an accent glow ring around a form field.
class _GlowField extends StatefulWidget {
  const _GlowField({required this.child});

  final Widget child;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        if (f != _focused) setState(() => _focused = f);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _focused ? AppTheme.neonGlow(accent, blur: 14) : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Minimalist 2×3 feature grid for the brand panel.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.people_alt_outlined, label: 'Members'),
    (icon: Icons.person_search_outlined, label: 'Leads'),
    (icon: Icons.receipt_long_outlined, label: 'Invoices'),
    (icon: Icons.how_to_reg_outlined, label: 'Attendance'),
    (icon: Icons.inventory_2_outlined, label: 'Inventory'),
    (icon: Icons.bar_chart_outlined, label: 'Reports'),
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        children: [
          for (var r = 0; r < _items.length; r += 3)
            Padding(
              padding: EdgeInsets.only(bottom: r + 3 < _items.length ? 14 : 0),
              child: Row(
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 14),
                    Expanded(
                      child: (r + col) < _items.length
                          ? _FeatureItem(icon: _items[r + col].icon, label: _items[r + col].label)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
          ),
          child: Icon(icon, size: 17, color: theme.colorScheme.tertiary),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }
}


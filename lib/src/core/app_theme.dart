// Central design-token registry for the Obsidian × Gold × Emerald ERP theme.
// Import this file for consistent styling across the entire app.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global border-radius scale for the enterprise desktop SaaS aesthetic.
///
/// Sharp, precise corners — not soft mobile bubbles. Use these tokens instead
/// of magic numbers so the geometry stays standardized app-wide:
///   • [large]  (14) — section blocks, grid/profile cards, container wrappers,
///                     panels, and modal dialogs.
///   • [medium] (8)  — form text fields, search bars, inline inputs.
///   • [small]  (6)  — dense table rows, status badges, role tags, chips.
///   • [pill]   (999) — intentional pill shapes (filter/tab selectors, avatars)
///                      — EXCLUDED from the sharpening pass.
abstract final class AppRadius {
  static const double small = 6;
  static const double medium = 8;
  static const double large = 14;
  static const double pill = 999;

  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumAll = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeAll = BorderRadius.all(Radius.circular(large));
}

abstract final class AppTheme {
  // ── CANVAS PALETTE ──────────────────────────────────────────────────────────
  /// Primary canvas — pure obsidian black.
  static const Color obsidian = Color(0xFF0B0B0C);

  /// Card / container surface — rich charcoal.
  static const Color charcoal = Color(0xFF16161A);

  /// Elevated surface for hover states and active rows.
  static const Color charcoalHigh = Color(0xFF1E1E24);

  // ── TRANSLUCENT BORDER SYSTEM (Linear / Vercel standard) ────────────────────
  /// Default card border — 5 % white. Gives shape without competing with content.
  static const Color borderSubtle = Color(0x0DFFFFFF);   // white  5 %

  /// Hover / focus card border — 8 % white shimmer.
  static const Color borderHover  = Color(0x14FFFFFF);   // white  8 %

  /// Accent border override — used only for explicitly selected states.
  /// Never apply to at-rest containers (keeps accent reserved for data).
  static const Color borderFocus  = Color(0x40FFFFFF);   // white 25 % (keyboard focus ring)

  /// Legacy opaque strokes — kept for light-mode fallbacks only.
  static const Color strokeSubtle = Color(0xFF252530);
  static const Color strokeNormal = Color(0xFF2F2F3D);

  // ── ACCENT PALETTE ──────────────────────────────────────────────────────────
  /// Burnished premium gold — financial metrics, VIP highlights, primary buttons.
  static const Color gold = Color(0xFFD4AF37);

  /// Warm gold gradient variant for shine effects.
  static const Color goldWarm = Color(0xFFE5A93C);

  /// Rich emerald — active member indicators, health metrics, successful check-ins.
  static const Color emerald = Color(0xFF10B981);

  /// Neon emerald — high-contrast active arcs and live status indicators.
  static const Color emeraldNeon = Color(0xFF00E676);

  /// Amber — at-risk warnings, pending alerts.
  static const Color alertAmber = Color(0xFFF59E0B);

  /// Danger red — errors, expired states.
  static const Color danger = Color(0xFFFF5C5C);

  // ── GLOW UTILITIES ──────────────────────────────────────────────────────────

  /// Two-layer neon glow for any element: tight core + wide diffuse halo.
  static List<BoxShadow> neonGlow(
    Color color, {
    double blur = 20,
    double spread = 0,
    Offset offset = Offset.zero,
  }) =>
      [
        BoxShadow(
          color: color.withAlpha(52),
          blurRadius: blur,
          spreadRadius: spread,
          offset: offset,
        ),
        BoxShadow(
          color: color.withAlpha(22),
          blurRadius: blur * 2.4,
          spreadRadius: spread * 0.5,
          offset: offset,
        ),
      ];

  /// Standard card shadow — accent-colored glow on hover, plain depth at rest.
  static List<BoxShadow> cardShadow({Color? accent, bool hover = false}) => [
        if (accent != null && hover)
          BoxShadow(
            color: accent.withAlpha(60),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        BoxShadow(
          color: Colors.black.withAlpha(hover ? 125 : 78),
          blurRadius: hover ? 34 : 22,
          offset: Offset(0, hover ? 18 : 10),
        ),
      ];

  // ── COMPONENT DECORATIONS ────────────────────────────────────────────────────

  /// Square icon container with accent fill and border glow.
  static BoxDecoration iconBox({
    required Color color,
    bool hover = false,
    double radius = 14,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: color.withAlpha(hover ? 56 : 32),
        border: Border.all(
          color: color.withAlpha(hover ? 155 : 88),
          width: hover ? 1.2 : 1.0,
        ),
      );

  /// Glassmorphic card background (used inside BackdropFilter widgets).
  /// At rest: white 5 % border — invisible to the eye, just gives shape.
  /// On hover: accent-tinted border appears as a signal of interactivity.
  static BoxDecoration glassCard({
    required Color accent,
    double radius = 16,
    bool hover = false,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            charcoalHigh.withAlpha(hover ? 88 : 68),
            charcoal.withAlpha(hover ? 72 : 55),
          ],
        ),
        // Translucent white border at rest; thin accent shimmer on hover.
        border: Border.all(
          color: hover ? accent.withAlpha(90) : borderSubtle,
          width: hover ? 1.1 : 0.8,
        ),
      );

  /// Quick-action card — solid elevated surface.
  /// Uses the same border discipline: white-only at rest.
  static BoxDecoration actionCard({
    required Color accent,
    bool hover = false,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: hover ? charcoalHigh : const Color(0xFF191920),
        border: Border.all(
          color: hover ? accent.withAlpha(80) : borderSubtle,
          width: hover ? 1.1 : 0.8,
        ),
        boxShadow: hover ? cardShadow(accent: accent, hover: true) : const [],
      );

  /// Sidebar navigation item — crisp tile system (HubSpot / Retool style).
  /// Selected → thin accent border (the ONE place accents live in chrome).
  /// Hover    → flat translucent-white tile, NO glow / shadow / scale.
  /// Radius 10 keeps the tile sharp and modern, close to the requested 8
  /// while harmonising with the app's 12–16px card system.
  static const double sidebarItemRadius = 10;

  static BoxDecoration sidebarItem({
    required Color accent,
    required bool selected,
    required bool hover,
  }) {
    if (selected) {
      return BoxDecoration(
        borderRadius: BorderRadius.circular(sidebarItemRadius),
        color: accent.withAlpha(22),
        // Thin accent border is intentional here — it identifies active route.
        border: Border.all(color: accent.withAlpha(70), width: 0.8),
      );
    }
    if (hover) {
      // Flat white 5% tile — no charcoal block, no border, no glow.
      // This is the crisp "soft rounded background" the brief asks for.
      return BoxDecoration(
        borderRadius: BorderRadius.circular(sidebarItemRadius),
        color: Colors.white.withAlpha(13), // ≈ white.withOpacity(0.05)
      );
    }
    return const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(sidebarItemRadius)),
    );
  }

  // ── GRADIENTS ────────────────────────────────────────────────────────────────

  /// Hero banner gradient — single-accent ambient bloom (Linear / Vercel style).
  /// Only the primary accent colour bleeds in; no secondary colour competes.
  /// The bloom lives in the top-left corner and decays quickly to pure charcoal.
  static Gradient heroBannerGradient({
    required Color primary,
    Color? tertiary,   // intentionally unused — kept for API compatibility
  }) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.40, 1.0],
        colors: [
          primary.withAlpha(38),   // soft single-colour bloom at origin
          charcoal.withAlpha(230), // fast decay to elevated surface
          charcoal,                // pure charcoal — no competing hue
        ],
      );

  /// Activity feed panel gradient.
  static LinearGradient feedPanelGradient({required Color accent}) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          charcoalHigh.withAlpha(210),
          charcoal.withAlpha(220),
        ],
      );

  // ── TYPOGRAPHY HELPERS ───────────────────────────────────────────────────────

  /// Gold value typography for financial KPI numbers.
  static TextStyle? kpiValue(TextTheme textTheme, Color gold) =>
      textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: gold,
        letterSpacing: -0.5,
      );

  /// Emerald count for health/active stats.
  static TextStyle? healthValue(TextTheme textTheme, Color emerald) =>
      textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: emerald,
        letterSpacing: -0.5,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Typography system
//
// Font pairing rationale:
//   • Bebas Neue — condensed, uppercase display face.
//     Carries the high-energy gym aesthetic for headings and KPI numbers.
//     Single weight → fontWeight overrides have no visual effect; use
//     letterSpacing and fontSize to control hierarchy instead.
//
//   • Inter — variable-weight, optimised for screen legibility.
//     Used for all data-dense content: member names, dates, table rows,
//     form fields, sidebar navigation, and any text that must remain
//     readable at 12–14 px on dark backgrounds.
//
// Naming convention:
//   • kpi*     → Bebas Neue, positive tracking, for metric values
//   • heading* → Bebas Neue, wider tracking, for section / page titles
//   • data*    → Inter, standard tracking, for list / table content
//   • label*   → Inter, semi-bold, for UI chips / column headers
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppTypography {
  // ── Bebas Neue helpers ─────────────────────────────────────────────────────

  /// Large KPI display number — revenue totals, member counts, check-ins.
  /// `fontSize` defaults to 36; scale up for hero-sized values.
  static TextStyle kpiValue({
    required Color color,
    double fontSize = 36,
    double letterSpacing = 2.0,
  }) =>
      GoogleFonts.bebasNeue(
        fontSize: fontSize,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.05,
      );

  /// Section header label — "QUICK ACTIONS", "AT-RISK MEMBERS", chart titles.
  static TextStyle sectionHeader({
    required Color color,
    double fontSize = 16,
  }) =>
      GoogleFonts.bebasNeue(
        fontSize: fontSize,
        color: color,
        letterSpacing: 2.5,
        height: 1.1,
      );

  /// Sidebar brand name — "GYM MANAGEMENT" lockup.
  static TextStyle brandTitle({required Color color}) =>
      GoogleFonts.bebasNeue(
        fontSize: 18,
        color: color,
        letterSpacing: 3.0,
        height: 1.0,
      );

  // ── Inter helpers ───────────────────────────────────────────────────────────

  /// Standard body text — member names, descriptions, list content.
  static TextStyle dataBody({
    required Color color,
    double fontSize = 14,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        height: 1.45,
      );

  /// Small UI label — timestamps, member codes, chip text, column headers.
  static TextStyle uiLabel({
    required Color color,
    double fontSize = 12,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.2,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: 1.35,
      );

  /// Emphasis label — sidebar nav items, button labels, active-state text.
  static TextStyle emphasisLabel({
    required Color color,
    double fontSize = 14,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );
}

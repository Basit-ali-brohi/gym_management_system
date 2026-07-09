// Central design-token registry — "Gym Floor" design system.
//
// Visual language: chalkboard workout log, scoreboard/interval timer, steel
// plates, locker-room signage. Flat and utilitarian — no shadows, no glow, no
// gradients, tight 6px radius. The brand ember accent is used with restraint:
// primary actions, active nav state, and financial/revenue data only.
//
// NOTE: token identifiers below are kept stable (obsidian, charcoal,
// charcoalHigh, emerald, alertAmber, borderSubtle, etc.) even though their
// values now point at the new palette. ~90 call sites across the app read
// these names directly; repointing values here cascades the new look without
// touching every file, the same technique used for the prior theme passes.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global border-radius scale. Tight and utilitarian (6px) — deliberately NOT
/// the soft 12–16px bubble radius of generic SaaS UI. This app looks like
/// equipment, not a lifestyle app.
abstract final class AppRadius {
  static const double small = 6;
  static const double medium = 6;
  static const double large = 6;
  static const double pill = 999;

  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumAll = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeAll = BorderRadius.all(Radius.circular(large));
}

abstract final class AppTheme {
  // ── DARK CHROME (sidebar, hero "board" panels — always dark, independent
  // of the light/dark content toggle, like a persistent equipment-room rail) ──
  /// Primary dark chrome — sidebar bg, hero board panel bg.
  static const Color obsidian = Color(0xFF15171B); // --charcoal
  static const Color charcoal = Color(0xFF1D2024); // --charcoal-2, secondary dark surface
  static const Color charcoalHigh = Color(0xFF262A2F); // elevated dark surface (hover rows)

  // ── LIGHT CANVAS (main page background + cards) ─────────────────────────────
  static const Color canvas = Color(0xFFF1F2EF); // cool chalk-white page bg
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE2E4DE); // hairline border, light mode
  static const Color ink = Color(0xFF1B1D1F); // primary text, light mode
  static const Color muted = Color(0xFF6B7178); // secondary text, light mode

  // ── HAIRLINE / BORDER SYSTEM (dark-chrome surfaces: sidebar, board panels) ──
  static const Color borderSubtle = Color(0x0FFFFFFF); // white ~6%
  static const Color borderHover = Color(0x1AFFFFFF); // white ~10%
  static const Color borderFocus = Color(0x40FFFFFF); // white 25% (focus ring)

  /// Legacy opaque strokes — light-mode fallback border.
  static const Color strokeSubtle = Color(0xFFE2E4DE); // == line
  static const Color strokeNormal = Color(0xFFD5D7D0);

  // ── CATEGORY COLOR SYSTEM ────────────────────────────────────────────────
  // The same 4 colours mean the same thing everywhere in the app: financial,
  // membership/active, operational/neutral, at-risk/overdue.

  /// Ember — brand accent. Financial/revenue data, primary actions, active nav.
  static const Color gold = Color(0xFFFF5A1F); // --ember (kept as `gold` for compat)
  static const Color goldWarm = Color(0xFFFF7A47); // lighter ember, hover/shine
  static const Color emberSoft = Color(0xFFFFE6DA);

  /// Spotter teal — membership / active / positive category.
  static const Color emerald = Color(0xFF1E7A6C); // --spotter (kept as `emerald` for compat)
  static const Color emeraldNeon = Color(0xFF1E7A6C); // no neon variant in this system — same teal
  static const Color spotterSoft = Color(0xFFDCEEEA);

  /// Iron slate — neutral / operational category.
  static const Color iron = Color(0xFF565C63);
  static const Color ironSoft = Color(0xFFE7E8E3);

  /// Alert — at-risk / overdue / expired. Muted brick red, never bright red.
  static const Color danger = Color(0xFFB23A2E); // --alert
  static const Color alertAmber = Color(0xFFB2662E); // muted amber — "due soon" (softer than danger)
  static const Color alertSoft = Color(0xFFF5DEDA);

  // ── SHADOW / GLOW ────────────────────────────────────────────────────────
  // This system is flat and utilitarian — like gym equipment. No shadows, no
  // glow, no gradients, anywhere. Both helpers intentionally return nothing.

  static List<BoxShadow> neonGlow(
    Color color, {
    double blur = 20,
    double spread = 0,
    Offset offset = Offset.zero,
  }) =>
      const <BoxShadow>[];

  static List<BoxShadow> cardShadow({Color? accent, bool hover = false}) => const <BoxShadow>[];

  // ── COMPONENT DECORATIONS ────────────────────────────────────────────────

  /// Small rounded-square icon chip using a soft-tint category colour — for
  /// status/insight icons only (stat cards use the colour-square + mono-numeral
  /// treatment instead, see [CategoryStatCard]).
  static BoxDecoration iconBox({
    required Color color,
    bool hover = false,
    double radius = AppRadius.small,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: color.withAlpha(hover ? 46 : 30),
        border: Border.all(color: color.withAlpha(hover ? 130 : 80), width: 1),
      );

  /// Flat surface — no gradient bloom (the chalkboard hero panel is flat
  /// charcoal + a faint ruled-line texture only, nothing else).
  static BoxDecoration glassCard({
    required Color accent,
    double radius = AppRadius.small,
    bool hover = false,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: charcoal,
        border: Border.all(color: hover ? accent.withAlpha(90) : borderSubtle, width: 1),
      );

  /// Quick-action / list-row surface on dark chrome — flat, no gradient.
  static BoxDecoration actionCard({
    required Color accent,
    bool hover = false,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.small),
        color: hover ? charcoalHigh : charcoal,
        border: Border.all(color: hover ? accent.withAlpha(90) : borderSubtle, width: 1),
      );

  /// Sidebar nav item radius — tight, matches the app's utilitarian language.
  static const double sidebarItemRadius = AppRadius.small;

  /// Active nav item reads like a loaded plate clipped onto a rack: solid 2px
  /// ember left border + a subtle ember-tinted background. Hover is a flat,
  /// barely-there white tint. No pill shape, no glow.
  static BoxDecoration sidebarItem({
    required Color accent,
    required bool selected,
    required bool hover,
  }) {
    if (selected) {
      return BoxDecoration(
        color: accent.withAlpha(24),
        border: Border(left: BorderSide(color: accent, width: 2)),
      );
    }
    if (hover) {
      return BoxDecoration(
        color: Colors.white.withAlpha(13),
        border: const Border(left: BorderSide(color: Colors.transparent, width: 2)),
      );
    }
    return const BoxDecoration(
      border: Border(left: BorderSide(color: Colors.transparent, width: 2)),
    );
  }

  // ── GRADIENTS ────────────────────────────────────────────────────────────
  // Kept for API compatibility with any remaining call site; both now return
  // a FLAT fill (single colour) — the chalkboard motif forbids gradient blooms.

  static Gradient heroBannerGradient({required Color primary, Color? tertiary}) => const LinearGradient(
        colors: [charcoal, charcoal],
      );

  static LinearGradient feedPanelGradient({required Color accent}) => const LinearGradient(
        colors: [charcoal, charcoal],
      );

  // ── TYPOGRAPHY HELPERS (legacy names, now Oswald / JetBrains Mono) ───────

  /// KPI number — routes through JetBrains Mono now (see [AppTypography.mono]).
  /// Kept for compatibility with call sites that pass a [TextTheme] directly.
  static TextStyle? kpiValue(TextTheme textTheme, Color color) => AppTypography.mono(
        color: color,
        fontSize: textTheme.headlineSmall?.fontSize ?? 24,
        weight: FontWeight.w700,
      );

  static TextStyle? healthValue(TextTheme textTheme, Color color) => AppTypography.mono(
        color: color,
        fontSize: textTheme.headlineSmall?.fontSize ?? 24,
        weight: FontWeight.w700,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Typography system — "Gym Floor"
//
//   • Oswald  — display / page titles / section headers / nav group labels /
//     hero headline / quick-action titles. Condensed, bold, uppercase —
//     reads like gym signage / locker-room lettering.
//
//   • Archivo — the workhorse: buttons, list rows, descriptions, form labels,
//     nav item labels, everything that isn't a headline or a number.
//
//   • JetBrains Mono — EVERY number, stat, currency figure, date, ID,
//     percentage. This is a firm rule: any numeral-heavy data point renders in
//     mono, never Archivo/Oswald. Gives the scoreboard / digital-timer feel.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppTypography {
  static const String displayFamily = 'Oswald';

  // ── Oswald helpers (display / headings / nav groups) ─────────────────────

  /// Large stat headline (rarely used directly — prefer [mono] for the actual
  /// numeral; this is for Oswald-set headline text next to/around a stat).
  static TextStyle kpiValue({
    required Color color,
    double fontSize = 34,
    double letterSpacing = 0.2,
  }) =>
      GoogleFonts.oswald(
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.05,
      );

  /// Section header label — "QUICK ACTIONS", "AT-RISK MEMBERS", panel titles,
  /// nav group labels, page titles. Condensed uppercase Oswald.
  static TextStyle sectionHeader({
    required Color color,
    double fontSize = 16,
  }) =>
      GoogleFonts.oswald(
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        color: color,
        letterSpacing: 0.4,
        height: 1.12,
      );

  /// Page-level heading directly under the top bar — "MEMBERS", "INVOICES".
  /// Oswald, uppercase (call [String.toUpperCase] at the call site — see
  /// [AppPageTitle] in gym_floor_components.dart), tracked. Weight 600, a
  /// touch lighter than [sectionHeader]'s w700, so it reads as the page's own
  /// heading tier rather than a smaller in-page section label.
  static TextStyle pageTitle({
    required Color color,
    double fontSize = 24,
  }) =>
      GoogleFonts.oswald(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        color: color,
        letterSpacing: 0.5,
        height: 1.1,
      );

  /// Sidebar brand wordmark.
  static TextStyle brandTitle({required Color color}) => GoogleFonts.oswald(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: color,
        letterSpacing: 0.3,
        height: 1.02,
      );

  // ── Archivo helpers (body / UI / labels) ─────────────────────────────────

  /// Standard body text — descriptions, list content.
  static TextStyle dataBody({
    required Color color,
    double fontSize = 14,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.archivo(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        height: 1.45,
      );

  /// Small UI label — chip text, column headers (non-numeric).
  static TextStyle uiLabel({
    required Color color,
    double fontSize = 12,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.2,
  }) =>
      GoogleFonts.archivo(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: 1.35,
      );

  /// Emphasis label — nav item labels, button labels, active-state text.
  static TextStyle emphasisLabel({
    required Color color,
    double fontSize = 14,
  }) =>
      GoogleFonts.archivo(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  // ── JetBrains Mono helpers (every number / stat / currency / date / ID) ──

  /// The scoreboard numeral. Use for every stat value, currency figure,
  /// percentage — anything numeral-heavy. Tabular figures.
  static TextStyle mono({
    required Color color,
    double fontSize = 28,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.1,
      );

  /// Row meta / micro-label — "LAST VISIT 2026-05-06", "(M-1002)". Small,
  /// uppercase, tracked, mono, muted. A deliberate consistent micro-pattern.
  static TextStyle monoMeta({
    required Color color,
    double fontSize = 10.5,
    double letterSpacing = 0.13,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w500,
        letterSpacing: letterSpacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// The single category-colour system used app-wide. The same colour always
/// means the same thing everywhere: financial data, membership/active status,
/// neutral/operational info, or at-risk/overdue alerts. Used by the small
/// colour-square on stat cards, list-row priority tabs, and status chips.
enum StatCategory { financial, membership, operational, atRisk }

extension StatCategoryColors on StatCategory {
  Color get color => switch (this) {
        StatCategory.financial => AppTheme.gold, // ember
        StatCategory.membership => AppTheme.emerald, // spotter teal
        StatCategory.operational => AppTheme.iron, // iron slate
        StatCategory.atRisk => AppTheme.danger, // alert brick red
      };

  Color get soft => switch (this) {
        StatCategory.financial => AppTheme.emberSoft,
        StatCategory.membership => AppTheme.spotterSoft,
        StatCategory.operational => AppTheme.ironSoft,
        StatCategory.atRisk => AppTheme.alertSoft,
      };
}

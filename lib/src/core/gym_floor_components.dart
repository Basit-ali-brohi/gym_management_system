// Shared "Gym Floor" signature components:
//   • AppPageTitle     — the large page-level heading under the top bar on
//                        every screen ("MEMBERS", "INVOICES").
//   • BoardHeroPanel   — the dark chalkboard "Today's Board" hero, reused at
//                        the top of every major module.
//   • CategoryStatCard — the scoreboard numeral stat tile (colour-square +
//                        mono numeral), replaces the old icon-box stat card.
//   • StopwatchDial    — the interval-timer ring for any ratio/percentage.
//   • BoardPrimaryButton / BoardDashedButton — hero-panel action buttons.
//
// All flat, no shadows/gradients/glow, tight 6px radius, category colours
// from [StatCategory]. Every numeral renders in JetBrains Mono.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppPageTitle
// ─────────────────────────────────────────────────────────────────────────────

/// The large page-level heading directly under the top bar on every screen
/// (e.g. "MEMBERS", "INVOICES") — the one shared page-header element used
/// consistently app-wide. Same Oswald display language as the hero panel
/// headline and uppercase section labels ("AT-RISK MEMBERS") elsewhere;
/// callers pass ordinary title-case text, this widget uppercases it.
class AppPageTitle extends StatelessWidget {
  const AppPageTitle(this.text, {super.key, this.color, this.fontSize});

  final String text;
  final Color? color;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: AppTypography.pageTitle(
        color: color ?? theme.colorScheme.onSurface,
        fontSize: fontSize ?? theme.textTheme.headlineSmall?.fontSize ?? 24,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BoardHeroPanel
// ─────────────────────────────────────────────────────────────────────────────

/// The dark "chalkboard" hero panel reused at the top of every major module.
/// Flat charcoal background + a faint ruled-line texture only — no gradient
/// bloom, no glow. [greetingPrefix] is the mono small-caps lead-in (e.g.
/// "GOOD MORNING"), [greetingEmphasis] is rendered in ember (e.g. the day/date).
class BoardHeroPanel extends StatelessWidget {
  const BoardHeroPanel({
    super.key,
    required this.greetingPrefix,
    required this.greetingEmphasis,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.actions = const [],
    this.trailing,
  });

  final String greetingPrefix;
  final String greetingEmphasis;
  final String title;
  final String? subtitle;
  final List<String> tags;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return ClipRRect(
      borderRadius: AppRadius.largeAll,
      child: Container(
        decoration: const BoxDecoration(color: AppTheme.obsidian),
        child: CustomPaint(
          painter: _ChalkboardTexturePainter(),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Builder(
              builder: (context) {
                final narrow = MediaQuery.sizeOf(context).width < 640;

                final content = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: AppTypography.monoMeta(color: Colors.white.withAlpha(150), fontSize: 11.5),
                        children: [
                          TextSpan(text: '$greetingPrefix · '),
                          TextSpan(
                            text: greetingEmphasis,
                            style: AppTypography.monoMeta(color: accent, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: AppTypography.sectionHeader(color: Colors.white, fontSize: 26),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: AppTypography.dataBody(color: Colors.white.withAlpha(160), fontSize: 13.5),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final t in tags) _BoardTagPill(label: t)],
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ],
                );

                if (trailing == null) return content;

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(alignment: Alignment.centerRight, child: trailing!),
                      content,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    const SizedBox(width: 16),
                    trailing!,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ChalkboardTexturePainter extends CustomPainter {
  const _ChalkboardTexturePainter();

  static const double _spacing = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(6) // ~0.025 opacity
      ..strokeWidth = 1;
    for (double y = _spacing; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChalkboardTexturePainter oldDelegate) => false;
}

class _BoardTagPill extends StatelessWidget {
  const _BoardTagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: AppRadius.smallAll,
        border: Border.all(color: Colors.white.withAlpha(46)),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.sectionHeader(color: Colors.white.withAlpha(210), fontSize: 11),
      ),
    );
  }
}

/// Primary hero action — solid ember, dark text, semibold.
class BoardPrimaryButton extends StatelessWidget {
  const BoardPrimaryButton({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isAccentDark = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark;
    final onAccent = isAccentDark ? Colors.white : AppTheme.obsidian;

    return Material(
      color: accent,
      borderRadius: AppRadius.smallAll,
      child: InkWell(
        borderRadius: AppRadius.smallAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: onAccent),
              const SizedBox(width: 8),
              Text(label, style: AppTypography.emphasisLabel(color: onAccent, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary hero action — chalk-drawn dashed outline, transparent bg, light
/// muted text. This dashed treatment is specific to dark board panels; it is
/// NOT used elsewhere in the app.
class BoardDashedButton extends StatelessWidget {
  const BoardDashedButton({super.key, required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.smallAll,
      child: InkWell(
        borderRadius: AppRadius.smallAll,
        onTap: onTap,
        child: CustomPaint(
          painter: const _DashedRRectPainter(color: Color(0x38FFFFFF), radius: AppRadius.small),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white.withAlpha(200)),
                const SizedBox(width: 8),
                Text(label, style: AppTypography.emphasisLabel(color: Colors.white.withAlpha(210), fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double dashWidth = 5;
  static const double gapWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// CategoryStatCard — scoreboard numeral stat tile
// ─────────────────────────────────────────────────────────────────────────────

/// Flat white card: a small solid colour square encodes the category, the
/// value renders as a large JetBrains Mono numeral above a thin scoreboard
/// divider rule. Replaces the old icon-box treatment — no repeated icon chip
/// on every card.
class CategoryStatCard extends StatelessWidget {
  const CategoryStatCard({
    super.key,
    required this.category,
    required this.label,
    required this.value,
    this.footnote,
    this.onTap,
  });

  final StatCategory category;
  final String label;
  final String value;
  final String? footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ruleColor = isDark ? AppTheme.charcoalHigh : AppTheme.canvas;
    final cardColor = isDark ? AppTheme.charcoal : AppTheme.card;
    final borderColor = isDark ? AppTheme.borderSubtle : AppTheme.line;

    return Material(
      color: cardColor,
      borderRadius: AppRadius.largeAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeAll,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.largeAll,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 9, height: 9, color: category.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.uiLabel(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        weight: FontWeight.w600,
                        letterSpacing: 0.14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.mono(color: theme.colorScheme.onSurface, fontSize: 26),
              ),
              const SizedBox(height: 8),
              Container(height: 2, color: ruleColor),
              if (footnote != null) ...[
                const SizedBox(height: 8),
                Text(
                  footnote!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.monoMeta(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StopwatchDial — interval-timer ring for any ratio/percentage
// ─────────────────────────────────────────────────────────────────────────────

/// A ratio/percentage rendered like a stopwatch dial: a faint dashed outer
/// tick-ring, a thick FLAT-capped inner progress arc (no rounded caps — this
/// isn't a soft wellness-app dial), percentage centered in mono with a small
/// uppercase label beneath.
class StopwatchDial extends StatelessWidget {
  const StopwatchDial({
    super.key,
    required this.value,
    required this.percentLabel,
    required this.label,
    this.color,
    this.size = 140,
    this.ringWidth = 10,
  });

  final double value; // 0..1
  final String percentLabel;
  final String label;
  final Color? color;
  final double size;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = color ?? theme.colorScheme.primary;
    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(
        painter: _StopwatchDialPainter(
          value: value.clamp(0.0, 1.0),
          ringColor: ringColor,
          trackColor: theme.colorScheme.outlineVariant,
          tickColor: theme.colorScheme.onSurfaceVariant.withAlpha(120),
          ringWidth: ringWidth,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(percentLabel, style: AppTypography.mono(color: theme.colorScheme.onSurface, fontSize: 24)),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: AppTypography.uiLabel(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, letterSpacing: 0.12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopwatchDialPainter extends CustomPainter {
  _StopwatchDialPainter({
    required this.value,
    required this.ringColor,
    required this.trackColor,
    required this.tickColor,
    required this.ringWidth,
  });

  final double value;
  final Color ringColor;
  final Color trackColor;
  final Color tickColor;
  final double ringWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final tickRadius = radius - 1;
    final arcRadius = radius - 12;

    // Outer dashed tick ring (60 ticks, like a stopwatch bezel).
    final tickPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.butt;
    const tickCount = 60;
    for (var i = 0; i < tickCount; i++) {
      final angle = (2 * math.pi * i) / tickCount;
      final isMajor = i % 5 == 0;
      final outer = Offset(center.dx + tickRadius * math.cos(angle), center.dy + tickRadius * math.sin(angle));
      final innerR = tickRadius - (isMajor ? 6 : 3);
      final inner = Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Track.
    final trackPaint = Paint()
      ..color = trackColor.withAlpha(140)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, arcRadius, trackPaint);

    // Progress arc — flat caps, starts at 12 o'clock.
    if (value > 0) {
      final progressPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.butt;
      final rect = Rect.fromCircle(center: center, radius: arcRadius);
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StopwatchDialPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.ringColor != ringColor || oldDelegate.trackColor != trackColor;
  }
}

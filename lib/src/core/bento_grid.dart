// Reusable responsive "bento" grid.
//
// A token-driven layout that arranges cards of varied sizes on one responsive
// grid (Linear / Vercel dashboard style) — independent floating tiles rather
// than one continuous panel. No external dependency: items are sized from a
// 12-col (desktop) / 8-col (tablet) / 1-col (mobile) span model and flowed with
// a plain [Wrap], so each tile keeps its own elevation and 15px radius.
//
// Every tile enters with the existing [AppEntrance] stagger in row-major (list)
// order, and all motion stays gated by [animationsEnabledProvider].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_theme.dart';
import 'motion.dart';

/// Column span of a tile at each breakpoint. Desktop is out of 12, tablet out
/// of 8, mobile is always a single full-width column.
class BentoSpan {
  const BentoSpan({required this.desktop, required this.tablet});

  final int desktop; // 1..12
  final int tablet; // 1..8

  // ── Reusable presets (shared vocabulary for every screen) ──────────────────
  /// Full-width hero / banner.
  static const hero = BentoSpan(desktop: 12, tablet: 8);

  /// Single KPI card → 4-up desktop, 2-up tablet.
  static const metric = BentoSpan(desktop: 3, tablet: 4);

  /// Large chart (e.g. revenue line) — the grid's visual anchor.
  static const chartLarge = BentoSpan(desktop: 8, tablet: 8);

  /// Small chart (e.g. donut) that pairs beside [chartLarge].
  static const chartSmall = BentoSpan(desktop: 4, tablet: 8);

  /// List panel (at-risk members, activity feed) → 2-up desktop.
  static const list = BentoSpan(desktop: 6, tablet: 8);

  /// Full-width strip / callout banner.
  static const wide = BentoSpan(desktop: 12, tablet: 8);
}

/// One tile in a [BentoGrid].
class BentoItem {
  const BentoItem({required this.span, required this.child, this.lift = false});

  final BentoSpan span;
  final Widget child;

  /// Adds a subtle hover-lift (floating-tile feel). Leave off for cards that
  /// already animate their own hover (e.g. metric / action cards).
  final bool lift;
}

class BentoGrid extends StatelessWidget {
  const BentoGrid({
    super.key,
    required this.items,
    this.gap = 16,
    this.stagger = true,
    this.staggerBase = 0,
  });

  final List<BentoItem> items;
  final double gap;

  /// Row-major entrance stagger via [AppEntrance].
  final bool stagger;

  /// Offset added to each tile's stagger index (so a grid placed below other
  /// animated content continues the cascade instead of restarting).
  final int staggerBase;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final maxW = box.maxWidth;
        // Breakpoints are measured on the grid's own content width (already net
        // of the rail + frame chrome), so the 12-col rich layout still reaches
        // typical laptops. 1 col below ~700 keeps phone/tablet stacks clean.
        final int totalCols = maxW >= 1100
            ? 12
            : maxW >= 700
                ? 8
                : 1;

        // Tiny safety margin avoids sub-pixel wrap when a row sums to exactly
        // the available width.
        final double unitW = (maxW - 0.5 - gap * (totalCols - 1)) / totalCols;

        int colsFor(BentoSpan s) {
          if (totalCols == 1) return 1;
          final raw = totalCols >= 12 ? s.desktop : s.tablet;
          return raw.clamp(1, totalCols);
        }

        final children = <Widget>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i];
          final cols = colsFor(item.span);
          final w = totalCols == 1 ? maxW : unitW * cols + gap * (cols - 1);

          Widget tile = SizedBox(width: w, child: item.lift ? _BentoLift(child: item.child) : item.child);
          if (stagger) tile = AppEntrance(index: staggerBase + i, child: tile);
          children.add(tile);
        }

        return Wrap(spacing: gap, runSpacing: gap, children: children);
      },
    );
  }
}

/// Subtle hover-lift used for tiles that don't animate themselves. Respects the
/// global animations gate.
class _BentoLift extends ConsumerStatefulWidget {
  const _BentoLift({required this.child});

  final Widget child;

  @override
  ConsumerState<_BentoLift> createState() => _BentoLiftState();
}

class _BentoLiftState extends ConsumerState<_BentoLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final animate = ref.watch(animationsEnabledProvider);
    final lifted = animate && _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, lifted ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: AppRadius.largeAll,
          boxShadow: lifted ? AppTheme.cardShadow(hover: true) : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

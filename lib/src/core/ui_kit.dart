// Reusable data-dense UI components for ERP screens (filter bars + tables).
//
// These are the shared, design-system versions of the patterns first built
// inline on the Leads screen. New screens (Members, etc.) should import from
// here; the Leads screen can adopt these in a later dedupe pass.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Compact, fixed-height input decoration for filter bars.
/// Identical decoration across controls => identical rendered height, which is
/// what makes a row of search box + dropdowns line up perfectly.
InputDecoration appDenseInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefixIcon,
  double radius = 10,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(
      color: isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(28),
      width: 0.8,
    ),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: GoogleFonts.inter(fontSize: 13.5, color: theme.colorScheme.onSurfaceVariant),
    prefixIcon: prefixIcon,
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    filled: true,
    fillColor: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2),
    ),
  );
}

/// Flat, low-profile filter tag (HubSpot / Retool style).
/// Selected → subtle accent tint + accent border + accent text.
/// Unselected → transparent fill + faint hairline border + muted text.
/// No full-bleed colour blocks — accent stays a signal, not a background.
class AppFilterPill extends StatefulWidget {
  const AppFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accentOverride,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Optional accent (e.g. amber for a warning filter like "Expiring").
  final Color? accentOverride;

  @override
  State<AppFilterPill> createState() => _AppFilterPillState();
}

class _AppFilterPillState extends State<AppFilterPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentOverride ?? theme.colorScheme.primary;

    late final Color bg;
    late final Color border;
    late final Color fg;
    if (widget.selected) {
      bg = accent.withAlpha(isDark ? 30 : 22);
      border = accent.withAlpha(isDark ? 130 : 95);
      fg = accent;
    } else {
      bg = _hover
          ? (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8))
          : Colors.transparent;
      border = isDark ? Colors.white.withAlpha(33) : Colors.black.withAlpha(33);
      fg = theme.colorScheme.onSurfaceVariant;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: fg,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Table row action icon with a translucent circular backdrop on hover.
/// `danger` variant fades to a soft muted red only while hovered.
class AppTableActionButton extends StatefulWidget {
  const AppTableActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<AppTableActionButton> createState() => _AppTableActionButtonState();
}

class _AppTableActionButtonState extends State<AppTableActionButton> {
  bool _hover = false;

  // Soft muted red — not the harsh error red. Only shown on danger-hover.
  static const Color _mutedRed = Color(0xFFE06C6C);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color fg = _hover
        ? (widget.danger ? _mutedRed : theme.colorScheme.onSurface)
        : theme.colorScheme.onSurfaceVariant;

    final Color bg = !_hover
        ? Colors.transparent
        : widget.danger
            ? _mutedRed.withAlpha(28)
            : (isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(12));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Icon(widget.icon, size: 18, color: fg),
          ),
        ),
      ),
    );
  }
}

/// A rounded panel with a dashed border — used for premium empty states.
/// Fill defaults to a barely-there tint (~white 2%); the dashed stroke is a
/// touch stronger so the outer bound stays visible.
class AppDashedPanel extends StatelessWidget {
  const AppDashedPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.dash = 6,
    this.gap = 4,
    this.strokeWidth = 1.2,
    this.borderColor,
    this.fillColor,
  });

  final Widget child;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;
  final Color? borderColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stroke = borderColor ??
        (isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(28));
    final fill = fillColor ??
        (isDark ? Colors.white.withAlpha(5) : Colors.black.withAlpha(4)); // ~2%
    return CustomPaint(
      painter: _DashedRRectPainter(color: stroke, radius: radius, dash: dash, gap: gap, strokeWidth: strokeWidth),
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), color: fill),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final len = dash < metric.length - distance ? dash : metric.length - distance;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius || old.dash != dash || old.gap != gap || old.strokeWidth != strokeWidth;
}

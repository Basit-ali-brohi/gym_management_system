// Central motion / animation utilities for the app.
//
// All motion is GATED by [animationsEnabledProvider] so users who turn off
// "Enable Animations" in Settings get an instant, static UI. Motion here is
// purposeful and fast — entrance fades, count-ups, and press feedback — never
// decorative or laggy.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global switch for all app motion. Mirrors the Settings "Enable Animations"
/// toggle. Defaults to on.
final animationsEnabledProvider = StateProvider<bool>((ref) => true);

/// Entrance animation: a soft fade + slight upward rise. Use to reveal cards,
/// list rows, panels and sections. [index] staggers items in a list/grid
/// (~40ms apart, capped so long lists never feel slow). Respects the gate.
class AppEntrance extends ConsumerWidget {
  const AppEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.slide = true,
    this.duration = const Duration(milliseconds: 340),
  });

  final Widget child;
  final int index;
  final bool slide;
  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(animationsEnabledProvider)) return child;
    final delay = Duration(milliseconds: index.clamp(0, 14) * 40);
    var anim = child.animate().fadeIn(duration: duration, delay: delay, curve: Curves.easeOut);
    if (slide) {
      anim = anim.slideY(begin: 0.08, end: 0, duration: duration, delay: delay, curve: Curves.easeOutCubic);
    }
    return anim;
  }
}

/// Counts a number up from 0 to [value] on first build / value change. The
/// [builder] receives the live interpolated value so you control formatting.
/// Falls back to a static render when motion is disabled.
class AnimatedCountUp extends ConsumerWidget {
  const AnimatedCountUp({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 700),
  });

  final num value;
  final Duration duration;
  final Widget Function(BuildContext context, num value) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(animationsEnabledProvider)) return builder(context, value);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => builder(context, v),
    );
  }
}

/// Wraps a tappable child with a subtle press-scale (0.97) micro-interaction.
/// Purely visual — forwards [onTap]. Respects the gate.
class Pressable extends ConsumerStatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  ConsumerState<Pressable> createState() => _PressableState();
}

class _PressableState extends ConsumerState<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final animate = ref.watch(animationsEnabledProvider);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: animate && _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

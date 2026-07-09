// Collapsible icon-rail sidebar (Linear / Vercel / Arc style).
//
// Default state is a slim 72px icon rail. On desktop it expands to 248px on
// hover (as an OVERLAY over the content, so the page grid never jumps) or can
// be PINNED open (persisted), in which case the content reflows to make room.
//
// The rail body is ALWAYS laid out at its full 248px width and clipped to the
// animating container width. That keeps the expand/collapse tween overflow-free
// (no RenderFlex squeeze mid-animation) and gives a smooth left-to-right reveal.
// Collapsed visuals are left-aligned so they stay visible inside the 72px slice.
//
// This widget owns ONLY navigation chrome + interaction. It carries the exact
// same nav data (routes + permission-gated items) the old fixed sidebar used —
// callers pass a prebuilt list of [SidebarEntry]. All tokens (colour, radius,
// typography) come from the existing design system; nothing new is invented.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/branding.dart';
import '../../core/motion.dart'; // animationsEnabledProvider
import '../../core/providers.dart'; // sidebarPinnedProvider

/// One entry in the sidebar: either a group header or a navigable item.
class SidebarEntry {
  const SidebarEntry._(this.label, this.icon, this.route, this.isHeader);

  const SidebarEntry.item(String label, IconData icon, String route)
      : this._(label, icon, route, false);

  const SidebarEntry.header(String label) : this._(label, null, null, true);

  final String label;
  final IconData? icon;
  final String? route;
  final bool isHeader;
}

const double _kRailWidth = 72;
// Wide enough that the brand lockup ("GYM MANAGEMENT" + the tenant's actual
// gym name below it) never has to squeeze into a sliver next to the logomark
// and pin toggle — see _RailHeader, which also wraps instead of truncating
// if a name is still too long for one line at this width.
const double _kExpandedWidth = 272;

class CollapsibleSidebar extends ConsumerStatefulWidget {
  const CollapsibleSidebar({
    super.key,
    required this.entries,
    required this.selectedRoute,
    required this.onGo,
    required this.onLogout,
    required this.tenantLabel,
    required this.userName,
    required this.email,
    required this.initials,
    required this.content,
  });

  final List<SidebarEntry> entries;
  final String selectedRoute;
  final void Function(String route) onGo;
  final VoidCallback onLogout;
  final String tenantLabel;
  final String userName;
  final String email;
  final String initials;

  /// The main app area (top bar + routed screen) laid out to the right of the
  /// rail. It is offset by the rail's reserved width and stays put while the
  /// rail expands as an overlay on hover.
  final Widget content;

  @override
  ConsumerState<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends ConsumerState<CollapsibleSidebar> {
  bool _hover = false;
  Timer? _enterTimer;
  Timer? _exitTimer;

  @override
  void dispose() {
    _enterTimer?.cancel();
    _exitTimer?.cancel();
    super.dispose();
  }

  void _onEnter(bool animate) {
    _exitTimer?.cancel();
    if (!animate) {
      if (!_hover) setState(() => _hover = true);
      return;
    }
    // Small debounce so a quick mouse-through doesn't flick the rail open.
    _enterTimer?.cancel();
    _enterTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _hover = true);
    });
  }

  void _onExit(bool animate) {
    _enterTimer?.cancel();
    if (!animate) {
      if (_hover) setState(() => _hover = false);
      return;
    }
    _exitTimer?.cancel();
    _exitTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _hover = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The rail is always dark chrome — independent of the app's light/dark
    // content toggle, like a persistent equipment-room rail (Linear/Notion
    // pattern). Only the main content area (canvas/cards) responds to theme.
    final pinned = ref.watch(sidebarPinnedProvider);
    final animate = ref.watch(animationsEnabledProvider);
    final expanded = pinned || _hover;
    final reservedWidth = pinned ? _kExpandedWidth : _kRailWidth;
    final dur = animate ? const Duration(milliseconds: 200) : Duration.zero;
    const borderColor = AppTheme.borderSubtle;

    // Flat — no shadow, no gradient. A hairline right border is enough to
    // separate the rail from content, even while it overlays on hover.
    const railDecoration = BoxDecoration(
      color: AppTheme.obsidian,
      border: Border(right: BorderSide(color: borderColor, width: 0.8)),
    );

    return Stack(
      children: [
        // Content reserves the rail's collapsed/pinned width. When the rail
        // expands on hover it overlays this content (no reflow); pinning grows
        // the reserved width so the content genuinely makes room.
        Positioned.fill(
          child: AnimatedPadding(
            duration: dur,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(left: reservedWidth),
            child: widget.content,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            onEnter: (_) => _onEnter(animate),
            onExit: (_) => _onExit(animate),
            child: AnimatedContainer(
              duration: dur,
              curve: Curves.easeOutCubic,
              width: expanded ? _kExpandedWidth : _kRailWidth,
              decoration: railDecoration,
              clipBehavior: Clip.hardEdge,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _kExpandedWidth,
                maxWidth: _kExpandedWidth,
                child: SizedBox(
                  width: _kExpandedWidth,
                  child: _RailBody(
                    expanded: expanded,
                    pinned: pinned,
                    entries: widget.entries,
                    selectedRoute: widget.selectedRoute,
                    onGo: widget.onGo,
                    onLogout: widget.onLogout,
                    onTogglePin: () => ref.read(sidebarPinnedProvider.notifier).toggle(),
                    tenantLabel: widget.tenantLabel,
                    userName: widget.userName,
                    email: widget.email,
                    initials: widget.initials,
                    borderColor: borderColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailBody extends StatelessWidget {
  const _RailBody({
    required this.expanded,
    required this.pinned,
    required this.entries,
    required this.selectedRoute,
    required this.onGo,
    required this.onLogout,
    required this.onTogglePin,
    required this.tenantLabel,
    required this.userName,
    required this.email,
    required this.initials,
    required this.borderColor,
  });

  final bool expanded;
  final bool pinned;
  final List<SidebarEntry> entries;
  final String selectedRoute;
  final void Function(String route) onGo;
  final VoidCallback onLogout;
  final VoidCallback onTogglePin;
  final String tenantLabel;
  final String userName;
  final String email;
  final String initials;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      children: [
        _RailHeader(
          expanded: expanded,
          pinned: pinned,
          accent: accent,
          tenantLabel: tenantLabel,
          onTogglePin: onTogglePin,
          borderColor: borderColor,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final e in entries)
                if (e.isHeader)
                  _RailGroupHeader(label: e.label, expanded: expanded)
                else
                  _RailNavItem(
                    icon: e.icon!,
                    label: e.label,
                    selected: selectedRoute == e.route,
                    expanded: expanded,
                    onTap: () => onGo(e.route!),
                  ),
            ],
          ),
        ),
        _RailFooter(
          expanded: expanded,
          initials: initials,
          userName: userName,
          email: email,
          accent: accent,
          onLogout: onLogout,
        ),
        if (expanded)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: PoweredByDeverosity(padding: EdgeInsets.symmetric(vertical: 8)),
          ),
      ],
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({
    required this.expanded,
    required this.pinned,
    required this.accent,
    required this.tenantLabel,
    required this.onTogglePin,
    required this.borderColor,
  });

  final bool expanded;
  final bool pinned;
  final Color accent;
  final String tenantLabel;
  final VoidCallback onTogglePin;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    // Rail text/icons are fixed light-on-dark — the rail stays charcoal no
    // matter which app theme (light/dark) the main content is using.
    const mutedOnDark = Color(0xFF9BA1A8);

    // Rounded-square icon mark (not circular) — locker-room signage, not a
    // lifestyle-app logo bubble.
    final logomark = Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(borderRadius: AppRadius.smallAll, color: accent),
      child: Icon(PhosphorIconsRegular.barbell, color: Colors.white, size: 20),
    );

    return Container(
      // No fixed height — the brand block sizes to its content so a long gym
      // name can wrap to a second line without being clipped or truncated.
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
      ),
      alignment: Alignment.centerLeft,
      child: expanded
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                logomark,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wraps to a 2nd line rather than truncating mid-word —
                      // fixes the "GYM MANAGEME…" clipping bug.
                      Text(
                        'GYM MANAGEMENT',
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.brandTitle(color: Colors.white).copyWith(fontSize: 14.5, letterSpacing: 0.2),
                      ),
                      const SizedBox(height: 2),
                      // The actual gym/tenant name — also wraps for long
                      // business names instead of ellipsis-truncating.
                      Text(
                        tenantLabel,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.uiLabel(color: mutedOnDark, fontSize: 11, letterSpacing: 0.1),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: pinned ? 'Unpin sidebar' : 'Pin sidebar open',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: onTogglePin,
                    icon: Icon(
                      pinned ? PhosphorIconsRegular.pushPin : PhosphorIconsRegular.pushPinSimple,
                      size: 16,
                      color: pinned ? accent : mutedOnDark,
                    ),
                  ),
                ),
              ],
            )
          : logomark,
    );
  }
}

class _RailGroupHeader extends StatelessWidget {
  const _RailGroupHeader({required this.label, required this.expanded});

  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      // Collapsed rail: a thin divider separates groups (no visible label).
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Divider(height: 1, color: AppTheme.borderSubtle),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: AppTypography.uiLabel(
          color: const Color(0xFF9BA1A8),
          fontSize: 11,
          weight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _RailNavItem extends StatefulWidget {
  const _RailNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_RailNavItem> createState() => _RailNavItemState();
}

class _RailNavItemState extends State<_RailNavItem> {
  bool _hover = false;

  static const _mutedOnDark = Color(0xFF9BA1A8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final hover = _hover && !widget.selected;
    // Selected reads like a loaded plate clipped onto a rack: solid 2px ember
    // left border + tinted bg. Hover is a flat, barely-there white tint. No
    // pill shape, no glow — see AppTheme.sidebarItem.
    final decoration = AppTheme.sidebarItem(accent: accent, selected: widget.selected, hover: hover);
    final iconColor = widget.selected ? accent : _mutedOnDark;
    final textColor = widget.selected ? Colors.white : _mutedOnDark;

    final icon = Icon(widget.icon, color: iconColor, size: 18);

    final Widget body = widget.expanded
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: decoration,
            child: Row(
              children: [
                SizedBox(width: 20, child: Center(child: icon)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: AppTypography.emphasisLabel(color: textColor).copyWith(
                      fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(PhosphorIconsRegular.caretRight, color: iconColor, size: 18),
              ],
            ),
          )
        : Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: 44,
              width: 44,
              decoration: decoration,
              child: Center(child: icon),
            ),
          );

    Widget tile = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppTheme.sidebarItemRadius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: body,
        ),
      ),
    );

    // Rail (collapsed): reveal the label as a tooltip on hover.
    if (!widget.expanded) {
      tile = Tooltip(message: widget.label, preferBelow: false, child: tile);
    }
    return tile;
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({
    required this.expanded,
    required this.initials,
    required this.userName,
    required this.email,
    required this.accent,
    required this.onLogout,
  });

  final bool expanded;
  final String initials;
  final String userName;
  final String email;
  final Color accent;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    const mutedOnDark = Color(0xFF9BA1A8);

    // Rounded-square (not circular) initials avatar, per the app-wide avatar
    // rule — reads like a locker nameplate, not a lifestyle-app profile bubble.
    final avatar = Container(
      height: 36,
      width: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: AppRadius.smallAll, color: accent.withAlpha(40)),
      child: Text(initials, style: AppTypography.emphasisLabel(color: accent, fontSize: 13)),
    );

    if (!expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(message: userName, preferBelow: false, child: avatar),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.charcoalHigh,
          borderRadius: AppRadius.smallAll,
          border: Border.all(color: AppTheme.borderHover, width: 0.8),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: avatar,
          title: Text(userName,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.emphasisLabel(color: Colors.white, fontSize: 13)),
          subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.uiLabel(color: mutedOnDark)),
          trailing: IconButton(
            tooltip: 'Logout',
            onPressed: onLogout,
            icon: const Icon(PhosphorIconsRegular.signOut, color: mutedOnDark),
          ),
        ),
      ),
    );
  }
}

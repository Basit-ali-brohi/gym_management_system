import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Lays its children as a horizontal grid of equal-width [Expanded] cells on
/// wide modals (the 2-/3-column row system), collapsing to a clean vertical
/// stack on narrow ones. Enforces the standard 16px gap in both axes.
///
/// Usage: `FormRow([fullNameField, phoneField])` →
///   wide  → [ Expanded | 16 | Expanded ]
///   narrow→ [ field, 16, field ] stacked
class FormRow extends StatelessWidget {
  const FormRow(this.children, {super.key, this.breakpoint = 560, this.gap = 16});

  final List<Widget> children;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (children.length <= 1 || c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// A compact section heading with optional helper micro-copy beneath it.
/// Use to group related fields inside a modal ("Member Details", "Emergency &
/// Safety", "Billing") and to surface contextual guidance to the operator.
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.title, {super.key, this.hint, this.icon});

  final String title;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (hint != null && hint!.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// One choice in a [FormSegmented] control.
class FormSegment<T> {
  const FormSegment(this.value, this.label, {this.icon, this.color});

  final T value;
  final String label;
  final IconData? icon;

  /// Optional per-segment accent used when this segment is active (e.g. blue
  /// for "Cold", amber for "Warm", red for "Hot").
  final Color? color;
}

/// A premium glassmorphic segmented control — an inline pill switcher used for
/// low-cardinality, high-intent choices (Lead Temperature, Payment Status,
/// Discount Type) where a dropdown would be one click too many.
class FormSegmented<T> extends StatelessWidget {
  const FormSegmented({
    super.key,
    required this.label,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.accent,
  });

  final String label;
  final T value;
  final List<FormSegment<T>> segments;
  final ValueChanged<T> onChanged;

  /// Fallback accent when a segment does not define its own [FormSegment.color].
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              for (final seg in segments)
                Expanded(
                  child: _SegmentCell<T>(
                    segment: seg,
                    selected: seg.value == value,
                    accent: seg.color ?? accent ?? cs.primary,
                    onTap: () => onChanged(seg.value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SegmentCell<T> extends StatelessWidget {
  const _SegmentCell({
    required this.segment,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final FormSegment<T> segment;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? accent : theme.colorScheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: selected ? accent.withAlpha(36) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? accent.withAlpha(120) : Colors.transparent,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (segment.icon != null) ...[
                  Icon(segment.icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
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
}

/// A labelled multi-select chip group (FilterChips). Used for tag-like data —
/// medical conditions, fitness goals — where several values can co-exist.
/// State is owned by the caller; [onToggle] fires with the tapped option.
class FormMultiChips extends StatelessWidget {
  const FormMultiChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.hint,
    this.accent,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? hint;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = accent ?? cs.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hint != null && hint!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withAlpha(170),
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              FilterChip(
                label: Text(opt),
                selected: selected.contains(opt),
                showCheckmark: false,
                selectedColor: c.withAlpha(40),
                side: BorderSide(
                  color: selected.contains(opt) ? c.withAlpha(140) : theme.dividerColor,
                ),
                labelStyle: TextStyle(
                  color: selected.contains(opt) ? c : cs.onSurface,
                  fontWeight: selected.contains(opt) ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (_) => onToggle(opt),
              ),
          ],
        ),
      ],
    );
  }
}

Future<T?> showAppFormDialog<T>({
  required BuildContext context,
  required IconData icon,
  required String title,
  String? subtitle,
  required Widget body,
  List<Widget> actions = const <Widget>[],
  double maxWidth = 760,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AppFormDialog(
            icon: icon,
            title: title,
            subtitle: subtitle,
            body: body,
            actions: actions,
          ),
        ),
      );
    },
  );
}

Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final theme = Theme.of(context);
  final c = danger ? theme.colorScheme.error : theme.colorScheme.primary;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: message == null || message.trim().isEmpty ? null : Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () async {
                  await Navigator.of(context).maybePop();
                },
                icon: const Icon(PhosphorIconsRegular.x),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: body,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions.isEmpty
                ? [
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context).maybePop();
                      },
                      child: const Text('Cancel'),
                    ),
                  ]
                : actions,
          ),
        ),
      ],
    );
  }
}

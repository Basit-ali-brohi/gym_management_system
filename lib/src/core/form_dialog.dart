import 'package:flutter/material.dart';

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
                icon: const Icon(Icons.close),
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

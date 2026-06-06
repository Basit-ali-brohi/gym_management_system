import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Deverosity corporate web gateway.
const String kDeverosityUrl = 'https://deverosity.com/';

/// Safely launches the Deverosity website in the OS default browser. Any
/// failure is logged rather than thrown, so callers never crash the UI.
Future<void> launchDeverosity() async {
  final Uri url = Uri.parse(kDeverosityUrl);
  try {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  } catch (e) {
    debugPrint('URL Launch Error: $e');
  }
}

/// A subtle, clickable "Powered by Deverosity" branding badge.
///
/// Shows a native click cursor on hover and opens [kDeverosityUrl]. Pass
/// [underline] for the underlined web-reference treatment (used inside the
/// Settings workspace); leave it false for the quiet sidebar footer.
class PoweredByDeverosity extends StatelessWidget {
  const PoweredByDeverosity({
    super.key,
    this.underline = false,
    this.padding = const EdgeInsets.symmetric(vertical: 16.0),
  });

  final bool underline;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: launchDeverosity,
        child: Padding(
          padding: padding,
          child: Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: muted,
                  letterSpacing: 0.5,
                ),
                children: [
                  const TextSpan(text: 'Powered by '),
                  TextSpan(
                    text: 'Deverosity',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: underline ? accent : muted,
                      decoration: underline ? TextDecoration.underline : null,
                      decorationColor: underline ? accent.withValues(alpha: 0.5) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

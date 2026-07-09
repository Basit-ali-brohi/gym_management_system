// In-app PDF preview architecture.
//
// Renders generated PDFs INSIDE the app (no external OS viewer / MS Word) using
// the `printing` package's rasteriser, wrapped in a themed elite modal with a
// clean close button plus built-in print and share/save hooks.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:printing/printing.dart';

import 'app_theme.dart';
import 'web_download_stub.dart' if (dart.library.html) 'web_download_web.dart';

/// Opens the embedded PDF previewer as a themed modal route.
Future<void> showInAppPdfPreview(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  String? fileName,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'PDF preview',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => InAppPdfPreviewer(
      bytes: bytes,
      title: title,
      fileName: fileName ?? 'document.pdf',
    ),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// High-level entry used by every screen's PDF action sheet.
/// - `preview: true`  → renders the PDF inside the app (no external launcher).
/// - `preview: false` → saves the bytes to disk via the platform download hook.
Future<void> presentPdf(
  BuildContext context, {
  required bool preview,
  required Uint8List bytes,
  required String fileName,
  String? title,
}) async {
  if (preview) {
    await showInAppPdfPreview(context, bytes: bytes, title: title ?? 'Document Preview', fileName: fileName);
    return;
  }
  final path = downloadBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf');
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(path == null ? 'Download started' : 'Saved: $path')),
  );
}

/// Embedded PDF viewport — themed header with close / print / share, and the
/// rasterised page view below. Never invokes an external application.
class InAppPdfPreviewer extends StatelessWidget {
  const InAppPdfPreviewer({
    super.key,
    required this.bytes,
    required this.title,
    required this.fileName,
  });

  final Uint8List bytes;
  final String title;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;

    final surface = isDark ? AppTheme.charcoal : Colors.white;
    final border = isDark ? AppTheme.borderSubtle : Colors.black.withValues(alpha: 0.08);
    final pageBackdrop = isDark ? AppTheme.obsidian : const Color(0xFFEEF1F4);

    Widget actionBtn(IconData icon, String tooltip, VoidCallback onTap) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        style: IconButton.styleFrom(
          hoverColor: theme.colorScheme.primary.withAlpha(22),
        ),
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.all(wide ? 40 : 12),
      backgroundColor: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border, width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Themed header bar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              child: Row(
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    decoration: AppTheme.iconBox(color: theme.colorScheme.primary),
                    child: Icon(PhosphorIconsRegular.filePdf, size: 19, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sectionHeader(color: theme.colorScheme.onSurface),
                    ),
                  ),
                  actionBtn(PhosphorIconsRegular.printer, 'Print', () {
                    Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
                  }),
                  actionBtn(PhosphorIconsRegular.shareNetwork, 'Share / Save', () {
                    Printing.sharePdf(bytes: bytes, filename: fileName);
                  }),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(PhosphorIconsRegular.x, size: 20, color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: border),
            // ── Embedded rasterised page viewport ────────────────────────
            Expanded(
              child: ColoredBox(
                color: pageBackdrop,
                child: PdfPreview(
                  build: (_) async => bytes,
                  // We supply our own header actions — hide the package toolbar.
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  scrollViewDecoration: BoxDecoration(color: pageBackdrop),
                  pdfPreviewPageDecoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6)),
                    ],
                  ),
                  loadingWidget: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

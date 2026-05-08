import 'dart:async';
import 'dart:html' as html;

String? downloadBytes({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
  anchor.remove();
  return null;
}

String? previewBytes({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Timer(const Duration(minutes: 1), () {
    html.Url.revokeObjectUrl(url);
  });
  return null;
}

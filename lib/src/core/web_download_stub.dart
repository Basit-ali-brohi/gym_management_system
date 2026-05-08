import 'dart:async';
import 'dart:io';

String? downloadBytes({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) {
  final sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  final finalName = sanitized.isEmpty ? 'invoice.pdf' : sanitized;
  final dir = Directory.systemTemp.createTempSync('gms_invoice_');
  final path = '${dir.path}${Platform.pathSeparator}$finalName';
  final file = File(path);
  file.writeAsBytesSync(bytes, flush: true);

  _tryOpenFile(path);
  return path;
}

String? previewBytes({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) {
  final sanitized = fileName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  final finalName = sanitized.isEmpty ? 'preview.pdf' : sanitized;
  final dir = Directory.systemTemp.createTempSync('gms_preview_');
  final path = '${dir.path}${Platform.pathSeparator}$finalName';
  final file = File(path);
  file.writeAsBytesSync(bytes, flush: true);

  _tryOpenFile(path);
  return path;
}

void _tryOpenFile(String path) {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

  Future<Process> start() {
    if (Platform.isWindows) return Process.start('cmd', ['/c', 'start', '', path], runInShell: true);
    if (Platform.isMacOS) return Process.start('open', [path], runInShell: true);
    return Process.start('xdg-open', [path], runInShell: true);
  }

  unawaited(start().then((_) {}, onError: (_) {}));
}

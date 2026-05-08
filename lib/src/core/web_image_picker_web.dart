import 'dart:async';
import 'dart:html' as html;

Future<String?> pickImageDataUrl({int maxBytes = 200000}) async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();

  await input.onChange.first;
  final file = input.files?.isNotEmpty == true ? input.files!.first : null;
  if (file == null) return null;
  if (file.size > maxBytes) throw Exception('file_too_large');

  final reader = html.FileReader();
  final completer = Completer<String?>();
  reader.onError.first.then((_) => completer.completeError(Exception('read_failed')));
  reader.onLoad.first.then((_) {
    final res = reader.result;
    completer.complete(res is String ? res : null);
  });
  reader.readAsDataUrl(file);
  return completer.future;
}

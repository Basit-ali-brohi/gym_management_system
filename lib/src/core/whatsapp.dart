import 'package:url_launcher/url_launcher.dart';

String normalizeWhatsAppPhone(String? raw) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('00') && digits.length > 2) return digits.substring(2);
  if (digits.length == 11 && digits.startsWith('03')) return '92${digits.substring(1)}';
  return digits;
}

Uri buildWhatsAppUri({required String phone, required String message}) {
  final digits = normalizeWhatsAppPhone(phone);
  return Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
}

Future<bool> openWhatsAppMessage({
  required String phone,
  required String message,
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  final digits = normalizeWhatsAppPhone(phone);
  if (digits.isEmpty) return false;
  final uri = buildWhatsAppUri(phone: digits, message: message);
  return launchUrl(uri, mode: mode);
}

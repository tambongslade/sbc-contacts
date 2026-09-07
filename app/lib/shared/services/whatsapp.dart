import 'package:url_launcher/url_launcher.dart';

/// Opens a WhatsApp conversation with the given number via the public `wa.me`
/// deep link (cahier §8). The app never sends messages automatically and never
/// controls WhatsApp — it only hands off to it.
Future<bool> openWhatsApp(String phoneNumber, {String? presetText}) async {
  final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final uri = Uri.parse(
    'https://wa.me/$digits${presetText != null ? '?text=${Uri.encodeComponent(presetText)}' : ''}',
  );
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}

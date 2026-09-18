import 'package:url_launcher/url_launcher.dart';

/// The message WhatsApp opens pre-filled when a member is contacted from the
/// app (cahier §8).
///
/// Pre-filled, never sent: `wa.me?text=` only puts the text in the composer, so
/// the member still reads it and presses send. That is the whole reason this is
/// a deep link and not an API call.
///
/// The name is addressed as SBC gives it; a member with no name on file gets
/// the greeting without one rather than "Salut null".
String whatsAppGreeting(String? contactName) {
  final name = (contactName ?? '').trim();
  final salutation = name.isEmpty ? 'Salut' : 'Salut $name';
  return '$salutation, je vous contacte à partir de l\'application SBC network.';
}

/// Opens a WhatsApp conversation with the given number via the public `wa.me`
/// deep link (cahier §8). The app never sends messages automatically and never
/// controls WhatsApp — it only hands off to it.
///
/// [contactName] fills in the standard greeting; pass [presetText] instead to
/// override it, or the empty string to open an empty composer.
Future<bool> openWhatsApp(
  String phoneNumber, {
  String? contactName,
  String? presetText,
}) async {
  final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final text = presetText ?? whatsAppGreeting(contactName);
  final uri = Uri.parse(
    'https://wa.me/$digits${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}',
  );
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}

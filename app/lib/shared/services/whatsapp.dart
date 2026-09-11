import 'package:url_launcher/url_launcher.dart';

/// Opens a WhatsApp conversation with the given number via the public `wa.me`
/// deep link (cahier §8). The app never sends messages automatically and never
/// controls WhatsApp — it only hands off to it, with the message pre-filled in
/// the composer for the user to review and send themselves.
Future<bool> openWhatsApp(
  String phoneNumber, {
  String? presetText,
  String? contactName,
}) async {
  final digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return false;
  final text = presetText ?? sbcWhatsAppMessage(contactName);
  final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}

/// The professional French introduction pre-filled when handing off to
/// WhatsApp. Greets the contact by name when a usable one is available, and
/// gracefully drops the greeting-by-name otherwise ("Membre SBC" is treated as
/// no usable name, since it's the app's fallback label, not a real name).
String sbcWhatsAppMessage(String? contactName) {
  final name = (contactName ?? '').trim();
  final usable = name.isNotEmpty && name != 'Membre SBC';
  final greeting = usable ? 'Bonjour $name' : 'Bonjour';
  return '$greeting, je me permets de vous contacter suite à notre mise en '
      'relation sur le réseau SBC (Sniper Business Center). Je serais '
      "ravi(e) d'échanger avec vous. Bien cordialement.";
}

import 'package:flutter_contacts/flutter_contacts.dart';

/// Result of writing one member to the phone book.
class ContactWriteResult {
  const ContactWriteResult({required this.success, this.deviceContactId, this.error});
  final bool success;
  final String? deviceContactId;
  final String? error;
}

/// Wraps the native contacts API (flutter_contacts 2.x). Contacts created by the
/// app are tagged with organisation "SBC" so they're identifiable for later
/// synchronisation and dedup (cahier §14/§15). No auto-messaging — ever.
class ContactService {
  Future<bool> requestPermission() async {
    final status = await FlutterContacts.permissions.request(PermissionType.readWrite);
    return status == PermissionStatus.granted || status == PermissionStatus.limited;
  }

  /// True if a contact with this phone number already exists on the device
  /// (cahier §15 duplicate detection — the authoritative check is native).
  Future<bool> existsByPhone(String phone) async {
    final normalized = _digits(phone);
    if (normalized.isEmpty) return false;
    final contacts = await FlutterContacts.getAll(properties: {ContactProperty.phone});
    for (final c in contacts) {
      for (final p in c.phones) {
        final d = _digits(p.number);
        if (d.isNotEmpty && (d.endsWith(normalized) || normalized.endsWith(d))) {
          return true;
        }
      }
    }
    return false;
  }

  Future<ContactWriteResult> addSbcContact({
    required String firstName,
    String? lastName,
    String? phone,
    String? profession,
    String? city,
    String? country,
  }) async {
    try {
      final contact = Contact(
        name: Name(first: firstName, last: lastName ?? ''),
        phones: [if (phone != null && phone.isNotEmpty) Phone(number: phone)],
        organizations: [Organization(name: 'SBC', jobTitle: profession ?? '')],
      );
      final id = await FlutterContacts.create(contact);
      return ContactWriteResult(success: true, deviceContactId: id);
    } catch (e) {
      return ContactWriteResult(success: false, error: e.toString());
    }
  }

  String _digits(String s) => s.replaceAll(RegExp('[^0-9]'), '');
}

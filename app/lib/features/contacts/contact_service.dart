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
    return _isUsable(status);
  }

  /// Current status without prompting — lets the UI explain itself before the
  /// system dialog appears, and lets it stay quiet once access is granted.
  Future<PermissionStatus> checkPermission() =>
      FlutterContacts.permissions.check(PermissionType.readWrite);

  Future<bool> hasPermission() async => _isUsable(await checkPermission());

  /// iOS 18 "limited" means the member picked specific contacts to share; that
  /// is still enough to create and dedup, so treat it as usable.
  static bool _isUsable(PermissionStatus s) =>
      s == PermissionStatus.granted || s == PermissionStatus.limited;

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

  /// Writes one member to the phone book.
  ///
  /// [displayName] is the member's whole name, and the only name input: SBC
  /// puts the full name in `name` and often leaves `firstName` null, so
  /// callers passing both ended up writing "Claude Durel Claude Durel SBC".
  /// Splitting one string here is the only way the two halves cannot disagree.
  Future<ContactWriteResult> addSbcContact({
    required String displayName,
    String? phone,
    String? profession,
    String? city,
    String? country,
  }) async {
    try {
      final contact = Contact(
        name: _nameFor(displayName),
        phones: [if (phone != null && phone.isNotEmpty) Phone(number: phone)],
        organizations: [Organization(name: 'SBC', jobTitle: profession ?? '')],
      );
      final id = await FlutterContacts.create(contact);
      return ContactWriteResult(success: true, deviceContactId: id);
    } catch (e) {
      return ContactWriteResult(success: false, error: e.toString());
    }
  }

  /// Splits a whole name into the given/family halves a phone book stores
  /// separately. The first word is the given name and everything after it the
  /// family name, which is where the "SBC" marker is appended — so the phone
  /// shows "Claude Durel SBC", not the name twice.
  static Name _nameFor(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return Name(first: 'Membre', last: _suffix);
    return Name(
      first: parts.first,
      last: _withSbcSuffix(parts.skip(1).join(' ')),
    );
  }

  /// Every contact the app writes ends in "SBC", so it is recognisable as one
  /// of ours straight from the phone's own contact list — the organisation tag
  /// is only visible once the contact is opened, which is too late to be
  /// useful when scrolling a phone book.
  ///
  /// Idempotent: a member already called "… SBC" is not suffixed twice.
  static String _withSbcSuffix(String? lastName) {
    final base = (lastName ?? '').trim();
    if (base.isEmpty) return _suffix;
    if (base.toUpperCase().endsWith(_suffix)) return base;
    return '$base $_suffix';
  }

  static const String _suffix = 'SBC';

  String _digits(String s) => s.replaceAll(RegExp('[^0-9]'), '');
}

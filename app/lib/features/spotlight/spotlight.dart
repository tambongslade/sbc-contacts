import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/status_boost/status_boost.dart';

/// "Mise en avant": whether the member's own profile is featured.
class SpotlightStatus {
  const SpotlightStatus({required this.active, required this.priceFcfa, this.until});

  factory SpotlightStatus.fromJson(Map<String, dynamic> json) => SpotlightStatus(
        active: json['active'] == true,
        until: DateTime.tryParse(json['until'] as String? ?? '')?.toLocal(),
        priceFcfa: (json['priceFcfa'] as num?)?.toInt() ?? 3000,
      );

  final bool active;

  /// End of an activation by SBC's team; null while it runs with the SBC subscription.
  final DateTime? until;
  final int priceFcfa;
}

class SpotlightRepository {
  SpotlightRepository(this._api);
  final ApiClient _api;

  /// Featured members this member has not saved yet (five at most).
  Future<List<StatusBoostEntry>> featured() async {
    final data = await _api.get('/spotlight/featured') as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().map(StatusBoostEntry.fromJson).toList();
  }

  Future<SpotlightStatus> me() async =>
      SpotlightStatus.fromJson(await _api.get('/spotlight/me') as Map<String, dynamic>);
}

final spotlightRepositoryProvider = Provider<SpotlightRepository>(
  (ref) => SpotlightRepository(ref.watch(apiClientProvider)),
);

final spotlightFeaturedProvider = FutureProvider.autoDispose<List<StatusBoostEntry>>(
  (ref) => ref.watch(spotlightRepositoryProvider).featured(),
);

final spotlightMeProvider = FutureProvider.autoDispose<SpotlightStatus>(
  (ref) => ref.watch(spotlightRepositoryProvider).me(),
);

/// Writes a member into the phone book and records it, the way every "save"
/// in the app does: it lands in "Mes contacts SBC" and tells the other member
/// « Quelqu'un t'a enregistré ». False when the contact could not be written;
/// a failed recording alone still counts, since the contact IS on the phone.
Future<bool> writeSbcContact(Ref ref, StatusBoostEntry entry) async {
  final contacts = ref.read(contactServiceProvider);
  final present = entry.phoneNumber.isNotEmpty && await contacts.existsByPhone(entry.phoneNumber);
  String? deviceContactId;
  if (!present) {
    final result = await contacts.addSbcContact(
      displayName: entry.name,
      phone: entry.phoneNumber,
      country: entry.country,
    );
    if (!result.success) return false;
    deviceContactId = result.deviceContactId;
  }
  try {
    await ref.read(syncRepositoryProvider).recordSingleContact(
          memberSbcId: entry.sbcId,
          deviceContactId: deviceContactId,
        );
  } catch (_) {
    // Bookkeeping only — the phone book is right either way.
  }
  return true;
}

/// [writeSbcContact] for widgets.
final sbcContactWriterProvider = Provider<Future<bool> Function(StatusBoostEntry)>(
  (ref) => (entry) => writeSbcContact(ref, entry),
);

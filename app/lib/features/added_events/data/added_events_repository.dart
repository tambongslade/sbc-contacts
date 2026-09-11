import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/added_events/domain/added_by_user.dart';

/// "Qui m'a ajouté ?" (cahier §21): who added the caller to their contacts,
/// and recording the caller's own adds.
class AddedEventsRepository {
  AddedEventsRepository(this._api);
  final ApiClient _api;

  /// The people who added the caller to their phone contacts, newest first.
  Future<Paginated<AddedByUser>> whoAddedMe({int page = 1, int limit = 20}) async {
    final data = await _api.get(
      '/added-events/who-added-me',
      query: {'page': page, 'limit': limit},
    ) as Map<String, dynamic>;
    return Paginated.fromJson(data, AddedByUser.fromJson);
  }

  /// Record that the caller added [memberSbcId] to their phone contacts.
  /// Best-effort at the call site — must never block the save UX.
  Future<void> recordAdd(String memberSbcId, {String? deviceContactId}) async {
    await _api.post('/added-events', body: {
      'memberSbcId': memberSbcId,
      if (deviceContactId != null) 'deviceContactId': deviceContactId,
    });
  }
}

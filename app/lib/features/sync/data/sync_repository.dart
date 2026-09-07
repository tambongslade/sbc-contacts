import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/network/paginated.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';

class SyncRepository {
  SyncRepository(this._api);
  final ApiClient _api;

  // ── criteria ──
  Future<List<SyncCriteria>> listCriteria() async {
    final data = await _api.get('/sync/criteria') as List<dynamic>;
    return data.whereType<Map<String, dynamic>>().map(SyncCriteria.fromJson).toList();
  }

  Future<SyncCriteria> createCriteria(Map<String, dynamic> payload) async =>
      SyncCriteria.fromJson(await _api.post('/sync/criteria', body: payload) as Map<String, dynamic>);

  Future<SyncCriteria> updateCriteria(String id, Map<String, dynamic> payload) async =>
      SyncCriteria.fromJson(
        await _api.patch('/sync/criteria/$id', body: payload) as Map<String, dynamic>,
      );

  Future<void> deleteCriteria(String id) => _api.delete('/sync/criteria/$id');

  Future<int> preview(String id) async {
    final data = await _api.get('/sync/criteria/$id/preview') as Map<String, dynamic>;
    return (data['matchCount'] as num?)?.toInt() ?? 0;
  }

  Future<int> previewAdhoc(Map<String, dynamic> payload) async {
    final data = await _api.post('/sync/criteria/preview', body: payload) as Map<String, dynamic>;
    return (data['matchCount'] as num?)?.toInt() ?? 0;
  }

  Future<Paginated<Member>> matches(String id, {int page = 1, int limit = 50}) async {
    final data = await _api.get('/sync/criteria/$id/matches', query: {'page': page, 'limit': limit})
        as Map<String, dynamic>;
    return Paginated.fromJson(data, Member.fromJson);
  }

  // ── runs ──
  Future<SyncRunStart> startRun({String? criteriaId, List<String>? memberSbcIds, String? deviceId}) async {
    final data = await _api.post('/sync/runs', body: {
      if (criteriaId != null) 'criteriaId': criteriaId,
      if (memberSbcIds != null) 'memberSbcIds': memberSbcIds,
      if (deviceId != null) 'deviceId': deviceId,
    }) as Map<String, dynamic>;
    return SyncRunStart.fromJson(data);
  }

  Future<void> reportRun(String runId, List<Map<String, dynamic>> results) =>
      _api.post('/sync/runs/$runId/report', body: {'results': results});

  Future<SyncSummary> summary() async =>
      SyncSummary.fromJson(await _api.get('/sync/summary') as Map<String, dynamic>);

  Future<Paginated<SyncRunEntry>> history({int page = 1, int limit = 20}) async {
    final data = await _api.get('/sync/history', query: {'page': page, 'limit': limit})
        as Map<String, dynamic>;
    return Paginated.fromJson(data, SyncRunEntry.fromJson);
  }

  /// "Mes contacts SBC" (cahier §16); [status] filters on the backend enum
  /// (PENDING / SYNCED / FAILED / STALE).
  Future<Paginated<SyncedContact>> syncedContacts({
    String? status,
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _api.get('/sync/contacts', query: {
      'page': page,
      'limit': limit,
      if (status != null) 'status': status,
    }) as Map<String, dynamic>;
    return Paginated.fromJson(data, SyncedContact.fromJson);
  }
}

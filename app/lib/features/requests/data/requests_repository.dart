import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';

/// The requests & pros endpoints (`/data/requests`, `/data/pro`).
class RequestsRepository {
  RequestsRepository(this._api);
  final ApiClient _api;

  ServiceRequestItem _request(dynamic d) => ServiceRequestItem.fromJson(d as Map<String, dynamic>);
  InboxItem _inbox(dynamic d) => InboxItem.fromJson(d as Map<String, dynamic>);
  ProSpace _space(dynamic d) => ProSpace.fromJson(d as Map<String, dynamic>);

  // ── Requester ───────────────────────────────────────────────────────────

  /// Analyse the free text; returns the AI's reading as a draft.
  Future<ServiceRequestItem> create({
    required String text,
    String? city,
    int? budget,
    String? desiredDate,
  }) async =>
      _request(await _api.post('/data/requests', body: {
        'text': text,
        if (city != null) 'city': city,
        if (budget != null) 'budget': budget,
        if (desiredDate != null) 'desiredDate': desiredDate,
      }));

  /// Corrections to the AI's reading, or an answer to its question.
  Future<ServiceRequestItem> update(String id, Map<String, dynamic> fields) async =>
      _request(await _api.patch('/data/requests/$id', body: fields));

  Future<ServiceRequestItem> send(String id) async =>
      _request(await _api.post('/data/requests/$id/send'));

  Future<List<ServiceRequestItem>> list() async {
    final data = await _api.get('/data/requests', query: {'page': 1, 'limit': 50}) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceRequestItem.fromJson)
        .toList();
  }

  Future<ServiceRequestItem> get(String id) async => _request(await _api.get('/data/requests/$id'));

  Future<ServiceRequestItem> select(String id, String dispatchId) async =>
      _request(await _api.post('/data/requests/$id/select', body: {'dispatchId': dispatchId}));

  Future<ServiceRequestItem> complete(
    String id, {
    required bool performed,
    int? stars,
    String? comment,
  }) async =>
      _request(await _api.post('/data/requests/$id/complete', body: {
        'performed': performed,
        if (stars != null) 'stars': stars,
        if (comment != null) 'comment': comment,
      }));

  Future<ServiceRequestItem> cancel(String id) async =>
      _request(await _api.post('/data/requests/$id/cancel'));

  /// Drafts are erased; anything else is cancelled if still open, then hidden.
  Future<void> remove(String id) => _api.delete('/data/requests/$id');

  /// Answer a pro's question, or write to a pro who answered.
  Future<ServiceRequestItem> sendMessage(String id, String dispatchId, String text) async =>
      _request(await _api.post('/data/requests/$id/messages', body: {'dispatchId': dispatchId, 'text': text}));

  /// "Relancer cette demande": a new draft with the same need.
  Future<ServiceRequestItem> reopen(String id) async =>
      _request(await _api.post('/data/requests/$id/reopen'));

  // ── Pro ─────────────────────────────────────────────────────────────────

  Future<ProSpace> proSpace() async => _space(await _api.get('/data/pro/profile'));

  Future<ProSpace> saveProfile(Map<String, dynamic> body) async =>
      _space(await _api.put('/data/pro/profile', body: body));

  Future<List<ServiceProposal>> structure(String text) async {
    final data = await _api.post('/data/pro/services/structure', body: {'text': text}) as Map<String, dynamic>;
    return (data['services'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceProposal.fromJson)
        .toList();
  }

  Future<ProSpace> addServices(List<Map<String, dynamic>> services) async =>
      _space(await _api.post('/data/pro/services', body: {'services': services}));

  /// Cleared fields go out as null so the server clears them too.
  Future<ProSpace> updateService(String id, Map<String, dynamic> body) async =>
      _space(await _api.patch('/data/pro/services/$id', body: body));

  Future<ProSpace> deleteService(String id) async => _space(await _api.delete('/data/pro/services/$id'));

  Future<List<InboxItem>> inbox() async {
    final data = await _api.get('/data/pro/inbox', query: {'page': 1, 'limit': 50}) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InboxItem.fromJson)
        .toList();
  }

  /// Opening marks the request seen.
  Future<InboxItem> open(String requestId) async => _inbox(await _api.get('/data/pro/inbox/$requestId'));

  /// action: INTERESTED, QUESTION, UNAVAILABLE or DECLINED.
  Future<InboxItem> respond(
    String requestId, {
    required String action,
    int? price,
    String? availability,
    String? delay,
    String? message,
  }) async =>
      _inbox(await _api.post('/data/pro/inbox/$requestId/respond', body: {
        'action': action,
        if (price != null) 'price': price,
        if (availability != null) 'availability': availability,
        if (delay != null) 'delay': delay,
        if (message != null) 'message': message,
      }));

  Future<InboxItem> proSendMessage(String requestId, String text) async =>
      _inbox(await _api.post('/data/pro/inbox/$requestId/messages', body: {'text': text}));

  Future<ProStats> stats() async =>
      ProStats.fromJson(await _api.get('/data/pro/stats') as Map<String, dynamic>);

  /// One turn of the AI setup conversation — nothing is saved.
  Future<AssistantTurn> assistantTurn(List<Map<String, String>> messages, ProDraft? draft) async =>
      AssistantTurn.fromJson(await _api.post('/data/pro/assistant', body: {
        'messages': messages,
        if (draft != null) 'draft': draft.json,
      }) as Map<String, dynamic>);
}

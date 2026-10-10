import 'package:intl/intl.dart';

/// How a service is delivered (backend `ServiceMode`).
enum ServiceMode {
  home('HOME', 'À domicile'),
  onSite('ON_SITE', 'Sur place'),
  online('ONLINE', 'En ligne'),
  delivery('DELIVERY', 'Livraison');

  const ServiceMode(this.wire, this.label);
  final String wire;
  final String label;

  static ServiceMode? fromWire(Object? v) {
    for (final m in values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

/// Where a request stands (backend `RequestStatus`).
enum RequestStatus {
  draft('DRAFT', 'Brouillon'),
  matching('MATCHING', 'Recherche en cours'),
  sent('SENT', 'Envoyée'),
  responded('RESPONDED', 'Réponses reçues'),
  locked('LOCKED', 'Réponses complètes'),
  selected('SELECTED', 'Professionnel retenu'),
  completed('COMPLETED', 'Terminée'),
  cancelled('CANCELLED', 'Annulée'),
  noMatch('NO_MATCH', 'Aucun professionnel'),
  noResponse('NO_RESPONSE', 'Sans réponse'),
  unknown('', '—');

  const RequestStatus(this.wire, this.label);
  final String wire;
  final String label;

  static RequestStatus fromWire(Object? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => RequestStatus.unknown);

  /// Still going: shown under "En cours" rather than "Terminées".
  bool get isOpen => const {draft, matching, sent, responded, locked, selected}.contains(this);

  /// Pros' answers are in and the member is choosing among them.
  bool get isChoosing => this == sent || this == responded || this == locked;

  /// Over: no more messages, and "Relancer cette demande" is offered.
  bool get isClosed => const {completed, cancelled, noMatch, noResponse}.contains(this);
}

/// A pro's side of one request (backend `DispatchStatus`).
enum DispatchStatus {
  sent('SENT', 'Nouvelle'),
  viewed('VIEWED', 'Vue'),
  interested('INTERESTED', 'Proposition envoyée'),
  question('QUESTION', 'Question posée'),
  unavailable('UNAVAILABLE', 'Pas disponible'),
  declined('DECLINED', 'Déclinée'),
  selected('SELECTED', 'Retenu'),
  lost('LOST', 'Close'),
  unknown('', '—');

  const DispatchStatus(this.wire, this.label);
  final String wire;
  final String label;

  static DispatchStatus fromWire(Object? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => DispatchStatus.unknown);

  /// The pro can still answer.
  bool get isOpen => this == sent || this == viewed || this == question;

  /// The pro and the requester can still talk.
  bool get canTalk => this == question || this == interested || this == selected;
}

String? _s(Object? v) => v == null ? null : v.toString();
int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
List<String> _list(Object? v) => (v as List<dynamic>? ?? const []).map((e) => '$e').toList();
List<Map<String, dynamic>> _maps(Object? v) =>
    (v as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

/// One line of the conversation between a requester and a pro (Data §10).
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.fromPro,
    required this.text,
    required this.createdAt,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> j) => ConversationMessage(
        id: _s(j['id']) ?? '',
        fromPro: j['author'] != 'REQUESTER',
        text: _s(j['text']) ?? '',
        createdAt: _d(j['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final bool fromPro;
  final String text;
  final DateTime createdAt;
}

/// One pro's answer, shown as a card to compare (backend `ResponseView`).
class RequestResponse {
  const RequestResponse({
    required this.id,
    required this.status,
    required this.proName,
    required this.profession,
    required this.city,
    required this.shopUrl,
    required this.confidenceScore,
    this.avatarUrl,
    this.whatsapp,
    this.serviceName,
    this.price,
    this.availability,
    this.delay,
    this.message,
    this.messages = const [],
  });

  factory RequestResponse.fromJson(Map<String, dynamic> j) {
    final p = (j['pro'] as Map<String, dynamic>?) ?? const {};
    return RequestResponse(
      id: _s(j['dispatchId']) ?? '',
      status: DispatchStatus.fromWire(j['status']),
      proName: _s(p['name']),
      avatarUrl: _s(p['avatarUrl']),
      profession: _s(p['profession']) ?? '',
      city: _s(p['city']) ?? '',
      whatsapp: _s(p['whatsapp']),
      shopUrl: _s(p['shopUrl']) ?? '',
      confidenceScore: _i(p['confidenceScore']) ?? 50,
      serviceName: _s(j['serviceName']),
      price: _i(j['price']),
      availability: _s(j['availability']),
      delay: _s(j['delay']),
      message: _s(j['message']),
      messages: _maps(j['messages']).map(ConversationMessage.fromJson).toList(),
    );
  }

  final String id; // dispatchId
  final DispatchStatus status;
  final String? proName;
  final String? avatarUrl;
  final String profession;
  final String city;
  final String? whatsapp;
  final String shopUrl;
  final int confidenceScore;
  final String? serviceName;
  final int? price;
  final String? availability;
  final String? delay;
  final String? message;
  final List<ConversationMessage> messages;

  String get displayName => (proName ?? '').isNotEmpty ? proName! : profession;
}

/// A request as its author sees it, with the pros' answers (backend `RequestView`).
class ServiceRequestItem {
  const ServiceRequestItem({
    required this.id,
    required this.rawText,
    required this.status,
    required this.createdAt,
    this.profession,
    this.service,
    this.specialties = const [],
    this.city,
    this.district,
    this.mode,
    this.desiredDate,
    this.desiredTime,
    this.budget,
    this.constraints = const [],
    this.clarificationQuestion,
    this.clarificationOptions = const [],
    this.clarificationAnswer,
    this.dispatchedCount = 0,
    this.responses = const [],
  });

  factory ServiceRequestItem.fromJson(Map<String, dynamic> j) => ServiceRequestItem(
        id: _s(j['id']) ?? '',
        rawText: _s(j['rawText']) ?? '',
        status: RequestStatus.fromWire(j['status']),
        createdAt: _d(j['createdAt']) ?? DateTime.now(),
        profession: _s(j['profession']),
        service: _s(j['service']),
        specialties: _list(j['specialties']),
        city: _s(j['city']),
        district: _s(j['district']),
        mode: ServiceMode.fromWire(j['mode']),
        desiredDate: _s(j['desiredDate']),
        desiredTime: _s(j['desiredTime']),
        budget: _i(j['budget']),
        constraints: _list(j['constraints']),
        clarificationQuestion: _s(j['clarificationQuestion']),
        clarificationOptions: _list(j['clarificationOptions']),
        clarificationAnswer: _s(j['clarificationAnswer']),
        dispatchedCount: _i(j['dispatchedCount']) ?? 0,
        responses: _maps(j['responses']).map(RequestResponse.fromJson).toList(),
      );

  final String id;
  final String rawText;
  final RequestStatus status;
  final DateTime createdAt;
  final String? profession;
  final String? service;
  final List<String> specialties;
  final String? city;
  final String? district;
  final ServiceMode? mode;
  final String? desiredDate;
  final String? desiredTime;
  final int? budget;
  final List<String> constraints;
  final String? clarificationQuestion;
  final List<String> clarificationOptions;
  final String? clarificationAnswer;
  final int dispatchedCount;
  final List<RequestResponse> responses;

  /// What to call the request in a list: the AI's service name, else the text.
  String get title => (service ?? '').isNotEmpty ? service! : rawText;

  String get place => [district, city].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  String get subtitle =>
      [place, mode?.label, desiredDate].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  bool get needsAnswer => clarificationQuestion != null && clarificationAnswer == null;

  /// Not while a chosen pro is waiting to do the job.
  bool get canDelete => status != RequestStatus.selected;

  String get deleteWarning => switch (status) {
        RequestStatus.draft => 'Le brouillon sera supprimé.',
        RequestStatus.matching ||
        RequestStatus.sent ||
        RequestStatus.responded ||
        RequestStatus.locked =>
          'La demande sera annulée pour les professionnels, puis retirée de ta liste.',
        _ => 'La demande sera retirée de ta liste.',
      };
}

/// A request a pro received (backend `InboxItemView`). Carries the need,
/// never who asked.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.status,
    required this.request,
    required this.createdAt,
    this.matchedService,
    this.price,
    this.availability,
    this.delay,
    this.message,
    this.viewedAt,
    this.respondedAt,
    this.messages = const [],
  });

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: _s(j['dispatchId']) ?? '',
        status: DispatchStatus.fromWire(j['status']),
        request: ServiceRequestItem.fromJson((j['request'] as Map<String, dynamic>?) ?? const {}),
        createdAt: _d(j['createdAt']) ?? DateTime.now(),
        matchedService: _s(j['matchedService']),
        price: _i(j['price']),
        availability: _s(j['availability']),
        delay: _s(j['delay']),
        message: _s(j['message']),
        viewedAt: _d(j['viewedAt']),
        respondedAt: _d(j['respondedAt']),
        messages: _maps(j['messages']).map(ConversationMessage.fromJson).toList(),
      );

  final String id; // dispatchId
  final DispatchStatus status;
  final ServiceRequestItem request;
  final DateTime createdAt;
  final String? matchedService;
  final int? price;
  final String? availability;
  final String? delay;
  final String? message;
  final DateTime? viewedAt;
  final DateTime? respondedAt;
  final List<ConversationMessage> messages;
}

/// What a pro adds on top of their SBC profile.
class ProProfile {
  const ProProfile({
    required this.profession,
    required this.description,
    required this.city,
    required this.zones,
    required this.modes,
    required this.availability,
    required this.shopUrl,
    required this.receivingEnabled,
    this.priceMin,
    this.priceMax,
    this.whatsapp,
    this.receivingUntil,
  });

  factory ProProfile.fromJson(Map<String, dynamic> j) => ProProfile(
        profession: _s(j['profession']) ?? '',
        description: _s(j['description']) ?? '',
        city: _s(j['city']) ?? '',
        zones: _list(j['zones']),
        modes: _list(j['modes']).map(ServiceMode.fromWire).whereType<ServiceMode>().toList(),
        availability: _s(j['availability']) ?? '',
        shopUrl: _s(j['shopUrl']) ?? '',
        receivingEnabled: j['receivingEnabled'] == true,
        priceMin: _i(j['priceMin']),
        priceMax: _i(j['priceMax']),
        whatsapp: _s(j['whatsapp']),
        receivingUntil: _d(j['receivingUntil']),
      );

  final String profession;
  final String description;
  final String city;
  final List<String> zones;
  final List<ServiceMode> modes;
  final String availability;
  final String shopUrl;
  final bool receivingEnabled;
  final int? priceMin;
  final int? priceMax;
  final String? whatsapp;
  final DateTime? receivingUntil;

  /// Every field matching relies on is really filled in — not blank, not a
  /// placeholder such as "À compléter".
  bool get isComplete =>
      !isPlaceholder(profession) &&
      !isPlaceholder(city) &&
      !isPlaceholder(availability) &&
      !isPlaceholder(description) &&
      description.length >= 10 &&
      modes.isNotEmpty &&
      isRealLink(shopUrl);
}

class ProServiceItem {
  const ProServiceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.profession,
    required this.isActive,
    this.synonyms = const [],
    this.specialties = const [],
    this.priceMin,
    this.priceMax,
    this.description,
    this.modes = const [],
    this.zones = const [],
    this.delay,
  });

  factory ProServiceItem.fromJson(Map<String, dynamic> j) => ProServiceItem(
        id: _s(j['id']) ?? '',
        name: _s(j['name']) ?? '',
        category: _s(j['category']) ?? '',
        profession: _s(j['profession']) ?? '',
        isActive: j['isActive'] != false,
        synonyms: _list(j['synonyms']),
        specialties: _list(j['specialties']),
        priceMin: _i(j['priceMin']),
        priceMax: _i(j['priceMax']),
        description: _s(j['description']),
        modes: _list(j['modes']).map(ServiceMode.fromWire).whereType<ServiceMode>().toList(),
        zones: _list(j['zones']),
        delay: _s(j['delay']),
      );

  final String id;
  final String name;
  final String category;
  final String profession;
  final bool isActive;
  final List<String> synonyms;
  final List<String> specialties;
  final int? priceMin;
  final int? priceMax;
  final String? description;
  final List<ServiceMode> modes;
  final List<String> zones;
  final String? delay;
}

/// What a pro still has to do before requests can reach them.
enum ProSetupItem {
  profile('Compléter mon profil (métier, ville, disponibilité, boutique)'),
  services('Ajouter au moins un service');

  const ProSetupItem(this.todo);
  final String todo;
}

/// Profile + services + whether requests are coming in (backend `ProProfileView`).
class ProSpace {
  const ProSpace({
    required this.services,
    required this.receivingActive,
    this.profile,
    this.phoneNumber,
  });

  factory ProSpace.fromJson(Map<String, dynamic> j) => ProSpace(
        profile: j['profile'] is Map<String, dynamic>
            ? ProProfile.fromJson(j['profile'] as Map<String, dynamic>)
            : null,
        phoneNumber: _s((j['identity'] as Map<String, dynamic>?)?['phoneNumber']),
        services: _maps(j['services']).map(ProServiceItem.fromJson).toList(),
        receivingActive: j['receivingActive'] == true,
      );

  final ProProfile? profile;
  final String? phoneNumber;
  final List<ProServiceItem> services;
  final bool receivingActive;

  bool get isPro => profile != null;

  /// Empty for a complete pro, and for someone who is not a pro at all.
  List<ProSetupItem> get missingSetup {
    final p = profile;
    if (p == null) return const [];
    return [
      if (!p.isComplete) ProSetupItem.profile,
      if (!services.any((s) => s.isActive)) ProSetupItem.services,
    ];
  }
}

/// A service the AI proposes; the pro keeps, edits or drops it.
class ServiceProposal {
  ServiceProposal({
    required this.name,
    required this.category,
    required this.profession,
    this.synonyms = const [],
    this.specialties = const [],
  });

  factory ServiceProposal.fromJson(Map<String, dynamic> j) => ServiceProposal(
        name: _s(j['name']) ?? '',
        category: _s(j['category']) ?? '',
        profession: _s(j['profession']) ?? '',
        synonyms: _list(j['synonyms']),
        specialties: _list(j['specialties']),
      );

  String name;
  final String category;
  final String profession;
  final List<String> synonyms;
  final List<String> specialties;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'profession': profession,
        'synonyms': synonyms,
        'specialties': specialties,
      };
}

/// "Mes statistiques" (backend `ProStats`).
class ProStats {
  const ProStats({
    this.received = 0,
    this.responded = 0,
    this.selected = 0,
    this.completed = 0,
    this.responseRate = 0,
    this.conversionRate = 0,
    this.topServices = const [],
  });

  factory ProStats.fromJson(Map<String, dynamic> j) => ProStats(
        received: _i(j['received']) ?? 0,
        responded: _i(j['responded']) ?? 0,
        selected: _i(j['selected']) ?? 0,
        completed: _i(j['completed']) ?? 0,
        responseRate: (j['responseRate'] as num?)?.toDouble() ?? 0,
        conversionRate: (j['conversionRate'] as num?)?.toDouble() ?? 0,
        topServices: _maps(j['topServices'])
            .map((m) => (name: _s(m['name']) ?? '—', count: _i(m['count']) ?? 0))
            .toList(),
      );

  final int received;
  final int responded;
  final int selected;
  final int completed;
  final double responseRate;
  final double conversionRate;
  final List<({String name, int count})> topServices;
}

/// The profile the AI setup conversation is building (backend `ProDraft`).
/// Sent back on every turn: the server keeps no state.
class ProDraft {
  const ProDraft(this.json);
  final Map<String, dynamic> json;

  Map<String, dynamic> get profile => (json['profile'] as Map<String, dynamic>?) ?? const {};
  List<Map<String, dynamic>> get services => _maps(json['services']);
}

/// One turn of the setup conversation (backend `AssistantTurn`).
class AssistantTurn {
  const AssistantTurn({
    required this.reply,
    required this.options,
    required this.draft,
    required this.complete,
    required this.available,
  });

  factory AssistantTurn.fromJson(Map<String, dynamic> j) => AssistantTurn(
        reply: _s(j['reply']) ?? '',
        options: _list(j['options']),
        draft: ProDraft((j['draft'] as Map<String, dynamic>?) ?? const {}),
        complete: j['complete'] == true,
        available: j['available'] != false,
      );

  final String reply;
  final List<String> options;
  final ProDraft draft;
  final bool complete;
  final bool available;
}

/// Blank, or a stand-in someone typed to fill the field ("À compléter").
bool isPlaceholder(String? value) {
  final folded = (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e');
  return folded.isEmpty || folded.startsWith('a completer') || folded == '-' || folded == '...';
}

/// An http(s) link that is not a stand-in like example.com.
bool isRealLink(String? value) {
  final uri = Uri.tryParse((value ?? '').trim());
  if (uri == null || !uri.scheme.startsWith('http') || !uri.host.contains('.')) return false;
  return !RegExp(r'(^|\.)example\.(com|org|net)$').hasMatch(uri.host);
}

/// "15 000 FCFA", with the French thousands separator.
String fcfa(int amount) => '${NumberFormat.decimalPattern('fr').format(amount)} FCFA';

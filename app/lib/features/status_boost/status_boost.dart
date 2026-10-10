import 'package:sbc_contacts/core/network/api_client.dart';

/// One member in "Je veux augmenter mon nombre de vues en statut WhatsApp".
class StatusBoostEntry {
  const StatusBoostEntry({
    required this.sbcId,
    required this.name,
    required this.phoneNumber,
    required this.subscriptionTypes,
    required this.savedByMe,
    required this.savedMe,
    this.avatarUrl,
    this.country,
  });

  factory StatusBoostEntry.fromJson(Map<String, dynamic> json) => StatusBoostEntry(
        sbcId: json['sbcId'] as String,
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? (json['name'] as String).trim()
            : 'Membre SBC',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        country: json['country'] as String?,
        subscriptionTypes: [
          for (final t in json['subscriptionTypes'] as List? ?? const []) t.toString(),
        ],
        savedByMe: json['savedByMe'] == true,
        savedMe: json['savedMe'] == true,
      );

  final String sbcId;
  final String name;
  final String phoneNumber;
  final String? avatarUrl;
  final String? country;
  final List<String> subscriptionTypes;

  /// Already in this phone, as far as the app recorded.
  final bool savedByMe;

  /// This member already saved the caller — the one to save back first.
  final bool savedMe;

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class StatusBoostPage {
  const StatusBoostPage({
    required this.items,
    required this.total,
    required this.hasMore,
    required this.subscriptionTypes,
  });

  factory StatusBoostPage.fromJson(Map<String, dynamic> json) => StatusBoostPage(
        items: [
          for (final i in json['items'] as List? ?? const [])
            StatusBoostEntry.fromJson(i as Map<String, dynamic>),
        ],
        total: (json['total'] as num?)?.toInt() ?? 0,
        hasMore: json['hasMore'] == true,
        subscriptionTypes: [
          for (final t in json['subscriptionTypes'] as List? ?? const []) t.toString(),
        ],
      );

  final List<StatusBoostEntry> items;
  final int total;
  final bool hasMore;

  /// Subscription types present among participants, for the filter chips.
  final List<String> subscriptionTypes;
}

/// Whether the caller takes part, and how many members do.
class StatusBoostMe {
  const StatusBoostMe({
    required this.optIn,
    required this.participants,
    required this.hasPhone,
  });

  factory StatusBoostMe.fromJson(Map<String, dynamic> json) => StatusBoostMe(
        optIn: json['optIn'] == true,
        participants: (json['participants'] as num?)?.toInt() ?? 0,
        hasPhone: json['hasPhone'] != false,
      );

  final bool optIn;
  final int participants;

  /// Without a number on the SBC account, nobody can save this member back.
  final bool hasPhone;
}

class StatusBoostRepository {
  StatusBoostRepository(this._api);
  final ApiClient _api;

  Future<StatusBoostPage> list({
    String? subscription,
    String? search,
    int page = 1,
    int limit = 30,
  }) async {
    final data = await _api.get('/status-boost', query: {
      'page': page,
      'limit': limit,
      if (subscription != null) 'subscription': subscription,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    }) as Map<String, dynamic>;
    return StatusBoostPage.fromJson(data);
  }

  Future<StatusBoostMe> me() async =>
      StatusBoostMe.fromJson(await _api.get('/status-boost/me') as Map<String, dynamic>);

  Future<StatusBoostMe> setOptIn({required bool optIn}) async => StatusBoostMe.fromJson(
        await _api.put('/status-boost/me', body: {'optIn': optIn}) as Map<String, dynamic>,
      );
}

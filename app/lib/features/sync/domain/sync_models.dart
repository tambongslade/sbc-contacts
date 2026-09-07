/// Saved sync criteria (backend `SyncCriteria`).
class SyncCriteria {
  const SyncCriteria({
    required this.id,
    required this.label,
    this.countries = const [],
    this.cities = const [],
    this.professions = const [],
    this.interests = const [],
    this.sex,
    this.ageMin,
    this.ageMax,
    this.isActive = true,
    this.lastMatchCount = 0,
  });

  factory SyncCriteria.fromJson(Map<String, dynamic> json) {
    List<String> l(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
    return SyncCriteria(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      countries: l(json['countries']),
      cities: l(json['cities']),
      professions: l(json['professions']),
      interests: l(json['interests']),
      sex: json['sex'] as String?,
      ageMin: (json['ageMin'] as num?)?.toInt(),
      ageMax: (json['ageMax'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? true,
      lastMatchCount: (json['lastMatchCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String label;
  final List<String> countries;
  final List<String> cities;
  final List<String> professions;
  final List<String> interests;
  final String? sex;
  final int? ageMin;
  final int? ageMax;
  final bool isActive;
  final int lastMatchCount;

  Map<String, dynamic> toPayload() => {
        'label': label,
        'countries': countries,
        'cities': cities,
        'professions': professions,
        'interests': interests,
        if (sex != null) 'sex': sex,
        if (ageMin != null) 'ageMin': ageMin,
        if (ageMax != null) 'ageMax': ageMax,
        'isActive': isActive,
      };
}

/// A member proposed for synchronisation, with the backend dedup hint.
class SyncTarget {
  const SyncTarget({
    required this.memberSbcId,
    this.name,
    this.firstName,
    this.profession,
    this.city,
    this.country,
    this.avatarUrl,
    this.phoneNumber,
    this.alreadySynced = false,
  });

  factory SyncTarget.fromJson(Map<String, dynamic> json) => SyncTarget(
        memberSbcId: (json['memberSbcId'] ?? '').toString(),
        name: json['name'] as String?,
        firstName: json['firstName'] as String?,
        profession: json['profession'] as String?,
        city: json['city'] as String?,
        country: json['country'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        alreadySynced: json['alreadySynced'] as bool? ?? false,
      );

  final String memberSbcId;
  final String? name;
  final String? firstName;
  final String? profession;
  final String? city;
  final String? country;
  final String? avatarUrl;
  final String? phoneNumber;
  final bool alreadySynced;

  String get displayName =>
      [firstName, name].where((e) => e != null && e.isNotEmpty).join(' ').trim();
}

/// Result of starting a sync run.
class SyncRunStart {
  const SyncRunStart({
    required this.syncRunId,
    required this.deviceId,
    required this.matchCount,
    required this.pendingCount,
    required this.items,
  });

  factory SyncRunStart.fromJson(Map<String, dynamic> json) => SyncRunStart(
        syncRunId: (json['syncRunId'] ?? '').toString(),
        deviceId: (json['deviceId'] ?? '').toString(),
        matchCount: (json['matchCount'] as num?)?.toInt() ?? 0,
        pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
        items: (json['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(SyncTarget.fromJson)
            .toList(),
      );

  final String syncRunId;
  final String deviceId;
  final int matchCount;
  final int pendingCount;
  final List<SyncTarget> items;
}

/// "Mes contacts SBC" dashboard counters.
class SyncSummary {
  const SyncSummary({
    required this.syncedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.activeCriteria,
    required this.currentMatches,
    this.lastSyncAt,
  });

  factory SyncSummary.fromJson(Map<String, dynamic> json) => SyncSummary(
        syncedCount: (json['syncedCount'] as num?)?.toInt() ?? 0,
        pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
        activeCriteria: (json['activeCriteria'] as num?)?.toInt() ?? 0,
        currentMatches: (json['currentMatches'] as num?)?.toInt() ?? 0,
        lastSyncAt: json['lastSyncAt'] == null
            ? null
            : DateTime.tryParse(json['lastSyncAt'].toString()),
      );

  final int syncedCount;
  final int pendingCount;
  final int failedCount;
  final int activeCriteria;
  final int currentMatches;
  final DateTime? lastSyncAt;
}

/// One member already written (or attempted) to a device — "Mes contacts SBC"
/// (cahier §16). `status` mirrors the backend SyncStatus enum.
class SyncedContact {
  const SyncedContact({
    required this.memberSbcId,
    required this.status,
    this.name,
    this.firstName,
    this.profession,
    this.city,
    this.country,
    this.avatarUrl,
    this.phoneNumber,
    this.syncedAt,
  });

  factory SyncedContact.fromJson(Map<String, dynamic> json) => SyncedContact(
        memberSbcId: (json['memberSbcId'] ?? '').toString(),
        status: (json['status'] ?? 'PENDING').toString(),
        name: json['name'] as String?,
        firstName: json['firstName'] as String?,
        profession: json['profession'] as String?,
        city: json['city'] as String?,
        country: json['country'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        syncedAt: json['syncedAt'] == null
            ? null
            : DateTime.tryParse(json['syncedAt'].toString()),
      );

  final String memberSbcId;
  final String status;
  final String? name;
  final String? firstName;
  final String? profession;
  final String? city;
  final String? country;
  final String? avatarUrl;
  final String? phoneNumber;
  final DateTime? syncedAt;

  String get displayName {
    final n = [firstName, name].where((e) => e != null && e.isNotEmpty).join(' ').trim();
    return n.isEmpty ? 'Membre SBC' : n;
  }

  String get location =>
      [city, country].whereType<String>().where((e) => e.isNotEmpty).join(', ');
}

/// One synchronisation run, for the history view (cahier §17).
class SyncRunEntry {
  const SyncRunEntry({
    required this.id,
    required this.status,
    required this.matchCount,
    required this.syncedCount,
    required this.failedCount,
    this.error,
    this.startedAt,
    this.finishedAt,
  });

  factory SyncRunEntry.fromJson(Map<String, dynamic> json) => SyncRunEntry(
        id: (json['id'] ?? '').toString(),
        status: (json['status'] ?? 'PENDING').toString(),
        matchCount: (json['matchCount'] as num?)?.toInt() ?? 0,
        syncedCount: (json['syncedCount'] as num?)?.toInt() ?? 0,
        failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
        error: json['error'] as String?,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.tryParse(json['startedAt'].toString()),
        finishedAt: json['finishedAt'] == null
            ? null
            : DateTime.tryParse(json['finishedAt'].toString()),
      );

  final String id;
  final String status;
  final int matchCount;
  final int syncedCount;
  final int failedCount;
  final String? error;
  final DateTime? startedAt;
  final DateTime? finishedAt;
}

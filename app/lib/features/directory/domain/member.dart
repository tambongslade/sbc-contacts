/// A directory member as returned by the backend `MemberView`. Parsed
/// defensively — the underlying SBC field set isn't fully frozen yet.
class Member {
  const Member({
    required this.id,
    required this.sbcId,
    this.name,
    this.firstName,
    this.profession,
    this.city,
    this.country,
    this.sex,
    this.age,
    this.interests = const [],
    this.skills = const [],
    this.avatarUrl,
    this.phoneNumber,
    this.isFavorite = false,
    this.isSynced = false,
    this.confidenceScore = 50,
    this.averageRating,
    this.reviewCount = 0,
    this.myRating,
  });

  factory Member.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    return Member(
      id: (json['id'] ?? '').toString(),
      sbcId: (json['sbcId'] ?? json['id'] ?? '').toString(),
      name: json['name'] as String?,
      firstName: json['firstName'] as String?,
      profession: json['profession'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      sex: json['sex'] as String?,
      age: (json['age'] as num?)?.toInt(),
      interests: strList(json['interests']),
      skills: strList(json['skills']),
      avatarUrl: json['avatarUrl'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      isSynced: json['isSynced'] as bool? ?? false,
      confidenceScore: (json['confidenceScore'] as num?)?.toInt() ?? 50,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      myRating: (json['myRating'] as num?)?.toInt(),
    );
  }

  final String id;
  final String sbcId;
  final String? name;
  final String? firstName;
  final String? profession;
  final String? city;
  final String? country;
  final String? sex;
  final int? age;
  final List<String> interests;
  final List<String> skills;
  final String? avatarUrl;
  final String? phoneNumber;
  final bool isFavorite;
  final bool isSynced;

  /// Reputation ("Score de confiance"), 0-100, neutral 50 when unrated.
  final int confidenceScore;
  final double? averageRating;
  final int reviewCount;

  /// The caller's own star rating for this member, if any.
  final int? myRating;

  String get displayName {
    final parts = [firstName, name].where((e) => e != null && e.isNotEmpty);
    final full = parts.join(' ').trim();
    return full.isEmpty ? 'Membre SBC' : full;
  }

  String get initials {
    final f = (firstName ?? name ?? '?').trim();
    return f.isEmpty ? '?' : f[0].toUpperCase();
  }

  String get location =>
      [city, country].where((e) => e != null && e.isNotEmpty).join(', ');

  Member copyWith({bool? isFavorite, bool? isSynced}) => Member(
        id: id,
        sbcId: sbcId,
        name: name,
        firstName: firstName,
        profession: profession,
        city: city,
        country: country,
        sex: sex,
        age: age,
        interests: interests,
        skills: skills,
        avatarUrl: avatarUrl,
        phoneNumber: phoneNumber,
        isFavorite: isFavorite ?? this.isFavorite,
        isSynced: isSynced ?? this.isSynced,
        confidenceScore: confidenceScore,
        averageRating: averageRating,
        reviewCount: reviewCount,
        myRating: myRating,
      );
}

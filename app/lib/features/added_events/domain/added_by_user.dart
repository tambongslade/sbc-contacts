/// A person who added the caller to their phone contacts (cahier §21).
///
/// Returned by `GET /added-events/who-added-me`. Parsed defensively — the
/// backend field set for this new endpoint isn't fully frozen yet.
class AddedByUser {
  const AddedByUser({
    required this.actorUserId,
    this.name,
    this.avatarUrl,
    this.phoneNumber,
    this.country,
    this.addedAt,
  });

  factory AddedByUser.fromJson(Map<String, dynamic> json) => AddedByUser(
        actorUserId: (json['actorUserId'] ?? '').toString(),
        name: json['name'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        country: json['country'] as String?,
        addedAt: DateTime.tryParse((json['addedAt'] ?? '').toString()),
      );

  final String actorUserId;
  final String? name;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? country;
  final DateTime? addedAt;

  String get displayName =>
      (name == null || name!.trim().isEmpty) ? 'Membre SBC' : name!.trim();

  String get initials {
    final n = displayName.trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }
}

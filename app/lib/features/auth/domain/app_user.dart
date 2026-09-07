/// The authenticated user (backend `PublicUser`). Identity comes from SBC.
class AppUser {
  const AppUser({
    required this.id,
    required this.sbcUserId,
    this.name,
    this.email,
    this.phoneNumber,
    this.country,
    this.avatarUrl,
    this.subscriptionTypes = const [],
    this.isActivated = false,
    this.role = 'USER',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] ?? '').toString(),
        sbcUserId: (json['sbcUserId'] ?? '').toString(),
        name: json['name'] as String?,
        email: json['email'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        country: json['country'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        subscriptionTypes: (json['subscriptionTypes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        isActivated: json['isActivated'] as bool? ?? false,
        role: (json['role'] ?? 'USER').toString(),
      );

  final String id;
  final String sbcUserId;
  final String? name;
  final String? email;
  final String? phoneNumber;
  final String? country;
  final String? avatarUrl;
  final List<String> subscriptionTypes;
  final bool isActivated;
  final String role;

  bool get hasActiveSubscription => subscriptionTypes.isNotEmpty;
  String get displayName => (name == null || name!.isEmpty) ? 'Membre SBC' : name!;
}

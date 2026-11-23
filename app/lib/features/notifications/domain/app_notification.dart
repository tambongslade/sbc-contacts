/// In-app notification (backend `Notification`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.data = const {},
    this.link,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
            DateTime(2020),
        readAt: json['readAt'] == null
            ? null
            : DateTime.tryParse(json['readAt'].toString()),
        data: (json['data'] as Map<String, dynamic>?) ?? const {},
        link: (json['link'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['link'] as String).trim(),
      );

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> data;

  /// App path (go_router location) a tap opens; null when there is none.
  final String? link;

  bool get isRead => readAt != null;
}

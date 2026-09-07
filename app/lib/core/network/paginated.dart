/// Mirrors the backend `PaginatedResult<T>` shape.
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasMore,
  });

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = (json['items'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(itemFromJson)
        .toList();
    return Paginated<T>(
      items: rawItems,
      total: (json['total'] as num?)?.toInt() ?? rawItems.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? rawItems.length,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 1,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  final List<T> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasMore;

  Paginated<T> concat(Paginated<T> next) => Paginated<T>(
        items: [...items, ...next.items],
        total: next.total,
        page: next.page,
        limit: next.limit,
        totalPages: next.totalPages,
        hasMore: next.hasMore,
      );
}

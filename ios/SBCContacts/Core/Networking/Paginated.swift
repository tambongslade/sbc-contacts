import Foundation

/// Mirrors the backend `PaginatedResult<T>` shape.
struct Paginated<T: Sendable>: Sendable {
    var items: [T]
    var total: Int
    var page: Int
    var limit: Int
    var totalPages: Int
    var hasMore: Bool

    func concat(_ next: Paginated<T>) -> Paginated<T> {
        Paginated(
            items: items + next.items,
            total: next.total,
            page: next.page,
            limit: next.limit,
            totalPages: next.totalPages,
            hasMore: next.hasMore
        )
    }

    func map<U: Sendable>(_ transform: (T) -> U) -> Paginated<U> {
        Paginated<U>(
            items: items.map(transform),
            total: total,
            page: page,
            limit: limit,
            totalPages: totalPages,
            hasMore: hasMore
        )
    }
}

extension Paginated: Decodable where T: Decodable {
    private enum CodingKeys: String, CodingKey {
        case items, total, page, limit, totalPages, hasMore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([Lossy<T>].self, forKey: .items)) ?? []
        items = raw.compactMap(\.value)
        total = c.int(.total) ?? items.count
        page = c.int(.page) ?? 1
        limit = c.int(.limit) ?? items.count
        totalPages = c.int(.totalPages) ?? 1
        hasMore = c.bool(.hasMore) ?? false
    }
}

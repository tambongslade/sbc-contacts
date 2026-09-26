import Foundation

/// In-app notification (backend `Notification`).
struct AppNotification: Identifiable, Sendable, Equatable {
    var id: String
    var type: String
    var title: String
    var body: String
    var createdAt: Date
    var readAt: Date?

    /// Who the alert is about, from the notification's `data` payload. A
    /// NEW_MATCH carries it, which is what lets the row offer to save the
    /// person without first asking the backend who they are.
    var memberSbcId: String?
    var criteriaId: String?

    var isRead: Bool { readAt != nil }
}

extension AppNotification: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, type, title, body, createdAt, readAt, data
    }

    /// Keys inside the free-form `data` object the backend attaches.
    private enum DataKeys: String, CodingKey {
        case memberSbcId, criteriaId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        type = c.string(.type) ?? ""
        title = c.string(.title) ?? ""
        body = c.string(.body) ?? ""
        createdAt = c.date(.createdAt) ?? Date(timeIntervalSince1970: 1_577_836_800)
        readAt = c.date(.readAt)
        // Absent on notification types that carry no member, and absent on
        // older rows written before the payload existed — hence optional, never
        // a decoding failure.
        let payload = try? c.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        memberSbcId = payload?.string(.memberSbcId)
        criteriaId = payload?.string(.criteriaId)
    }
}

struct NotificationsRepository: Sendable {
    let api: APIClient

    private struct Count: Decodable, Sendable {
        let count: Int

        private enum CodingKeys: String, CodingKey { case count }

        init(from decoder: Decoder) throws {
            count = (try decoder.container(keyedBy: CodingKeys.self)).int(.count) ?? 0
        }
    }

    private struct DeviceBody: Encodable, Sendable {
        let platform: String
        let pushToken: String?
    }

    func list(page: Int = 1, limit: Int = 30, unreadOnly: Bool = false) async throws -> Paginated<AppNotification> {
        var query: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
        ]
        if unreadOnly { query.append(.init(name: "unreadOnly", value: "true")) }
        return try await api.get("/notifications", query: query)
    }

    func unreadCount() async throws -> Int {
        let result: Count = try await api.get("/notifications/unread-count")
        return result.count
    }

    func markRead(id: String) async throws {
        try await api.post("/notifications/\(id)/read")
    }

    func markAllRead() async throws {
        try await api.post("/notifications/read-all")
    }

    func registerDevice(platform: String, pushToken: String?) async throws {
        try await api.post("/notifications/devices", body: DeviceBody(platform: platform, pushToken: pushToken))
    }
}

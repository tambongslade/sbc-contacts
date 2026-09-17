import Foundation

/// A favorited member (backend `FavoriteItem`), mapped onto `Member` for reuse.
struct FavoriteItem: Decodable, Sendable {
    let member: Member

    private enum CodingKeys: String, CodingKey {
        case memberSbcId, name, firstName, profession, city, country, avatarUrl, phoneNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sbcId = c.string(.memberSbcId) ?? ""
        member = Member(
            id: sbcId,
            sbcId: sbcId,
            name: c.string(.name),
            firstName: c.string(.firstName),
            profession: c.string(.profession),
            city: c.string(.city),
            country: c.string(.country),
            avatarUrl: c.string(.avatarUrl),
            phoneNumber: c.string(.phoneNumber),
            isFavorite: true
        )
    }
}

struct FavoritesRepository: Sendable {
    let api: APIClient

    private struct AddBody: Encodable, Sendable {
        let memberSbcId: String
    }

    func list(page: Int = 1, limit: Int = 50) async throws -> Paginated<Member> {
        let result: Paginated<FavoriteItem> = try await api.get(
            "/favorites",
            query: [.init(name: "page", value: String(page)), .init(name: "limit", value: String(limit))]
        )
        return result.map(\.member)
    }

    func add(memberSbcId: String) async throws {
        try await api.post("/favorites", body: AddBody(memberSbcId: memberSbcId))
    }

    func remove(memberSbcId: String) async throws {
        try await api.delete("/favorites/\(memberSbcId)")
    }
}

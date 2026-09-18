import Foundation

struct DirectoryRepository: Sendable {
    let api: APIClient

    func search(_ filters: SearchFilters, page: Int = 1, limit: Int = 20) async throws -> Paginated<Member> {
        try await api.get("/directory/search", query: filters.queryItems(page: page, limit: limit))
    }

    /// Régions per country, built by the backend from its member mirror.
    func regions() async throws -> [RegionEntry] {
        let result: RegionsResponse = try await api.get("/directory/regions")
        return result.regions
    }

    private struct RegionsResponse: Decodable, Sendable {
        let regions: [RegionEntry]

        private enum CodingKeys: String, CodingKey { case regions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            regions = ((try? c.decodeIfPresent([Lossy<RegionEntry>].self, forKey: .regions)) ?? []).compactMap(\.value)
        }
    }

    func profile(sbcId: String) async throws -> Member {
        try await api.get("/directory/members/\(sbcId)")
    }
}

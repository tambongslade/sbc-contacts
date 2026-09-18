import Foundation

struct ReviewsRepository: Sendable {
    let api: APIClient

    private struct SubmitBody: Encodable, Sendable {
        let memberSbcId: String
        let stars: Int
        let comment: String?
    }

    private struct SubmitResult: Decodable, Sendable {
        let summary: ScoreSummary

        private enum CodingKeys: String, CodingKey { case summary }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            summary = (try? c.decodeIfPresent(ScoreSummary.self, forKey: .summary)) ?? ScoreSummary()
        }
    }

    /// A page of reviews for a member, with the aggregate score and the caller's
    /// own review.
    func list(memberSbcId: String, page: Int = 1, limit: Int = 20) async throws -> MemberReviews {
        try await api.get(
            "/reviews/\(memberSbcId)",
            query: [.init(name: "page", value: String(page)), .init(name: "limit", value: String(limit))]
        )
    }

    /// Create or update the caller's review (upsert). Returns the fresh aggregate.
    @discardableResult
    func submit(memberSbcId: String, stars: Int, comment: String?) async throws -> ScoreSummary {
        let trimmed = comment?.isEmpty == false ? comment : nil
        let result: SubmitResult = try await api.post(
            "/reviews",
            body: SubmitBody(memberSbcId: memberSbcId, stars: stars, comment: trimmed)
        )
        return result.summary
    }

    /// Delete the caller's own review. Returns the fresh aggregate.
    @discardableResult
    func remove(memberSbcId: String) async throws -> ScoreSummary {
        try await api.delete("/reviews/\(memberSbcId)")
    }
}

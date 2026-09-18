import Foundation

/// A single review of a member (backend `ReviewView`).
struct Review: Identifiable, Sendable, Equatable {
    var id: String
    var memberSbcId: String
    var stars: Int
    var comment: String?
    var reviewerName: String?
    var reviewerAvatarUrl: String?
    var isMine = false
    var createdAt: Date?
    var updatedAt: Date?

    var reviewerDisplayName: String {
        (reviewerName?.isEmpty ?? true) ? "Membre SBC" : reviewerName!
    }

    var reviewerInitials: String {
        reviewerDisplayName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

extension Review: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, memberSbcId, stars, comment, reviewerName, reviewerAvatarUrl, isMine, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        memberSbcId = c.string(.memberSbcId) ?? ""
        stars = c.int(.stars) ?? 0
        comment = c.string(.comment)
        reviewerName = c.string(.reviewerName)
        reviewerAvatarUrl = c.string(.reviewerAvatarUrl)
        isMine = c.bool(.isMine) ?? false
        createdAt = c.date(.createdAt)
        updatedAt = c.date(.updatedAt)
    }
}

/// Aggregate reputation for a member (backend `ScoreSummary`), returned
/// alongside the review list and after each write.
struct ScoreSummary: Sendable, Equatable {
    var memberSbcId = ""
    var averageStars: Double = 0
    var reviewCount = 0
    var confidenceScore = 50
}

extension ScoreSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case memberSbcId, averageStars, reviewCount, confidenceScore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberSbcId = c.string(.memberSbcId) ?? ""
        averageStars = c.double(.averageStars) ?? 0
        reviewCount = c.int(.reviewCount) ?? 0
        confidenceScore = c.int(.confidenceScore) ?? 50
    }
}

/// A page of a member's reviews plus the aggregate and the caller's own review
/// (backend `MemberReviewsResult`).
struct MemberReviews: Sendable, Equatable {
    var reviews: [Review]
    var summary: ScoreSummary
    var hasMore: Bool
    var page: Int
    var myReview: Review?
}

extension MemberReviews: Decodable {
    private enum CodingKeys: String, CodingKey {
        case items, summary, hasMore, page, myReview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviews = ((try? c.decodeIfPresent([Lossy<Review>].self, forKey: .items)) ?? []).compactMap(\.value)
        summary = (try? c.decodeIfPresent(ScoreSummary.self, forKey: .summary)) ?? ScoreSummary()
        hasMore = c.bool(.hasMore) ?? false
        page = c.int(.page) ?? 1
        myReview = try? c.decodeIfPresent(Review.self, forKey: .myReview)
    }
}

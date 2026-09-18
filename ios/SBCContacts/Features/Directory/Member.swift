import Foundation

/// A directory member as returned by the backend `MemberView`. Parsed
/// defensively — the underlying SBC field set isn't fully frozen yet.
struct Member: Identifiable, Sendable, Equatable, Hashable {
    var id: String
    var sbcId: String
    var name: String?
    var firstName: String?
    var profession: String?
    var city: String?
    var country: String?
    var sex: String?
    var age: Int?
    var interests: [String] = []
    var skills: [String] = []
    var avatarUrl: String?
    var phoneNumber: String?
    var isFavorite = false
    var isSynced = false

    /// Reputation ("Score de confiance"), 0-100, neutral 50 when unrated.
    var confidenceScore = 50
    var averageRating: Double?
    var reviewCount = 0

    /// The caller's own star rating for this member, if any.
    var myRating: Int?

    var displayName: String {
        let full = [firstName, name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Membre SBC" : full
    }

    var initials: String {
        let f = (firstName ?? name ?? "?").trimmingCharacters(in: .whitespaces)
        return f.first.map { String($0).uppercased() } ?? "?"
    }

    var location: String {
        [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension Member: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, sbcId, name, firstName, profession, city, country, sex, age, interests, skills
        case avatarUrl, phoneNumber, isFavorite, isSynced, confidenceScore, averageRating, reviewCount, myRating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        sbcId = c.string(.sbcId) ?? c.string(.id) ?? ""
        name = c.string(.name)
        firstName = c.string(.firstName)
        profession = c.string(.profession)
        city = c.string(.city)
        country = c.string(.country)
        sex = c.string(.sex)
        age = c.int(.age)
        interests = c.strings(.interests)
        skills = c.strings(.skills)
        avatarUrl = c.string(.avatarUrl)
        phoneNumber = c.string(.phoneNumber)
        isFavorite = c.bool(.isFavorite) ?? false
        isSynced = c.bool(.isSynced) ?? false
        confidenceScore = c.int(.confidenceScore) ?? 50
        averageRating = c.double(.averageRating)
        reviewCount = c.int(.reviewCount) ?? 0
        myRating = c.int(.myRating)
    }
}

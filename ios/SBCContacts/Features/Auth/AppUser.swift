import Foundation

/// The authenticated user (backend `PublicUser`). Identity comes from SBC.
struct AppUser: Sendable, Equatable {
    var id: String
    var sbcUserId: String
    var name: String?
    var email: String?
    var phoneNumber: String?
    var country: String?
    var avatarUrl: String?
    var subscriptionTypes: [String] = []
    var isActivated = false
    var role = "USER"

    var hasActiveSubscription: Bool { !subscriptionTypes.isEmpty }
    var displayName: String { (name?.isEmpty ?? true) ? "Membre SBC" : name! }
}

extension AppUser: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, sbcUserId, name, email, phoneNumber, country, avatarUrl, subscriptionTypes, isActivated, role
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        sbcUserId = c.string(.sbcUserId) ?? ""
        name = c.string(.name)
        email = c.string(.email)
        phoneNumber = c.string(.phoneNumber)
        country = c.string(.country)
        avatarUrl = c.string(.avatarUrl)
        subscriptionTypes = c.strings(.subscriptionTypes)
        isActivated = c.bool(.isActivated) ?? false
        role = c.string(.role) ?? "USER"
    }
}

/// `POST /auth/sso-callback` response.
struct SSOSession: Decodable, Sendable {
    struct Tokens: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
    }

    let tokens: Tokens
    let user: AppUser
}

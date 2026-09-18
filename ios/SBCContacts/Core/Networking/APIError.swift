import Foundation

/// Normalised API error mirroring the backend's error envelope
/// `{ success:false, statusCode, message, code, errors }`.
struct APIError: Error, LocalizedError, Sendable, Equatable {
    /// 0 for transport failures (offline, timeout, DNS…).
    let statusCode: Int
    let message: String
    let code: String?

    init(statusCode: Int, message: String, code: String? = nil) {
        self.statusCode = statusCode
        self.message = message
        self.code = code
    }

    var isUnauthorized: Bool { statusCode == 401 }
    var isForbidden: Bool { statusCode == 403 }
    var isSubscriptionRequired: Bool { code == "SUBSCRIPTION_REQUIRED" }

    var errorDescription: String? { message }
}

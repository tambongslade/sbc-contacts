import Foundation

struct AuthRepository: Sendable {
    let api: APIClient
    let storage: TokenStorage

    private struct CallbackBody: Encodable, Sendable {
        let code: String
        let redirectUri: String
        let deviceId: String?
    }

    private struct LogoutBody: Encodable, Sendable {
        let refreshToken: String
    }

    /// Exchange the SBC authorization code for an app session and persist tokens.
    func ssoCallback(code: String, deviceId: String? = nil) async throws -> AppUser {
        let session: SSOSession = try await api.post(
            "/auth/sso-callback",
            // SBC requires the exchange to repeat the redirect_uri used on
            // /sso/authorize; the backend cannot know which flow we took.
            body: CallbackBody(code: code, redirectUri: AppConfig.ssoRedirectURI, deviceId: deviceId)
        )
        await storage.save(access: session.tokens.accessToken, refresh: session.tokens.refreshToken)
        return session.user
    }

    func me() async throws -> AppUser {
        try await api.get("/auth/me")
    }

    func refreshProfile() async throws -> AppUser {
        try await api.get("/auth/me/refresh-profile")
    }

    func logout() async {
        if let refresh = await storage.readRefresh() {
            // Best-effort; clear locally regardless.
            try? await api.post("/auth/logout", body: LogoutBody(refreshToken: refresh))
        }
        await storage.clear()
    }

    func hasSession() async -> Bool {
        await storage.readAccess() != nil
    }
}

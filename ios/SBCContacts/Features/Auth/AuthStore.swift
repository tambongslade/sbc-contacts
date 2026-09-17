import Foundation
import Observation

/// Holds the authenticated user. On launch it restores a session from the
/// stored token by calling `/auth/me`.
@MainActor
@Observable
final class AuthStore {
    enum Phase: Equatable {
        case restoring
        case signedOut
        case signedIn(AppUser)
    }

    private(set) var phase: Phase = .restoring
    /// True while an authorization code is being exchanged.
    private(set) var isExchangingCode = false
    /// Why the last sign-in failed, shown under the login button.
    private(set) var loginError: Error?

    private let repo: AuthRepository

    init(repo: AuthRepository) {
        self.repo = repo
    }

    var user: AppUser? {
        if case let .signedIn(user) = phase { return user }
        return nil
    }

    func restore() async {
        guard await repo.hasSession() else {
            phase = .signedOut
            return
        }
        do {
            phase = .signedIn(try await repo.me())
        } catch {
            phase = .signedOut // token invalid/expired → treat as signed out
        }
    }

    /// Complete SSO by exchanging the code from SBC's consent redirect.
    func login(code: String, deviceId: String? = nil) async {
        guard !isExchangingCode else { return }
        isExchangingCode = true
        loginError = nil
        defer { isExchangingCode = false }
        do {
            phase = .signedIn(try await repo.ssoCallback(code: code, deviceId: deviceId))
        } catch {
            loginError = error
            phase = .signedOut
        }
    }

    func logout() async {
        await repo.logout()
        loginError = nil
        phase = .signedOut
    }

    /// Re-reads the profile (and subscription) from SBC.
    ///
    /// Unlike the Flutter app, a failed refresh keeps the member signed in with
    /// the profile they already had: a flaky network should not bounce them to
    /// the login screen.
    func refreshProfile() async {
        guard case .signedIn = phase else { return }
        if let fresh = try? await repo.refreshProfile() {
            phase = .signedIn(fresh)
        }
    }

    /// Handles `sbccontacts://auth/callback?code=…` (or the https App Link)
    /// arriving as a deep link, so no manual paste is needed.
    func handleDeepLink(_ url: URL) {
        let isCallback = url.scheme == "sbccontacts"
            || (url.scheme == "https" && url.path.hasPrefix("/auth/callback"))
        guard isCallback,
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { return }
        Task { await login(code: code) }
    }
}

/// Human-readable reason for a failed login (surfaces the backend message).
func loginErrorMessage(_ error: Error?) -> String {
    if let error = error as? APIError {
        if error.isSubscriptionRequired { return "Abonnement SBC requis pour accéder aux contacts." }
        if error.statusCode == 400 { return "Code invalide, expiré ou déjà utilisé. Reconnecte-toi." }
        return error.message
    }
    return "Échec de connexion. Vérifie ta connexion et réessaie."
}

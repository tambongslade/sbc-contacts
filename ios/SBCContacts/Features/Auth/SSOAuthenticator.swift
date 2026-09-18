import AuthenticationServices
import Security
import UIKit

/// Runs "Log in with SBC" without leaving the app.
///
/// The consent page opens in an `ASWebAuthenticationSession` that the app owns,
/// and the `sbccontacts://` redirect is captured and handed straight back — no
/// switching to Safari, no copying a code by hand. The session shares Safari's
/// cookies, so a member already signed in to SBC goes straight to consent.
@MainActor
final class SSOAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Outcome {
        case code(String)
        case cancelled
        case failed(String)
    }

    private var session: ASWebAuthenticationSession?

    func authorize() async -> Outcome {
        let state = Self.newState()
        var components = URLComponents(url: AppConfig.ssoAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: AppConfig.ssoClientId),
            .init(name: "redirect_uri", value: AppConfig.ssoRedirectURI),
            .init(name: "scope", value: AppConfig.ssoScopes),
            // Mandatory per SSO_INTEGRATION_GUIDE.md: without it the callback
            // cannot be proven to belong to this request (CSRF).
            .init(name: "state", value: state),
        ]

        let callback: URL
        do {
            callback = try await start(url: components.url!)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return .cancelled // the member closed the sheet — not worth shouting about
        } catch {
            return .failed("Connexion impossible. Vérifie ta connexion et réessaie.")
        }

        let params = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String? { params.first { $0.name == name }?.value }

        if let error = param("error") {
            return .failed("SBC a refusé la connexion (\(error)).")
        }
        guard param("state") == state else {
            return .failed("Réponse de connexion invalide. Réessaie.")
        }
        guard let code = param("code"), !code.isEmpty else {
            return .failed("Aucun code reçu de SBC. Réessaie.")
        }
        return .code(code)
    }

    private func start(url: URL) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.ssoCallbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    /// Random, unguessable value tying the callback to this request.
    private static func newState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

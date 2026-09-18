import Foundation

/// Static app configuration.
///
/// The API base URL comes from the `API_BASE_URL` build setting (surfaced in
/// Info.plist as `APIBaseURL`) — the counterpart of Flutter's
/// `--dart-define=API_BASE_URL=...`. For a local backend on the simulator,
/// set it to `http://localhost:3030/api/v1`.
enum AppConfig {
    static let defaultAPIBaseURL = "https://contacts.sniperbusinesscenterlive.com/api/v1"

    static var apiBaseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String)?
            .trimmingCharacters(in: .whitespaces)
        if let raw, !raw.isEmpty, !raw.hasPrefix("$("), let url = URL(string: raw) {
            return url
        }
        return URL(string: defaultAPIBaseURL)!
    }

    /// SBC "Log in with SBC" authorize URL + client params (frontend side).
    static let ssoAuthorizeURL = URL(string: "https://sniperbuisnesscenter.com/sso/authorize")!

    /// Dedicated SBC Network SSO client (seeded on SBC's side).
    static let ssoClientId = "sbc-contacts"

    /// The custom scheme, not the web bridge. ASWebAuthenticationSession
    /// captures this redirect itself, so the code never has to be copied by
    /// hand. SBC requires the code exchange to repeat it verbatim.
    static let ssoRedirectURI = "sbccontacts://auth/callback"

    static let ssoScopes = "profile.read contacts.read"

    /// Scheme of `ssoRedirectURI` — tells the auth session which redirect ends it.
    static var ssoCallbackScheme: String { URL(string: ssoRedirectURI)?.scheme ?? "sbccontacts" }
}

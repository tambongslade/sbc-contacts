/// Static app configuration. The API base URL is compile-time configurable via
/// `--dart-define=API_BASE_URL=...`.
///
/// Defaults:
/// - Android emulator reaches the host machine on `10.0.2.2`.
/// - For a physical device, pass your machine's LAN IP.
/// - Integration tests override this to `http://localhost:3030/api/v1`.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Deployed backend. Override with --dart-define=API_BASE_URL=... for local
    // dev (e.g. http://10.0.2.2:3030/api/v1 on the Android emulator).
    defaultValue: 'https://contacts.sniperbusinesscenterlive.com/api/v1',
  );

  /// SBC "Log in with SBC" authorize URL + client params (frontend side).
  static const String ssoAuthorizeUrl = String.fromEnvironment(
    'SBC_SSO_AUTHORIZE_URL',
    defaultValue: 'https://sniperbuisnesscenter.com/sso/authorize',
  );

  // Dedicated SBC Contacts SSO client (seeded on SBC's side).
  static const String ssoClientId = String.fromEnvironment(
    'SBC_SSO_CLIENT_ID',
    defaultValue: 'sbc-contacts',
  );

  // Registered redirect. The HTTPS callback bridge (backend GET /auth/callback)
  // captures the code and deep-links it into the app.
  static const String ssoRedirectUri = String.fromEnvironment(
    'SBC_SSO_REDIRECT_URI',
    // The custom scheme, not the web bridge. flutter_web_auth_2 owns this
    // scheme and captures the redirect itself, so the code never has to be
    // copied by hand. Both URIs are registered for the sbc-contacts client;
    // the https bridge stays available as the manual fallback.
    defaultValue: 'sbccontacts://auth/callback',
  );

  // Native deep-link scheme (also registered) — used to hand the code to the app.
  static const String ssoDeepLink = 'sbccontacts://auth/callback';

  static const String ssoScopes = String.fromEnvironment(
    'SBC_SSO_SCOPES',
    defaultValue: 'profile.read contacts.read',
  );

  /// Scheme of [ssoRedirectUri] — flutter_web_auth_2 needs it to know which
  /// redirect ends the session.
  static String get ssoCallbackScheme => Uri.parse(ssoRedirectUri).scheme;
}

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

  static const String ssoClientId = String.fromEnvironment(
    'SBC_SSO_CLIENT_ID',
    defaultValue: 'sbc-contacts',
  );

  static const String ssoRedirectUri = String.fromEnvironment(
    'SBC_SSO_REDIRECT_URI',
    defaultValue: 'sbccontacts://auth/callback',
  );

  static const String ssoScopes = 'profile.read contacts.read';
}

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:sbc_contacts/core/config/app_config.dart';

/// Opens SBC's own sign-up page, for someone who wants an SBC account rather
/// than an SBC Network one. It runs in the same in-app tab as "Se connecter
/// avec SBC", which shares the browser session, so once the account exists,
/// signing in goes straight to the consent step.
///
/// Sign-up never redirects to the app: this returns when the member closes it.
Future<void> openSbcSignup() async {
  try {
    await FlutterWebAuth2.authenticate(
      url: AppConfig.sbcSignupUrl,
      callbackUrlScheme: AppConfig.ssoCallbackScheme,
      options: const FlutterWebAuth2Options(timeout: 1800),
    );
  } catch (_) {
    // Closed by the member — the expected way out.
  }
}

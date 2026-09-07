import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';

/// Listens for the SSO redirect coming back into the app as a deep link
/// (`sbccontacts://auth/callback?code=...`, or the https App Link) and completes
/// login by exchanging the code — no manual paste needed.
class SsoLinkHandler {
  SsoLinkHandler(this._ref);

  final Ref _ref;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handle(initial);
    _sub = _appLinks.uriLinkStream.listen(_handle);
  }

  void _handle(Uri uri) {
    final isCallback = uri.scheme == 'sbccontacts' ||
        (uri.scheme == 'https' && uri.path.startsWith('/auth/callback'));
    if (!isCallback) return;
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      _ref.read(authControllerProvider.notifier).loginWithCode(code);
    }
  }

  void dispose() => _sub?.cancel();
}

final ssoLinkHandlerProvider = Provider<SsoLinkHandler>((ref) {
  final handler = SsoLinkHandler(ref);
  ref.onDispose(handler.dispose);
  return handler;
});

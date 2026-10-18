import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/config/app_config.dart';
import 'package:sbc_contacts/core/network/api_exception.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:sbc_contacts/shared/widgets/sbc_logo.dart';

/// Human-readable reason for a failed login (surfaces the backend message).
String loginErrorMessage(Object? error) {
  if (error is ApiException) {
    if (error.isSubscriptionRequired) {
      return 'Abonnement SBC requis pour accéder aux contacts.';
    }
    if (error.statusCode == 400) {
      return 'Code invalide, expiré ou déjà utilisé. Reconnecte-toi.';
    }
    return error.message;
  }
  return 'Échec de connexion. Vérifie ta connexion et réessaie.';
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _codeCtrl = TextEditingController();
  final _sponsorCtrl = TextEditingController();
  bool _showCode = false;
  bool _showSignup = false;
  bool _busy = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _sponsorCtrl.dispose();
    super.dispose();
  }

  /// Random, unguessable value tying the callback to this request.
  static String _newState() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Sign in without ever leaving the app.
  ///
  /// The consent page opens in a Chrome Custom Tab (ASWebAuthenticationSession
  /// on iOS) that the app owns, and the `sbccontacts://` redirect is captured
  /// and handed straight back here — no switching to Chrome, and no copying a
  /// code by hand. It also shares the browser's cookie jar, so a member
  /// already signed in to SBC goes straight to the consent step.
  Future<void> _startSso() async {
    final state = _newState();
    final uri = Uri.parse(AppConfig.ssoAuthorizeUrl).replace(
      queryParameters: {
        'client_id': AppConfig.ssoClientId,
        'redirect_uri': AppConfig.ssoRedirectUri,
        'scope': AppConfig.ssoScopes,
        // Mandatory per SSO_INTEGRATION_GUIDE.md: without it the callback
        // cannot be proven to belong to this request (CSRF).
        'state': state,
      },
    );

    setState(() => _busy = true);
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: uri.toString(),
        callbackUrlScheme: AppConfig.ssoCallbackScheme,
        options: const FlutterWebAuth2Options(
          // Give the member time to type their SBC password.
          timeout: 300,
        ),
      );

      final back = Uri.parse(result);
      final error = back.queryParameters['error'];
      if (error != null) {
        _fail('SBC a refusé la connexion ($error).');
        return;
      }
      if (back.queryParameters['state'] != state) {
        _fail('Réponse de connexion invalide. Réessaie.');
        return;
      }
      final code = back.queryParameters['code'];
      if (code == null || code.isEmpty) {
        _fail('Aucun code reçu de SBC. Réessaie.');
        return;
      }
      await ref.read(authControllerProvider.notifier).loginWithCode(code);
    } on PlatformException {
      // The member closed the tab — not an error worth shouting about.
    } catch (e) {
      _fail('Connexion impossible. Vérifie ta connexion et réessaie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Create an SBC account without leaving the app.
  ///
  /// App accounts are SBC accounts, so this opens SBC's own sign-up page (OTP,
  /// sponsor, subscription stay theirs) in the same in-app tab as sign-in. That
  /// tab shares the browser session, so once the account exists "Se connecter
  /// avec SBC" goes straight to the consent step.
  Future<void> _startSignup() async {
    final sponsor = _sponsorCtrl.text.trim();
    final uri = Uri.parse(AppConfig.sbcSignupUrl).replace(
      queryParameters: sponsor.isEmpty ? null : {'affiliationCode': sponsor},
    );

    setState(() => _busy = true);
    try {
      // Sign-up never redirects to the app: the member closes the tab when done.
      await FlutterWebAuth2.authenticate(
        url: uri.toString(),
        callbackUrlScheme: AppConfig.ssoCallbackScheme,
        options: const FlutterWebAuth2Options(timeout: 1800),
      );
    } catch (_) {
      // Closed by the member — the expected way out.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showSignup = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Compte créé ? Touche « Se connecter avec SBC » pour entrer.'),
        ));
      }
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    await ref.read(authControllerProvider.notifier).loginWithCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SbcLogo(height: 96),
                const Gap(18),
                Text(
                  'Ton réseau SBC, directement dans ton téléphone.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const Gap(4),
                Container(
                  height: 4,
                  width: 120,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    gradient: SbcColors.brandArc,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Gap(36),
                if (auth.isLoading || _busy)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _busy ? null : _startSso,
                    icon: const Icon(Icons.login),
                    label: const Text('Se connecter avec SBC'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                if (auth.hasError) ...[
                  const Gap(12),
                  Text(
                    loginErrorMessage(auth.error),
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Gap(12),
                if (!auth.isLoading && !_busy)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showSignup = !_showSignup),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Créer un compte'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                if (_showSignup && !_busy) ...[
                  const Gap(12),
                  TextField(
                    controller: _sponsorCtrl,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Code parrain (facultatif)',
                      hintText: 'Ex. AB12CD',
                      helperText: "Le code de la personne qui t'a invité. Tu peux le laisser vide.",
                      helperMaxLines: 2,
                    ),
                  ),
                  const Gap(10),
                  FilledButton(
                    onPressed: _startSignup,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text("Continuer l'inscription sur SBC"),
                  ),
                ],
                const Gap(4),
                TextButton(
                  onPressed: () => setState(() => _showCode = !_showCode),
                  child: const Text("J'ai un code d'autorisation"),
                ),
                if (_showCode) ...[
                  TextField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Code SBC',
                      hintText: 'Colle le code reçu',
                    ),
                  ),
                  const Gap(10),
                  OutlinedButton(
                    onPressed: _submitCode,
                    child: const Text('Valider le code'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

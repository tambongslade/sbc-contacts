import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/config/app_config.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _codeCtrl = TextEditingController();
  bool _showCode = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSso() async {
    final params = {
      'client_id': AppConfig.ssoClientId,
      'redirect_uri': AppConfig.ssoRedirectUri,
      'scope': AppConfig.ssoScopes,
    };
    final uri = Uri.parse(AppConfig.ssoAuthorizeUrl).replace(queryParameters: params);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    gradient: SbcColors.brandArc,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.contacts, color: Colors.white, size: 40),
                ),
                const Gap(20),
                Text('SBC Contacts', style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
                const Gap(6),
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
                if (auth.isLoading)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _startSso,
                    icon: const Icon(Icons.login),
                    label: const Text('Se connecter avec SBC'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                if (auth.hasError) ...[
                  const Gap(12),
                  Text(
                    'Échec de connexion. Réessaie.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const Gap(12),
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

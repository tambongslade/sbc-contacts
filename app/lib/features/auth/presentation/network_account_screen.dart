import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/network/api_exception.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';
import 'package:sbc_contacts/shared/widgets/sbc_logo.dart';

/// International dialing codes for [FilterOptions.countries], shown in front
/// of the WhatsApp number. The backend completes the number the same way.
const Map<String, String> dialCodes = {
  'CM': '237',
  'CI': '225',
  'TG': '228',
  'BJ': '229',
  'CG': '242',
  'CD': '243',
  'SN': '221',
  'GA': '241',
  'NE': '227',
  'ML': '223',
  'BF': '226',
  'TD': '235',
  'CF': '236',
  'GN': '224',
  'FR': '33',
  'BE': '32',
  'CA': '1',
  'US': '1',
};

/// An SBC Network account: created here, it lives in SBC Network only — no
/// SBC account behind it. [create] opens the sign-up form, otherwise sign-in.
class NetworkAccountScreen extends ConsumerStatefulWidget {
  const NetworkAccountScreen({super.key, this.create = true});

  final bool create;

  @override
  ConsumerState<NetworkAccountScreen> createState() => _NetworkAccountScreenState();
}

class _NetworkAccountScreenState extends ConsumerState<NetworkAccountScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _create = widget.create;
  String _country = 'CM';
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = ref.read(authControllerProvider.notifier);
    try {
      if (_create) {
        await auth.register(
          name: _name.text.trim(),
          country: _country,
          phoneNumber: _phone.text.trim(),
          password: _password.text,
        );
      } else {
        await auth.loginWithPhone(
          country: _country,
          phoneNumber: _phone.text.trim(),
          password: _password.text,
        );
      }
      // Signed in: the router leaves the login flow on its own.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Échec. Vérifie ta connexion et réessaie.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dial = dialCodes[_country] ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(_create ? 'Créer un compte' : 'Se connecter')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              const Center(child: SbcLogo(height: 64)),
              const Gap(16),
              Text(
                _create ? 'Ton compte SBC Network' : 'Connexion à SBC Network',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const Gap(6),
              Text(
                _create
                    ? 'Il reste sur SBC Network : pas besoin de compte SBC.'
                    : 'Avec le numéro WhatsApp et le mot de passe de ton compte SBC Network.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Gap(24),
              if (_create) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Indique ton nom' : null,
                ),
                const Gap(14),
              ],
              DropdownButtonFormField<String>(
                initialValue: _country,
                decoration: const InputDecoration(
                  labelText: 'Pays',
                  prefixIcon: Icon(Icons.public),
                ),
                items: [
                  for (final e in FilterOptions.countries.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _country = v ?? _country),
              ),
              const Gap(14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Numéro WhatsApp',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  prefixText: '+$dial ',
                ),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length < 6 ? 'Numéro WhatsApp invalide' : null;
                },
              ),
              const Gap(14),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: _create ? TextInputAction.next : TextInputAction.done,
                onFieldSubmitted: _create ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  helperText: _create ? 'Au moins 8 caractères' : null,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Masquer' : 'Afficher',
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Indique ton mot de passe';
                  if (_create && v.length < 8) return 'Au moins 8 caractères';
                  return null;
                },
              ),
              if (_create) ...[
                const Gap(14),
                TextFormField(
                  controller: _confirm,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirme le mot de passe',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => v != _password.text
                      ? 'Les mots de passe ne correspondent pas'
                      : null,
                ),
              ],
              if (_error != null) ...[
                const Gap(14),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const Gap(24),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Text(_create ? 'Créer mon compte' : 'Se connecter'),
                ),
              const Gap(8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _create = !_create;
                          _error = null;
                        }),
                child: Text(
                  _create
                      ? "J'ai déjà un compte SBC Network"
                      : 'Pas encore de compte ? Créer un compte',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

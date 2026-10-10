import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';

/// The sheet shown after login: the invitation for a member who is not a pro,
/// or what is left to set up for a pro. Both lead to the AI assistant.
Future<void> showProPrompt(BuildContext context, ProInvite kind) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => _ProPromptSheet(kind: kind),
    );

class _ProPromptSheet extends ConsumerWidget {
  const _ProPromptSheet({required this.kind});
  final ProInvite kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final space = ref.watch(proSpaceProvider).value;
    final finish = kind == ProInvite.finishSetup;
    final missing = space?.missingSetup ?? const [];

    Widget benefit(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: SbcColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: SbcColors.primary),
              ),
              const Gap(12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: finish ? null : SbcColors.brandArc,
                  color: finish ? SbcColors.accentDark : null,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(finish ? Icons.priority_high_rounded : Icons.work_rounded, color: Colors.white, size: 28),
              ),
            ),
            const Gap(16),
            Text(
              finish ? 'Termine ton profil pro' : 'Tu proposes un service ?',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Gap(16),
            if (finish) ...[
              Text(
                space?.receivingActive == true
                    ? "Ton abonnement Pro est actif, mais aucune demande ne peut t'arriver tant que ton profil n'est pas complet."
                    : "Aucune demande ne peut t'arriver tant que ton profil n'est pas complet.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Gap(16),
              RequestPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final m in missing)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          const Icon(Icons.radio_button_unchecked, color: SbcColors.accentDark, size: 18),
                          const Gap(12),
                          Expanded(child: Text(m.todo, style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ],
                ),
              ),
            ] else ...[
              benefit(Icons.chat_bubble_outline, 'Décris ce que tu sais faire, avec tes mots.'),
              benefit(Icons.move_to_inbox_outlined, 'Reçois les demandes des membres qui en ont besoin, près de chez toi.'),
              benefit(Icons.thumb_up_outlined, 'Réponds avec ton prix, le client te choisit et te contacte sur WhatsApp.'),
            ],
            const Gap(20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                // Take the router before the sheet closes: its context goes with it.
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push('/pro/assistant');
              },
              child: Text(finish ? 'Compléter mon profil' : 'Devenir professionnel'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Plus tard')),
          ],
        ),
      ),
    );
  }
}

/// Pro setup as a conversation: the AI asks, the member answers in their own
/// words, and the profile and services are filled in from the answers. Nothing
/// is saved until the member confirms the summary.
class ProAssistantScreen extends ConsumerStatefulWidget {
  const ProAssistantScreen({super.key});

  @override
  ConsumerState<ProAssistantScreen> createState() => _ProAssistantScreenState();
}

class _ProAssistantScreenState extends ConsumerState<ProAssistantScreen> {
  final _messages = <Map<String, String>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ProDraft? _draft;
  List<String> _options = [];
  bool _complete = false;
  bool _unavailable = false;
  bool _thinking = false;
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _send(null);
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _send(String? text) async {
    if (text != null && text.trim().isNotEmpty) {
      _messages.add({'role': 'user', 'text': text.trim()});
    } else if (_messages.isNotEmpty) {
      return;
    }
    setState(() {
      _thinking = true;
      _options = [];
      _error = null;
    });
    _scrollDown();
    try {
      final turn = await ref.read(requestsRepositoryProvider).assistantTurn(_messages, _draft);
      setState(() {
        _messages.add({'role': 'assistant', 'text': turn.reply});
        _draft = turn.draft;
        _options = turn.options;
        _complete = turn.complete;
        _unavailable = !turn.available;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _thinking = false);
      _scrollDown();
    }
  }

  Future<void> _save() async {
    final p = _draft?.profile ?? const {};
    setState(() => _saving = true);
    try {
      final repo = ref.read(requestsRepositoryProvider);
      var space = await repo.saveProfile({
        'profession': p['profession'],
        'description': p['description'],
        'city': p['city'],
        'zones': p['zones'] ?? const [],
        'modes': p['modes'] ?? const [],
        'availability': p['availability'],
        if (p['priceMin'] != null) 'priceMin': p['priceMin'],
        if (p['priceMax'] != null) 'priceMax': p['priceMax'],
        'shopUrl': p['shopUrl'],
        if (ref.read(proSpaceProvider).value?.profile?.whatsapp != null)
          'whatsapp': ref.read(proSpaceProvider).value!.profile!.whatsapp,
      });
      final services = _draft?.services ?? const [];
      if (services.isNotEmpty) space = await repo.addServices(services);
      ref.read(proSpaceProvider.notifier).set(space);
      ref.invalidate(inboxProvider);
      setState(() => _done = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_done) return const _ReadyScreen();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant pro'),
        actions: [TextButton(onPressed: () => context.pushReplacement('/pro/profile'), child: const Text('Remplir moi-même'))],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in _messages) _Bubble(text: m['text']!, mine: m['role'] == 'user'),
          if (_thinking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))]),
            ),
          if (_complete && _draft != null) _DraftSummary(draft: _draft!),
          if (_unavailable)
            FilledButton(onPressed: () => context.pushReplacement('/pro/profile'), child: const Text('Remplir moi-même')),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_complete) ...[
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Création…' : 'Créer mon profil'),
                ),
                const Gap(4),
                Text('Quelque chose à corriger ? Écris-le simplement ci-dessous.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Gap(6),
              ],
              if (_options.isNotEmpty && !_thinking)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final o in _options)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(label: Text(o), onPressed: () => _send(o)),
                        ),
                    ],
                  ),
                ),
              const Gap(6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (v) {
                        _input.clear();
                        _send(v);
                      },
                      decoration: const InputDecoration(hintText: 'Ta réponse…'),
                    ),
                  ),
                  const Gap(8),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _input.text.trim().isEmpty || _thinking
                        ? null
                        : () {
                            final t = _input.text;
                            _input.clear();
                            _send(t);
                          },
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? SbcColors.primary : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: mine ? Colors.white : null)),
      ),
    );
  }
}

/// "Voici ton profil" — what will be saved, to check before confirming.
class _DraftSummary extends ConsumerWidget {
  const _DraftSummary({required this.draft});
  final ProDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = draft.profile;
    String s(Object? v) => v == null ? '—' : '$v';
    final modes = ((p['modes'] as List?) ?? const [])
        .map((m) => ServiceMode.fromWire(m)?.label)
        .whereType<String>()
        .join(', ');
    final existing = ref.watch(proSpaceProvider).value?.services.map((x) => x.name) ?? const <String>[];
    final names = [...existing, ...draft.services.map((x) => '${x['name']}')];
    return RequestPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: SbcColors.primary, size: 18),
            const Gap(6),
            Text('Voici ton profil',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: SbcColors.primary)),
          ]),
          FactRow('Métier', s(p['profession'])),
          FactRow('Lieu', [p['city'], ...((p['zones'] as List?) ?? const [])].whereType<Object>().join(', ')),
          FactRow('Prestation', modes.isEmpty ? '—' : modes),
          FactRow('Disponibilité', s(p['availability'])),
          if (p['priceMin'] != null || p['priceMax'] != null)
            FactRow('Prix', [p['priceMin'], p['priceMax']].whereType<num>().map((x) => fcfa(x.toInt())).join(' – ')),
          FactRow('Boutique', s(p['shopUrl'])),
          if (p['description'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('${p['description']}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (names.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: [for (final n in names) Chip(label: Text(n))]),
        ],
      ),
    );
  }
}

/// The end of the setup. Reception is the paid part, so it says plainly that
/// requests start once the Pro subscription is active.
class _ReadyScreen extends ConsumerWidget {
  const _ReadyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final active = ref.watch(proSpaceProvider).value?.receivingActive == true;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.verified_rounded, color: SbcColors.success, size: 64),
              const Gap(16),
              Text('Ton profil pro est prêt', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const Gap(10),
              Text(
                active
                    ? 'Tu recevras ici les demandes qui correspondent à tes services.'
                    : "Pour recevoir les demandes, active l'abonnement Pro (2 000 FCFA/mois) auprès de SBC. Tu retrouves tout dans Profil › Espace pro.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => context.pop(),
                child: const Text('Terminer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

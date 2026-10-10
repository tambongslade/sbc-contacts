import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';

String? _nilIfBlank(String s) => s.trim().isEmpty ? null : s.trim();

class _StepHeader extends StatelessWidget {
  const _StepHeader(this.step);
  final int step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Étape $step/2',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Gap(8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: step / 2, minHeight: 5),
        ),
      ],
    );
  }
}

/// Step 1 — "De quoi avez-vous besoin ?" (Data §6). One big text field: the
/// member does not pick a profession first. The optional details only override
/// what the AI reads from the text.
class RequestComposerScreen extends ConsumerStatefulWidget {
  const RequestComposerScreen({super.key});

  @override
  ConsumerState<RequestComposerScreen> createState() => _RequestComposerScreenState();
}

class _RequestComposerScreenState extends ConsumerState<RequestComposerScreen> {
  final _text = TextEditingController();
  final _city = TextEditingController();
  final _date = TextEditingController();
  final _budget = TextEditingController();
  bool _analysing = false;
  String? _error;

  bool get _canContinue => _text.text.trim().length >= 8 && !_analysing;

  Future<void> _analyse() async {
    setState(() {
      _analysing = true;
      _error = null;
    });
    try {
      final draft = await ref.read(requestsRepositoryProvider).create(
            text: _text.text.trim(),
            city: _nilIfBlank(_city.text),
            budget: int.tryParse(_budget.text.replaceAll(RegExp(r'\D'), '')),
            desiredDate: _nilIfBlank(_date.text),
          );
      ref.read(myRequestsProvider.notifier).upsert(draft);
      if (mounted) context.pushReplacement('/requests/review', extra: draft);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget detail(IconData icon, Color tint, String label, String hint, TextEditingController c,
            {TextInputType? keyboard}) =>
        ListTile(
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: tint, size: 18),
          ),
          title: Text(label),
          trailing: SizedBox(
            width: 160,
            child: TextField(
              controller: c,
              keyboardType: keyboard,
              textAlign: TextAlign.end,
              decoration: InputDecoration(hintText: hint, border: InputBorder.none, filled: false),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle demande')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StepHeader(1),
          const Gap(18),
          Text('De quoi avez-vous besoin ?',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const Gap(6),
          Text("Écris librement, comme à un ami. L'IA comprend et trouve les bons pros.",
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Gap(18),
          RequestPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RequestSectionLabel('Ton besoin'),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: "Ex. Je cherche quelqu'un pour réparer mes locks à domicile samedi à Yaoundé",
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
              ],
            ),
          ),
          const Gap(18),
          const RequestSectionLabel('Précisions (facultatif)'),
          const Gap(8),
          RequestPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                detail(Icons.place_outlined, SbcColors.primary, 'Lieu', 'Ville ou quartier', _city),
                const Divider(height: 1, indent: 72),
                detail(Icons.calendar_today_outlined, SbcColors.secondaryDark, 'Date', 'Ex. samedi', _date),
                const Divider(height: 1, indent: 72),
                detail(Icons.payments_outlined, SbcColors.accentDark, 'Budget', 'FCFA', _budget,
                    keyboard: TextInputType.number),
              ],
            ),
          ),
          if (_error != null) ...[
            const Gap(12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _canContinue ? _analyse : null,
            child: Text(_analysing ? "L'IA analyse ta demande…" : 'Continuer'),
          ),
        ),
      ),
    );
  }
}

/// Step 2 — "Vérifie ta demande": the AI's reading, correctable, plus its
/// question when the need is ambiguous (Data §6, §7).
class RequestReviewScreen extends ConsumerStatefulWidget {
  const RequestReviewScreen({required this.request, super.key});
  final ServiceRequestItem request;

  @override
  ConsumerState<RequestReviewScreen> createState() => _RequestReviewScreenState();
}

class _RequestReviewScreenState extends ConsumerState<RequestReviewScreen> {
  late ServiceRequestItem _request = widget.request;
  bool _busy = false;
  String? _error;

  void _set(ServiceRequestItem r) {
    setState(() => _request = r);
    ref.read(myRequestsProvider.notifier).upsert(r);
  }

  Future<void> _answer(String answer) async {
    setState(() => _busy = true);
    try {
      _set(await ref.read(requestsRepositoryProvider).update(_request.id, {'clarificationAnswer': answer}));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final sent = await ref.read(requestsRepositoryProvider).send(_request.id);
      ref.read(myRequestsProvider.notifier).upsert(sent);
      if (!mounted) return;
      showToast(context, 'Demande envoyée. On la transmet aux professionnels concernés.');
      context.pushReplacement('/requests/${sent.id}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<ServiceRequestItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditReadingSheet(request: _request),
    );
    if (updated != null) _set(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _request;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Résumé'),
        actions: [
          if (r.canDelete)
            IconButton(
              tooltip: 'Supprimer le brouillon',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDeleteRequest(context, ref, r) && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _StepHeader(2),
          const Gap(16),
          Text('Vérifie ta demande', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const Gap(16),
          RequestPanel(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: SbcColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, size: 18, color: SbcColors.primary),
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text("L'IA a compris",
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    TextButton(onPressed: _edit, child: const Text('Modifier')),
                  ],
                ),
                FactRow('Métier', r.profession ?? '—'),
                const Divider(height: 1),
                FactRow('Service', r.service ?? '—'),
                const Divider(height: 1),
                FactRow('Lieu', r.place.isEmpty ? '—' : r.place),
                const Divider(height: 1),
                FactRow('Prestation', r.mode?.label ?? 'Indifférent'),
                const Divider(height: 1),
                FactRow('Date',
                    [r.desiredDate, r.desiredTime].whereType<String>().join(' à ').ifEmpty('Flexible')),
                const Divider(height: 1),
                FactRow('Budget', r.budget != null ? '${fcfa(r.budget!)} max' : 'Non précisé'),
                if (r.constraints.isNotEmpty) ...[
                  const Divider(height: 1),
                  FactRow('Conditions', r.constraints.join(', ')),
                ],
              ],
            ),
          ),
          if (r.clarificationQuestion != null) ...[
            const Gap(16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SbcColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SbcColors.accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('UNE PETITE QUESTION',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1, color: SbcColors.accentDark)),
                  const Gap(6),
                  Text(r.clarificationQuestion!,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap(10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in r.clarificationOptions)
                        ChoiceChip(
                          label: Text(o),
                          selected: r.clarificationAnswer == o,
                          onSelected: _busy ? null : (_) => _answer(o),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const Gap(16),
          const PrivacyNote('Ton numéro reste privé. Les pros voient seulement ta demande, jusqu\'à ce que tu les contactes.'),
          if (_error != null) ...[
            const Gap(12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy || r.needsAnswer ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Envoyer ma demande'),
          ),
        ),
      ),
    );
  }
}

/// Correct what the AI read before sending.
class _EditReadingSheet extends ConsumerStatefulWidget {
  const _EditReadingSheet({required this.request});
  final ServiceRequestItem request;

  @override
  ConsumerState<_EditReadingSheet> createState() => _EditReadingSheetState();
}

class _EditReadingSheetState extends ConsumerState<_EditReadingSheet> {
  late final _service = TextEditingController(text: widget.request.service);
  late final _city = TextEditingController(text: widget.request.city);
  late final _district = TextEditingController(text: widget.request.district);
  late final _date = TextEditingController(text: widget.request.desiredDate);
  late final _budget = TextEditingController(text: widget.request.budget?.toString());
  late ServiceMode? _mode = widget.request.mode;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await ref.read(requestsRepositoryProvider).update(widget.request.id, {
        if (_nilIfBlank(_service.text) != null) 'service': _service.text.trim(),
        if (_nilIfBlank(_city.text) != null) 'city': _city.text.trim(),
        if (_nilIfBlank(_district.text) != null) 'district': _district.text.trim(),
        if (_mode != null) 'mode': _mode!.wire,
        if (_nilIfBlank(_date.text) != null) 'desiredDate': _date.text.trim(),
        if (int.tryParse(_budget.text.replaceAll(RegExp(r'\D'), '')) != null)
          'budget': int.parse(_budget.text.replaceAll(RegExp(r'\D'), '')),
      });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Modifier', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Gap(12),
            TextField(controller: _service, decoration: const InputDecoration(labelText: 'Ce que tu cherches')),
            const Gap(10),
            TextField(controller: _city, decoration: const InputDecoration(labelText: 'Ville')),
            const Gap(10),
            TextField(controller: _district, decoration: const InputDecoration(labelText: 'Quartier (facultatif)')),
            const Gap(10),
            DropdownButtonFormField<ServiceMode?>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Prestation'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Indifférent')),
                for (final m in ServiceMode.values) DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (m) => setState(() => _mode = m),
            ),
            const Gap(10),
            TextField(controller: _date, decoration: const InputDecoration(labelText: 'Date souhaitée')),
            const Gap(10),
            TextField(
              controller: _budget,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Budget max (FCFA)'),
            ),
            const Gap(16),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';

List<String> _splitList(String s) => s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
int? _amount(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), ''));

/// Mode toggles shared by the profile and the service editor.
class _ModeToggles extends StatelessWidget {
  const _ModeToggles({required this.selected, required this.onChanged});
  final Set<ServiceMode> selected;
  final ValueChanged<Set<ServiceMode>> onChanged;

  static const _icons = {
    ServiceMode.home: Icons.home_outlined,
    ServiceMode.onSite: Icons.storefront_outlined,
    ServiceMode.online: Icons.public,
    ServiceMode.delivery: Icons.local_shipping_outlined,
  };

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final m in ServiceMode.values)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(_icons[m]),
              title: Text(m.label),
              value: selected.contains(m),
              onChanged: (on) => onChanged(on ? {...selected, m} : ({...selected}..remove(m))),
            ),
        ],
      );
}

/// Create or edit the pro profile. Name, photo and WhatsApp come from SBC —
/// only what SBC does not know is asked (Data §2, §3).
class ProProfileFormScreen extends ConsumerStatefulWidget {
  const ProProfileFormScreen({this.onSaved, super.key});

  /// Set by the guided setup to move on instead of closing.
  final VoidCallback? onSaved;

  @override
  ConsumerState<ProProfileFormScreen> createState() => _ProProfileFormScreenState();
}

class _ProProfileFormScreenState extends ConsumerState<ProProfileFormScreen> {
  final _profession = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController();
  final _zones = TextEditingController();
  final _availability = TextEditingController();
  final _priceMin = TextEditingController();
  final _priceMax = TextEditingController();
  final _shopUrl = TextEditingController();
  final _whatsapp = TextEditingController();
  Set<ServiceMode> _modes = {ServiceMode.home};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = ref.read(proSpaceProvider).value?.profile;
    if (p == null) return;
    // Placeholders ("À compléter") show as empty fields, not as answers.
    String real(String s) => isPlaceholder(s) ? '' : s;
    _profession.text = real(p.profession);
    _description.text = real(p.description);
    _city.text = real(p.city);
    _zones.text = p.zones.where((z) => !isPlaceholder(z)).join(', ');
    if (p.modes.isNotEmpty) _modes = p.modes.toSet();
    _availability.text = real(p.availability);
    _priceMin.text = p.priceMin?.toString() ?? '';
    _priceMax.text = p.priceMax?.toString() ?? '';
    _shopUrl.text = isRealLink(p.shopUrl) ? p.shopUrl : '';
    _whatsapp.text = p.whatsapp ?? '';
  }

  bool get _valid =>
      _profession.text.trim().isNotEmpty &&
      _description.text.trim().length >= 10 &&
      _city.text.trim().isNotEmpty &&
      _modes.isNotEmpty &&
      _availability.text.trim().isNotEmpty &&
      isRealLink(_shopUrl.text);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final space = await ref.read(requestsRepositoryProvider).saveProfile({
        'profession': _profession.text.trim(),
        'description': _description.text.trim(),
        'city': _city.text.trim(),
        'zones': _splitList(_zones.text),
        'modes': [for (final m in ServiceMode.values) if (_modes.contains(m)) m.wire],
        'availability': _availability.text.trim(),
        if (_amount(_priceMin.text) != null) 'priceMin': _amount(_priceMin.text),
        if (_amount(_priceMax.text) != null) 'priceMax': _amount(_priceMax.text),
        'shopUrl': _shopUrl.text.trim(),
        if (_whatsapp.text.trim().isNotEmpty) 'whatsapp': _whatsapp.text.trim(),
      });
      ref.read(proSpaceProvider.notifier).set(space);
      ref.invalidate(inboxProvider);
      if (!mounted) return;
      widget.onSaved != null ? widget.onSaved!() : context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(proSpaceProvider).value?.isPro ?? false;
    final phone = ref.watch(proSpaceProvider).value?.phoneNumber;
    Widget field(TextEditingController c, String label, {String? hint, TextInputType? keyboard, int lines = 1}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: keyboard,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 2),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(isPro ? 'Mon profil pro' : 'Devenir pro'),
        actions: [TextButton(onPressed: _valid && !_saving ? _save : null, child: const Text('Enregistrer'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const RequestSectionLabel('Activité'),
          const Gap(8),
          field(_profession, 'Métier (ex. Coiffeur)'),
          field(_description, 'Présente ton activité', lines: 3,
              hint: 'Ton nom, ta photo et ton numéro viennent de ton compte SBC.'),
          const Gap(8),
          const RequestSectionLabel('Où tu interviens'),
          const Gap(8),
          field(_city, 'Ville principale'),
          field(_zones, 'Autres quartiers ou villes, séparés par des virgules'),
          const Gap(8),
          const RequestSectionLabel('Comment tu travailles'),
          _ModeToggles(selected: _modes, onChanged: (m) => setState(() => _modes = m)),
          field(_availability, 'Disponibilité (ex. lun–sam 8h–18h)'),
          const Gap(8),
          const RequestSectionLabel('Prix indicatifs (facultatif)'),
          const Gap(8),
          field(_priceMin, 'À partir de (FCFA)', keyboard: TextInputType.number),
          field(_priceMax, "Jusqu'à (FCFA)", keyboard: TextInputType.number),
          const Gap(8),
          const RequestSectionLabel('Boutique SBC Shop'),
          const Gap(8),
          field(_shopUrl, 'https://…',
              keyboard: TextInputType.url,
              hint: "Tes photos et réalisations restent sur ta boutique : les clients l'ouvrent depuis ta réponse."),
          field(_whatsapp, phone ?? 'WhatsApp, si différent de ton compte SBC', keyboard: TextInputType.phone),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}

/// "Ajouter un service": free text → AI proposals → keep, rename or drop →
/// save (Data §4, §5).
class AddServicesScreen extends ConsumerStatefulWidget {
  const AddServicesScreen({this.onSaved, super.key});
  final VoidCallback? onSaved;

  @override
  ConsumerState<AddServicesScreen> createState() => _AddServicesScreenState();
}

class _AddServicesScreenState extends ConsumerState<AddServicesScreen> {
  final _text = TextEditingController();
  List<ServiceProposal> _proposals = [];
  bool _analysing = false;
  bool _saving = false;
  String? _error;

  Future<void> _analyse() async {
    setState(() {
      _analysing = true;
      _error = null;
    });
    try {
      final list = await ref.read(requestsRepositoryProvider).structure(_text.text.trim());
      setState(() => _proposals = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _analysing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final space = await ref.read(requestsRepositoryProvider).addServices([for (final p in _proposals) p.toJson()]);
      ref.read(proSpaceProvider.notifier).set(space);
      if (!mounted) return;
      widget.onSaved != null ? widget.onSaved!() : context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final synonyms = {for (final p in _proposals) ...p.synonyms}.take(8).join(', ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un service'),
        actions: [if (widget.onSaved != null) TextButton(onPressed: widget.onSaved, child: const Text('Plus tard'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RequestPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RequestSectionLabel('Ce que tu proposes'),
                TextField(
                  controller: _text,
                  minLines: 2,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Ex. je fais les dreads, pose de locks, entretien et réparation',
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _text.text.trim().length < 3 || _analysing ? null : _analyse,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(_analysing ? 'Analyse…' : "Analyser avec l'IA"),
                ),
              ],
            ),
          ),
          if (_proposals.isNotEmpty) ...[
            const Gap(16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SbcColors.primary, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("PROPOSITION DE L'IA · À VALIDER",
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1, color: SbcColors.primary)),
                  const Gap(8),
                  for (var i = 0; i < _proposals.length; i++)
                    Row(
                      key: ObjectKey(_proposals[i]),
                      children: [
                        const Icon(Icons.check_box_rounded, color: SbcColors.primary),
                        const Gap(8),
                        Expanded(
                          child: TextFormField(
                            initialValue: _proposals[i].name,
                            onChanged: (v) => _proposals[i].name = v,
                            decoration: const InputDecoration(border: InputBorder.none, filled: false),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Retirer ${_proposals[i].name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _proposals.removeAt(i)),
                        ),
                      ],
                    ),
                  if (synonyms.isNotEmpty)
                    Text('Mots reconnus aussi : $synonyms',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
          if (_error != null) ...[const Gap(12), Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
        ],
      ),
      bottomNavigationBar: _proposals.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: theme.colorScheme.onSurface,
                  ),
                  onPressed: _saving ? null : _save,
                  child: const Text('Valider ces services'),
                ),
              ),
            ),
    );
  }
}

/// The details of one service (Data §4), each falling back to the profile when
/// left empty. Cleared fields are sent as null so the server clears them.
class ServiceEditScreen extends ConsumerStatefulWidget {
  const ServiceEditScreen({required this.service, super.key});
  final ProServiceItem service;

  @override
  ConsumerState<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends ConsumerState<ServiceEditScreen> {
  static const _delays = ['', 'Immédiat', 'Sous 24 h', 'Quelques jours', 'Sur devis'];
  late final _name = TextEditingController(text: widget.service.name);
  late final _description = TextEditingController(text: widget.service.description);
  late final _specialties = TextEditingController(text: widget.service.specialties.join(', '));
  late final _priceMin = TextEditingController(text: widget.service.priceMin?.toString());
  late final _priceMax = TextEditingController(text: widget.service.priceMax?.toString());
  late final _zones = TextEditingController(text: widget.service.zones.join(', '));
  late Set<ServiceMode> _modes = widget.service.modes.toSet();
  late String _delay = _delays.contains(widget.service.delay) ? widget.service.delay! : '';
  late bool _active = widget.service.isActive;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final min = _amount(_priceMin.text);
    final max = _amount(_priceMax.text);
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Le prix minimum dépasse le maximum.');
      return;
    }
    setState(() => _saving = true);
    try {
      final space = await ref.read(requestsRepositoryProvider).updateService(widget.service.id, {
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'specialties': _splitList(_specialties.text),
        'priceMin': min,
        'priceMax': max,
        'modes': [for (final m in ServiceMode.values) if (_modes.contains(m)) m.wire],
        'zones': _splitList(_zones.text),
        'delay': _delay.isEmpty ? null : _delay,
        'isActive': _active,
      });
      ref.read(proSpaceProvider.notifier).set(space);
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le service'),
        actions: [
          TextButton(
            onPressed: _name.text.trim().length < 2 || _saving ? null : _save,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const RequestSectionLabel('Service'),
          const Gap(8),
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nom du service')),
          const Gap(10),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Ce qui est réalisé exactement (facultatif)'),
          ),
          const Gap(10),
          TextField(controller: _specialties, decoration: const InputDecoration(labelText: 'Spécialités, séparées par des virgules')),
          const Gap(16),
          const RequestSectionLabel('Prix'),
          const Gap(8),
          TextField(controller: _priceMin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'À partir de (FCFA)')),
          const Gap(10),
          TextField(
            controller: _priceMax,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Jusqu'à (FCFA)", helperText: 'Vide = sur devis.'),
          ),
          const Gap(16),
          const RequestSectionLabel('Comment et où'),
          _ModeToggles(selected: _modes, onChanged: (m) => setState(() => _modes = m)),
          TextField(
            controller: _zones,
            decoration: const InputDecoration(
              labelText: 'Zones, si différentes du profil',
              helperText: 'Rien de coché et pas de zone = ceux de ton profil.',
            ),
          ),
          const Gap(16),
          DropdownButtonFormField<String>(
            initialValue: _delay,
            decoration: const InputDecoration(labelText: 'Délai'),
            items: [for (final d in _delays) DropdownMenuItem(value: d, child: Text(d.isEmpty ? 'Non précisé' : d))],
            onChanged: (d) => setState(() => _delay = d ?? ''),
          ),
          const Gap(8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Service actif'),
            subtitle: const Text('En pause, ce service ne reçoit plus de demandes.'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}

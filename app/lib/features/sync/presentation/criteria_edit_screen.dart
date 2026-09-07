import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';

/// Define which categories of members to save (cahier §10).
///
/// Values come from [FilterOptions] — the live SBC vocabularies. Typing them
/// freehand was the previous design and it silently matched nothing whenever
/// the spelling or accent differed ("Maçon" vs SBC's "Macon"). Sexe and âge
/// existed on the model but had no control at all, so they could never be set.
class CriteriaEditScreen extends ConsumerStatefulWidget {
  const CriteriaEditScreen({this.existing, super.key});
  final SyncCriteria? existing;

  @override
  ConsumerState<CriteriaEditScreen> createState() => _CriteriaEditScreenState();
}

class _CriteriaEditScreenState extends ConsumerState<CriteriaEditScreen> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final Set<String> _countries = {...?widget.existing?.countries};
  late final Set<String> _regions = {...?widget.existing?.cities};
  late final Set<String> _professions = {...?widget.existing?.professions};
  late final Set<String> _interests = {...?widget.existing?.interests};
  late String? _sex = widget.existing?.sex;
  late double _ageMin = (widget.existing?.ageMin ?? 18).toDouble();
  late double _ageMax = (widget.existing?.ageMax ?? 65).toDouble();

  int? _preview;
  bool _previewing = false;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload() => {
        'label': _label.text.trim().isEmpty ? 'Sans titre' : _label.text.trim(),
        'countries': _countries.toList(),
        // The backend mirrors SBC's `region` into Member.city, so the criteria's
        // `cities` field is what régions match against.
        'cities': _regions.toList(),
        'professions': _professions.toList(),
        'interests': _interests.toList(),
        if (_sex != null) 'sex': _sex,
        'ageMin': _ageMin.round(),
        'ageMax': _ageMax.round(),
      };

  Future<void> _refreshPreview() async {
    setState(() => _previewing = true);
    try {
      final count = await ref.read(adhocPreviewProvider(_payload()).future);
      if (mounted) setState(() => _preview = count);
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ctrl = ref.read(criteriaControllerProvider.notifier);
    try {
      if (widget.existing == null) {
        await ctrl.create(_payload());
      } else {
        await ctrl.updateCriteria(widget.existing!.id, _payload());
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouveau critère' : 'Modifier le critère'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Nom du critère',
              hintText: 'Ex. Maçons de Douala',
            ),
          ),
          const Gap(20),

          _MultiSelect(
            title: 'Pays',
            selected: _countries,
            options: FilterOptions.countries.keys.toList(),
            labelFor: (code) => FilterOptions.countries[code] ?? code,
            onChanged: (s) => setState(() {
              _countries
                ..clear()
                ..addAll(s);
              _preview = null;
            }),
          ),
          const Gap(16),
          _MultiSelect(
            title: 'Régions',
            selected: _regions,
            options: FilterOptions.topRegions,
            onChanged: (s) => setState(() {
              _regions
                ..clear()
                ..addAll(s);
              _preview = null;
            }),
          ),
          const Gap(16),
          _MultiSelect(
            title: 'Professions',
            selected: _professions,
            options: FilterOptions.professions,
            onChanged: (s) => setState(() {
              _professions
                ..clear()
                ..addAll(s);
              _preview = null;
            }),
          ),
          const Gap(16),
          _MultiSelect(
            title: "Centres d'intérêt",
            selected: _interests,
            options: FilterOptions.interests,
            onChanged: (s) => setState(() {
              _interests
                ..clear()
                ..addAll(s);
              _preview = null;
            }),
          ),

          const Gap(20),
          Text('Sexe', style: theme.textTheme.labelLarge),
          const Gap(6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tous'),
                selected: _sex == null,
                onSelected: (_) => setState(() {
                  _sex = null;
                  _preview = null;
                }),
              ),
              for (final e in FilterOptions.sexes.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _sex == e.key,
                  onSelected: (_) => setState(() {
                    _sex = e.key;
                    _preview = null;
                  }),
                ),
            ],
          ),

          const Gap(20),
          Text(
            'Âge : ${_ageMin.round()} – ${_ageMax.round()} ans',
            style: theme.textTheme.labelLarge,
          ),
          RangeSlider(
            min: 16,
            max: 80,
            divisions: 64,
            values: RangeValues(_ageMin, _ageMax),
            labels: RangeLabels('${_ageMin.round()}', '${_ageMax.round()}'),
            onChanged: (v) => setState(() {
              _ageMin = v.start;
              _ageMax = v.end;
              _preview = null;
            }),
          ),

          const Gap(20),
          // §10: show how many members the criteria matches before saving it.
          Card(
            child: ListTile(
              leading: const Icon(Icons.group),
              title: Text(
                _preview == null
                    ? 'Combien de membres correspondent ?'
                    : '$_preview membre(s) correspondent',
              ),
              subtitle: _preview == null
                  ? null
                  : const Text('Estimation à partir des membres déjà connus'),
              trailing: _previewing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _refreshPreview,
                      child: const Text('Calculer'),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce critère ?'),
        content: const Text(
          'Les contacts déjà enregistrés dans votre téléphone ne seront pas supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(criteriaControllerProvider.notifier).remove(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }
}

/// A labelled set of chips plus a searchable sheet, for choosing several values
/// out of a long vocabulary.
class _MultiSelect extends StatelessWidget {
  const _MultiSelect({
    required this.title,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.labelFor,
  });

  final String title;
  final Set<String> selected;
  final List<String> options;
  final ValueChanged<Set<String>> onChanged;
  final String Function(String)? labelFor;

  String _label(String v) => labelFor?.call(v) ?? v;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MultiSelectSheet(
        title: title,
        options: options,
        selected: {...selected},
        labelFor: _label,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(selected.isEmpty ? 'Choisir' : 'Modifier'),
            ),
          ],
        ),
        if (selected.isEmpty)
          Text(
            'Tous',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final v in selected)
                InputChip(
                  label: Text(_label(v)),
                  onDeleted: () => onChanged({...selected}..remove(v)),
                ),
            ],
          ),
      ],
    );
  }
}

class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelFor,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final String Function(String) labelFor;

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _picked = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.options
        .where((o) => widget.labelFor(o).toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _picked.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(_picked.clear),
                        child: const Text('Effacer'),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const Gap(8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final o = shown[i];
                  return CheckboxListTile(
                    dense: true,
                    value: _picked.contains(o),
                    title: Text(widget.labelFor(o)),
                    onChanged: (on) => setState(
                      () => (on ?? false) ? _picked.add(o) : _picked.remove(o),
                    ),
                  );
                },
              ),
            ),
            const Gap(8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_picked),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              child: Text('Valider (${_picked.length})'),
            ),
          ],
        ),
      ),
    );
  }
}

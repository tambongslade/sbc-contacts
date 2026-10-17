import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/directory/application/search_controller.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';

/// The filters a criteria narrows members by. Shared by the criteria screen
/// and "Augmenter mes vues WhatsApp", which filters its list the same way.
class CriteriaFilters {
  CriteriaFilters({
    Set<String>? countries,
    Set<String>? regions,
    Set<String>? professions,
    Set<String>? interests,
    this.sex,
    this.ageEnabled = false,
    this.ageMin = 18,
    this.ageMax = 65,
  })  : countries = countries ?? {},
        regions = regions ?? {},
        professions = professions ?? {},
        interests = interests ?? {};

  final Set<String> countries;
  final Set<String> regions;
  final Set<String> professions;
  final Set<String> interests;
  String? sex;

  /// Off unless the criteria actually carries an age range.
  ///
  /// This used to be permanently on, defaulting to 18–65, and it was silently
  /// destroying criteria: SBC does not give an age for every member, and a
  /// range comparison drops every row whose age is NULL. A criterion the member
  /// never meant to filter by age would therefore match nobody, with nothing
  /// on screen to explain why.
  bool ageEnabled;
  double ageMin;
  double ageMax;

  CriteriaFilters copy() => CriteriaFilters(
        countries: {...countries},
        regions: {...regions},
        professions: {...professions},
        interests: {...interests},
        sex: sex,
        ageEnabled: ageEnabled,
        ageMin: ageMin,
        ageMax: ageMax,
      );

  /// Keeps the country only: what a subscription other than Ciblé may use.
  CriteriaFilters countryOnly() => CriteriaFilters(countries: {...countries});

  bool get isEmpty => countries.isEmpty && !hasAdvanced;

  /// Any filter besides the country.
  bool get hasAdvanced =>
      regions.isNotEmpty ||
      professions.isNotEmpty ||
      interests.isNotEmpty ||
      sex != null ||
      ageEnabled;

  /// Request body fields. Explicit empties and nulls, not omission: on an
  /// update, leaving a key out would keep whatever the criteria already had.
  Map<String, dynamic> toJson() => {
        'countries': countries.toList(),
        // The backend mirrors SBC's `region` into Member.city, so the criteria's
        // `cities` field is what régions match against.
        'cities': regions.toList(),
        'professions': professions.toList(),
        'interests': interests.toList(),
        'sex': sex,
        'ageMin': ageEnabled ? ageMin.round() : null,
        'ageMax': ageEnabled ? ageMax.round() : null,
      };

  /// Query parameters for a list endpoint: only what is set.
  Map<String, dynamic> toQuery() => {
        if (countries.isNotEmpty) 'countries': countries.toList(),
        if (regions.isNotEmpty) 'cities': regions.toList(),
        if (professions.isNotEmpty) 'professions': professions.toList(),
        if (interests.isNotEmpty) 'interests': interests.toList(),
        if (sex != null) 'sex': sex,
        if (ageEnabled) 'ageMin': ageMin.round(),
        if (ageEnabled) 'ageMax': ageMax.round(),
      };

  /// Short labels for what is set, for a summary line.
  List<String> get labels => [
        for (final c in countries) FilterOptions.countries[c] ?? c,
        ...regions,
        ...professions,
        ...interests,
        if (sex != null) FilterOptions.sexes[sex] ?? sex!,
        if (ageEnabled) '${ageMin.round()}–${ageMax.round()} ans',
      ];
}

/// Pays, régions, professions, centres d'intérêt, sexe and âge. With
/// [countryOnly], everything but the country is locked behind the Ciblé
/// subscription.
class CriteriaFiltersForm extends ConsumerWidget {
  const CriteriaFiltersForm({
    required this.filters,
    required this.onChanged,
    this.countryOnly = false,
    super.key,
  });

  final CriteriaFilters filters;

  /// Called after [filters] was changed in place.
  final VoidCallback onChanged;
  final bool countryOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final f = filters;
    void set(void Function() change) {
      change();
      onChanged();
    }

    void replace(Set<String> target, Set<String> values) => set(() {
          target
            ..clear()
            ..addAll(values);
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MultiSelect(
          title: 'Pays',
          selected: f.countries,
          options: FilterOptions.countries.keys.toList(),
          labelFor: (code) => FilterOptions.countries[code] ?? code,
          onChanged: (s) => replace(f.countries, s),
        ),
        const Gap(16),
        if (countryOnly)
          const _LockedFilters()
        else ...[
          // The live list for the chosen pays, not a static one: a région the
          // base does not actually carry is a criterion that matches nobody.
          // One country selected scopes it; several (or none) keep it global,
          // since the endpoint narrows to a single country at a time.
          _MultiSelect(
            title: 'Régions',
            selected: f.regions,
            options: ref
                    .watch(regionOptionsProvider(
                      f.countries.length == 1 ? f.countries.first : null,
                    ))
                    .value ??
                FilterOptions.regionsFor(
                  f.countries.length == 1 ? f.countries.first : null,
                ),
            onChanged: (s) => replace(f.regions, s),
          ),
          const Gap(16),
          _MultiSelect(
            title: 'Professions',
            selected: f.professions,
            options: FilterOptions.professions,
            onChanged: (s) => replace(f.professions, s),
          ),
          const Gap(16),
          _MultiSelect(
            title: "Centres d'intérêt",
            selected: f.interests,
            options: FilterOptions.interests,
            onChanged: (s) => replace(f.interests, s),
          ),
          const Gap(20),
          Text('Sexe', style: theme.textTheme.labelLarge),
          const Gap(6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tous'),
                selected: f.sex == null,
                onSelected: (_) => set(() => f.sex = null),
              ),
              for (final e in FilterOptions.sexes.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: f.sex == e.key,
                  onSelected: (_) => set(() => f.sex = e.key),
                ),
            ],
          ),
          const Gap(20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: f.ageEnabled,
            title: Text('Filtrer par âge', style: theme.textTheme.labelLarge),
            subtitle: Text(
              f.ageEnabled
                  ? '${f.ageMin.round()} – ${f.ageMax.round()} ans'
                  : "Tous les âges — les membres dont l'âge est inconnu "
                      'restent inclus',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onChanged: (v) => set(() => f.ageEnabled = v),
          ),
          if (f.ageEnabled)
            RangeSlider(
              min: 16,
              max: 80,
              divisions: 64,
              values: RangeValues(f.ageMin, f.ageMax),
              labels: RangeLabels('${f.ageMin.round()}', '${f.ageMax.round()}'),
              onChanged: (v) => set(() {
                f
                  ..ageMin = v.start
                  ..ageMax = v.end;
              }),
            ),
        ],
      ],
    );
  }
}

/// Stands in for the filters a subscription other than Ciblé cannot use.
class _LockedFilters extends StatelessWidget {
  const _LockedFilters();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SbcColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, size: 20, color: SbcColors.accent),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Abonnement Ciblé requis', style: theme.textTheme.titleSmall),
                const Gap(2),
                Text(
                  "Régions, professions, centres d'intérêt, sexe et âge sont "
                  'réservés à l’abonnement Ciblé. Ton abonnement filtre par pays.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';

/// Bottom sheet for the combinable directory filters (cahier §6).
///
/// Values come from [FilterOptions], sampled from the live SBC base, so the
/// member picks a term that exists rather than typing one that silently
/// matches nothing. Profession and région still accept free text — profession
/// matches partially server-side, and 598 of the 658 régions are outside the
/// suggested list.
class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.initial, super.key});
  final SearchFilters initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late String? _country = widget.initial.country;
  late String? _region = widget.initial.region;
  late String? _profession = widget.initial.profession;
  late String? _sex = widget.initial.sex;
  late final Set<String> _interests = {...widget.initial.interests};
  late double _ageMin = (widget.initial.ageMin ?? 18).toDouble();
  late double _ageMax = (widget.initial.ageMax ?? 65).toDouble();

  /// The age range is only sent once the member has actually moved it.
  /// Sending the 18–65 default unasked silently hid every member outside it —
  /// and the active-filter chips would then always show an age the member
  /// never chose.
  late bool _ageTouched =
      widget.initial.ageMin != null || widget.initial.ageMax != null;

  void _apply() {
    Navigator.of(context).pop(
      SearchFilters(
        search: widget.initial.search,
        country: _country,
        region: _region,
        city: widget.initial.city,
        profession: _profession,
        sex: _sex,
        ageMin: _ageTouched ? _ageMin.round() : null,
        ageMax: _ageTouched ? _ageMax.round() : null,
        interests: _interests.toList(),
      ),
    );
  }

  int get _activeCount =>
      [_country, _region, _profession, _sex].where((v) => v != null).length +
      (_interests.isEmpty ? 0 : 1) +
      (_ageTouched ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Filtres',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Gap(10),
                if (_activeCount > 0) _ActiveCountPill(count: _activeCount),
              ],
            ),
            const Gap(4),
            Text(
              'Les filtres se combinent entre eux.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Gap(16),

            // Country is picked by name but sent as its ISO code.
            _CodePicker(
              label: 'Pays',
              icon: Icons.public,
              value: _country,
              labels: FilterOptions.countries,
              onChanged: (v) => setState(() => _country = v),
            ),
            const Gap(10),
            _PickerField(
              label: 'Région',
              icon: Icons.location_on_outlined,
              value: _region,
              options: FilterOptions.topRegions,
              helper: 'Suggestions les plus fréquentes — tapez pour en chercher une autre',
              onChanged: (v) => setState(() => _region = v),
            ),
            const Gap(10),
            _PickerField(
              label: 'Profession',
              icon: Icons.work_outline,
              value: _profession,
              options: FilterOptions.professions,
              helper: 'Recherche partielle : « design » trouve « Designer graphique »',
              onChanged: (v) => setState(() => _profession = v),
            ),

            const Gap(20),
            const _SectionLabel('Sexe'),
            const Gap(8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: _sex == null,
                  onSelected: (_) => setState(() => _sex = null),
                ),
                for (final e in FilterOptions.sexes.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _sex == e.key,
                    onSelected: (_) => setState(() => _sex = e.key),
                  ),
              ],
            ),

            const Gap(20),
            const _SectionLabel("Centres d'intérêt"),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final i in FilterOptions.interests)
                  FilterChip(
                    label: Text(i),
                    selected: _interests.contains(i),
                    onSelected: (on) => setState(
                      () => on ? _interests.add(i) : _interests.remove(i),
                    ),
                  ),
              ],
            ),

            const Gap(20),
            Row(
              children: [
                const _SectionLabel('Âge'),
                const Spacer(),
                Text(
                  _ageTouched
                      ? '${_ageMin.round()} – ${_ageMax.round()} ans'
                      : 'Tous les âges',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _ageTouched
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_ageTouched)
                  IconButton(
                    tooltip: 'Ne pas filtrer par âge',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _ageTouched = false),
                  ),
              ],
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
                _ageTouched = true;
              }),
            ),

            const Gap(20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(const SearchFilters()),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Réinitialiser'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Appliquer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Group heading — one consistent weight for every section of the sheet.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// How many filters are currently set — stated as a number, never as a colour.
class _ActiveCountPill extends StatelessWidget {
  const _ActiveCountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 14, color: theme.colorScheme.primary),
            const Gap(6),
            Text(
              '$count actif${count > 1 ? 's' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Free-text-capable picker: suggests known values while typing, and offers a
/// searchable list to browse when the member does not know what to type.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final String? helper;
  final ValueChanged<String?> onChanged;

  Future<void> _browse(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OptionList(title: label, options: options, selected: value),
    );
    if (picked != null) onChanged(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value ?? ''),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((o) => o.toLowerCase().contains(q));
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            helperMaxLines: 2,
            prefixIcon: Icon(icon),
            suffixIcon: IconButton(
              tooltip: 'Choisir dans la liste',
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: () => _browse(context),
            ),
          ),
          onChanged: (t) => onChanged(t.trim().isEmpty ? null : t.trim()),
          onSubmitted: (_) => onSubmit(),
        );
      },
    );
  }
}

/// Picker over a fixed code→label map: shows the label, emits the code.
class _CodePicker extends StatelessWidget {
  const _CodePicker({
    required this.label,
    required this.icon,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String? value;
  final Map<String, String> labels;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        const DropdownMenuItem<String?>(child: Text('Tous')),
        for (final e in labels.entries)
          DropdownMenuItem<String?>(value: e.key, child: Text('${e.value} (${e.key})')),
      ],
      onChanged: onChanged,
    );
  }
}

/// Scrollable, searchable list behind the picker's browse affordance.
class _OptionList extends StatefulWidget {
  const _OptionList({required this.title, required this.options, this.selected});
  final String title;
  final List<String> options;
  final String? selected;

  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.options
        .where((o) => o.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Rechercher ${widget.title.toLowerCase()}',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const Gap(8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.clear),
                    title: const Text('Tous'),
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final o in shown)
                    ListTile(
                      title: Text(o),
                      trailing: o == widget.selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(context).pop(o),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

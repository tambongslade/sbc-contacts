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

  void _apply() {
    Navigator.of(context).pop(
      SearchFilters(
        search: widget.initial.search,
        country: _country,
        region: _region,
        city: widget.initial.city,
        profession: _profession,
        sex: _sex,
        ageMin: _ageMin.round(),
        ageMax: _ageMax.round(),
        interests: _interests.toList(),
      ),
    );
  }

  int get _activeCount =>
      [_country, _region, _profession, _sex].where((v) => v != null).length +
      (_interests.isEmpty ? 0 : 1);

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
                Text('Filtres', style: theme.textTheme.titleLarge),
                const Gap(8),
                if (_activeCount > 0)
                  Chip(
                    label: Text('$_activeCount actif${_activeCount > 1 ? 's' : ''}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const Gap(14),

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

            const Gap(16),
            Text('Sexe', style: theme.textTheme.labelLarge),
            const Gap(6),
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

            const Gap(16),
            Text("Centres d'intérêt", style: theme.textTheme.labelLarge),
            const Gap(6),
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

            const Gap(16),
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
              }),
            ),

            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(const SearchFilters()),
                    child: const Text('Réinitialiser'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: FilledButton(onPressed: _apply, child: const Text('Appliquer')),
                ),
              ],
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

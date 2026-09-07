import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';

/// Bottom sheet for the combinable directory filters (cahier §6).
class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.initial, super.key});
  final SearchFilters initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final _country = TextEditingController(text: widget.initial.country);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _profession = TextEditingController(text: widget.initial.profession);
  late String? _sex = widget.initial.sex;
  late double _ageMin = (widget.initial.ageMin ?? 18).toDouble();
  late double _ageMax = (widget.initial.ageMax ?? 65).toDouble();

  @override
  void dispose() {
    _country.dispose();
    _city.dispose();
    _profession.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _apply() {
    Navigator.of(context).pop(
      SearchFilters(
        search: widget.initial.search,
        country: _clean(_country),
        city: _clean(_city),
        profession: _clean(_profession),
        sex: _sex,
        ageMin: _ageMin.round(),
        ageMax: _ageMax.round(),
        interests: widget.initial.interests,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Filtres', style: Theme.of(context).textTheme.titleLarge),
            const Gap(12),
            TextField(controller: _country, decoration: const InputDecoration(labelText: 'Pays')),
            const Gap(10),
            TextField(controller: _city, decoration: const InputDecoration(labelText: 'Ville')),
            const Gap(10),
            TextField(
              controller: _profession,
              decoration: const InputDecoration(labelText: 'Profession'),
            ),
            const Gap(12),
            const Text('Sexe'),
            Wrap(
              spacing: 8,
              children: [
                for (final s in [null, 'M', 'F'])
                  ChoiceChip(
                    label: Text(s ?? 'Tous'),
                    selected: _sex == s,
                    onSelected: (_) => setState(() => _sex = s),
                  ),
              ],
            ),
            const Gap(12),
            Text('Âge: ${_ageMin.round()} – ${_ageMax.round()} ans'),
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

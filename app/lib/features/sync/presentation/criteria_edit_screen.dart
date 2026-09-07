import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';

class CriteriaEditScreen extends ConsumerStatefulWidget {
  const CriteriaEditScreen({this.existing, super.key});
  final SyncCriteria? existing;

  @override
  ConsumerState<CriteriaEditScreen> createState() => _CriteriaEditScreenState();
}

class _CriteriaEditScreenState extends ConsumerState<CriteriaEditScreen> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _countries = TextEditingController(text: widget.existing?.countries.join(', '));
  late final _cities = TextEditingController(text: widget.existing?.cities.join(', '));
  late final _professions = TextEditingController(text: widget.existing?.professions.join(', '));
  late final _interests = TextEditingController(text: widget.existing?.interests.join(', '));
  int? _preview;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_label, _countries, _cities, _professions, _interests]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(TextEditingController c) => c.text
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Map<String, dynamic> _payload() => {
        'label': _label.text.trim().isEmpty ? 'Sans titre' : _label.text.trim(),
        'countries': _split(_countries),
        'cities': _split(_cities),
        'professions': _split(_professions),
        'interests': _split(_interests),
      };

  Future<void> _refreshPreview() async {
    final count = await ref.read(adhocPreviewProvider(_payload()).future);
    if (mounted) setState(() => _preview = count);
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouveau critère' : 'Modifier le critère'),
        actions: [
          if (!isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(criteriaControllerProvider.notifier)
                    .remove(widget.existing!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Nom du critère'),
          ),
          const Gap(12),
          TextField(
            controller: _countries,
            decoration: const InputDecoration(
              labelText: 'Pays (séparés par des virgules)',
              hintText: 'Cameroun',
            ),
          ),
          const Gap(12),
          TextField(
            controller: _cities,
            decoration: const InputDecoration(labelText: 'Villes', hintText: 'Yaoundé, Douala'),
          ),
          const Gap(12),
          TextField(
            controller: _professions,
            decoration: const InputDecoration(labelText: 'Professions', hintText: 'Maçon, Designer'),
          ),
          const Gap(12),
          TextField(
            controller: _interests,
            decoration:
                const InputDecoration(labelText: "Centres d'intérêt", hintText: 'Business'),
          ),
          const Gap(16),
          OutlinedButton.icon(
            onPressed: _refreshPreview,
            icon: const Icon(Icons.calculate),
            label: Text(
              _preview == null ? 'Prévisualiser le nombre' : '$_preview membre(s) correspondant(s)',
            ),
          ),
          const Gap(24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

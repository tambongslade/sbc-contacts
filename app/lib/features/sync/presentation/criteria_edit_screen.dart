import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/status_boost/status_boost_screen.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';
import 'package:sbc_contacts/features/sync/presentation/criteria_filters_form.dart';

/// Define which categories of members to save (cahier §10).
///
/// Values come from [CriteriaFiltersForm] — the live SBC vocabularies. Typing them
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
  late final CriteriaFilters _filters = CriteriaFilters(
    countries: {...?widget.existing?.countries},
    regions: {...?widget.existing?.cities},
    professions: {...?widget.existing?.professions},
    interests: {...?widget.existing?.interests},
    sex: widget.existing?.sex,
    ageEnabled: widget.existing?.ageMin != null || widget.existing?.ageMax != null,
    ageMin: (widget.existing?.ageMin ?? 18).toDouble(),
    ageMax: (widget.existing?.ageMax ?? 65).toDouble(),
  );

  int? _preview;
  bool _previewing = false;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Its members are the "Augmenter mes vues WhatsApp" list, narrowed by the
  /// filters the member's subscription allows.
  bool get _boost => widget.existing?.statusBoost ?? false;

  /// Ciblé filters by everything; anyone else, on the list, by country only.
  bool get _countryOnly =>
      _boost && ref.watch(statusBoostMeProvider).value?.filterAccess != 'all';

  Map<String, dynamic> _payload() {
    final label = _label.text.trim();
    // Sent as such, a filter the subscription does not allow would be refused.
    final filters = _countryOnly ? _filters.countryOnly() : _filters;
    return {
      'label': label.isNotEmpty ? label : (_boost ? 'Vues WhatsApp' : 'Sans titre'),
      ...filters.toJson(),
    };
  }

  Future<void> _refreshPreview() async {
    setState(() => _previewing = true);
    try {
      final count = await ref.read(adhocPreviewProvider({
        ..._payload(),
        // Counted among the members of the list, not the whole mirror.
        if (_boost) 'statusBoost': true,
      }).future);
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
          if (_boost) ...[const _StatusBoostNote(), const Gap(20)],
          CriteriaFiltersForm(
            filters: _filters,
            countryOnly: _countryOnly,
            onChanged: () => setState(() => _preview = null),
          ),
          const Gap(20),
          // §10: show how many members the criteria matches before saving it.
          //
          // The caveat is shown before the number, not under it as an
          // afterthought: a criteria counts only members already mirrored from
          // previous searches, so it is always well below what the same filter
          // returns in the annuaire. Reading "2 membres" next to "863" in the
          // directory looks like a broken filter unless this says why.
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.group),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _preview == null
                              ? 'Combien de membres correspondent ?'
                              : '$_preview membre(s) correspondent',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Gap(3),
                        Text(
                          _boost
                              ? 'Compté parmi les membres de la liste.'
                              : 'Compté parmi les membres déjà consultés dans '
                                  "l'annuaire, pas sur toute la base SBC.",
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  if (_previewing)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton(
                      onPressed: _refreshPreview,
                      child: const Text('Calculer'),
                    ),
                ],
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

/// What a "Vues WhatsApp" criteria is, above its filters.
class _StatusBoostNote extends StatelessWidget {
  const _StatusBoostNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.visibility_rounded, color: SbcColors.whatsapp),
            const Gap(14),
            Expanded(
              child: Text(
                'Ce critère enregistre les membres de « Augmenter mes vues '
                'WhatsApp » qui correspondent aux filtres ci-dessous. Il suit la '
                'liste : tu es prévenu quand quelqu’un la rejoint, et il se '
                'désactive si tu la quittes.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/directory/data/directory_repository.dart';
import 'package:sbc_contacts/features/directory/domain/filter_options.dart';

/// Full-height sheet for the combinable directory filters (cahier §6), walked
/// as three steps: **où** (pays, région), **qui** (sexe, âge, profession),
/// **quoi** (centres d'intérêt).
///
/// One screen of eleven controls made every filter look equally mandatory and
/// buried the two that actually narrow the base. Split in three, each step
/// asks one question and the stepper says how much is left — while every step
/// stays skippable, because no filter is required to search.
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
  static const List<String> _stepLabels = ['PAYS', 'PROFIL', 'INTÉRÊTS'];
  static const double _ageFloor = 16;
  static const double _ageCeil = 80;

  /// Shared by the slider's track shape and the badges drawn above it, so the
  /// two cannot drift apart — see [_FixedInsetTrackShape].
  static const double _sliderTrackInset = 20;

  int _step = 0;

  /// Which way the last step change went, so the body slides in from the side
  /// it came from instead of always from the right.
  bool _forward = true;

  late String? _country = widget.initial.country;
  late String? _region = widget.initial.region;
  late String? _profession = widget.initial.profession;
  late String? _sex = widget.initial.sex;
  late final Set<String> _interests = {...widget.initial.interests};
  late double _ageMin = (widget.initial.ageMin ?? 18).toDouble();
  late double _ageMax = (widget.initial.ageMax ?? 65).toDouble();
  String _interestQuery = '';

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
        // Carried through, not edited here: the sort is chosen on the results
        // screen, and rebuilding the filters from scratch would silently drop it.
        sortByConfidence: widget.initial.sortByConfidence,
      ),
    );
  }

  int get _activeCount =>
      [_country, _region, _profession, _sex].where((v) => v != null).length +
      (_interests.isEmpty ? 0 : 1) +
      (_ageTouched ? 1 : 0);

  /// How many filters one step alone carries — drawn on the stepper so a
  /// member on step 3 still sees that step 1 is holding something.
  int _countOn(int step) => switch (step) {
        0 => [_country, _region].where((v) => v != null).length,
        1 => [_sex, _profession].where((v) => v != null).length +
            (_ageTouched ? 1 : 0),
        _ => _interests.length,
      };

  /// Changing the pays drops a région that cannot belong to it: the pair would
  /// match nothing, and a search that silently returns zero reads as a bug
  /// rather than as a contradiction the member introduced.
  void _selectCountry(String? code) {
    setState(() {
      _country = code;
      final region = _region;
      if (region != null && !FilterOptions.regionMatchesCountry(region, code)) {
        _region = null;
      }
    });
  }

  void _goTo(int step) {
    final next = step.clamp(0, _stepLabels.length - 1);
    if (next == _step) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = next > _step;
      _step = next;
    });
  }

  void _next() => _step == _stepLabels.length - 1 ? _apply() : _goTo(_step + 1);

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      _goTo(_step - 1);
    }
  }

  void _clearAll() => setState(() {
        _country = null;
        _region = null;
        _profession = null;
        _sex = null;
        _interests.clear();
        _ageMin = 18;
        _ageMax = 65;
        _ageTouched = false;
        _interestQuery = '';
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final height = (size.height * 0.9) - insets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: height < 380 ? 380 : height,
        child: Column(
          children: [
            _SheetHeader(
              onBack: _back,
              onClear: _activeCount == 0 ? null : _clearAll,
            ),
            _StepBar(
              current: _step,
              labels: _stepLabels,
              countOf: _countOn,
              onTap: _goTo,
            ),
            Expanded(
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(_forward ? 0.06 : -0.06, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _placeStep(),
                      1 => _profileStep(),
                      _ => _interestStep(),
                    },
                  ),
                ),
              ),
            ),
            _Footer(
              onBack: _step == 0 ? null : _back,
              onNext: _next,
              label: _step == _stepLabels.length - 1
                  ? 'Voir les résultats'
                  : 'Continuer',
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- step 1

  Widget _placeStep() {
    return _StepBody(
      children: [
        const _StepTitle('Où cherches-tu ?'),
        const Gap(14),
        _ChoiceTile(
          title: 'Tous les pays',
          subtitle: 'Chercher dans toute la base',
          leading: Icons.public_rounded,
          selected: _country == null,
          onTap: () => setState(() => _country = null),
        ),
        const Gap(10),
        // Country is picked by name but sent as its ISO code — which is also
        // the glyph on the tile: two letters read at a glance and, unlike a
        // flag emoji, render on every device.
        _TileGrid(
          children: [
            for (final e in FilterOptions.countries.entries)
              _ChoiceTile(
                title: e.key,
                subtitle: e.value,
                emphasis: true,
                selected: _country == e.key,
                onTap: () => _selectCountry(_country == e.key ? null : e.key),
              ),
          ],
        ),
        const Gap(14),
        _PickerField(
          // Keyed on the country so the field rebuilds its suggestions — and
          // its text — when the pays changes underneath it.
          key: ValueKey('region-${_country ?? 'all'}'),
          label: 'Région',
          icon: Icons.location_on_outlined,
          value: _region,
          options: FilterOptions.regionsFor(_country),
          helper: _country == null
              ? 'Suggestions les plus fréquentes — tapez pour en chercher une autre'
              : 'Régions de ${FilterOptions.countries[_country]} — tapez pour en chercher une autre',
          onChanged: (v) => setState(() => _region = v),
        ),
        const Gap(14),
        const _TipCard(
          title: 'Astuce rapide',
          body: 'Un seul pays à la fois. Laisse « Tous les pays » pour ratisser '
              'large, puis affine avec la région.',
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 2

  Widget _profileStep() {
    final theme = Theme.of(context);
    return _StepBody(
      children: [
        const _StepTitle('Ton profil idéal'),
        const Gap(16),
        const _Eyebrow('Sexe'),
        const Gap(8),
        Row(
          children: [
            for (final tile in const [
              ('male', 'Homme', Icons.man_rounded, SbcColors.primary),
              ('female', 'Femme', Icons.woman_rounded, SbcColors.accent),
              ('other', 'Autre', Icons.transgender_rounded, SbcColors.secondary),
              (null, 'Tous', Icons.groups_rounded, SbcColors.info),
            ]) ...[
              Expanded(
                child: _IconTile(
                  icon: tile.$3,
                  label: tile.$2,
                  tint: tile.$4,
                  selected: _sex == tile.$1,
                  onTap: () => setState(() => _sex = tile.$1),
                ),
              ),
              if (tile.$1 != null) const Gap(8),
            ],
          ],
        ),
        const Gap(20),
        _Eyebrow(
          _ageTouched
              ? 'Âge · ${_ageMin.round()} – ${_ageMax.round()} ans'
              : 'Âge · tous',
          trailing: _ageTouched
              ? _MiniTextButton(
                  label: 'Tous les âges',
                  onTap: () => setState(() => _ageTouched = false),
                )
              : null,
        ),
        const Gap(8),
        _Card(
          child: Column(
            children: [
              _AgeThumbLabels(
                min: _ageMin,
                max: _ageMax,
                floor: _ageFloor,
                ceil: _ageCeil,
                trackInset: _sliderTrackInset,
                muted: !_ageTouched,
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: _ageTouched
                      ? SbcColors.secondary
                      : theme.colorScheme.outlineVariant,
                  inactiveTrackColor:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  showValueIndicator: ShowValueIndicator.never,
                  rangeThumbShape:
                      const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: _sliderTrackInset,
                  ),
                  // The track shape is what decides where a thumb can travel,
                  // so owning it is the only way the badges above can be sure
                  // where the thumbs are — see [_FixedInsetTrackShape].
                  rangeTrackShape:
                      const _FixedInsetTrackShape(_sliderTrackInset),
                ),
                child: RangeSlider(
                  min: _ageFloor,
                  max: _ageCeil,
                  divisions: (_ageCeil - _ageFloor).round(),
                  values: RangeValues(_ageMin, _ageMax),
                  onChanged: (v) => setState(() {
                    _ageMin = v.start;
                    _ageMax = v.end;
                    _ageTouched = true;
                  }),
                ),
              ),
              const Gap(4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in const [
                    ('18 – 25', 18.0, 25.0),
                    ('26 – 35', 26.0, 35.0),
                    ('36 – 50', 36.0, 50.0),
                    ('50 et +', 50.0, _ageCeil),
                  ])
                    _SmallChip(
                      label: p.$1,
                      selected:
                          _ageTouched && _ageMin == p.$2 && _ageMax == p.$3,
                      onTap: () => setState(() {
                        _ageMin = p.$2;
                        _ageMax = p.$3;
                        _ageTouched = true;
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Gap(14),
        _PickerField(
          label: 'Profession',
          icon: Icons.work_outline_rounded,
          value: _profession,
          options: FilterOptions.professions,
          helper: 'Recherche partielle : « design » trouve « Designer graphique »',
          onChanged: (v) => setState(() => _profession = v),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 3

  Widget _interestStep() {
    final q = _interestQuery.trim().toLowerCase();
    final matches = FilterOptions.interests
        .where((i) => q.isEmpty || i.toLowerCase().contains(q))
        .toList();
    // Chosen interests stay at the top: once the list is filtered or scrolled,
    // what is already selected must not be the thing you have to hunt for.
    final ordered = [
      ...matches.where(_interests.contains),
      ...matches.where((i) => !_interests.contains(i)),
    ];

    return _StepBody(
      children: [
        Row(
          children: [
            const Expanded(child: _StepTitle("Centres d'intérêt")),
            if (_interests.isNotEmpty)
              _CountPill(
                label: '${_interests.length} sélectionné'
                    '${_interests.length > 1 ? 's' : ''}',
              ),
          ],
        ),
        const Gap(14),
        _SearchField(
          hint: 'Rechercher un intérêt',
          value: _interestQuery,
          onChanged: (v) => setState(() => _interestQuery = v),
        ),
        const Gap(14),
        if (ordered.isEmpty)
          const _EmptyLine("Aucun centre d'intérêt ne correspond.")
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in ordered)
                _InterestChip(
                  label: i,
                  selected: _interests.contains(i),
                  onTap: () => setState(
                    () => _interests.contains(i)
                        ? _interests.remove(i)
                        : _interests.add(i),
                  ),
                ),
            ],
          ),
        const Gap(16),
        _TipCard(
          title: _interests.isEmpty ? 'Astuce rapide' : 'Bien vu',
          body: _interests.isEmpty
              ? "Deux ou trois centres d'intérêt suffisent : au-delà, la liste "
                  'de résultats se resserre vite.'
              : 'Les filtres se combinent entre eux — $_activeCount actif'
                  '${_activeCount > 1 ? 's' : ''} pour cette recherche.',
          done: _interests.isNotEmpty,
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- chrome

/// Near-black is the sheet's one saturated object, as everywhere else in the
/// app; in dark mode it would sink into the ground, so it inverts instead.
Color _ink(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.surfaceContainerHighest
    : const Color(0xFF10182B);

Color _onInk(ThemeData theme) => theme.brightness == Brightness.dark
    ? theme.colorScheme.onSurface
    : Colors.white;

Color _hairline(ThemeData theme) =>
    theme.colorScheme.outlineVariant.withValues(alpha: 0.55);

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onBack, required this.onClear});

  final VoidCallback onBack;

  /// Null when there is nothing to clear — the affordance stays in place and
  /// reads as inert, rather than vanishing and shifting the header.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: SbcColors.secondary.withValues(alpha: 0.16),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onBack,
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 20,
                      color: theme.brightness == Brightness.dark
                          ? SbcColors.secondaryLight
                          : SbcColors.secondaryDark,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Filtres',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                child: const Text('Effacer'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three steps, their state, and how many filters each one holds.
class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.current,
    required this.labels,
    required this.countOf,
    required this.onTap,
  });

  final int current;
  final List<String> labels;
  final int Function(int) countOf;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Container(
                    height: 2,
                    color:
                        i <= current ? SbcColors.secondary : _hairline(theme),
                  ),
                ),
              ),
            _StepDot(
              index: i,
              label: labels[i],
              count: countOf(i),
              done: i < current,
              active: i == current,
              onTap: () => onTap(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.label,
    required this.count,
    required this.done,
    required this.active,
    required this.onTap,
  });

  final int index;
  final String label;
  final int count;
  final bool done;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = done
        ? SbcColors.secondary
        : active
            ? _ink(theme)
            : theme.scaffoldBackgroundColor;
    final onFill = done
        ? Colors.white
        : active
            ? _onInk(theme)
            : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: active,
      label: 'Étape ${index + 1} sur 3, $label'
          '${count > 0 ? ', $count filtre${count > 1 ? 's' : ''}' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: done || active
                          ? null
                          : Border.all(color: _hairline(theme)),
                    ),
                    child: done
                        ? Icon(Icons.check_rounded, size: 17, color: onFill)
                        : Text(
                            '${index + 1}',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: onFill, fontSize: 12.5),
                          ),
                  ),
                  // How many filters a step the member is not looking at holds:
                  // "this one has something" must never be colour alone.
                  if (count > 0 && !active)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 15,
                        height: 15,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: SbcColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 8.5,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Gap(6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: active
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: done ? 1 : 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.onBack,
    required this.onNext,
    required this.label,
  });

  final VoidCallback? onBack;
  final VoidCallback onNext;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: _hairline(theme))),
      ),
      // The sheet is opened with `useSafeArea`, which only guards the top; the
      // gesture inset at the bottom is this footer's to clear.
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            _GhostButton(label: 'Retour', onTap: onBack!),
            const Gap(12),
          ],
          Expanded(child: _PrimaryButton(label: label, onTap: onNext)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: _ink(theme),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _onInk(theme),
                  ),
                ),
              ),
              const Gap(8),
              Icon(Icons.chevron_right_rounded, size: 20, color: _onInk(theme)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 22),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- pieces

/// The scrolling area of one step: the same gutters and bottom slack on all
/// three, so moving between steps never nudges the content sideways.
class _StepBody extends StatelessWidget {
  const _StepBody({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

/// All-caps group heading, optionally with an action on its right.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _MiniTextButton extends StatelessWidget {
  const _MiniTextButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 11.5,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// A pale object on the step's ground — the only container shape used here.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _hairline(theme)),
      ),
      child: child,
    );
  }
}

/// Three tiles per row, sized from the available width rather than by an
/// aspect ratio, so the grid keeps its rhythm on a 360 dp phone and a tablet.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const spacing = 10.0;
    const columns = 3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _SelectedDot extends StatelessWidget {
  const _SelectedDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: SbcColors.secondary,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Selectable tile. Selection is a dark border *and* a dot, never a tint on
/// its own — the palette already spends its colour on the brand arc.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.emphasis = false,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final bool selected;

  /// Draws the title as the tile's glyph (the ISO code), not as a label.
  final bool emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: subtitle == null ? title : '$title, $subtitle',
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: emphasis ? 12 : 16,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? _ink(theme) : _hairline(theme),
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: emphasis
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    if (leading != null)
                      Row(
                        children: [
                          Icon(
                            leading,
                            size: 19,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const Gap(8),
                          Text(title, style: theme.textTheme.titleSmall),
                        ],
                      )
                    else
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: emphasis
                            ? theme.textTheme.titleLarge?.copyWith(fontSize: 21)
                            : theme.textTheme.titleSmall,
                      ),
                    if (subtitle != null) ...[
                      Gap(emphasis ? 2 : 3),
                      Padding(
                        padding:
                            EdgeInsets.only(left: leading != null ? 27 : 0),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign:
                              emphasis ? TextAlign.center : TextAlign.start,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (selected)
                  const Positioned(right: -4, top: -4, child: _SelectedDot()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sex tile.
///
/// The glyph is a vector icon, not an emoji: emoji are drawn by whatever font
/// the device ships, so they arrived in a different style on every phone and
/// could not take the brand tint. An icon is one flat shape this app controls.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? _ink(theme) : _hairline(theme),
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 21, color: tint),
                    ),
                    const Gap(7),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (selected)
                  const Positioned(right: -2, top: -2, child: _SelectedDot()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two ends of the age range, drawn over the track they belong to.
///
/// The slider's own value indicator only shows while a thumb is held — which
/// is exactly when the member's thumb is covering it.
class _AgeThumbLabels extends StatelessWidget {
  const _AgeThumbLabels({
    required this.min,
    required this.max,
    required this.floor,
    required this.ceil,
    required this.trackInset,
    required this.muted,
  });

  final double min;
  final double max;
  final double floor;
  final double ceil;

  /// Half the slider's overlay width — what Flutter insets the track by on
  /// each side, and therefore where a thumb's travel actually starts and ends.
  /// Guessing it here is what put the badges 10 px off their thumbs.
  final double trackInset;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    const badgeWidth = 40.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxWidth - trackInset * 2;
        double leftFor(double value) {
          final ratio = (value - floor) / (ceil - floor);
          return (trackInset + ratio * span - badgeWidth / 2)
              .clamp(0.0, constraints.maxWidth - badgeWidth);
        }

        return SizedBox(
          height: 26,
          child: Stack(
            children: [
              Positioned(
                left: leftFor(min),
                child: _AgeBadge(value: min, muted: muted),
              ),
              Positioned(
                left: leftFor(max),
                child: _AgeBadge(value: max, muted: muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AgeBadge extends StatelessWidget {
  const _AgeBadge({required this.value, required this.muted});
  final double value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: muted ? theme.scaffoldBackgroundColor : _ink(theme),
        borderRadius: BorderRadius.circular(12),
        border: muted ? Border.all(color: _hairline(theme)) : null,
      ),
      child: Text(
        '${value.round()}',
        style: theme.textTheme.labelMedium?.copyWith(
          fontSize: 11.5,
          color: muted ? theme.colorScheme.onSurfaceVariant : _onInk(theme),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? _ink(theme) : theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          // An edge, because these sit on a white card: filled with the page
          // ground alone they read as plain text and nobody tries tapping them.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _ink(theme) : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 12,
              color: selected ? _onInk(theme) : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Interest chip: glyph first, so the list is scannable before it is read.
class _InterestChip extends StatelessWidget {
  const _InterestChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The wire value carries a parenthetical gloss ("Musique (instruments,
  /// chant)") that doubles the chip's width for nothing. Only the display is
  /// trimmed — [label] is still what gets selected and sent.
  String get _short {
    final cut = label.indexOf(' (');
    return cut == -1 ? label : label.substring(0, cut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = FilterOptions.interestEmoji[label];
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? SbcColors.secondary : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? SbcColors.secondary : _hairline(theme),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null) ...[
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  const Gap(7),
                ],
                // Flexible, not a bare Text: the longest interests ("Aide aux
                // personnes defavorisees") are wider than the screen, and a
                // chip in a Wrap is handed the whole line to measure against.
                // Two lines keep the label readable where an ellipsis would
                // just hide which interest this is.
                Flexible(
                  child: Text(
                    _short,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      height: 1.2,
                      color:
                          selected ? Colors.white : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (selected) ...[
                  const Gap(6),
                  const Icon(Icons.check_rounded, size: 15, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: SbcColors.secondary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SbcColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontSize: 11.5,
          color: theme.brightness == Brightness.dark
              ? SbcColors.secondaryLight
              : SbcColors.secondaryDark,
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.title, required this.body, this.done = false});
  final String title;
  final String body;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = done ? SbcColors.secondary : theme.colorScheme.primary;
    return _Card(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              done ? Icons.check_circle_outline_rounded : Icons.auto_awesome,
              size: 19,
              color: tint,
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const Gap(2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: theme.colorScheme.surface,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: widget.value.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: _hairline(theme)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: _hairline(theme)),
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
    super.key,
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
      builder: (_) =>
          _OptionList(title: label, options: options, selected: value),
    );
    if (picked != null) onChanged(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
              const Gap(8),
              Expanded(child: _Eyebrow(label)),
              if (value != null)
                _MiniTextButton(label: 'Effacer', onTap: () => onChanged(null)),
            ],
          ),
          const Gap(8),
          Autocomplete<String>(
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
                  hintText: 'Toutes',
                  isDense: true,
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
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
          ),
          if (helper != null) ...[
            const Gap(8),
            Text(
              helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
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
                      trailing:
                          o == widget.selected ? const Icon(Icons.check) : null,
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

/// Range-slider track with an inset this file chooses.
///
/// Material's own horizontal inset is derived from the overlay shape and has
/// changed between versions; it is not exposed anywhere the widget above can
/// read it. Guessing it put the age badges ten pixels off their thumbs on a
/// real phone while looking correct in a 400 px test render. The thumb travel
/// is computed from the rect this returns, so defining it here makes the
/// badges and the thumbs share one number by construction.
class _FixedInsetTrackShape extends RoundedRectRangeSliderTrackShape {
  const _FixedInsetTrackShape(this.inset);
  final double inset;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 6;
    return Rect.fromLTWH(
      offset.dx + inset,
      offset.dy + (parentBox.size.height - height) / 2,
      parentBox.size.width - inset * 2,
      height,
    );
  }
}

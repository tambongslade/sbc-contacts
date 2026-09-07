import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// Skeleton placeholders for the list-shaped screens.
///
/// A bare spinner tells the member nothing about what is coming and makes the
/// app feel like it stalled; a skeleton shows the shape of the result and the
/// screen stops jumping when data lands. Used wherever a list is loading.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({this.rows = 7, this.hasLeading = true, super.key});

  final int rows;
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: ListView.builder(
        itemCount: rows,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, i) => ListTile(
          leading: hasLeading ? const CircleAvatar(radius: 22) : null,
          title: const Text('Nom du membre SBC'),
          subtitle: const Text('Profession · Région'),
          trailing: const Icon(Icons.circle, size: 36),
        ),
      ),
    );
  }
}

/// Skeleton for the synchronisation dashboard counters.
class SummarySkeleton extends StatelessWidget {
  const SummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Skeletonizer(
      child: Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(
            children: [
              _Stat(),
              _Stat(),
              _Stat(),
              _Stat(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: Column(
        children: [
          Icon(Icons.circle, size: 22),
          SizedBox(height: 6),
          Text('12'),
          Text('Libellé'),
        ],
      ),
    );
  }
}

/// Skeleton for a card list (search results, criteria).
///
/// Mirrors the real member-card geometry — same margins, same avatar size,
/// same trailing actions — so nothing shifts when the data lands.
class CardListSkeleton extends StatelessWidget {
  const CardListSkeleton({this.rows = 5, this.hasActions = true, super.key});

  final int rows;
  final bool hasActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Skeletonizer(
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              child: Row(
                children: [
                  const CircleAvatar(radius: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nom du membre SBC'),
                        SizedBox(height: 4),
                        Text('Profession · Région'),
                      ],
                    ),
                  ),
                  if (hasActions) ...[
                    const Icon(Icons.circle, size: 24),
                    const SizedBox(width: 12),
                    const Icon(Icons.circle, size: 46),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

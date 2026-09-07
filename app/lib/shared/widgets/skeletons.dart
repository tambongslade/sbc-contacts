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
class CardListSkeleton extends StatelessWidget {
  const CardListSkeleton({this.rows = 5, super.key});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            const Card(
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(radius: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Nom du membre'),
                          SizedBox(height: 4),
                          Text('Profession · Région'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/theme/app_theme.dart';
import 'package:sbc_contacts/features/favorites/application/favorites_controller.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_card.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes favoris')),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Erreur',
          message: e.toString(),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const EmptyState(
              icon: Icons.star_border,
              title: 'Aucun favori',
              message: 'Ajoute des membres à tes favoris pour les retrouver ici.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(favoritesControllerProvider),
            child: ListView.builder(
              // Clears the floating nav bar the list scrolls under.
              padding: EdgeInsets.only(
                top: 8,
                bottom: AppTheme.navInsetOf(context),
              ),
              itemCount: members.length,
              itemBuilder: (context, i) => MemberCard(
                member: members[i],
                onTap: () => context.push('/profile/${members[i].sbcId}'),
              ),
            ),
          );
        },
      ),
    );
  }
}

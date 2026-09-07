import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: MemberAvatar(
                    initials: (user.name ?? '?').isNotEmpty ? user.name![0] : '?',
                    avatarUrl: user.avatarUrl,
                    radius: 44,
                  ),
                ),
                const Gap(12),
                Center(
                  child: Text(
                    user.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (user.email != null) Center(child: Text(user.email!)),
                const Gap(20),
                Card(
                  child: ListTile(
                    leading: Icon(
                      user.hasActiveSubscription ? Icons.verified : Icons.info_outline,
                      color: user.hasActiveSubscription
                          ? theme.colorScheme.secondary
                          : theme.colorScheme.tertiary,
                    ),
                    title: const Text('Abonnement'),
                    subtitle: Text(
                      user.hasActiveSubscription
                          ? user.subscriptionTypes.join(', ')
                          : 'Aucun abonnement actif',
                    ),
                  ),
                ),
                if (user.country != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('Pays'),
                      subtitle: Text(user.country!),
                    ),
                  ),
                const Gap(24),
                OutlinedButton.icon(
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
    );
  }
}

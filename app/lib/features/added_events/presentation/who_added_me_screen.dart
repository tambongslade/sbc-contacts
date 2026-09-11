import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/features/added_events/application/who_added_me_controller.dart';
import 'package:sbc_contacts/features/added_events/domain/added_by_user.dart';
import 'package:sbc_contacts/shared/widgets/empty_state.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/skeletons.dart';
import 'package:sbc_contacts/shared/widgets/whatsapp_button.dart';

/// "Qui m'a ajouté ?" (cahier §21): the members who saved the caller to their
/// phone contacts, so the caller can reach back out.
class WhoAddedMeScreen extends ConsumerWidget {
  const WhoAddedMeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(whoAddedMeControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Qui m'a ajouté ?")),
      body: async.when(
        loading: () => const CardListSkeleton(),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Erreur',
          message: e.toString(),
          action: FilledButton(
            onPressed: () => ref.invalidate(whoAddedMeControllerProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (people) {
          if (people.isEmpty) {
            return const EmptyState(
              icon: Icons.person_add_disabled,
              title: 'Personne ne vous a encore ajouté',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(whoAddedMeControllerProvider),
            child: ListView.separated(
              itemCount: people.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _PersonTile(person: people[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});
  final AddedByUser person;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: MemberAvatar(
        initials: person.initials,
        avatarUrl: person.avatarUrl,
      ),
      title: Text(person.displayName),
      subtitle: const Text('vous a ajouté à ses contacts'),
      trailing: WhatsAppButton(
        phoneNumber: person.phoneNumber,
        contactName: person.displayName,
        size: 40,
      ),
    );
  }
}

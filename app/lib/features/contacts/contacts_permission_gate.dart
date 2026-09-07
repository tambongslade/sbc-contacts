import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sbc_contacts/core/providers/core_providers.dart';

/// Asks for contacts access when the app opens, explaining why first.
///
/// Android only shows its system dialog twice before denying permanently, so
/// firing the raw request on launch burns those attempts against a member who
/// has no idea what is being asked. This shows the reason first (cahier §12,
/// §13, §20), and once permission is permanently denied it stops asking and
/// points at Settings, which is the only place left to grant it.
class ContactsPermissionGate {
  const ContactsPermissionGate._();

  static Future<void> ensure(BuildContext context, WidgetRef ref) async {
    final service = ref.read(contactServiceProvider);

    final status = await service.checkPermission();
    if (status == PermissionStatus.granted || status == PermissionStatus.limited) {
      return; // already usable — never nag
    }
    if (!context.mounted) return;

    final permanentlyBlocked = status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.contacts_outlined, size: 32),
        title: const Text('Accès à vos contacts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SBC Contacts a besoin de votre carnet de contacts pour :',
            ),
            const Gap(12),
            const _Reason(
              icon: Icons.person_add_alt,
              text: 'enregistrer les membres SBC que vous choisissez',
            ),
            const _Reason(
              icon: Icons.sync,
              text: 'synchroniser ceux qui correspondent à vos critères',
            ),
            const _Reason(
              icon: Icons.copy_all_outlined,
              text: 'éviter les doublons avant de créer une fiche',
            ),
            const Gap(12),
            Text(
              permanentlyBlocked
                  ? "L'accès a été refusé. Vous pouvez l'activer dans les "
                      'paramètres du téléphone.'
                  : "Rien n'est ajouté sans votre confirmation, et aucun "
                      'message n\'est envoyé automatiquement.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(permanentlyBlocked ? 'Ouvrir les paramètres' : 'Autoriser'),
          ),
        ],
      ),
    );

    if (accepted != true) return;

    if (permanentlyBlocked) {
      await ph.openAppSettings();
      return;
    }

    final granted = await service.requestPermission();
    if (!granted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Sans cet accès, l'ajout au téléphone et la synchronisation "
            'resteront indisponibles.',
          ),
        ),
      );
    }
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const Gap(10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

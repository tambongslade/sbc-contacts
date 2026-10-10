import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';

/// White, softly-shadowed panel — the same surface as the profile screen.
class RequestPanel extends StatelessWidget {
  const RequestPanel({required this.child, this.padding = const EdgeInsets.all(16), super.key});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: SbcColors.primary.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

/// Small uppercase section heading ("EN COURS").
class RequestSectionLabel extends StatelessWidget {
  const RequestSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Tinted capsule for a status ("3 réponses", "Terminée").
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {required this.tone, super.key});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: tone),
        ),
      );
}

/// Label + value line in a summary card.
class FactRow extends StatelessWidget {
  const FactRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// "Ton numéro reste privé…" — said wherever a member might worry about it.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: muted),
        const Gap(8),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: muted))),
      ],
    );
  }
}

Color toneForRequest(RequestStatus s) => switch (s) {
      RequestStatus.responded || RequestStatus.locked || RequestStatus.selected => SbcColors.primary,
      RequestStatus.completed => SbcColors.success,
      RequestStatus.sent || RequestStatus.matching || RequestStatus.draft => SbcColors.accentDark,
      _ => Colors.grey.shade600,
    };

Color toneForDispatch(DispatchStatus s) => switch (s) {
      DispatchStatus.sent => SbcColors.primary,
      DispatchStatus.interested || DispatchStatus.question => SbcColors.accentDark,
      DispatchStatus.selected => SbcColors.success,
      _ => Colors.grey.shade600,
    };

final _when = DateFormat('d MMM à HH:mm', 'fr');
String formatWhen(DateTime d) => _when.format(d);

/// "il y a 5 min", in French.
String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  return DateFormat('d MMM', 'fr').format(d);
}

/// The messages between a requester and one pro, oldest first.
class ConversationThread extends StatelessWidget {
  const ConversationThread({
    required this.messages,
    required this.meIsPro,
    required this.otherName,
    super.key,
  });

  final List<ConversationMessage> messages;
  final bool meIsPro;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final m in messages)
          Builder(builder: (context) {
            final mine = m.fromPro == meIsPro;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: mine ? SbcColors.primary : theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      m.text,
                      style: theme.textTheme.bodyMedium?.copyWith(color: mine ? Colors.white : null),
                    ),
                  ),
                  const Gap(2),
                  Text(
                    '${mine ? 'Toi' : otherName} · ${relativeTime(m.createdAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// A short message sheet: answer a question or write to the other side.
/// [onSend] returns true once sent, which closes the sheet.
Future<void> showMessageComposer(
  BuildContext context, {
  required String title,
  required Future<bool> Function(String text) onSend,
  String placeholder = 'Ton message',
  String? hint,
}) {
  final controller = TextEditingController();
  var sending = false;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Gap(12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              decoration: InputDecoration(hintText: placeholder, helperText: hint, helperMaxLines: 2),
              onChanged: (_) => setState(() {}),
            ),
            const Gap(8),
            FilledButton(
              onPressed: controller.text.trim().isEmpty || sending
                  ? null
                  : () async {
                      setState(() => sending = true);
                      final ok = await onSend(controller.text.trim());
                      if (!context.mounted) return;
                      setState(() => sending = false);
                      if (ok) Navigator.of(sheetContext).pop();
                    },
              child: Text(sending ? 'Envoi…' : 'Envoyer'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Asks, then deletes a request and drops it from "Mes demandes".
Future<bool> confirmDeleteRequest(BuildContext context, WidgetRef ref, ServiceRequestItem request) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Supprimer cette demande ?'),
      content: Text(request.deleteWarning),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.of(c).pop(true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await ref.read(requestsRepositoryProvider).remove(request.id);
    ref.read(myRequestsProvider.notifier).remove(request.id);
    if (context.mounted) showToast(context, 'Demande supprimée.');
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, e.toString());
    return false;
  }
}

void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// Always-on reminder for a pro whose setup is incomplete.
class ProSetupBanner extends StatelessWidget {
  const ProSetupBanner({required this.missing, super.key});
  final List<ProSetupItem> missing;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: SbcColors.accent.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: SbcColors.accent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(missing.contains(ProSetupItem.profile) ? '/pro/profile' : '/pro/services/add'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_rounded, color: SbcColors.accentDark),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Profil pro incomplet', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const Gap(4),
                    Text(
                      "Aucune demande ne peut t'arriver tant que ce n'est pas fait :",
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    for (final m in missing)
                      Text('• ${m.todo}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    const Gap(4),
                    Text(
                      'Compléter maintenant',
                      style: theme.textTheme.labelLarge?.copyWith(color: SbcColors.primary, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

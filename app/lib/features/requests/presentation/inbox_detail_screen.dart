import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';

/// A request as the pro sees it: the need, never who asked, the four answers,
/// the conversation and what happened since (Data §10, §18, §22). Opening it
/// marks it seen.
class InboxDetailScreen extends ConsumerStatefulWidget {
  const InboxDetailScreen({required this.requestId, this.initial, super.key});
  final String requestId;
  final InboxItem? initial;

  @override
  ConsumerState<InboxDetailScreen> createState() => _InboxDetailScreenState();
}

class _InboxDetailScreenState extends ConsumerState<InboxDetailScreen> {
  late InboxItem? _item = widget.initial;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  void _set(InboxItem item) {
    setState(() => _item = item);
    ref.read(inboxProvider.notifier).upsert(item);
  }

  Future<void> _open() async {
    try {
      _set(await ref.read(requestsRepositoryProvider).open(widget.requestId));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<bool> _respond(String action, {int? price, String? availability, String? delay, String? message}) async {
    setState(() => _busy = true);
    try {
      _set(await ref.read(requestsRepositoryProvider).respond(
            widget.requestId,
            action: action,
            price: price,
            availability: availability,
            delay: delay,
            message: message,
          ));
      if (!mounted) return true;
      switch (action) {
        case 'INTERESTED':
          showToast(context, 'Proposition envoyée. Le client compare et choisit.');
        case 'QUESTION':
          showToast(context, 'Question envoyée au client.');
        default:
          showToast(context, "C'est noté.");
          context.pop();
      }
      return true;
    } catch (e) {
      if (mounted) showToast(context, e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final theme = Theme.of(context);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Demande reçue')),
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final r = item.request;
    final canAnswer = item.status.isOpen && (r.status == RequestStatus.sent || r.status == RequestStatus.responded);
    final canWrite = item.status.canTalk && !r.status.isClosed;

    return Scaffold(
      appBar: AppBar(title: const Text('Demande reçue')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(r.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          if (item.matchedService != null) ...[
            const Gap(8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusTag('Correspond à ton service « ${item.matchedService} »', tone: SbcColors.primary),
            ),
          ],
          const Gap(14),
          Text('« ${r.rawText} »', style: theme.textTheme.bodyLarge),
          const Gap(14),
          RequestPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                FactRow('Lieu', r.place.isEmpty ? 'Non précisé' : r.place),
                const Divider(height: 1),
                FactRow('Prestation', r.mode?.label ?? 'Indifférent'),
                const Divider(height: 1),
                FactRow('Date', [r.desiredDate, r.desiredTime].whereType<String>().join(' à ').isEmpty
                    ? 'Flexible'
                    : [r.desiredDate, r.desiredTime].whereType<String>().join(' à ')),
                const Divider(height: 1),
                FactRow('Budget', r.budget != null ? '${fcfa(r.budget!)} max' : 'Non précisé'),
                if (r.constraints.isNotEmpty) ...[
                  const Divider(height: 1),
                  FactRow('Conditions', r.constraints.join(', ')),
                ],
              ],
            ),
          ),
          const Gap(12),
          const PrivacyNote("Les coordonnées du client s'affichent quand il choisit de te contacter."),
          if (item.messages.isNotEmpty) ...[
            const Gap(16),
            const RequestSectionLabel('Conversation'),
            const Gap(8),
            RequestPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConversationThread(messages: item.messages, meIsPro: true, otherName: 'Le client'),
                  if (canWrite)
                    OutlinedButton.icon(
                      onPressed: () => showMessageComposer(
                        context,
                        title: 'Écrire au client',
                        onSend: (text) async {
                          try {
                            _set(await ref.read(requestsRepositoryProvider).proSendMessage(widget.requestId, text));
                            return true;
                          } catch (e) {
                            if (mounted) showToast(context, e.toString());
                            return false;
                          }
                        },
                      ),
                      icon: const Icon(Icons.reply_rounded),
                      label: const Text('Écrire au client'),
                    ),
                ],
              ),
            ),
          ],
          const Gap(16),
          _ProTimeline(item: item),
          if (!item.status.isOpen) ...[
            const Gap(16),
            RequestPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusTag(item.status.label, tone: toneForDispatch(item.status)),
                  if (item.price != null) FactRow('Prix proposé', fcfa(item.price!)),
                  if (item.availability != null) FactRow('Disponibilité', item.availability!),
                  if (item.delay != null) FactRow('Durée', item.delay!),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: canAnswer
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _busy ? null : () => _proposal(r),
                      child: const Text('Je suis intéressé'),
                    ),
                    const Gap(8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => showMessageComposer(
                                context,
                                title: 'Poser une question',
                                placeholder: 'Ex. Les locks sont-elles longues ?',
                                hint: 'Le client la voit avec ta réponse.',
                                onSend: (text) => _respond('QUESTION', message: text),
                              ),
                      child: const Text('Poser une question'),
                    ),
                    const Gap(8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _respond('UNAVAILABLE'),
                            child: const Text('Pas disponible'),
                          ),
                        ),
                        const Gap(10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : () => _respond('DECLINED'),
                            child: const Text('Je ne peux pas'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  /// "Ta proposition" — price, slot, duration, message (Data §10).
  Future<void> _proposal(ServiceRequestItem r) async {
    final price = TextEditingController();
    final availability = TextEditingController();
    final delay = TextEditingController();
    final message = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ta proposition',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Gap(12),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Prix proposé (FCFA)',
                    helperText: r.budget != null ? 'Budget du client : ${fcfa(r.budget!)} max' : null,
                  ),
                ),
                const Gap(10),
                TextField(
                  controller: availability,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Disponibilité', hintText: 'Ex. samedi 14h'),
                ),
                const Gap(10),
                TextField(controller: delay, decoration: const InputDecoration(labelText: 'Durée (facultatif)')),
                const Gap(10),
                TextField(
                  controller: message,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Message (facultatif)'),
                ),
                const Gap(16),
                FilledButton(
                  onPressed: availability.text.trim().isEmpty
                      ? null
                      : () async {
                          final ok = await _respond(
                            'INTERESTED',
                            price: int.tryParse(price.text.replaceAll(RegExp(r'\D'), '')),
                            availability: availability.text.trim(),
                            delay: delay.text.trim().isEmpty ? null : delay.text.trim(),
                            message: message.text.trim().isEmpty ? null : message.text.trim(),
                          );
                          if (ok && sheet.mounted) Navigator.of(sheet).pop();
                        },
                  child: const Text('Envoyer ma proposition'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Received, seen, answered, and how it ended (Data §18).
class _ProTimeline extends StatelessWidget {
  const _ProTimeline({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = Colors.grey.shade600;
    final outcome = switch (item.status) {
      DispatchStatus.selected when item.request.status == RequestStatus.completed =>
        ('Prestation terminée', true, SbcColors.success),
      DispatchStatus.selected => ('Tu as été retenu', true, SbcColors.success),
      DispatchStatus.lost => (
          item.request.status == RequestStatus.cancelled ? 'Demande annulée' : 'Un autre professionnel a été retenu',
          true,
          grey
        ),
      DispatchStatus.unavailable || DispatchStatus.declined => ('Tu as décliné', true, grey),
      _ => ('En attente du choix du client', false, SbcColors.primary),
    };
    final steps = [
      ('Demande reçue', item.createdAt as DateTime?, true, SbcColors.primary),
      ('Vue', item.viewedAt, item.viewedAt != null, SbcColors.primary),
      (item.status == DispatchStatus.question ? 'Question posée' : 'Ta réponse', item.respondedAt, item.respondedAt != null,
          SbcColors.primary),
      (outcome.$1, null, outcome.$2, outcome.$3),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RequestSectionLabel('Suivi'),
        const Gap(8),
        RequestPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: steps[i].$3 ? steps[i].$4 : theme.colorScheme.surface,
                              border: Border.all(color: steps[i].$3 ? steps[i].$4 : theme.colorScheme.outlineVariant, width: 2),
                            ),
                          ),
                          if (i < steps.length - 1)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: steps[i + 1].$3
                                    ? SbcColors.primary.withValues(alpha: 0.4)
                                    : theme.colorScheme.outlineVariant,
                              ),
                            ),
                        ],
                      ),
                      const Gap(12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                steps[i].$1,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: steps[i].$3 ? FontWeight.w700 : FontWeight.w500,
                                  color: steps[i].$3 ? null : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (steps[i].$2 != null)
                                Text(formatWhen(steps[i].$2!),
                                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/requests/application/requests_controllers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';
import 'package:sbc_contacts/shared/services/whatsapp.dart';
import 'package:sbc_contacts/shared/widgets/confidence_score_badge.dart';
import 'package:sbc_contacts/shared/widgets/member_avatar.dart';
import 'package:sbc_contacts/shared/widgets/star_rating.dart';
import 'package:url_launcher/url_launcher.dart';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// One of the member's requests: where it stands, the answers as comparable
/// cards, the conversations, choosing a pro, and closing it (Data §11–§16, §19).
class RequestDetailScreen extends ConsumerStatefulWidget {
  const RequestDetailScreen({required this.requestId, super.key});
  final String requestId;

  @override
  ConsumerState<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  ServiceRequestItem? _request;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _set(ServiceRequestItem r) {
    setState(() => _request = r);
    ref.read(myRequestsProvider.notifier).upsert(r);
    // Matching runs on the server for a few seconds; follow it.
    _poll?.cancel();
    if (r.status == RequestStatus.matching) {
      _poll = Timer(const Duration(seconds: 2), _load);
    }
  }

  Future<void> _load() async {
    try {
      _set(await ref.read(requestsRepositoryProvider).get(widget.requestId));
    } catch (e) {
      if (_request == null) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<ServiceRequestItem> Function() call, {String? toast}) async {
    setState(() => _busy = true);
    try {
      _set(await call());
      if (toast != null && mounted) showToast(context, toast);
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(RequestResponse response) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Retenir ce professionnel ?'),
        content: Text('${response.displayName} recevra une notification. Les autres verront que la demande est pourvue.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Retenir')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(requestsRepositoryProvider).select(widget.requestId, response.id),
      toast: 'Choix enregistré. Écris à ${response.displayName} sur WhatsApp pour caler les détails.',
    );
  }

  Future<void> _write(RequestResponse response) => showMessageComposer(
        context,
        title: response.status == DispatchStatus.question ? 'Répondre' : 'Écrire à ${response.displayName}',
        hint: "Reste dans l'application pour les détails ; tes coordonnées ne sont pas partagées.",
        onSend: (text) async {
          try {
            _set(await ref.read(requestsRepositoryProvider).sendMessage(widget.requestId, response.id, text));
            return true;
          } catch (e) {
            if (mounted) showToast(context, e.toString());
            return false;
          }
        },
      );

  Future<void> _relaunch() async {
    setState(() => _busy = true);
    try {
      final draft = await ref.read(requestsRepositoryProvider).reopen(widget.requestId);
      ref.read(myRequestsProvider.notifier).upsert(draft);
      if (mounted) context.push('/requests/review', extra: draft);
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Non')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Annuler la demande'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => ref.read(requestsRepositoryProvider).cancel(widget.requestId));
  }

  @override
  Widget build(BuildContext context) {
    final r = _request;
    final theme = Theme.of(context);
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Demande')),
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final answers = r.responses
        .where((x) => x.status != DispatchStatus.unavailable && x.status != DispatchStatus.declined)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demande'),
        actions: [
          if (r.canDelete)
            IconButton(
              tooltip: 'Supprimer la demande',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDeleteRequest(context, ref, r) && context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(r.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Gap(4),
            Text(
              [if (r.subtitle.isNotEmpty) r.subtitle, if (r.budget != null) '${fcfa(r.budget!)} max'].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Gap(16),
            _StatusTimeline(status: r.status),
            const Gap(16),
            if (r.status == RequestStatus.matching)
              const _InfoCard(icon: Icons.manage_search_rounded, text: 'On cherche les professionnels qui correspondent…', busy: true)
            else if (r.status == RequestStatus.sent && answers.isEmpty)
              _InfoCard(
                icon: Icons.send_rounded,
                text:
                    'Transmise à ${r.dispatchedCount} professionnel${r.dispatchedCount > 1 ? 's' : ''}. Leurs réponses apparaîtront ici.',
              )
            else if (r.status == RequestStatus.noMatch)
              const _InfoCard(
                icon: Icons.person_search_outlined,
                text: 'Aucun professionnel ne correspond encore à cette demande. Essaie de la formuler autrement ou élargis le lieu.',
              )
            else if (r.status == RequestStatus.noResponse)
              const _InfoCard(icon: Icons.hourglass_empty_rounded, text: "Aucun professionnel n'a répondu à temps.")
            else if (r.status == RequestStatus.cancelled)
              const _InfoCard(icon: Icons.cancel_outlined, text: 'Tu as annulé cette demande.'),
            if (answers.isNotEmpty) ...[
              const Gap(8),
              Row(
                children: [
                  Expanded(
                    child: Text('${answers.length} réponse${answers.length > 1 ? 's' : ''}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (r.status.isChoosing)
                    Text('Compare et choisis',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const Gap(10),
              for (final a in answers)
                _ResponseCard(
                  response: a,
                  request: r,
                  canChoose: r.status.isChoosing && !_busy,
                  onChoose: () => _choose(a),
                  onWrite: () => _write(a),
                ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: switch (r.status) {
            RequestStatus.selected => FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  final updated = await showModalBottomSheet<ServiceRequestItem>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _CompleteSheet(request: r),
                  );
                  if (updated != null) _set(updated);
                },
                child: const Text('Prestation terminée ?'),
              ),
            _ when r.status.isClosed => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _relaunch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Relancer cette demande'),
              ),
            RequestStatus.sent || RequestStatus.responded || RequestStatus.locked || RequestStatus.matching =>
              TextButton(
                onPressed: _cancel,
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                child: const Text('Annuler la demande'),
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

/// Envoyée → Réponses → Retenu → Terminée.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final RequestStatus status;

  int get _reached => switch (status) {
        RequestStatus.draft || RequestStatus.matching => 0,
        RequestStatus.responded || RequestStatus.locked => 2,
        RequestStatus.selected => 3,
        RequestStatus.completed => 4,
        _ => 1,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = ['Envoyée', 'Réponses', 'Retenu', 'Terminée'];
    return Semantics(
      label: 'Statut : ${status.label}',
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 0 ? Colors.transparent : (i < _reached ? SbcColors.primary : theme.colorScheme.outlineVariant),
                        ),
                      ),
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _reached ? SbcColors.primary : theme.colorScheme.surface,
                          border: Border.all(
                            color: i < _reached ? SbcColors.primary : theme.colorScheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == steps.length - 1
                              ? Colors.transparent
                              : (i + 1 < _reached ? SbcColors.primary : theme.colorScheme.outlineVariant),
                        ),
                      ),
                    ],
                  ),
                  const Gap(6),
                  Text(
                    steps[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: i < _reached ? FontWeight.w800 : FontWeight.w500,
                      color: i < _reached ? null : theme.colorScheme.onSurfaceVariant,
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text, this.busy = false});
  final IconData icon;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) => RequestPanel(
        child: Row(
          children: [
            busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, color: SbcColors.primary),
            const Gap(12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      );
}

/// One pro's answer: who, for what, at what price and when — plus the
/// conversation, WhatsApp, their SBC Shop and "Retenir" (Data §11, §13, §14).
class _ResponseCard extends StatelessWidget {
  const _ResponseCard({
    required this.response,
    required this.request,
    required this.canChoose,
    required this.onChoose,
    required this.onWrite,
  });

  final RequestResponse response;
  final ServiceRequestItem request;
  final bool canChoose;
  final VoidCallback onChoose;
  final VoidCallback onWrite;

  bool get _canWrite => response.status.canTalk && !request.status.isClosed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = response;
    Widget fact(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(value, maxLines: 2, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RequestPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(initials: _initials(a.displayName), avatarUrl: a.avatarUrl, radius: 26, rounded: true),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.displayName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const Gap(4),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [Chip(label: Text(a.profession), visualDensity: VisualDensity.compact), ConfidenceScorePill(score: a.confidenceScore)],
                      ),
                    ],
                  ),
                ),
                if (a.status == DispatchStatus.selected) const StatusTag('Retenu', tone: SbcColors.success),
                if (a.status == DispatchStatus.lost) StatusTag('Non retenu', tone: Colors.grey.shade600),
                if (a.status == DispatchStatus.question) const StatusTag('Question', tone: SbcColors.accentDark),
              ],
            ),
            if (a.serviceName != null) ...[
              const Gap(10),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Service : ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                TextSpan(text: a.serviceName, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]), style: theme.textTheme.bodySmall),
            ],
            if (a.price != null || a.availability != null || a.delay != null) ...[
              const Gap(10),
              Row(children: [
                fact('Prix', a.price != null ? fcfa(a.price!) : 'Sur devis'),
                const Gap(8),
                fact('Dispo', a.availability ?? '—'),
                const Gap(8),
                fact('Durée', a.delay ?? '—'),
              ]),
            ],
            const Gap(10),
            if (a.messages.isNotEmpty) ...[
              ConversationThread(messages: a.messages, meIsPro: false, otherName: a.displayName),
              if (_canWrite)
                OutlinedButton.icon(
                  onPressed: onWrite,
                  icon: const Icon(Icons.reply_rounded),
                  label: Text(a.messages.last.fromPro ? 'Répondre' : 'Écrire'),
                ),
            ] else ...[
              if ((a.message ?? '').isNotEmpty) Text('« ${a.message} »', style: theme.textTheme.bodyMedium),
              if (_canWrite)
                TextButton(onPressed: onWrite, child: Text('Poser une question à ${a.displayName}')),
            ],
            const Gap(10),
            Row(
              children: [
                IconButton.filled(
                  tooltip: 'Contacter sur WhatsApp',
                  style: IconButton.styleFrom(backgroundColor: SbcColors.whatsapp, fixedSize: const Size(46, 46)),
                  onPressed: a.whatsapp == null
                      ? null
                      : () => openWhatsApp(
                            a.whatsapp!,
                            presetText:
                                'Bonjour, je vous contacte via SBC Network concernant ma demande de ${request.service ?? 'service'}.',
                          ),
                  icon: const Icon(Icons.chat_rounded, color: Colors.white),
                ),
                const Gap(8),
                if (a.shopUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(a.shopUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Boutique'),
                  ),
                const Spacer(),
                if (canChoose && (a.status == DispatchStatus.interested || a.status == DispatchStatus.question))
                  FilledButton(onPressed: onChoose, child: const Text('Retenir')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Comment ça s'est passé ?" — done or not, stars, comment, or a report (Data §15).
class _CompleteSheet extends ConsumerStatefulWidget {
  const _CompleteSheet({required this.request});
  final ServiceRequestItem request;

  @override
  ConsumerState<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends ConsumerState<_CompleteSheet> {
  bool _performed = true;
  int _stars = 0;
  final _comment = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final updated = await ref.read(requestsRepositoryProvider).complete(
            widget.request.id,
            performed: _performed,
            stars: _performed ? _stars : null,
            comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) showToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSubmit = !_saving && (_performed ? _stars > 0 : _comment.text.trim().isNotEmpty);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Fin de prestation', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Gap(16),
            Text('La prestation a-t-elle été réalisée ?', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Gap(8),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Oui')), ButtonSegment(value: false, label: Text('Non'))],
              selected: {_performed},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _performed = s.first),
            ),
            if (_performed) ...[
              const Gap(16),
              Center(child: Text('Ta note', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              Center(child: StarRatingInput(value: _stars, onChanged: (v) => setState(() => _stars = v))),
            ],
            const Gap(12),
            TextField(
              controller: _comment,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _performed ? 'Commentaire (facultatif)' : "Que s'est-il passé ?",
              ),
            ),
            if (!_performed) ...[
              const Gap(8),
              const PrivacyNote("Ton signalement est transmis à l'équipe SBC, pas au professionnel."),
            ],
            const Gap(16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: _performed ? null : theme.colorScheme.error,
              ),
              onPressed: canSubmit ? _submit : null,
              child: Text(_performed ? 'Terminer et publier mon avis' : 'Signaler un problème'),
            ),
          ],
        ),
      ),
    );
  }
}

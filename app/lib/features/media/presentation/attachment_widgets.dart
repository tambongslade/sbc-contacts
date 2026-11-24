import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:sbc_contacts/core/theme/sbc_colors.dart';
import 'package:sbc_contacts/features/media/data/media_repository.dart';
import 'package:sbc_contacts/features/media/domain/attachment.dart';
import 'package:sbc_contacts/features/media/presentation/attachment_draft.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

// ── Composing ────────────────────────────────────────────────────────────────

/// "📎 Joindre": opens Caméra / Galerie / PDF for [draft].
class AttachButton extends StatelessWidget {
  const AttachButton({required this.draft, this.label = 'Joindre', super.key});
  final AttachmentDraft draft;
  final String label;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: draft,
        builder: (context, _) => TextButton.icon(
          onPressed: draft.isFull ? null : () => draft.pick(context),
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(draft.isEmpty ? label : '$label (${draft.items.length}/$maxAttachments)'),
        ),
      );
}

/// The picked files, each with its upload progress and a cross to remove it.
class AttachmentDraftStrip extends StatelessWidget {
  const AttachmentDraftStrip({required this.draft, super.key});
  final AttachmentDraft draft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: draft,
        builder: (context, _) {
          if (draft.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8, right: 8),
              itemCount: draft.items.length,
              separatorBuilder: (_, _) => const Gap(10),
              itemBuilder: (context, i) => _DraftTile(draft: draft, item: draft.items[i]),
            ),
          );
        },
      );
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, required this.item});
  final AttachmentDraft draft;
  final PendingAttachment item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = switch (item.kind) {
      AttachmentKind.image when item.path != null => Image.file(File(item.path!), fit: BoxFit.cover, cacheWidth: 200),
      AttachmentKind.video => _VideoPlaceholder(durationSec: item.durationSec),
      _ => _FilePlaceholder(name: item.name),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          label: item.error != null ? 'Échec de l’envoi, touche pour réessayer' : item.name,
          child: GestureDetector(
            onTap: item.error != null ? () => draft.retry(item) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    preview,
                    if (item.uploading)
                      ColoredBox(
                        color: Colors.black38,
                        child: Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              value: item.progress > 0 && item.progress < 1 ? item.progress : null,
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (item.error != null)
                      ColoredBox(
                        color: theme.colorScheme.error.withValues(alpha: 0.75),
                        child: const Icon(Icons.refresh_rounded, color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: Material(
            color: theme.colorScheme.inverseSurface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => draft.remove(item),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.onInverseSurface),
                ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The error to show for a draft that is not ready, or null when it is.
String? draftProblem(AttachmentDraft draft) {
  if (draft.uploading) return 'Patiente, les fichiers sont en cours d’envoi…';
  if (draft.hasErrors) return 'Un fichier n’a pas pu être envoyé : réessaie ou retire-le.';
  return null;
}

// ── Showing ──────────────────────────────────────────────────────────────────

/// Photos and videos as tiles, PDFs as rows. Tap opens, long-press offers "Signaler".
class AttachmentGallery extends StatelessWidget {
  const AttachmentGallery({
    required this.attachments,
    this.tileSize = 88,
    this.onDark = false,
    this.alignEnd = false,
    super.key,
  });
  final List<Attachment> attachments;
  final double tileSize;

  /// My own message: tiles hug the right edge, like the bubble.
  final bool alignEnd;

  /// Inside a coloured bubble: files read in white.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final media = attachments.where((a) => a.isImage || a.isVideo).toList();
    final files = attachments.where((a) => !a.isImage && !a.isVideo).toList();
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (media.isNotEmpty)
          Wrap(
            alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < media.length; i++)
                _MediaTile(
                  attachment: media[i],
                  size: tileSize,
                  onTap: () => openMediaViewer(context, media, i),
                ),
            ],
          ),
        if (media.isNotEmpty && files.isNotEmpty) const Gap(6),
        for (final f in files) _FileRow(attachment: f, onDark: onDark),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.attachment, required this.size, required this.onTap});
  final Attachment attachment;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return Semantics(
      button: true,
      label: a.isVideo ? 'Vidéo${a.durationSec != null ? ', ${formatDuration(a.durationSec!)}' : ''}' : 'Photo',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => confirmReport(context, a),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: a.isImage
                ? CachedNetworkImage(
                    imageUrl: a.absoluteUrl.toString(),
                    cacheKey: 'media-${a.id}',
                    fit: BoxFit.cover,
                    memCacheWidth: (size * 3).round(),
                    placeholder: (_, _) => ColoredBox(color: Colors.grey.shade200),
                    errorWidget: (_, _, _) => ColoredBox(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  )
                : _VideoPlaceholder(durationSec: a.durationSec),
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment, required this.onDark});
  final Attachment attachment;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = onDark ? Colors.white : theme.colorScheme.onSurface;
    final muted = onDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: onDark ? Colors.white.withValues(alpha: 0.15) : theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openExternally(context, attachment),
          onLongPress: () => confirmReport(context, attachment),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf_rounded, color: onDark ? Colors.white : SbcColors.error),
                const Gap(8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: fg),
                      ),
                      Text('PDF · ${formatBytes(attachment.size)}',
                          style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({this.durationSec});
  final double? durationSec;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF1B1F2A),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34)),
            if (durationSec != null)
              Positioned(
                right: 6,
                bottom: 4,
                child: Text(
                  formatDuration(durationSec!),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      );
}

class _FilePlaceholder extends StatelessWidget {
  const _FilePlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.grey.shade200,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: SbcColors.error),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
}

/// A PDF (or anything the app does not show itself) in the phone's own viewer.
Future<void> openExternally(BuildContext context, Attachment a) async {
  final ok = await launchUrl(a.absoluteUrl, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) _toast(context, 'Impossible d’ouvrir ce fichier.');
}

/// "Signaler": asks why (optional), then tells the team.
Future<void> confirmReport(BuildContext context, Attachment a) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Signaler ce contenu ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Notre équipe va le vérifier. Les contenus choquants, frauduleux ou hors sujet sont retirés.'),
          const Gap(12),
          TextField(
            controller: reason,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Pourquoi ? (facultatif)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.of(c).pop(true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
          child: const Text('Signaler'),
        ),
      ],
    ),
  );
  final why = reason.text.trim();
  reason.dispose();
  if (ok != true || !context.mounted) return;
  try {
    await ProviderScope.containerOf(context).read(mediaRepositoryProvider).report(a.id, reason: why);
    if (context.mounted) _toast(context, 'Merci, c’est signalé. Notre équipe va vérifier.');
  } catch (e) {
    if (context.mounted) _toast(context, e.toString());
  }
}

void openMediaViewer(BuildContext context, List<Attachment> media, int index) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => MediaViewerScreen(items: media, initialIndex: index),
  ));
}

/// Full screen: zoom into a photo, play a video, swipe between them.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({required this.items, this.initialIndex = 0, super.key});
  final List<Attachment> items;
  final int initialIndex;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: widget.items.length > 1 ? Text('${_index + 1} / ${widget.items.length}') : null,
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans une autre application',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => openExternally(context, current),
          ),
          IconButton(
            tooltip: 'Signaler',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => confirmReport(context, current),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final a = widget.items[i];
          return a.isVideo
              ? _VideoPage(attachment: a, active: i == _index)
              : InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: a.absoluteUrl.toString(),
                      cacheKey: 'media-${a.id}',
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                      errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                    ),
                  ),
                );
        },
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({required this.attachment, required this.active});
  final Attachment attachment;
  final bool active;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(widget.attachment.absoluteUrl);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _c.initialize();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() {});
    if (widget.active) await _c.play();
  }

  @override
  void didUpdateWidget(_VideoPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && _c.value.isPlaying) unawaited(_c.pause());
  }

  @override
  void dispose() {
    unawaited(_c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text('Impossible de lire cette vidéo.', style: TextStyle(color: Colors.white70)),
      );
    }
    if (!_c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () => unawaited(_c.value.isPlaying ? _c.pause() : _c.play()),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))),
          ValueListenableBuilder(
            valueListenable: _c,
            builder: (context, v, _) => Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (!v.isPlaying)
                  const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 72)),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Text(formatDuration(v.position.inMilliseconds / 1000),
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                        const Gap(10),
                        Expanded(
                          child: VideoProgressIndicator(
                            _c,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(playedColor: SbcColors.primary),
                          ),
                        ),
                        const Gap(10),
                        Text(formatDuration(v.duration.inMilliseconds / 1000),
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
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

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

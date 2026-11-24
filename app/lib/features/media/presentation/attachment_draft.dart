import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sbc_contacts/features/media/data/media_repository.dart';
import 'package:sbc_contacts/features/media/domain/attachment.dart';
import 'package:video_player/video_player.dart';

/// Attachments one request, proposal or message may carry (server limit).
const int maxAttachments = 5;
const int _maxImageBytes = 10 * 1024 * 1024;
const int _maxVideoBytes = 50 * 1024 * 1024;
const int _maxPdfBytes = 20 * 1024 * 1024;
const int _maxVideoSeconds = 60;

/// One picked file, uploading or uploaded.
class PendingAttachment {
  PendingAttachment({required this.kind, required this.name, this.path, this.bytes, this.durationSec});

  final AttachmentKind kind;
  final String name;
  final String? path;
  final Uint8List? bytes;
  final double? durationSec;
  int? width;
  int? height;
  double progress = 0;
  Attachment? uploaded;
  String? error;
  CancelToken? cancel;

  bool get uploading => uploaded == null && error == null;
}

/// What the member is about to send: picked files, each uploaded as soon as
/// it is picked so that sending is instant. Owned by one composer; dispose it
/// with the composer.
class AttachmentDraft extends ChangeNotifier {
  AttachmentDraft(this._repo, {ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final MediaRepository _repo;
  final ImagePicker _picker;
  final List<PendingAttachment> _items = [];
  bool _disposed = false;

  List<PendingAttachment> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isFull => _items.length >= maxAttachments;
  int get remaining => maxAttachments - _items.length;

  /// Some file is still on its way: sending must wait.
  bool get uploading => _items.any((i) => i.uploading);

  /// A failed upload: remove it (or retry) before sending.
  bool get hasErrors => _items.any((i) => i.error != null);

  /// Ready to go with the message.
  List<String> get ids => [for (final i in _items) if (i.uploaded != null) i.uploaded!.id];

  bool get ready => !uploading && !hasErrors;

  /// "Caméra / Galerie / Fichier PDF", then upload what was picked.
  Future<void> pick(BuildContext context) async {
    if (isFull) {
      _toast(context, '$maxAttachments pièces jointes maximum.');
      return;
    }
    final choice = await showModalBottomSheet<_Source>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(c).pop(_Source.cameraPhoto),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Filmer une vidéo'),
              subtitle: const Text('60 secondes maximum'),
              onTap: () => Navigator.of(c).pop(_Source.cameraVideo),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie (photo ou vidéo)'),
              onTap: () => Navigator.of(c).pop(_Source.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Fichier PDF'),
              subtitle: const Text('Un devis, une facture…'),
              onTap: () => Navigator.of(c).pop(_Source.pdf),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      switch (choice) {
        case _Source.cameraPhoto:
          final x = await _picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 80,
            maxWidth: 2048,
            maxHeight: 2048,
          );
          if (x != null && context.mounted) await _addMedia(context, x);
        case _Source.cameraVideo:
          final x = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: _maxVideoSeconds),
          );
          if (x != null && context.mounted) await _addMedia(context, x, video: true);
        case _Source.gallery:
          final picked = remaining >= 2
              ? await _picker.pickMultipleMedia(imageQuality: 80, maxWidth: 2048, maxHeight: 2048, limit: remaining)
              : [?await _picker.pickMedia(imageQuality: 80, maxWidth: 2048, maxHeight: 2048)];
          for (final x in picked.take(remaining)) {
            if (!context.mounted) return;
            await _addMedia(context, x);
          }
        case _Source.pdf:
          final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
          if (f != null && context.mounted) await _addPdf(context, f);
      }
    } on PlatformException catch (e) {
      if (context.mounted) _toast(context, _permissionMessage(e));
    }
  }

  Future<void> _addMedia(BuildContext context, XFile x, {bool video = false}) async {
    final isVideo = video || _looksLikeVideo(x);
    final size = await x.length();
    if (isVideo) {
      if (size > _maxVideoBytes) {
        if (context.mounted) _toast(context, 'Cette vidéo dépasse 50 Mo. Choisis-en une plus courte.');
        return;
      }
      final info = await _videoInfo(x.path);
      if (info != null && info.seconds > _maxVideoSeconds + 0.5) {
        if (context.mounted) {
          _toast(context, 'Cette vidéo dure plus de 60 secondes. Coupe-la avant de l’envoyer.');
        }
        return;
      }
      _start(
        PendingAttachment(kind: AttachmentKind.video, name: x.name, path: x.path, durationSec: info?.seconds)
          ..width = info?.width
          ..height = info?.height,
      );
      return;
    }
    if (size > _maxImageBytes) {
      if (context.mounted) _toast(context, 'Cette photo dépasse 10 Mo.');
      return;
    }
    final item = PendingAttachment(kind: AttachmentKind.image, name: x.name, path: x.path);
    final dims = await _imageSize(x);
    item
      ..width = dims?.$1
      ..height = dims?.$2;
    _start(item);
  }

  Future<void> _addPdf(BuildContext context, PlatformFile f) async {
    final size = f.lengthSync() ?? await f.length() ?? 0;
    if (size > _maxPdfBytes) {
      if (context.mounted) _toast(context, 'Ce PDF dépasse 20 Mo.');
      return;
    }
    final path = f.path;
    _start(PendingAttachment(
      kind: AttachmentKind.file,
      name: f.name,
      path: path,
      bytes: path == null ? await f.readAsBytes() : null,
    ));
  }

  void _start(PendingAttachment item) {
    if (_disposed || isFull) return;
    _items.add(item);
    _notify();
    unawaited(_upload(item));
  }

  Future<void> _upload(PendingAttachment item) async {
    item
      ..error = null
      ..progress = 0
      ..cancel = CancelToken();
    _notify();
    try {
      item.uploaded = await _repo.upload(
        fileName: item.name,
        path: item.path,
        bytes: item.bytes,
        width: item.width,
        height: item.height,
        durationSec: item.durationSec,
        cancelToken: item.cancel,
        onProgress: (p) {
          item.progress = p;
          _notify();
        },
      );
    } catch (e) {
      if (item.cancel?.isCancelled ?? false) return;
      item.error = e.toString();
    }
    _notify();
  }

  /// Tries a failed upload again.
  void retry(PendingAttachment item) {
    if (item.error != null) unawaited(_upload(item));
  }

  void remove(PendingAttachment item) {
    item.cancel?.cancel();
    _items.remove(item);
    _notify();
  }

  void clear() {
    for (final i in _items) {
      i.cancel?.cancel();
    }
    _items.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _items) {
      if (i.uploading) i.cancel?.cancel();
    }
    super.dispose();
  }
}

enum _Source { cameraPhoto, cameraVideo, gallery, pdf }

bool _looksLikeVideo(XFile x) {
  final mime = x.mimeType ?? '';
  if (mime.startsWith('video/')) return true;
  if (mime.startsWith('image/')) return false;
  final name = x.name.toLowerCase();
  return const ['.mp4', '.mov', '.m4v', '.3gp', '.webm', '.mkv'].any(name.endsWith);
}

Future<({double seconds, int? width, int? height})?> _videoInfo(String path) async {
  final c = VideoPlayerController.file(File(path));
  try {
    await c.initialize();
    final v = c.value;
    return (
      seconds: v.duration.inMilliseconds / 1000,
      width: v.size.width > 0 ? v.size.width.round() : null,
      height: v.size.height > 0 ? v.size.height.round() : null,
    );
  } catch (_) {
    return null; // The server still refuses what it cannot take.
  } finally {
    unawaited(c.dispose());
  }
}

/// Width and height without decoding the whole picture.
Future<(int, int)?> _imageSize(XFile x) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await x.readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

String _permissionMessage(PlatformException e) {
  final code = e.code.toLowerCase();
  if (code.contains('camera')) return 'Autorise l’appareil photo dans les réglages pour prendre une photo.';
  if (code.contains('photo') || code.contains('access')) {
    return 'Autorise l’accès aux photos dans les réglages.';
  }
  return 'Impossible d’ouvrir ce fichier.';
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

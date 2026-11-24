import 'package:sbc_contacts/core/config/app_config.dart';

enum AttachmentKind {
  image,
  video,
  file;

  static AttachmentKind fromWire(Object? v) => switch ('$v'.toUpperCase()) {
        'IMAGE' => AttachmentKind.image,
        'VIDEO' => AttachmentKind.video,
        _ => AttachmentKind.file,
      };
}

/// A photo, a video or a PDF sent with a request, a proposal or a message
/// (backend `AttachmentView`).
class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.size,
    required this.url,
    this.fileName,
    this.width,
    this.height,
    this.durationSec,
  });

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: '${j['id'] ?? ''}',
        kind: AttachmentKind.fromWire(j['kind']),
        mimeType: '${j['mimeType'] ?? ''}',
        size: (j['size'] as num?)?.toInt() ?? 0,
        url: '${j['url'] ?? ''}',
        fileName: j['fileName'] as String?,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        durationSec: (j['durationSec'] as num?)?.toDouble(),
      );

  /// Parses a list from the API, skipping anything that is not an object.
  static List<Attachment> listFrom(Object? v) =>
      (v as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map(Attachment.fromJson).toList();

  final String id;
  final AttachmentKind kind;
  final String mimeType;
  final int size;

  /// Signed path below the API host (`/api/v1/media/<id>?exp=…&sig=…`).
  final String url;
  final String? fileName;
  final int? width;
  final int? height;
  final double? durationSec;

  /// The link to open or stream: no auth header needed, the signature is the permission.
  Uri get absoluteUrl => resolveMediaUrl(url);

  bool get isImage => kind == AttachmentKind.image;
  bool get isVideo => kind == AttachmentKind.video;

  String get displayName => (fileName ?? '').isNotEmpty ? fileName! : (isVideo ? 'Vidéo' : isImage ? 'Photo' : 'Document');

  /// Width over height, when known and sane.
  double? get aspectRatio =>
      width != null && height != null && width! > 0 && height! > 0 ? width! / height! : null;
}

/// Resolves a signed media path against the API's origin. An absolute URL is
/// returned as is.
Uri resolveMediaUrl(String url, {String apiBase = AppConfig.apiBaseUrl}) => Uri.parse(apiBase).resolve(url);

/// "2,4 Mo", "830 Ko".
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
  return '${(bytes / 1024).ceil()} Ko';
}

/// "0:42", "1:05".
String formatDuration(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

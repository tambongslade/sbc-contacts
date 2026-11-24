import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/media/domain/attachment.dart';

/// `/media`: upload a file before sending it, and "Signaler".
class MediaRepository {
  MediaRepository(this._api);
  final ApiClient _api;

  /// Uploads one file; its id then goes in `attachmentIds` of what it is sent with.
  /// Either [path] (a local file) or [bytes] must be given.
  Future<Attachment> upload({
    required String fileName,
    String? path,
    List<int>? bytes,
    int? width,
    int? height,
    double? durationSec,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    assert(path != null || bytes != null, 'path or bytes');
    final data = await _api.upload(
      '/media',
      buildForm: () => FormData.fromMap({
        'file': path != null
            ? MultipartFile.fromFileSync(path, filename: fileName)
            : MultipartFile.fromBytes(bytes!, filename: fileName),
        'fileName': fileName,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationSec != null) 'durationSec': durationSec,
      }),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return Attachment.fromJson(data as Map<String, dynamic>);
  }

  Future<void> report(String id, {String? reason}) =>
      _api.post('/media/$id/report', body: {if (reason != null && reason.isNotEmpty) 'reason': reason});
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) => MediaRepository(ref.watch(apiClientProvider)));

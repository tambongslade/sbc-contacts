import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sbc_contacts/core/config/app_config.dart';
import 'package:sbc_contacts/core/network/api_exception.dart';
import 'package:sbc_contacts/core/storage/token_storage.dart';

/// Thin wrapper over Dio that talks to the SBC Contacts backend.
///
/// Responsibilities:
/// - attach the app access token to every non-auth request,
/// - unwrap the backend's `{ success, data }` envelope,
/// - convert failures into [ApiException] (never leak DioException),
/// - transparently refresh the token on 401 (single-flight) and retry once.
class ApiClient {
  ApiClient({required TokenStorage storage, Dio? dio, String? baseUrl})
      : _storage = storage,
        _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl ?? AppConfig.apiBaseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers['Content-Type'] = 'application/json'
      ..validateStatus = (s) => s != null && s < 500;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!_isAuthPath(options.path)) {
            final access = await _storage.readAccess();
            if (access != null) {
              options.headers['Authorization'] = 'Bearer $access';
            }
          }
          handler.next(options);
        },
      ),
    );

    // Bare Dio for refresh calls (no interceptors → no recursion).
    _bare = Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
      ..options.headers['Content-Type'] = 'application/json';
  }

  final Dio _dio;
  late final Dio _bare;
  final TokenStorage _storage;
  Future<bool>? _refreshing;

  bool _isAuthPath(String path) =>
      path.contains('/auth/sso-callback') || path.contains('/auth/refresh');

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool retried = false,
  }) async {
    Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }

    final status = res.statusCode ?? 0;
    if (status == 401 && !_isAuthPath(path) && !retried) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return _send(method, path, query: query, body: body, retried: true);
      }
    }

    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is Map<String, dynamic> && data.containsKey('data')) {
        return data['data'];
      }
      return data;
    }
    throw _statusToApiException(res);
  }

  /// Single-flight refresh: concurrent 401s share one refresh round-trip.
  Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = await _storage.readRefresh();
    if (refresh == null) return false;
    try {
      final res = await _bare.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = (res.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      await _storage.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      await _storage.clear(); // session is dead; force re-login
      return false;
    }
  }

  ApiException _toApiException(DioException e) {
    if (e.response != null) return _statusToApiException(e.response!);
    return ApiException(statusCode: 0, message: e.message ?? 'Network error');
  }

  ApiException _statusToApiException(Response<dynamic> res) {
    final data = res.data;
    if (data is Map<String, dynamic>) {
      return ApiException(
        statusCode: res.statusCode ?? 0,
        message: (data['message'] ?? 'Request failed').toString(),
        code: data['code'] as String?,
        errors: data['errors'] as List<dynamic>?,
      );
    }
    return ApiException(statusCode: res.statusCode ?? 0, message: 'Request failed');
  }
}

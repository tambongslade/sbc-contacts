import 'package:sbc_contacts/core/network/api_client.dart';
import 'package:sbc_contacts/core/storage/token_storage.dart';
import 'package:sbc_contacts/features/auth/domain/app_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._storage);

  final ApiClient _api;
  final TokenStorage _storage;

  /// Exchange the SBC authorization code for an app session and persist tokens.
  Future<AppUser> ssoCallback(String code, {String? deviceId}) async {
    final data = await _api.post(
      '/auth/sso-callback',
      body: {'code': code, if (deviceId != null) 'deviceId': deviceId},
    ) as Map<String, dynamic>;
    final tokens = data['tokens'] as Map<String, dynamic>;
    await _storage.save(
      access: tokens['accessToken'] as String,
      refresh: tokens['refreshToken'] as String,
    );
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser> me() async =>
      AppUser.fromJson(await _api.get('/auth/me') as Map<String, dynamic>);

  Future<AppUser> refreshProfile() async =>
      AppUser.fromJson(await _api.get('/auth/me/refresh-profile') as Map<String, dynamic>);

  Future<void> logout() async {
    final refresh = await _storage.readRefresh();
    if (refresh != null) {
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refresh});
      } catch (_) {
        // best-effort; clear locally regardless
      }
    }
    await _storage.clear();
  }

  Future<bool> hasSession() async => (await _storage.readAccess()) != null;
}

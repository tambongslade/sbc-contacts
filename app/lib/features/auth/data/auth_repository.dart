import 'package:sbc_contacts/core/config/app_config.dart';
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
      body: {
        'code': code,
        // SBC requires the exchange to repeat the redirect_uri used on
        // /sso/authorize; the backend cannot know which flow we took.
        'redirectUri': AppConfig.ssoRedirectUri,
        if (deviceId != null) 'deviceId': deviceId,
      },
    ) as Map<String, dynamic>;
    return _startSession(data);
  }

  /// Create an SBC Network account — it lives in SBC Network only — and sign
  /// it in.
  Future<AppUser> register({
    required String name,
    required String country,
    required String phoneNumber,
    required String password,
    required String sex,
    required DateTime birthDate,
    required String region,
    required String profession,
    required List<String> interests,
  }) async {
    final data = await _api.post(
      '/auth/register',
      body: {
        'name': name,
        'country': country,
        'phoneNumber': phoneNumber,
        'password': password,
        'sex': sex,
        'birthDate': birthDate.toIso8601String().substring(0, 10),
        'region': region,
        'profession': profession,
        'interests': interests,
      },
    ) as Map<String, dynamic>;
    return _startSession(data);
  }

  /// Sign in to an SBC Network account with its WhatsApp number.
  Future<AppUser> loginWithPhone({
    required String country,
    required String phoneNumber,
    required String password,
  }) async {
    final data = await _api.post(
      '/auth/login-phone',
      body: {'country': country, 'phoneNumber': phoneNumber, 'password': password},
    ) as Map<String, dynamic>;
    return _startSession(data);
  }

  Future<AppUser> _startSession(Map<String, dynamic> data) async {
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

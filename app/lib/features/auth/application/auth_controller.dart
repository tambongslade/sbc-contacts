import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/auth/domain/app_user.dart';

/// Holds the authenticated user (null = signed out). On build it tries to
/// restore a session from the stored token by calling `/auth/me`.
class AuthController extends AsyncNotifier<AppUser?> {
  @override
  FutureOr<AppUser?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    if (!await repo.hasSession()) return null;
    try {
      return await repo.me();
    } catch (_) {
      return null; // token invalid/expired → treat as signed out
    }
  }

  /// Complete SSO by exchanging the code from SBC's consent redirect.
  Future<void> loginWithCode(String code, {String? deviceId}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).ssoCallback(code, deviceId: deviceId),
    );
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncValue.data(null);
  }

  Future<void> refreshProfile() async {
    final repo = ref.read(authRepositoryProvider);
    state = await AsyncValue.guard(repo.refreshProfile);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);

/// Convenience: is a user currently signed in?
final isAuthenticatedProvider = Provider<bool>((ref) {
  final auth = ref.watch(authControllerProvider);
  return auth.value != null;
});

import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/auth/application/auth_controller.dart';
import 'package:sbc_contacts/features/notifications/application/notifications_controller.dart';
import 'package:sbc_contacts/router/app_router.dart';

/// Lets a push that arrives while the app is open show a SnackBar from anywhere.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The home shell's selected tab, so a notification can switch to Alertes.
class HomeTab extends Notifier<int> {
  static const alerts = 3;

  @override
  int build() => 0;

  // A method rather than a setter: it is passed as the nav bar's callback.
  // ignore: use_setters_to_change_properties
  void select(int index) => state = index;
}

final homeTabProvider = NotifierProvider<HomeTab, int>(HomeTab.new);

/// Push notifications over Firebase Cloud Messaging (Android).
///
/// The backend sends each push with a `link`, an app path that is also a
/// go_router location (`/requests/:id`, `/inbox/:id`, `/profile/:sbcId`,
/// `/sync/saved-me`). Tapping the notification opens that screen on top of the
/// Alertes tab; a push with no link opens Alertes.
///
/// Without google-services.json Firebase cannot start: push is then simply off
/// and the rest of the app is unaffected.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  bool _ready = false;
  String? _token;
  String? _deviceId;

  /// A tapped notification waiting for the session (a cold start taps before
  /// the stored session is restored). The inner value is the link, maybe null.
  ({String? link})? _pending;

  /// The iOS app is the native Swift one; this Flutter build ships on Android.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// At app start, so the tap that launched the app is not missed.
  Future<void> init() async {
    if (!_supported) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push off: Firebase not configured ($e)');
      return;
    }
    _ready = true;
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _tapped(m.data));
    FirebaseMessaging.onMessage.listen(_foreground);
    // Registration tokens, which the backend's firebase-admin multicast takes.
    // Their FID replacement (register/onRegistered) needs a backend change first.
    // ignore: deprecated_member_use
    messaging.onTokenRefresh.listen((token) {
      _token = token;
      unawaited(_register());
    });
    final initial = await messaging.getInitialMessage();
    if (initial != null) _tapped(initial.data);
  }

  /// Once signed in and the contacts prompt is out of the way: asks for the
  /// permission (Android 13+ shows a dialog the first time) and registers the
  /// phone with the backend.
  Future<void> start() async {
    if (!_ready) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // ignore: deprecated_member_use, see onTokenRefresh in init().
      _token = await FirebaseMessaging.instance.getToken();
      await _register();
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
    _deliver();
  }

  /// Before signing out, while the session still authorizes the call: this
  /// phone stops receiving the account's pushes.
  Future<void> signOut() async {
    final id = _deviceId;
    _deviceId = null;
    _pending = null;
    _ref.read(homeTabProvider.notifier).select(0);
    if (id == null) return;
    try {
      await _ref.read(notificationsRepositoryProvider).removeDevice(id);
    } catch (_) {
      // The backend also drops a token once another account registers it.
    }
  }

  /// Opens an app path from a notification, above the Alertes tab so Back
  /// lands on the list of alerts.
  void openLink(String? link) {
    final router = _ref.read(goRouterProvider);
    _ref.read(homeTabProvider.notifier).select(HomeTab.alerts);
    _ref
      ..invalidate(notificationsControllerProvider)
      ..invalidate(unreadCountProvider);
    if (link != null && link.startsWith('/') && link != '/') {
      unawaited(router.push(link));
    } else {
      router.go('/');
    }
  }

  Future<void> _register() async {
    final token = _token;
    if (token == null || _ref.read(authControllerProvider).value == null) {
      return;
    }
    try {
      _deviceId = await _ref
          .read(notificationsRepositoryProvider)
          .registerDevice(platform: 'ANDROID', pushToken: token);
    } catch (_) {
      // Retried on the next start or token refresh.
    }
  }

  void _foreground(RemoteMessage message) {
    _ref
      ..invalidate(unreadCountProvider)
      ..invalidate(notificationsControllerProvider);
    final n = message.notification;
    if (n == null) return;
    final link = message.data['link']?.toString();
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(n.title ?? n.body ?? 'Nouvelle notification'),
        action: SnackBarAction(label: 'Voir', onPressed: () => openLink(link)),
      ),
    );
  }

  void _tapped(Map<String, dynamic> data) {
    final link = data['link']?.toString().trim();
    _pending = (link: link == null || link.isEmpty ? null : link);
    _deliver();
  }

  /// Opens the pending tap once there is a signed-in session to open it in.
  void _deliver() {
    final tap = _pending;
    if (tap == null || _ref.read(authControllerProvider).value == null) return;
    _pending = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => openLink(tap.link));
    WidgetsBinding.instance.scheduleFrame();
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  // A tap that arrived before sign-in opens once the session is there.
  ref.listen(authControllerProvider, (_, next) {
    if (next.value != null) service._deliver();
  });
  return service;
});

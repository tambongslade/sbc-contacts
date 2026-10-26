import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/shared/services/location.dart';

/// The member's own requests ("Mes demandes").
class MyRequestsController extends AsyncNotifier<List<ServiceRequestItem>> {
  @override
  FutureOr<List<ServiceRequestItem>> build() => ref.watch(requestsRepositoryProvider).list();

  /// Replace one request in place after a screen changed it.
  void upsert(ServiceRequestItem request) {
    final list = [...?state.value];
    final i = list.indexWhere((r) => r.id == request.id);
    if (i >= 0) {
      list[i] = request;
    } else {
      list.insert(0, request);
    }
    state = AsyncValue.data(list);
  }

  void remove(String id) {
    state = AsyncValue.data([...?state.value?.where((r) => r.id != id)]);
  }
}

final myRequestsProvider =
    AsyncNotifierProvider<MyRequestsController, List<ServiceRequestItem>>(MyRequestsController.new);

/// The pro space: profile, services, reception. `profile == null` = not a pro.
class ProSpaceController extends AsyncNotifier<ProSpace> {
  @override
  FutureOr<ProSpace> build() => ref.watch(requestsRepositoryProvider).proSpace();

  void set(ProSpace space) => state = AsyncValue.data(space);
}

final proSpaceProvider = AsyncNotifierProvider<ProSpaceController, ProSpace>(ProSpaceController.new);

/// "Partager ma position": while on, a pro's app reports where they are each
/// time it comes to the foreground, so requests close by reach them first.
/// On unless the pro turned it off; the choice stays on this phone.
class ProLocationController extends AsyncNotifier<bool> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'proLocation.sharing';

  /// The backend keeps a position three days; more often than this is noise.
  static const _every = Duration(minutes: 15);
  DateTime? _lastSent;

  @override
  FutureOr<bool> build() async => await _storage.read(key: _key) != 'off';

  Future<void> setSharing(bool on) async {
    state = AsyncValue.data(on);
    await _storage.write(key: _key, value: on ? 'on' : 'off');
    if (on) {
      await report(force: true);
    } else {
      _lastSent = null;
      try {
        await ref.read(requestsRepositoryProvider).clearLocation();
      } catch (_) {
        // A stale position expires on its own after three days.
      }
    }
  }

  /// Sends the current position if this member is a pro and shares it.
  Future<void> report({bool force = false}) async {
    try {
      if (!await future) return;
      final last = _lastSent;
      if (!force && last != null && DateTime.now().difference(last) < _every) return;
      final space = await ref.read(proSpaceProvider.future);
      if (!space.isPro) return;
      final here = await ref.read(locationServiceProvider).current();
      if (here == null) return;
      await ref.read(requestsRepositoryProvider).updateLocation(here);
      _lastSent = DateTime.now();
    } catch (_) {
      // Next time the app comes back; the zones still match meanwhile.
    }
  }
}

final proLocationProvider = AsyncNotifierProvider<ProLocationController, bool>(ProLocationController.new);

/// Requests routed to the pro ("Reçues").
class InboxController extends AsyncNotifier<List<InboxItem>> {
  @override
  FutureOr<List<InboxItem>> build() async {
    final space = await ref.watch(proSpaceProvider.future);
    if (!space.isPro) return const [];
    return ref.read(requestsRepositoryProvider).inbox();
  }

  void upsert(InboxItem item) {
    final list = [...?state.value];
    final i = list.indexWhere((x) => x.id == item.id);
    if (i >= 0) list[i] = item;
    state = AsyncValue.data(list);
  }
}

final inboxProvider = AsyncNotifierProvider<InboxController, List<InboxItem>>(InboxController.new);

/// New requests the pro has not opened yet — the tab badge.
final unopenedCountProvider = Provider<int>((ref) {
  final items = ref.watch(inboxProvider).value ?? const [];
  return items.where((i) => i.status == DispatchStatus.sent).length;
});

final proStatsProvider = FutureProvider.autoDispose<ProStats>(
  (ref) => ref.watch(requestsRepositoryProvider).stats(),
);

/// The two prompts shown after login, and when each may show again.
///
/// A member who is not a pro is invited at most once a week. A pro whose setup
/// is incomplete is reminded daily: they may be paying for reception and
/// getting nothing, and should know why.
enum ProInvite {
  becomePro(Duration(days: 7)),
  finishSetup(Duration(days: 1));

  const ProInvite(this.snooze);
  final Duration snooze;

  static const _storage = FlutterSecureStorage();

  static ProInvite? kindFor(ProSpace space) {
    if (!space.isPro) return ProInvite.becomePro;
    return space.missingSetup.isEmpty ? null : ProInvite.finishSetup;
  }

  String _key(String userId) => '$name.lastShown.$userId';

  Future<bool> isDue(String userId) async {
    final raw = await _storage.read(key: _key(userId));
    final last = raw == null ? null : DateTime.tryParse(raw);
    return last == null || DateTime.now().difference(last) > snooze;
  }

  Future<void> markShown(String userId) =>
      _storage.write(key: _key(userId), value: DateTime.now().toIso8601String());
}

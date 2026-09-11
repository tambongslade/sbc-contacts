import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sbc_contacts/core/providers/core_providers.dart';
import 'package:sbc_contacts/features/sync/application/sync_controllers.dart';
import 'package:sbc_contacts/features/sync/domain/sync_models.dart';

/// Live state of a synchronisation while it writes to the phone book.
@immutable
class SyncProgress {
  const SyncProgress({
    this.total = 0,
    this.done = 0,
    this.synced = 0,
    this.skipped = 0,
    this.failed = 0,
    this.running = false,
    this.finished = false,
    this.error,
  });

  final int total;
  final int done;
  final int synced;

  /// Already present on the device — deduplicated rather than written twice
  /// (cahier §15).
  final int skipped;
  final int failed;
  final bool running;
  final bool finished;
  final String? error;

  double get fraction => total == 0 ? 0 : done / total;

  SyncProgress copyWith({
    int? total,
    int? done,
    int? synced,
    int? skipped,
    int? failed,
    bool? running,
    bool? finished,
    String? error,
  }) =>
      SyncProgress(
        total: total ?? this.total,
        done: done ?? this.done,
        synced: synced ?? this.synced,
        skipped: skipped ?? this.skipped,
        failed: failed ?? this.failed,
        running: running ?? this.running,
        finished: finished ?? this.finished,
        error: error ?? this.error,
      );
}

/// Drives one synchronisation: open a run on the backend, write the chosen
/// members into the phone book, then report each outcome back so "Mes contacts
/// SBC" (§16) and the history (§17) reflect what actually happened.
///
/// Nothing is written without the member having chosen it and granted contacts
/// permission — the cahier is explicit that automation stays inside the
/// platform's rules (§11).
class SyncRunner extends Notifier<SyncProgress> {
  @override
  SyncProgress build() => const SyncProgress();

  void reset() => state = const SyncProgress();

  /// Opens a run for the selected members and writes them to the device.
  /// The run is created here — not when the review screen is merely opened.
  Future<void> run({required List<String> memberSbcIds, String? criteriaId}) async {
    if (state.running) return;

    final contacts = ref.read(contactServiceProvider);
    final repo = ref.read(syncRepositoryProvider);

    if (!await contacts.requestPermission()) {
      state = const SyncProgress(
        finished: true,
        error: "Permission contacts refusée — impossible d'enregistrer.",
      );
      return;
    }

    state = SyncProgress(total: memberSbcIds.length, running: true);

    final SyncRunStart run;
    try {
      run = await repo.startRun(criteriaId: criteriaId, memberSbcIds: memberSbcIds);
    } catch (e) {
      state = state.copyWith(running: false, finished: true, error: e.toString());
      return;
    }

    // The backend knows what it has already synced; the device is the
    // authority on what is already in the phone book. Check both.
    final pending = run.items.where((t) => !t.alreadySynced).toList();
    final results = <Map<String, dynamic>>[];
    var synced = 0;
    var skipped = 0;
    var failed = 0;
    var done = 0;

    for (final t in pending) {
      final phone = t.phoneNumber;
      if (phone != null && phone.isNotEmpty && await contacts.existsByPhone(phone)) {
        skipped++;
        done++;
        // Record it as synced: the contact IS on the device, which is what
        // "Mes contacts SBC" is reporting on.
        results.add({'memberSbcId': t.memberSbcId, 'status': 'SYNCED'});
        state = state.copyWith(done: done, skipped: skipped);
        continue;
      }

      final r = await contacts.addSbcContact(
        displayName: t.displayName,
        phone: phone,
        profession: t.profession,
        city: t.city,
        country: t.country,
      );
      done++;
      if (r.success) {
        synced++;
      } else {
        failed++;
      }
      results.add({
        'memberSbcId': t.memberSbcId,
        if (r.deviceContactId != null) 'deviceContactId': r.deviceContactId,
        'status': r.success ? 'SYNCED' : 'FAILED',
      });
      state = state.copyWith(done: done, synced: synced, failed: failed);
    }

    String? reportError;
    if (results.isNotEmpty) {
      try {
        await repo.reportRun(run.syncRunId, results);
      } catch (e) {
        // The contacts are on the phone either way; only the bookkeeping failed.
        reportError = 'Contacts enregistrés, mais le rapport au serveur a échoué : $e';
      }
    }

    state = state.copyWith(running: false, finished: true, error: reportError);
    ref
      ..invalidate(syncSummaryProvider)
      ..invalidate(syncedContactsProvider)
      ..invalidate(syncHistoryProvider);
  }
}

final syncRunnerProvider =
    NotifierProvider<SyncRunner, SyncProgress>(SyncRunner.new);

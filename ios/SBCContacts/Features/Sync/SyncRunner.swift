import Foundation
import Observation

/// Drives one synchronisation: open a run on the backend, write the chosen
/// members into the phone book, then report each outcome back so "Mes contacts
/// SBC" (§16) and the history (§17) reflect what actually happened.
///
/// Nothing is written without the member having chosen it and granted contacts
/// permission — automation stays inside the platform's rules (§11).
@MainActor
@Observable
final class SyncRunner {
    private(set) var total = 0
    private(set) var done = 0
    private(set) var synced = 0
    /// Already present on the device — deduplicated rather than written twice (§15).
    private(set) var skipped = 0
    private(set) var failed = 0
    private(set) var running = false
    private(set) var finished = false
    private(set) var error: String?

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }

    private let repo: SyncRepository
    private let contacts = ContactService()

    init(repo: SyncRepository) {
        self.repo = repo
    }

    /// Opens a run for the selected members and writes them to the device.
    /// The run is created here — not when the review screen is merely opened.
    func run(memberSbcIds: [String], criteriaId: String?) async {
        guard !running else { return }
        reset()

        guard await contacts.requestPermission() else {
            finished = true
            error = "Permission contacts refusée — impossible d'enregistrer."
            return
        }

        total = memberSbcIds.count
        running = true

        let start: SyncRunStart
        do {
            start = try await repo.startRun(criteriaId: criteriaId, memberSbcIds: memberSbcIds)
        } catch {
            running = false
            finished = true
            self.error = error.localizedDescription
            return
        }

        // The backend knows what it has already synced; the device is the
        // authority on what is already in the phone book. Check both.
        let pending = start.items.filter { !$0.alreadySynced }
        var results: [SyncRunResult] = []

        for target in pending {
            if let phone = target.phoneNumber, !phone.isEmpty, await contacts.existsByPhone(phone) {
                skipped += 1
                done += 1
                // Recorded as synced: the contact IS on the device, which is
                // what "Mes contacts SBC" reports on.
                results.append(SyncRunResult(memberSbcId: target.memberSbcId, status: .synced))
                continue
            }

            let written = await contacts.addSBCContact(
                displayName: target.displayName.isEmpty ? "Membre SBC" : target.displayName,
                phone: target.phoneNumber,
                profession: target.profession
            )
            done += 1
            if written.success { synced += 1 } else { failed += 1 }
            results.append(SyncRunResult(
                memberSbcId: target.memberSbcId,
                deviceContactId: written.deviceContactId,
                status: written.success ? .synced : .failed
            ))
        }

        if !results.isEmpty {
            do {
                try await repo.reportRun(id: start.syncRunId, results: results)
            } catch {
                // The contacts are on the phone either way; only the bookkeeping failed.
                self.error = "Contacts enregistrés, mais le rapport au serveur a échoué : \(error.localizedDescription)"
            }
        }

        running = false
        finished = true
    }

    private func reset() {
        total = 0
        done = 0
        synced = 0
        skipped = 0
        failed = 0
        finished = false
        error = nil
    }
}

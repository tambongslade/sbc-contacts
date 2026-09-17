import Foundation
import Observation

/// Synchronisation home state: dashboard counters and saved criteria.
@MainActor
@Observable
final class SyncStore {
    enum Loadable<T> {
        case loading
        case loaded(T)
        case failed(Error)

        var value: T? {
            if case let .loaded(v) = self { return v }
            return nil
        }
    }

    private(set) var summary: Loadable<SyncSummary> = .loading
    private(set) var criteria: Loadable<[SyncCriteria]> = .loading

    let repo: SyncRepository

    init(repo: SyncRepository) {
        self.repo = repo
    }

    func load() async {
        async let s: Void = loadSummary()
        async let c: Void = loadCriteria()
        _ = await (s, c)
    }

    func loadSummary() async {
        do {
            summary = .loaded(try await repo.summary())
        } catch {
            summary = .failed(error)
        }
    }

    func loadCriteria() async {
        do {
            criteria = .loaded(try await repo.listCriteria())
        } catch {
            criteria = .failed(error)
        }
    }

    func create(_ payload: CriteriaPayload) async throws {
        _ = try await repo.createCriteria(payload)
        await load()
    }

    func update(id: String, _ payload: CriteriaPayload) async throws {
        _ = try await repo.updateCriteria(id: id, payload)
        await load()
    }

    func remove(id: String) async throws {
        try await repo.deleteCriteria(id: id)
        await load()
    }
}

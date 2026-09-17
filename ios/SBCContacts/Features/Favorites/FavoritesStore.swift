import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    enum State {
        case loading
        case loaded([Member])
        case failed(Error)
    }

    private(set) var state: State = .loading
    private let repo: FavoritesRepository

    init(repo: FavoritesRepository) {
        self.repo = repo
    }

    func load() async {
        do {
            state = .loaded(try await repo.list().items)
        } catch {
            state = .failed(error)
        }
    }

    func add(_ memberSbcId: String) async throws {
        try await repo.add(memberSbcId: memberSbcId)
        await load()
    }

    func remove(_ memberSbcId: String) async throws {
        // Optimistic removal.
        if case let .loaded(members) = state {
            state = .loaded(members.filter { $0.sbcId != memberSbcId })
        }
        try await repo.remove(memberSbcId: memberSbcId)
    }
}

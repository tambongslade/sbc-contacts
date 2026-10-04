import Foundation
import Observation

/// State behind the "Demandes" tab: the member's own requests and, for pros,
/// the requests they received and their professional space.
@MainActor
@Observable
final class RequestsStore {
    enum Load<T> {
        case loading
        case loaded(T)
        case failed(Error)
    }

    private(set) var mine: Load<[ServiceRequestItem]> = .loading
    private(set) var inbox: Load<[InboxItem]> = .loading
    /// Nil until first loaded; `profile == nil` inside means "not a pro yet".
    private(set) var proSpace: ProSpace?
    let repo: RequestsRepository

    init(repo: RequestsRepository) {
        self.repo = repo
    }

    var isPro: Bool { proSpace?.profile != nil }

    /// New requests the pro has not opened yet — the tab badge.
    var unopenedCount: Int {
        guard case let .loaded(items) = inbox else { return 0 }
        return items.filter { $0.status == .sent }.count
    }

    func load() async {
        async let mineTask: Void = loadMine()
        async let proTask: Void = loadPro()
        _ = await (mineTask, proTask)
    }

    func loadMine() async {
        do {
            mine = .loaded(try await repo.list().items)
        } catch {
            if case .loaded = mine { return } // keep what is on screen
            mine = .failed(error)
        }
    }

    func loadPro() async {
        do {
            let space = try await repo.proSpace()
            proSpace = space
            if space.profile != nil {
                inbox = .loaded(try await repo.inbox().items)
            } else {
                inbox = .loaded([])
            }
        } catch {
            if case .loaded = inbox { return }
            inbox = .failed(error)
        }
    }

    /// Replace one request in place after a screen changed it.
    func upsert(_ request: ServiceRequestItem) {
        guard case var .loaded(list) = mine else {
            mine = .loaded([request])
            return
        }
        if let i = list.firstIndex(where: { $0.id == request.id }) {
            list[i] = request
        } else {
            list.insert(request, at: 0)
        }
        mine = .loaded(list)
    }

    func remove(requestId: String) {
        guard case let .loaded(list) = mine else { return }
        mine = .loaded(list.filter { $0.id != requestId })
    }

    func upsert(_ item: InboxItem) {
        guard case var .loaded(list) = inbox, let i = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[i] = item
        inbox = .loaded(list)
    }

    func setProSpace(_ space: ProSpace) {
        proSpace = space
    }
}

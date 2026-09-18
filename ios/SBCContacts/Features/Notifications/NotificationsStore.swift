import Foundation
import Observation

@MainActor
@Observable
final class NotificationsStore {
    enum State {
        case loading
        case loaded([AppNotification])
        case failed(Error)
    }

    private(set) var state: State = .loading
    private(set) var unreadCount = 0

    private let repo: NotificationsRepository

    init(repo: NotificationsRepository) {
        self.repo = repo
    }

    func load() async {
        do {
            state = .loaded(try await repo.list().items)
        } catch {
            state = .failed(error)
        }
    }

    func refreshUnreadCount() async {
        if let count = try? await repo.unreadCount() {
            unreadCount = count
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.isRead else { return }
        try? await repo.markRead(id: notification.id)
        await reload()
    }

    func markAllRead() async {
        try? await repo.markAllRead()
        await reload()
    }

    private func reload() async {
        async let list: Void = load()
        async let count: Void = refreshUnreadCount()
        _ = await (list, count)
    }
}

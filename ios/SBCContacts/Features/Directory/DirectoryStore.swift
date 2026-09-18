import Foundation
import Observation

/// Directory search state: filters, paged results, and error/paywall status.
@MainActor
@Observable
final class DirectoryStore {
    private(set) var filters = SearchFilters()
    private(set) var members: [Member] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var hasMore = false
    private(set) var page = 1
    private(set) var total = 0
    private(set) var error: String?
    private(set) var errorCode: String?
    private(set) var hasSearched = false

    var subscriptionRequired: Bool { errorCode == "SUBSCRIPTION_REQUIRED" }

    private let repo: DirectoryRepository
    private var generation = 0

    init(repo: DirectoryRepository) {
        self.repo = repo
    }

    func apply(_ filters: SearchFilters) async {
        self.filters = filters
        await search()
    }

    func search() async {
        hasSearched = true
        generation += 1
        let current = generation
        loading = true
        error = nil
        errorCode = nil
        do {
            let result = try await repo.search(filters)
            guard current == generation else { return } // a newer query superseded this one
            #if DEBUG
            print("[Directory] page \(result.page): \(result.items.count) items, total \(result.total), hasMore \(result.hasMore)")
            #endif
            members = result.items
            page = result.page
            hasMore = result.hasMore
            total = result.total
        } catch {
            guard current == generation else { return }
            fail(error)
        }
        loading = false
    }

    func loadMore() async {
        guard hasMore, !loadingMore, !loading else { return }
        let current = generation
        loadingMore = true
        defer { loadingMore = false }
        do {
            let result = try await repo.search(filters, page: page + 1)
            guard current == generation else { return }
            members += result.items
            page = result.page
            hasMore = result.hasMore
        } catch {
            guard current == generation else { return }
            fail(error)
        }
    }

    /// Optimistically reflect a favorite toggle in the current result list.
    func setFavoriteLocal(sbcId: String, isFavorite: Bool) {
        for index in members.indices where members[index].sbcId == sbcId {
            members[index].isFavorite = isFavorite
        }
    }

    /// Same, for a contact just written to the phone: the row says "déjà dans
    /// tes contacts" straight away instead of after the next search.
    func setSyncedLocal(sbcId: String) {
        for index in members.indices where members[index].sbcId == sbcId {
            members[index].isSynced = true
        }
    }

    private func fail(_ error: Error) {
        #if DEBUG
        print("[Directory] search failed: \(error)")
        #endif
        let api = error as? APIError
        self.error = api?.message ?? error.localizedDescription
        errorCode = api?.code
    }
}

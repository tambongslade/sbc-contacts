import Foundation

struct SyncRepository: Sendable {
    let api: APIClient

    private struct MatchCount: Decodable, Sendable {
        let matchCount: Int

        private enum CodingKeys: String, CodingKey { case matchCount }

        init(from decoder: Decoder) throws {
            matchCount = (try decoder.container(keyedBy: CodingKeys.self)).int(.matchCount) ?? 0
        }
    }

    private struct StartBody: Encodable, Sendable {
        let criteriaId: String?
        let memberSbcIds: [String]?
        let deviceId: String?
    }

    private struct ReportBody: Encodable, Sendable {
        let results: [SyncRunResult]
    }

    private static func paging(_ page: Int, _ limit: Int) -> [URLQueryItem] {
        [.init(name: "page", value: String(page)), .init(name: "limit", value: String(limit))]
    }

    // MARK: Criteria

    func listCriteria() async throws -> [SyncCriteria] {
        let items: [Lossy<SyncCriteria>] = try await api.get("/sync/criteria")
        return items.compactMap(\.value)
    }

    func createCriteria(_ payload: CriteriaPayload) async throws -> SyncCriteria {
        try await api.post("/sync/criteria", body: payload)
    }

    func updateCriteria(id: String, _ payload: CriteriaPayload) async throws -> SyncCriteria {
        try await api.patch("/sync/criteria/\(id)", body: payload)
    }

    func deleteCriteria(id: String) async throws {
        try await api.delete("/sync/criteria/\(id)")
    }

    func preview(id: String) async throws -> Int {
        let result: MatchCount = try await api.get("/sync/criteria/\(id)/preview")
        return result.matchCount
    }

    /// Live match count for an unsaved criteria form.
    func previewAdhoc(_ payload: CriteriaPayload) async throws -> Int {
        let result: MatchCount = try await api.post("/sync/criteria/preview", body: payload)
        return result.matchCount
    }

    /// Read-only: opening the review screen must not create a SyncRun.
    func matches(id: String, page: Int = 1, limit: Int = 50) async throws -> Paginated<Member> {
        try await api.get("/sync/criteria/\(id)/matches", query: Self.paging(page, limit))
    }

    // MARK: Runs

    func startRun(criteriaId: String?, memberSbcIds: [String]?, deviceId: String? = nil) async throws -> SyncRunStart {
        try await api.post(
            "/sync/runs",
            body: StartBody(criteriaId: criteriaId, memberSbcIds: memberSbcIds, deviceId: deviceId)
        )
    }

    func reportRun(id: String, results: [SyncRunResult]) async throws {
        try await api.post("/sync/runs/\(id)/report", body: ReportBody(results: results))
    }

    func summary() async throws -> SyncSummary {
        try await api.get("/sync/summary")
    }

    func history(page: Int = 1, limit: Int = 20) async throws -> Paginated<SyncRunEntry> {
        try await api.get("/sync/history", query: Self.paging(page, limit))
    }

    /// Records one contact written to the phone outside a criteria run (the
    /// profile's "Ajouter"). Without it the contact is on the device but absent
    /// from "Mes contacts SBC", which reads the backend, not the phone book.
    ///
    /// Returns false when the backend does not know this member: a run can only
    /// target someone already mirrored, so reporting one it never resolved would
    /// look like a success and leave "Mes contacts SBC" empty with nothing said.
    @discardableResult
    func recordSingleContact(memberSbcId: String, deviceContactId: String?) async throws -> Bool {
        let run = try await startRun(criteriaId: nil, memberSbcIds: [memberSbcId])
        guard !run.items.isEmpty else { return false }
        try await reportRun(id: run.syncRunId, results: [
            SyncRunResult(memberSbcId: memberSbcId, deviceContactId: deviceContactId, status: .synced),
        ])
        return true
    }

    /// "Qui m'a enregistré ?" (cahier §21) — the members who saved YOU.
    func savedMe(page: Int = 1, limit: Int = 30) async throws -> Paginated<SavedMeEntry> {
        try await api.get("/sync/saved-me", query: Self.paging(page, limit))
    }

    /// "Mes contacts SBC" (cahier §16); `status` filters on the backend enum
    /// (PENDING / SYNCED / FAILED / STALE).
    func syncedContacts(status: String? = nil, page: Int = 1, limit: Int = 30) async throws -> Paginated<SyncedContact> {
        var query = Self.paging(page, limit)
        if let status { query.append(.init(name: "status", value: status)) }
        return try await api.get("/sync/contacts", query: query)
    }
}

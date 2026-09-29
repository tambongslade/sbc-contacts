import Foundation

/// The requests & pros endpoints (`/data/requests`, `/data/pro`).
struct RequestsRepository: Sendable {
    let api: APIClient

    // MARK: Requester

    struct CreateBody: Encodable, Sendable {
        var text: String
        var city: String?
        var budget: Int?
        var desiredDate: String?
        var mode: ServiceMode?
    }

    /// Corrections to the AI's reading, or an answer to its question.
    struct UpdateBody: Encodable, Sendable {
        var profession: String?
        var service: String?
        var city: String?
        var district: String?
        var mode: ServiceMode?
        var desiredDate: String?
        var desiredTime: String?
        var budget: Int?
        var clarificationAnswer: String?
    }

    private struct SelectBody: Encodable, Sendable { let dispatchId: String }

    struct CompleteBody: Encodable, Sendable {
        var performed: Bool
        var stars: Int?
        var comment: String?
    }

    func create(_ body: CreateBody) async throws -> ServiceRequestItem {
        try await api.post("/data/requests", body: body)
    }

    func update(_ id: String, _ body: UpdateBody) async throws -> ServiceRequestItem {
        try await api.patch("/data/requests/\(id)", body: body)
    }

    func send(_ id: String) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(id)/send")
    }

    func list(page: Int = 1, limit: Int = 50) async throws -> Paginated<ServiceRequestItem> {
        try await api.get("/data/requests", query: [.init(name: "page", value: String(page)), .init(name: "limit", value: String(limit))])
    }

    func get(_ id: String) async throws -> ServiceRequestItem {
        try await api.get("/data/requests/\(id)")
    }

    func select(_ id: String, dispatchId: String) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(id)/select", body: SelectBody(dispatchId: dispatchId))
    }

    func complete(_ id: String, _ body: CompleteBody) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(id)/complete", body: body)
    }

    func cancel(_ id: String) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(id)/cancel")
    }

    // MARK: Pro

    struct ProfileBody: Encodable, Sendable {
        var profession: String
        var description: String
        var city: String
        var zones: [String]
        var modes: [ServiceMode]
        var availability: String
        var priceMin: Int?
        var priceMax: Int?
        var shopUrl: String
        var whatsapp: String?
    }

    private struct TextBody: Encodable, Sendable { let text: String }
    private struct ServicesBody: Encodable, Sendable { let services: [ServiceProposal] }

    enum ProAction: String, Encodable, Sendable {
        case interested = "INTERESTED", question = "QUESTION", unavailable = "UNAVAILABLE", declined = "DECLINED"
    }

    struct RespondBody: Encodable, Sendable {
        var action: ProAction
        var price: Int?
        var availability: String?
        var delay: String?
        var message: String?
    }

    func proSpace() async throws -> ProSpace {
        try await api.get("/data/pro/profile")
    }

    func saveProfile(_ body: ProfileBody) async throws -> ProSpace {
        try await api.put("/data/pro/profile", body: body)
    }

    func structure(_ text: String) async throws -> StructuredServices {
        try await api.post("/data/pro/services/structure", body: TextBody(text: text))
    }

    func addServices(_ services: [ServiceProposal]) async throws -> ProSpace {
        try await api.post("/data/pro/services", body: ServicesBody(services: services))
    }

    func deleteService(_ id: String) async throws -> ProSpace {
        try await api.delete("/data/pro/services/\(id)")
    }

    func inbox(page: Int = 1, limit: Int = 50) async throws -> Paginated<InboxItem> {
        try await api.get("/data/pro/inbox", query: [.init(name: "page", value: String(page)), .init(name: "limit", value: String(limit))])
    }

    /// Opening marks the request seen.
    func open(requestId: String) async throws -> InboxItem {
        try await api.get("/data/pro/inbox/\(requestId)")
    }

    func respond(requestId: String, _ body: RespondBody) async throws -> InboxItem {
        try await api.post("/data/pro/inbox/\(requestId)/respond", body: body)
    }

    func stats() async throws -> ProStats {
        try await api.get("/data/pro/stats")
    }
}

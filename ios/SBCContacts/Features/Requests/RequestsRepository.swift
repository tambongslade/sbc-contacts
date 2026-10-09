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

    /// Drafts are erased; anything else is cancelled if still open, then hidden.
    func remove(_ id: String) async throws {
        try await api.delete("/data/requests/\(id)")
    }

    private struct RequesterMessageBody: Encodable, Sendable { let dispatchId: String; let text: String }
    private struct MessageBody: Encodable, Sendable { let text: String }

    /// Answer a pro's question, or write to a pro who answered.
    func sendMessage(requestId: String, dispatchId: String, text: String) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(requestId)/messages", body: RequesterMessageBody(dispatchId: dispatchId, text: text))
    }

    /// "Relancer cette demande": a new draft with the same need.
    func reopen(_ id: String) async throws -> ServiceRequestItem {
        try await api.post("/data/requests/\(id)/reopen")
    }

    /// The pro writes to the requester in the request conversation.
    func proSendMessage(requestId: String, text: String) async throws -> InboxItem {
        try await api.post("/data/pro/inbox/\(requestId)/messages", body: MessageBody(text: text))
    }

    struct ServiceUpdate: Encodable, Sendable {
        var name: String
        var description: String?
        var specialties: [String]
        var priceMin: Int?
        var priceMax: Int?
        var modes: [ServiceMode]
        var zones: [String]
        var delay: String?
        var isActive: Bool

        private enum CodingKeys: String, CodingKey {
            case name, description, specialties, priceMin, priceMax, modes, zones, delay, isActive
        }

        /// Cleared fields go out as null so the server clears them too; a
        /// missing key would mean "leave as it was".
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(specialties, forKey: .specialties)
            try c.encode(priceMin, forKey: .priceMin)
            try c.encode(priceMax, forKey: .priceMax)
            try c.encode(modes, forKey: .modes)
            try c.encode(zones, forKey: .zones)
            try c.encode(delay, forKey: .delay)
            try c.encode(isActive, forKey: .isActive)
        }
    }

    func updateService(_ id: String, _ body: ServiceUpdate) async throws -> ProSpace {
        try await api.patch("/data/pro/services/\(id)", body: body)
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

import Foundation

/// How a service is delivered (backend `ServiceMode`).
enum ServiceMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case home = "HOME"
    case onSite = "ON_SITE"
    case online = "ONLINE"
    case delivery = "DELIVERY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "À domicile"
        case .onSite: "Sur place"
        case .online: "En ligne"
        case .delivery: "Livraison"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .onSite: "storefront"
        case .online: "globe"
        case .delivery: "shippingbox"
        }
    }
}

/// Where a request stands (backend `RequestStatus`).
enum RequestStatus: String, Sendable {
    case draft = "DRAFT"
    case matching = "MATCHING"
    case sent = "SENT"
    case responded = "RESPONDED"
    case locked = "LOCKED"
    case selected = "SELECTED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case noMatch = "NO_MATCH"
    case noResponse = "NO_RESPONSE"
    case unknown

    var label: String {
        switch self {
        case .draft: "Brouillon"
        case .matching: "Recherche en cours"
        case .sent: "Envoyée"
        case .responded: "Réponses reçues"
        case .locked: "Réponses complètes"
        case .selected: "Professionnel retenu"
        case .completed: "Terminée"
        case .cancelled: "Annulée"
        case .noMatch: "Aucun professionnel"
        case .noResponse: "Sans réponse"
        case .unknown: "—"
        }
    }

    /// Pros' answers are in and the member is choosing among them.
    var isChoosing: Bool { self == .sent || self == .responded || self == .locked }

    /// Over: no more messages, and "Relancer cette demande" is offered.
    var isClosed: Bool { self == .completed || self == .cancelled || self == .noMatch || self == .noResponse }

    /// Still going: shown under "En cours" rather than "Terminées".
    var isOpen: Bool {
        switch self {
        case .draft, .matching, .sent, .responded, .locked, .selected: true
        default: false
        }
    }
}

/// A pro's side of one request (backend `DispatchStatus`).
enum DispatchStatus: String, Sendable {
    case sent = "SENT"
    case viewed = "VIEWED"
    case interested = "INTERESTED"
    case question = "QUESTION"
    case unavailable = "UNAVAILABLE"
    case declined = "DECLINED"
    case selected = "SELECTED"
    case lost = "LOST"
    case unknown

    var label: String {
        switch self {
        case .sent: "Nouvelle"
        case .viewed: "Vue"
        case .interested: "Proposition envoyée"
        case .question: "Question posée"
        case .unavailable: "Pas disponible"
        case .declined: "Déclinée"
        case .selected: "Retenu"
        case .lost: "Close"
        case .unknown: "—"
        }
    }

    /// The pro can still answer.
    var isOpen: Bool { self == .sent || self == .viewed || self == .question }
}

/// One line of the conversation between a requester and a pro (Data §10).
struct ConversationMessage: Identifiable, Sendable, Equatable, Decodable {
    enum Author: String, Sendable { case pro = "PRO", requester = "REQUESTER" }
    var id: String
    var author: Author
    var text: String
    var createdAt: Date

    private enum CodingKeys: String, CodingKey { case id, author, text, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? UUID().uuidString
        author = Author(rawValue: c.string(.author) ?? "") ?? .pro
        text = c.string(.text) ?? ""
        createdAt = c.date(.createdAt) ?? .now
    }
}

/// The dispatch states in which the pro and the requester can still talk.
extension DispatchStatus {
    var canTalk: Bool { self == .question || self == .interested || self == .selected }
}

/// A request as its author sees it, with the pros' answers (backend `RequestView`).
struct ServiceRequestItem: Identifiable, Sendable, Hashable {
    var id: String
    var rawText: String
    var status: RequestStatus
    var profession: String?
    var service: String?
    var specialties: [String]
    var city: String?
    var district: String?
    var mode: ServiceMode?
    var desiredDate: String?
    var desiredTime: String?
    var budget: Int?
    var constraints: [String]
    var clarificationQuestion: String?
    var clarificationOptions: [String]
    var clarificationAnswer: String?
    var createdAt: Date
    var dispatchedCount: Int
    var responses: [RequestResponse]

    /// What to call the request in a list: the AI's service name, else the text.
    var title: String {
        if let service, !service.isEmpty { return service }
        return rawText
    }

    var subtitle: String {
        [[district, city].compactMap { $0 }.joined(separator: ", "), mode?.label, desiredDate]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var needsAnswer: Bool { clarificationQuestion != nil && clarificationAnswer == nil }

    /// Not while a chosen pro is waiting to do the job: that one is closed
    /// through "Prestation terminée ?" first.
    var canDelete: Bool { status != .selected }

    /// What deleting does, said before the member confirms.
    var deleteWarning: String {
        switch status {
        case .draft: "Le brouillon sera supprimé."
        case .matching, .sent, .responded: "La demande sera annulée pour les professionnels, puis retirée de ta liste."
        default: "La demande sera retirée de ta liste."
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.status == b.status && a.responses == b.responses }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One pro's answer, shown as a card to compare (backend `ResponseView`).
struct RequestResponse: Identifiable, Sendable, Equatable {
    var id: String // dispatchId
    var status: DispatchStatus
    var proUserId: String
    var proSbcUserId: String
    var name: String?
    var avatarUrl: String?
    var profession: String
    var city: String
    var whatsapp: String?
    var shopUrl: String
    var confidenceScore: Int
    var reviewCount: Int
    var serviceName: String?
    var price: Int?
    var availability: String?
    var delay: String?
    var message: String?
    var messages: [ConversationMessage] = []

    var displayName: String { name?.isEmpty == false ? name! : profession }
}

/// A request a pro received (backend `InboxItemView`). Carries the need, never
/// who asked.
struct InboxItem: Identifiable, Sendable, Hashable {
    var id: String // dispatchId
    var status: DispatchStatus
    var matchedService: String?
    var request: ServiceRequestItem
    var price: Int?
    var availability: String?
    var delay: String?
    var message: String?
    var createdAt: Date
    var viewedAt: Date?
    var respondedAt: Date?
    var messages: [ConversationMessage] = []

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.status == b.status && a.messages.count == b.messages.count && a.request.status == b.request.status
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What a pro adds on top of their SBC profile.
struct ProProfile: Sendable, Equatable {
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
    var receivingEnabled: Bool
    var receivingUntil: Date?
}

struct ProServiceItem: Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var category: String
    var profession: String
    var synonyms: [String]
    var specialties: [String]
    var priceMin: Int?
    var priceMax: Int?
    var isActive: Bool
    var description: String?
    var modes: [ServiceMode] = []
    var zones: [String] = []
    var delay: String?
}

/// Profile + services + whether requests are coming in (backend `ProProfileView`).
struct ProSpace: Sendable, Equatable {
    var profile: ProProfile?
    var phoneNumber: String?
    var services: [ProServiceItem]
    var receivingActive: Bool
}

/// What a pro still has to do before requests can reach them.
enum ProSetupItem: Hashable, Sendable {
    case profile
    case services

    var todo: String {
        switch self {
        case .profile: "Compléter mon profil (métier, ville, disponibilité, boutique)"
        case .services: "Ajouter au moins un service"
        }
    }
}

extension ProProfile {
    /// Every field matching relies on is really filled in — not blank, not a
    /// placeholder such as "À compléter".
    var isComplete: Bool {
        !isPlaceholder(profession) && !isPlaceholder(city) && !isPlaceholder(availability)
            && !isPlaceholder(description) && description.count >= 10
            && !modes.isEmpty
            && !isPlaceholder(shopUrl) && isRealLink(shopUrl)
    }
}

extension ProSpace {
    /// Empty for a complete pro, and for someone who is not a pro at all.
    var missingSetup: [ProSetupItem] {
        guard let profile else { return [] }
        var out: [ProSetupItem] = []
        if !profile.isComplete { out.append(.profile) }
        if !services.contains(where: \.isActive) { out.append(.services) }
        return out
    }
}

/// An http(s) link that is not a stand-in like example.com.
func isRealLink(_ value: String) -> Bool {
    guard let url = URL(string: value.trimmingCharacters(in: .whitespaces)),
          url.scheme?.hasPrefix("http") == true, let host = url.host(), host.contains(".")
    else { return false }
    return !["example.com", "example.org", "example.net"].contains { host == $0 || host.hasSuffix("." + $0) }
}

/// Blank, or a stand-in someone typed to fill the field ("À compléter").
func isPlaceholder(_ value: String) -> Bool {
    let folded = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return folded.isEmpty || folded.hasPrefix("a completer") || folded == "-" || folded == "..."
}

/// A service the AI proposes; the pro keeps, edits or drops it.
struct ServiceProposal: Identifiable, Sendable, Equatable, Codable {
    var id = UUID()
    var name: String
    var category: String
    var profession: String
    var synonyms: [String]
    var specialties: [String]

    private enum CodingKeys: String, CodingKey { case name, category, profession, synonyms, specialties }
}

struct StructuredServices: Sendable {
    var profession: String
    var category: String
    var services: [ServiceProposal]
}

/// "Mes statistiques" (backend `ProStats`).
struct ProStats: Sendable, Equatable {
    var received = 0
    var responded = 0
    var interested = 0
    var selected = 0
    var completed = 0
    var responseRate = 0.0
    var conversionRate = 0.0
    var topServices: [(name: String, count: Int)] = []

    static func == (a: Self, b: Self) -> Bool {
        a.received == b.received && a.responded == b.responded && a.selected == b.selected
    }
}

// MARK: - Decoding

extension ServiceRequestItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, rawText, status, profession, service, specialties, city, district, mode, desiredDate,
             desiredTime, budget, constraints, clarificationQuestion, clarificationOptions,
             clarificationAnswer, createdAt, dispatchedCount, responses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        rawText = c.string(.rawText) ?? ""
        status = RequestStatus(rawValue: c.string(.status) ?? "") ?? .unknown
        profession = c.string(.profession)
        service = c.string(.service)
        specialties = c.strings(.specialties)
        city = c.string(.city)
        district = c.string(.district)
        mode = c.string(.mode).flatMap(ServiceMode.init(rawValue:))
        desiredDate = c.string(.desiredDate)
        desiredTime = c.string(.desiredTime)
        budget = c.int(.budget)
        constraints = c.strings(.constraints)
        clarificationQuestion = c.string(.clarificationQuestion)
        clarificationOptions = c.strings(.clarificationOptions)
        clarificationAnswer = c.string(.clarificationAnswer)
        createdAt = c.date(.createdAt) ?? .now
        dispatchedCount = c.int(.dispatchedCount) ?? 0
        responses = ((try? c.decodeIfPresent([Lossy<RequestResponse>].self, forKey: .responses)) ?? []).compactMap(\.value)
    }
}

extension RequestResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case dispatchId, status, pro, serviceName, price, availability, delay, message, messages
    }

    private enum ProKeys: String, CodingKey {
        case userId, sbcUserId, name, avatarUrl, profession, city, whatsapp, shopUrl, confidenceScore, reviewCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let p = try c.nestedContainer(keyedBy: ProKeys.self, forKey: .pro)
        id = c.string(.dispatchId) ?? ""
        status = DispatchStatus(rawValue: c.string(.status) ?? "") ?? .unknown
        proUserId = p.string(.userId) ?? ""
        proSbcUserId = p.string(.sbcUserId) ?? ""
        name = p.string(.name)
        avatarUrl = p.string(.avatarUrl)
        profession = p.string(.profession) ?? ""
        city = p.string(.city) ?? ""
        whatsapp = p.string(.whatsapp)
        shopUrl = p.string(.shopUrl) ?? ""
        confidenceScore = p.int(.confidenceScore) ?? 50
        reviewCount = p.int(.reviewCount) ?? 0
        serviceName = c.string(.serviceName)
        price = c.int(.price)
        availability = c.string(.availability)
        delay = c.string(.delay)
        message = c.string(.message)
        messages = ((try? c.decodeIfPresent([Lossy<ConversationMessage>].self, forKey: .messages)) ?? []).compactMap(\.value)
    }
}

extension InboxItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case dispatchId, status, matchedService, request, price, availability, delay, message, createdAt,
             viewedAt, respondedAt, messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.dispatchId) ?? ""
        status = DispatchStatus(rawValue: c.string(.status) ?? "") ?? .unknown
        matchedService = c.string(.matchedService)
        request = try c.decode(ServiceRequestItem.self, forKey: .request)
        price = c.int(.price)
        availability = c.string(.availability)
        delay = c.string(.delay)
        message = c.string(.message)
        createdAt = c.date(.createdAt) ?? .now
        viewedAt = c.date(.viewedAt)
        respondedAt = c.date(.respondedAt)
        messages = ((try? c.decodeIfPresent([Lossy<ConversationMessage>].self, forKey: .messages)) ?? []).compactMap(\.value)
    }
}

extension ProSpace: Decodable {
    private enum CodingKeys: String, CodingKey { case profile, identity, services, receivingActive }
    private enum IdentityKeys: String, CodingKey { case phoneNumber }
    private enum ProfileKeys: String, CodingKey {
        case profession, description, city, zones, modes, availability, priceMin, priceMax, shopUrl,
             whatsapp, receivingEnabled, receivingUntil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let p = try? c.nestedContainer(keyedBy: ProfileKeys.self, forKey: .profile) {
            profile = ProProfile(
                profession: p.string(.profession) ?? "",
                description: p.string(.description) ?? "",
                city: p.string(.city) ?? "",
                zones: p.strings(.zones),
                modes: p.strings(.modes).compactMap(ServiceMode.init(rawValue:)),
                availability: p.string(.availability) ?? "",
                priceMin: p.int(.priceMin),
                priceMax: p.int(.priceMax),
                shopUrl: p.string(.shopUrl) ?? "",
                whatsapp: p.string(.whatsapp),
                receivingEnabled: p.bool(.receivingEnabled) ?? false,
                receivingUntil: p.date(.receivingUntil)
            )
        } else {
            profile = nil
        }
        phoneNumber = (try? c.nestedContainer(keyedBy: IdentityKeys.self, forKey: .identity))?.string(.phoneNumber)
        services = ((try? c.decodeIfPresent([Lossy<ProServiceItem>].self, forKey: .services)) ?? []).compactMap(\.value)
        receivingActive = c.bool(.receivingActive) ?? false
    }
}

extension ProServiceItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, category, profession, synonyms, specialties, priceMin, priceMax, isActive,
             description, modes, zones, delay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        name = c.string(.name) ?? ""
        category = c.string(.category) ?? ""
        profession = c.string(.profession) ?? ""
        synonyms = c.strings(.synonyms)
        specialties = c.strings(.specialties)
        priceMin = c.int(.priceMin)
        priceMax = c.int(.priceMax)
        isActive = c.bool(.isActive) ?? true
        description = c.string(.description)
        modes = c.strings(.modes).compactMap(ServiceMode.init(rawValue:))
        zones = c.strings(.zones)
        delay = c.string(.delay)
    }
}

extension StructuredServices: Decodable {
    private enum CodingKeys: String, CodingKey { case profession, category, services }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profession = c.string(.profession) ?? ""
        category = c.string(.category) ?? ""
        services = ((try? c.decodeIfPresent([Lossy<ServiceProposal>].self, forKey: .services)) ?? []).compactMap(\.value)
    }
}

extension ProStats: Decodable {
    private enum CodingKeys: String, CodingKey {
        case received, responded, interested, selected, completed, responseRate, conversionRate, topServices
    }

    private struct Top: Decodable {
        let name: String
        let count: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        received = c.int(.received) ?? 0
        responded = c.int(.responded) ?? 0
        interested = c.int(.interested) ?? 0
        selected = c.int(.selected) ?? 0
        completed = c.int(.completed) ?? 0
        responseRate = c.double(.responseRate) ?? 0
        conversionRate = c.double(.conversionRate) ?? 0
        topServices = ((try? c.decodeIfPresent([Top].self, forKey: .topServices)) ?? []).map { ($0.name, $0.count) }
    }
}

/// "15 000 FCFA", with the non-breaking thousands separator French uses.
func fcfa(_ amount: Int) -> String {
    "\(amount.formatted(.number.locale(Locale(identifier: "fr_FR")))) FCFA"
}

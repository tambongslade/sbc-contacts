import Foundation

/// Saved sync criteria (backend `SyncCriteria`).
struct SyncCriteria: Identifiable, Sendable, Equatable {
    var id: String
    var label: String
    var countries: [String] = []
    var cities: [String] = []
    var professions: [String] = []
    var interests: [String] = []
    var sex: String?
    var ageMin: Int?
    var ageMax: Int?
    var isActive = true
    var lastMatchCount = 0

    var payload: CriteriaPayload {
        CriteriaPayload(
            label: label, countries: countries, cities: cities, professions: professions,
            interests: interests, sex: sex, ageMin: ageMin, ageMax: ageMax, isActive: isActive
        )
    }
}

extension SyncCriteria: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, label, countries, cities, professions, interests, sex, ageMin, ageMax, isActive, lastMatchCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        label = c.string(.label) ?? ""
        countries = c.strings(.countries)
        cities = c.strings(.cities)
        professions = c.strings(.professions)
        interests = c.strings(.interests)
        sex = c.string(.sex)
        ageMin = c.int(.ageMin)
        ageMax = c.int(.ageMax)
        isActive = c.bool(.isActive) ?? true
        lastMatchCount = c.int(.lastMatchCount) ?? 0
    }
}

/// One person who saved YOU to their phone (cahier §21). Only confirmed device
/// writes reach this list, so "X t'a enregistré" is a fact, not an inference.
struct SavedMeEntry: Identifiable, Sendable, Equatable {
    var actorSbcId: String
    var savedAt: Date
    var name: String?
    var profession: String?
    var city: String?
    var country: String?
    var avatarUrl: String?
    var phoneNumber: String?

    /// Whether you have already saved them back.
    var alreadySaved = false

    var id: String { actorSbcId }

    var displayName: String {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Membre SBC" : n
    }

    var location: String {
        [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension SavedMeEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case actorSbcId, savedAt, name, profession, city, country, avatarUrl, phoneNumber
        case alreadySaved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actorSbcId = c.string(.actorSbcId) ?? ""
        savedAt = c.date(.savedAt) ?? Date()
        name = c.string(.name)
        profession = c.string(.profession)
        city = c.string(.city)
        country = c.string(.country)
        avatarUrl = c.string(.avatarUrl)
        phoneNumber = c.string(.phoneNumber)
        alreadySaved = c.bool(.alreadySaved) ?? false
    }
}

/// Body for create / update / ad-hoc preview.
struct CriteriaPayload: Encodable, Sendable, Equatable {
    var label: String
    var countries: [String]
    /// The backend mirrors SBC's `region` into Member.city, so régions go here.
    var cities: [String]
    var professions: [String]
    var interests: [String]
    var sex: String?
    var ageMin: Int?
    var ageMax: Int?
    var isActive: Bool?

    private enum CodingKeys: String, CodingKey {
        case label, countries, cities, professions, interests, sex, ageMin, ageMax, isActive
    }

    /// `ageMin` / `ageMax` are sent as explicit nulls: on an update, leaving the
    /// keys out would keep whatever range the criteria already had.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(countries, forKey: .countries)
        try c.encode(cities, forKey: .cities)
        try c.encode(professions, forKey: .professions)
        try c.encode(interests, forKey: .interests)
        try c.encodeIfPresent(sex, forKey: .sex)
        try c.encode(ageMin, forKey: .ageMin)
        try c.encode(ageMax, forKey: .ageMax)
        try c.encodeIfPresent(isActive, forKey: .isActive)
    }
}

/// A member proposed for synchronisation, with the backend dedup hint.
struct SyncTarget: Sendable, Equatable {
    var memberSbcId: String
    var name: String?
    var firstName: String?
    var profession: String?
    var city: String?
    var country: String?
    var avatarUrl: String?
    var phoneNumber: String?
    var alreadySynced = false

    var displayName: String {
        [firstName, name].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

extension SyncTarget: Decodable {
    private enum CodingKeys: String, CodingKey {
        case memberSbcId, name, firstName, profession, city, country, avatarUrl, phoneNumber, alreadySynced
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberSbcId = c.string(.memberSbcId) ?? ""
        name = c.string(.name)
        firstName = c.string(.firstName)
        profession = c.string(.profession)
        city = c.string(.city)
        country = c.string(.country)
        avatarUrl = c.string(.avatarUrl)
        phoneNumber = c.string(.phoneNumber)
        alreadySynced = c.bool(.alreadySynced) ?? false
    }
}

/// Result of starting a sync run.
struct SyncRunStart: Sendable {
    var syncRunId: String
    var deviceId: String
    var matchCount: Int
    var pendingCount: Int
    var items: [SyncTarget]
}

extension SyncRunStart: Decodable {
    private enum CodingKeys: String, CodingKey {
        case syncRunId, deviceId, matchCount, pendingCount, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncRunId = c.string(.syncRunId) ?? ""
        deviceId = c.string(.deviceId) ?? ""
        matchCount = c.int(.matchCount) ?? 0
        pendingCount = c.int(.pendingCount) ?? 0
        items = ((try? c.decodeIfPresent([Lossy<SyncTarget>].self, forKey: .items)) ?? []).compactMap(\.value)
    }
}

/// One outcome reported back after writing to the phone book.
struct SyncRunResult: Encodable, Sendable, Equatable {
    enum Status: String, Encodable, Sendable {
        case synced = "SYNCED", failed = "FAILED"
    }

    var memberSbcId: String
    var deviceContactId: String?
    var status: Status
}

/// "Mes contacts SBC" dashboard counters.
struct SyncSummary: Sendable, Equatable {
    var syncedCount = 0
    var pendingCount = 0
    var failedCount = 0
    var activeCriteria = 0

    /// Every criterion, active or paused — the denominator of the dashboard ring.
    var criteriaCount = 0
    var currentMatches = 0
    var favoritesCount = 0

    /// How many members have saved your contact (§21).
    var savedMeCount = 0
    var lastSyncAt: Date?
}

extension SyncSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case syncedCount, pendingCount, failedCount, activeCriteria, criteriaCount
        case currentMatches, favoritesCount, savedMeCount, lastSyncAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncedCount = c.int(.syncedCount) ?? 0
        pendingCount = c.int(.pendingCount) ?? 0
        failedCount = c.int(.failedCount) ?? 0
        activeCriteria = c.int(.activeCriteria) ?? 0
        // Falls back to the active count so an older backend still renders a
        // sane "N / M critères" instead of "3 / 0".
        criteriaCount = c.int(.criteriaCount) ?? activeCriteria
        currentMatches = c.int(.currentMatches) ?? 0
        favoritesCount = c.int(.favoritesCount) ?? 0
        savedMeCount = c.int(.savedMeCount) ?? 0
        lastSyncAt = c.date(.lastSyncAt)
    }
}

/// One member already written (or attempted) to a device — "Mes contacts SBC"
/// (cahier §16). `status` mirrors the backend SyncStatus enum.
struct SyncedContact: Identifiable, Sendable, Equatable {
    var memberSbcId: String
    var status: String
    var name: String?
    var firstName: String?
    var profession: String?
    var city: String?
    var country: String?
    var avatarUrl: String?
    var phoneNumber: String?
    var syncedAt: Date?

    var id: String { memberSbcId }

    var displayName: String {
        let n = [firstName, name].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Membre SBC" : n
    }

    var location: String {
        [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension SyncedContact: Decodable {
    private enum CodingKeys: String, CodingKey {
        case memberSbcId, status, name, firstName, profession, city, country, avatarUrl, phoneNumber, syncedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberSbcId = c.string(.memberSbcId) ?? ""
        status = c.string(.status) ?? "PENDING"
        name = c.string(.name)
        firstName = c.string(.firstName)
        profession = c.string(.profession)
        city = c.string(.city)
        country = c.string(.country)
        avatarUrl = c.string(.avatarUrl)
        phoneNumber = c.string(.phoneNumber)
        syncedAt = c.date(.syncedAt)
    }
}

/// One synchronisation run, for the history view (cahier §17).
struct SyncRunEntry: Identifiable, Sendable, Equatable {
    var id: String
    var status: String
    var matchCount: Int
    var syncedCount: Int
    var failedCount: Int
    var error: String?
    var startedAt: Date?
    var finishedAt: Date?
}

extension SyncRunEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, matchCount, syncedCount, failedCount, error, startedAt, finishedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        status = c.string(.status) ?? "PENDING"
        matchCount = c.int(.matchCount) ?? 0
        syncedCount = c.int(.syncedCount) ?? 0
        failedCount = c.int(.failedCount) ?? 0
        error = c.string(.error)
        startedAt = c.date(.startedAt)
        finishedAt = c.date(.finishedAt)
    }
}

import Foundation

/// Combinable directory filters (cahier §6).
struct SearchFilters: Sendable, Equatable {
    var search: String?
    /// ISO 3166-1 alpha-2 (e.g. "CM"), not a display name.
    var country: String?
    /// The member's real location field in SBC — coarser than `city` and the
    /// one that actually has data (658 distinct values across countries).
    var region: String?
    var city: String?
    var profession: String?
    var sex: String?
    var ageMin: Int?
    var ageMax: Int?
    var interests: [String] = []

    /// Order each page by "score de confiance" instead of SBC's own relevance
    /// order. Not counted as a filter: it changes the order of the results, not
    /// which members are in them.
    var sortByConfidence = false

    var isEmpty: Bool {
        (search?.isEmpty ?? true)
            && country == nil && region == nil && city == nil && profession == nil
            && sex == nil && ageMin == nil && ageMax == nil && interests.isEmpty
    }

    /// Query string for `/directory/search`; `interests` repeats its key.
    func queryItems(page: Int, limit: Int) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let search, !search.isEmpty { items.append(.init(name: "search", value: search)) }
        if let country { items.append(.init(name: "country", value: country)) }
        if let region { items.append(.init(name: "region", value: region)) }
        if let city { items.append(.init(name: "city", value: city)) }
        if let profession { items.append(.init(name: "profession", value: profession)) }
        if let sex { items.append(.init(name: "sex", value: sex)) }
        if let ageMin { items.append(.init(name: "ageMin", value: String(ageMin))) }
        if let ageMax { items.append(.init(name: "ageMax", value: String(ageMax))) }
        items += interests.map { URLQueryItem(name: "interests", value: $0) }
        if sortByConfidence { items.append(.init(name: "sort", value: "confidence")) }
        return items
    }
}

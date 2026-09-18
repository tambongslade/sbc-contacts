import Foundation

/// One human-readable, removable filter derived from `SearchFilters`.
struct ActiveFilter: Identifiable, Hashable {
    enum Kind: Hashable {
        case country, region, city, profession, sex, age, interest
    }

    let kind: Kind
    let systemImage: String
    let label: String
    /// Only used by `.interest`, where each entry is removable on its own.
    var value: String?

    var id: String { "\(kind)-\(value ?? label)" }

    static func of(_ f: SearchFilters) -> [ActiveFilter] {
        var out: [ActiveFilter] = []
        if let c = f.country { out.append(.init(kind: .country, systemImage: "globe", label: FilterOptions.countryLabel(c))) }
        if let r = f.region { out.append(.init(kind: .region, systemImage: "mappin.and.ellipse", label: r)) }
        if let c = f.city { out.append(.init(kind: .city, systemImage: "building.2", label: c)) }
        if let p = f.profession { out.append(.init(kind: .profession, systemImage: "briefcase", label: p)) }
        if let s = f.sex { out.append(.init(kind: .sex, systemImage: "person", label: FilterOptions.sexLabel(s))) }
        if f.ageMin != nil || f.ageMax != nil {
            out.append(.init(kind: .age, systemImage: "birthday.cake", label: "\(f.ageMin ?? 16) – \(f.ageMax ?? 80) ans"))
        }
        for i in f.interests {
            out.append(.init(kind: .interest, systemImage: "heart", label: i, value: i))
        }
        return out
    }

    /// `SearchFilters` without this one filter, everything else untouched.
    func removed(from f: SearchFilters) -> SearchFilters {
        var next = f
        switch kind {
        case .country: next.country = nil
        case .region: next.region = nil
        case .city: next.city = nil
        case .profession: next.profession = nil
        case .sex: next.sex = nil
        case .age:
            next.ageMin = nil
            next.ageMax = nil
        case .interest: next.interests.removeAll { $0 == value }
        }
        return next
    }
}

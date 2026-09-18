import Foundation
import Observation

/// One région of one country, with how many members live there
/// (backend `GET /directory/regions`).
struct RegionEntry: Decodable, Sendable, Equatable {
    let country: String
    let region: String
    let count: Int

    private enum CodingKeys: String, CodingKey { case country, region, count }

    init(country: String, region: String, count: Int) {
        self.country = country
        self.region = region
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = (c.string(.country) ?? "").uppercased()
        region = c.string(.region) ?? ""
        count = c.int(.count) ?? 0
    }
}

/// Which régions belong to which country.
struct RegionCatalog: Sendable, Equatable {
    /// ISO code → régions, most-populated first.
    let byCountry: [String: [String]]
    /// Every région, most-populated first — offered when no pays is chosen.
    let all: [String]

    init(entries: [RegionEntry]) {
        var grouped: [String: [(String, Int)]] = [:]
        var totals: [String: Int] = [:]
        for e in entries where !e.country.isEmpty && !e.region.isEmpty {
            grouped[e.country, default: []].append((e.region, e.count))
            totals[e.region, default: 0] += e.count
        }
        byCountry = grouped.mapValues { $0.sorted { $0.1 > $1.1 }.map(\.0) }
        all = totals.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    /// The built-in mapping of the 60 most common régions, used until the
    /// backend list arrives (or if it cannot be reached).
    static let builtIn = RegionCatalog(entries: FilterOptions.topRegions.enumerated().flatMap { index, region in
        (FilterOptions.regionCountries[region] ?? []).map {
            RegionEntry(country: $0, region: region, count: FilterOptions.topRegions.count - index)
        }
    })

    /// Régions of any of `countries`; all régions when none is chosen.
    func regions(for countries: Set<String>) -> [String] {
        guard !countries.isEmpty else { return all }
        var seen = Set<String>()
        return countries.sorted().flatMap { byCountry[$0] ?? [] }.filter { seen.insert($0).inserted }
    }

    /// False only for a région known to belong exclusively to other countries.
    /// Free-typed names the catalog has never seen are left alone.
    func region(_ region: String, belongsTo countries: Set<String>) -> Bool {
        guard !countries.isEmpty else { return true }
        let owners = byCountry.filter { $0.value.contains(region) }.keys
        return owners.isEmpty || !Set(owners).isDisjoint(with: countries)
    }
}

/// Loads the région catalog once per session.
@MainActor
@Observable
final class RegionsStore {
    private(set) var catalog = RegionCatalog.builtIn
    /// True once the backend list replaced the built-in one.
    private(set) var isLive = false

    private let repo: DirectoryRepository
    private var loading = false

    init(repo: DirectoryRepository) {
        self.repo = repo
    }

    func loadIfNeeded() async {
        guard !isLive, !loading else { return }
        loading = true
        defer { loading = false }
        // Endpoint not deployed yet, or offline: keep the built-in catalog.
        guard let entries = try? await repo.regions(), !entries.isEmpty else { return }
        catalog = RegionCatalog(entries: entries)
        isLive = true
    }
}

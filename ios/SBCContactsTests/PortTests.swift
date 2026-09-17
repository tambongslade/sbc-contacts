import Foundation
import Testing
@testable import SBCContacts

struct ContactNameTests {
    @Test func splitsFirstWordAndAppendsSBC() {
        let parts = ContactService.nameParts("Claude Durel")
        #expect(parts.given == "Claude")
        #expect(parts.family == "Durel SBC")
    }

    @Test func singleWordGetsSBCAsFamilyName() {
        #expect(ContactService.nameParts("Claude") == ("Claude", "SBC"))
    }

    @Test func doesNotSuffixTwice() {
        #expect(ContactService.nameParts("Claude Durel SBC").family == "Durel SBC")
    }

    @Test func emptyNameFallsBack() {
        #expect(ContactService.nameParts("   ") == ("Membre", "SBC"))
    }
}

struct CriteriaPayloadTests {
    @Test func sendsExplicitNullAgeWhenDisabled() throws {
        let payload = CriteriaPayload(label: "Test", countries: ["CM"], cities: [], professions: [], interests: [], sex: nil, ageMin: nil, ageMax: nil)
        let json = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
        #expect(json.contains("\"ageMin\":null"))
        #expect(json.contains("\"ageMax\":null"))
        #expect(!json.contains("\"sex\""))
    }
}

struct SearchFiltersTests {
    @Test func repeatsInterestsAndAddsSort() {
        let filters = SearchFilters(country: "CM", interests: ["Football", "Lecture"], sortByConfidence: true)
        let items = filters.queryItems(page: 2, limit: 20)
        #expect(items.filter { $0.name == "interests" }.map(\.value) == ["Football", "Lecture"])
        #expect(items.contains(URLQueryItem(name: "sort", value: "confidence")))
        #expect(items.contains(URLQueryItem(name: "page", value: "2")))
    }

    @Test func omitsSortByDefault() {
        #expect(!SearchFilters().queryItems(page: 1, limit: 20).contains { $0.name == "sort" })
    }

    @Test func regionScopedToCountry() {
        #expect(FilterOptions.regionsFor("SN") == ["Dakar", "Thiès"])
        #expect(!FilterOptions.regionMatchesCountry("Dakar", "CM"))
        #expect(FilterOptions.regionMatchesCountry("Centre", "BF"))
        // Free-typed régions are outside the table and always allowed.
        #expect(FilterOptions.regionMatchesCountry("Wouri", "CM"))
    }

    @Test func criteriaRegionsFollowSelectedCountries() {
        let cm = FilterOptions.regionsFor(countries: ["CM"])
        #expect(cm.contains("Littoral") && cm.contains("Extrême-Nord"))
        #expect(!cm.contains("Dakar") && !cm.contains("Abidjan"))
        #expect(Set(FilterOptions.regionsFor(countries: ["CM", "SN"])).isSuperset(of: ["Dakar", "Ouest"]))
        // No mapped région: nothing from other countries is offered.
        #expect(FilterOptions.regionsFor(countries: ["FR"]).isEmpty)
        #expect(FilterOptions.regionsFor(countries: []).count == FilterOptions.topRegions.count)
        #expect(!FilterOptions.regionMatches("Dakar", countries: ["CM", "CI"]))
        #expect(FilterOptions.regionMatches("Savanes", countries: ["CI"]))
    }

    @Test @MainActor func compactMemberCount() {
        #expect(SearchView.compact(47_011) == "47k")
        #expect(SearchView.compact(999) == "999")
    }
}

struct RegionCatalogTests {
    private let catalog = RegionCatalog(entries: [
        RegionEntry(country: "CM", region: "Littoral", count: 800),
        RegionEntry(country: "CM", region: "Ouest", count: 400),
        RegionEntry(country: "BF", region: "Centre", count: 300),
        RegionEntry(country: "CM", region: "Centre", count: 600),
        RegionEntry(country: "FR", region: "Île-de-France", count: 40),
    ])

    @Test func regionsOfOneCountryMostPopulatedFirst() {
        #expect(catalog.regions(for: ["CM"]) == ["Littoral", "Centre", "Ouest"])
        #expect(catalog.regions(for: ["FR"]) == ["Île-de-France"])
        #expect(catalog.regions(for: ["SN"]).isEmpty)
    }

    @Test func noCountryOffersEverythingOnce() {
        // "Centre" exists in two countries but is listed once, by combined count.
        #expect(catalog.all == ["Centre", "Littoral", "Ouest", "Île-de-France"])
    }

    @Test func membership() {
        #expect(catalog.region("Centre", belongsTo: ["BF"]))
        #expect(!catalog.region("Littoral", belongsTo: ["FR"]))
        #expect(catalog.region("Wouri", belongsTo: ["CM"]))
        #expect(catalog.region("Littoral", belongsTo: []))
    }

    @Test func builtInMatchesStaticMapping() {
        #expect(RegionCatalog.builtIn.regions(for: ["SN"]) == ["Dakar", "Thiès"])
        #expect(RegionCatalog.builtIn.all.count == FilterOptions.topRegions.count)
    }

    @Test func decodesBackendPayload() throws {
        let json = #"{"country": "cm", "region": "Littoral", "count": 12}"#
        let entry = try JSONDecoder().decode(RegionEntry.self, from: Data(json.utf8))
        #expect(entry == RegionEntry(country: "CM", region: "Littoral", count: 12))
    }
}

struct DecodingTests {
    @Test func memberDecodesLeniently() throws {
        let json = #"{"id": 12, "name": "Durel", "age": 31.0, "interests": ["Yoga", 3], "reviewCount": 2}"#
        let member = try JSONDecoder().decode(Member.self, from: Data(json.utf8))
        #expect(member.sbcId == "12")
        #expect(member.age == 31)
        #expect(member.interests == ["Yoga", "3"])
        #expect(member.confidenceScore == 50)
    }

    @Test func paginatedSkipsUnusableItems() throws {
        let json = #"{"items": [{"id": "a"}, 42, {"id": "b"}], "total": 9, "hasMore": true}"#
        let page = try JSONDecoder().decode(Paginated<Member>.self, from: Data(json.utf8))
        #expect(page.items.map(\.id) == ["a", "b"])
        #expect(page.total == 9)
        #expect(page.hasMore)
    }

    @Test func savedMeEntryDecodes() throws {
        let json = #"{"actorSbcId": "x1", "savedAt": "2026-09-01T10:00:00.000Z", "name": "Awa", "city": "Dakar", "country": "SN"}"#
        let entry = try JSONDecoder().decode(SavedMeEntry.self, from: Data(json.utf8))
        #expect(entry.displayName == "Awa")
        #expect(entry.location == "Dakar, SN")
        // Absent means "not saved back": the row must offer "Ajouter", not
        // claim the contact is already in the phone book.
        #expect(entry.alreadySaved == false)
    }

    @Test func savedMeEntryCarriesTheReciprocal() throws {
        let json = #"{"actorSbcId": "x1", "savedAt": "2026-09-01T10:00:00.000Z", "alreadySaved": true}"#
        let entry = try JSONDecoder().decode(SavedMeEntry.self, from: Data(json.utf8))
        #expect(entry.alreadySaved)
    }

    @Test func summaryDecodesTheDashboardCounters() throws {
        let json = #"{"syncedCount": 3, "activeCriteria": 2, "criteriaCount": 5, "currentMatches": 9, "favoritesCount": 4, "savedMeCount": 7}"#
        let summary = try JSONDecoder().decode(SyncSummary.self, from: Data(json.utf8))
        #expect(summary.criteriaCount == 5)
        #expect(summary.favoritesCount == 4)
        #expect(summary.savedMeCount == 7)
    }

    @Test func summaryFallsBackToActiveCriteriaOnAnOlderBackend() throws {
        // Without the fallback the ring would read "2 / 0" against a backend
        // that has not shipped `criteriaCount` yet.
        let json = #"{"activeCriteria": 2}"#
        let summary = try JSONDecoder().decode(SyncSummary.self, from: Data(json.utf8))
        #expect(summary.criteriaCount == 2)
    }

    @Test func envelopeIsUnwrapped() throws {
        let data = APIClient.unwrap(Data(#"{"success": true, "data": {"count": 4}}"#.utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Int]
        #expect(object == ["count": 4])
    }
}

/// The pre-filled WhatsApp message (cahier §8). Pre-filled, never sent.
struct WhatsAppGreetingTests {
    @Test func addressesTheMemberByName() {
        #expect(whatsAppGreeting(for: "Awa Diop")
            == "Salut Awa Diop, je vous contacte à partir de l'application SBC network.")
    }

    @Test func greetsWithoutANameRatherThanWithABlank() {
        let expected = "Salut, je vous contacte à partir de l'application SBC network."
        #expect(whatsAppGreeting(for: nil) == expected)
        #expect(whatsAppGreeting(for: "   ") == expected)
    }

    @Test func trimsTheNameSBCGaveUs() {
        #expect(whatsAppGreeting(for: "  Awa  ").hasPrefix("Salut Awa,"))
    }
}

#if DEBUG
import Foundation

/// Debug-only offline mode: launch with `-demo` to run the whole app on canned
/// data (no SBC login, no network), so screens can be checked in the simulator.
enum DemoMode {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demo")

    /// Which tab to open on launch — `-tab synchro`. Lets a screen be checked
    /// in the simulator without driving the UI, which needs accessibility
    /// permissions a build machine does not have.
    static var initialTab: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1].lowercased()
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let payload = Self.payload(for: path, query: request.url?.query ?? "")
        let body = try? JSONSerialization.data(withJSONObject: ["success": true, "statusCode": 200, "data": payload])
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        // A little latency, so loading states are visible.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body ?? Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static let names = [
        ("Claude", "Durel"), ("Awa", "Diop"), ("Jean Paul", "Mbarga"), ("Fatou", "Sow"),
        ("Koffi", "Mensah"), ("Aïcha", "Traoré"), ("Serge", "Nkoulou"), ("Mariam", "Keita"),
        ("Didier", "Kouassi"), ("Nadège", "Ateba"), ("Ibrahim", "Ouédraogo"), ("Grâce", "Mabiala"),
    ]
    private static let places = [("Littoral", "CM"), ("Dakar", "SN"), ("Centre", "CM"), ("Abidjan", "CI"), ("Maritime", "TG"), ("Ouest", "CM")]
    private static let jobs = ["Designer graphique", "Enseignant", "Comptable", "Electricien", "Developpeur de logiciels", nil]

    private static func member(_ i: Int) -> [String: Any] {
        let (first, last) = names[i % names.count]
        let (city, country) = places[i % places.count]
        var m: [String: Any] = [
            "id": "demo-\(i)", "sbcId": "demo-\(i)", "firstName": first, "name": last,
            "city": city, "country": country, "sex": i % 2 == 0 ? "male" : "female", "age": 22 + i % 30,
            "interests": ["Football", "Lecture", "Programmation"].prefix(1 + i % 3).map { $0 },
            "skills": ["Photoshop", "Excel"], "phoneNumber": i % 4 == 3 ? NSNull() : "+2376990000\(10 + i)",
            "isFavorite": i % 5 == 1, "isSynced": i % 6 == 2,
            "confidenceScore": [50, 82, 64, 45, 91, 30][i % 6], "reviewCount": i % 3 == 0 ? 0 : 3 + i % 4,
            "averageRating": 4.2,
        ]
        if let job = jobs[i % jobs.count] { m["profession"] = job }
        return m
    }

    private static func page(_ items: [Any], total: Int? = nil) -> [String: Any] {
        let t = total ?? items.count
        return ["items": items, "total": t, "page": 1, "limit": 20, "totalPages": max(1, t / 20), "hasMore": t > items.count]
    }

    private static func payload(for path: String, query: String) -> Any {
        let now = ISO8601DateFormatter().string(from: Date())
        switch true {
        case path.hasSuffix("/auth/me"), path.hasSuffix("/auth/me/refresh-profile"):
            return ["id": "u1", "sbcUserId": "me", "name": "Tambong Kersten", "email": "demo@sbc.test",
                    "phoneNumber": "+237699000000", "country": "CM", "subscriptionTypes": ["CIBLE"], "isActivated": true, "role": "USER"]
        case path.hasSuffix("/notifications/unread-count"):
            return ["count": 2]
        case path.hasSuffix("/notifications"):
            return page([
                ["id": "n1", "type": "CONTACT_SAVED", "title": "Quelqu'un t'a enregistré", "body": "Awa Diop vient d'ajouter ton contact à son répertoire.", "createdAt": now],
                ["id": "n2", "type": "NEW_MATCH", "title": "3 nouveaux membres", "body": "Ils correspondent à « Designers de Douala ».", "createdAt": now, "readAt": now],
            ])
        case path.hasSuffix("/directory/search"):
            return page((0..<20).map(member), total: 48_124)
        case path.contains("/directory/members/"):
            return member(Int(path.split(separator: "-").last ?? "0") ?? 0)
        case path.hasSuffix("/directory/regions"):
            return ["regions": [
                ["country": "CM", "region": "Littoral", "count": 812], ["country": "CM", "region": "Centre", "count": 640],
                ["country": "CM", "region": "Ouest", "count": 410], ["country": "SN", "region": "Dakar", "count": 530],
                ["country": "FR", "region": "Île-de-France", "count": 44], ["country": "FR", "region": "Auvergne-Rhône-Alpes", "count": 12],
            ]]
        case path.contains("/reviews/"):
            return ["items": [["id": "r1", "memberSbcId": "demo-1", "stars": 5, "comment": "Très sérieux, livraison à temps.", "reviewerName": "Koffi Mensah", "createdAt": now]],
                    "summary": ["averageStars": 5, "reviewCount": 1, "confidenceScore": 82], "hasMore": false, "page": 1]
        case path.hasSuffix("/favorites"):
            return page((0..<3).map { i -> [String: Any] in
                var m = member(i * 2 + 1)
                m["memberSbcId"] = m["sbcId"]
                return m
            })
        case path.hasSuffix("/sync/summary"):
            return ["syncedCount": 124, "pendingCount": 6, "failedCount": 1, "activeCriteria": 2, "currentMatches": 342]
        case path.hasSuffix("/sync/criteria"):
            return [
                ["id": "c1", "label": "Designers de Douala", "countries": ["CM"], "cities": ["Littoral"], "professions": ["Designer graphique"], "interests": [], "lastMatchCount": 58],
                ["id": "c2", "label": "Enseignants Sénégal", "countries": ["SN"], "cities": [], "professions": ["Enseignant"], "interests": ["Lecture"], "lastMatchCount": 211],
            ]
        case path.hasSuffix("/matches"):
            return page((0..<8).map(member))
        case path.hasSuffix("/sync/history"):
            return page([["id": "h1", "status": "COMPLETED", "matchCount": 58, "syncedCount": 55, "failedCount": 1, "startedAt": now]])
        case path.hasSuffix("/sync/contacts"):
            return page((0..<5).map { i -> [String: Any] in
                var m = member(i)
                m["memberSbcId"] = m["sbcId"]
                m["status"] = ["SYNCED", "PENDING", "FAILED", "SYNCED", "STALE"][i]
                return m
            })
        case path.hasSuffix("/sync/saved-me"):
            return page([["actorSbcId": "demo-1", "savedAt": now, "name": "Awa Diop", "profession": "Comptable", "city": "Dakar", "country": "SN", "phoneNumber": "+221770000000"]])
        case path.hasSuffix("/preview"):
            return ["matchCount": 42]
        default:
            return [String: Any]()
        }
    }
}
#endif

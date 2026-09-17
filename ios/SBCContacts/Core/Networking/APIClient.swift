import Foundation

/// Talks to the SBC Network backend.
///
/// Responsibilities (same contract as the Flutter `ApiClient`):
/// - attach the app access token to every non-auth request,
/// - unwrap the backend's `{ success, data }` envelope,
/// - convert every failure into `APIError`,
/// - transparently refresh the token on 401 (single-flight) and retry once.
actor APIClient {
    enum Method: String, Sendable {
        case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
    }

    private let baseURL: URL
    private let storage: TokenStorage
    private let session: URLSession
    private var refreshing: Task<Bool, Never>?

    init(baseURL: URL = AppConfig.apiBaseURL, storage: TokenStorage, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.storage = storage
        self.session = session
    }

    // MARK: - Typed helpers

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try decode(try await send(.get, path, query: query))
    }

    func post<T: Decodable & Sendable>(_ path: String, body: (some Encodable & Sendable)? = Empty?.none) async throws -> T {
        try decode(try await send(.post, path, body: encode(body)))
    }

    func patch<T: Decodable & Sendable>(_ path: String, body: some Encodable & Sendable) async throws -> T {
        try decode(try await send(.patch, path, body: encode(body)))
    }

    func delete<T: Decodable & Sendable>(_ path: String) async throws -> T {
        try decode(try await send(.delete, path))
    }

    /// Fire-and-check variants for endpoints whose payload is not used.
    func post(_ path: String, body: (some Encodable & Sendable)? = Empty?.none) async throws {
        _ = try await send(.post, path, body: encode(body))
    }

    func delete(_ path: String) async throws {
        _ = try await send(.delete, path)
    }

    // MARK: - Core

    /// Performs the request and returns the unwrapped `data` payload as JSON.
    func send(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        retried: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path, query: query))
        request.httpMethod = method.rawValue
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        if !Self.isAuthPath(path), let access = await storage.readAccess() {
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }

        let (data, status) = try await perform(request)
        #if DEBUG
        print("[API] \(method.rawValue) \(request.url?.absoluteString ?? path) → \(status) (\(data.count) B)")
        if !(200..<300).contains(status) {
            print("[API]   body: \(String(decoding: data.prefix(500), as: UTF8.self))")
        }
        #endif

        if status == 401, !Self.isAuthPath(path), !retried {
            if await refreshOnce() {
                return try await send(method, path, query: query, body: body, retried: true)
            }
        }

        guard (200..<300).contains(status) else {
            throw Self.error(status: status, data: data)
        }
        return Self.unwrap(data)
    }

    // MARK: - Refresh

    /// Concurrent 401s share one refresh round-trip.
    private func refreshOnce() async -> Bool {
        if let refreshing { return await refreshing.value }
        let task = Task { await doRefresh() }
        refreshing = task
        let ok = await task.value
        refreshing = nil
        return ok
    }

    private func doRefresh() async -> Bool {
        guard let refresh = await storage.readRefresh() else { return false }
        do {
            var request = URLRequest(url: url(for: "/auth/refresh", query: []))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["refreshToken": refresh])
            let (data, status) = try await perform(request)
            guard (200..<300).contains(status) else { throw Self.error(status: status, data: data) }
            let tokens = try JSONDecoder().decode(TokenPair.self, from: Self.unwrap(data))
            await storage.save(access: tokens.accessToken, refresh: tokens.refreshToken)
            return true
        } catch {
            await storage.clear() // session is dead; force re-login
            return false
        }
    }

    // MARK: - Plumbing

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw APIError(statusCode: 0, message: error.localizedDescription.isEmpty ? "Network error" : error.localizedDescription)
        }
    }

    private func url(for path: String, query: [URLQueryItem]) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let full = baseURL.appendingPathComponent(trimmed)
        guard !query.isEmpty, var components = URLComponents(url: full, resolvingAgainstBaseURL: false) else {
            return full
        }
        // URLComponents leaves "+" alone, which servers decode as a space.
        components.percentEncodedQueryItems = query.map {
            URLQueryItem(name: Self.encodeQuery($0.name), value: $0.value.map(Self.encodeQuery))
        }
        return components.url ?? full
    }

    private static func encodeQuery(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func isAuthPath(_ path: String) -> Bool {
        path.contains("/auth/sso-callback") || path.contains("/auth/refresh")
    }

    /// `{ data: X }` → X, anything else is returned as-is.
    static func unwrap(_ data: Data) -> Data {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dict = object as? [String: Any],
              let inner = dict["data"],
              let innerData = try? JSONSerialization.data(withJSONObject: inner, options: [.fragmentsAllowed])
        else { return data }
        return innerData
    }

    static func error(status: Int, data: Data) -> APIError {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return APIError(statusCode: status, message: "Request failed")
        }
        let message: String
        switch object["message"] {
        case let s as String: message = s
        case let list as [Any]: message = list.map { "\($0)" }.joined(separator: ", ")
        case let other?: message = "\(other)"
        case nil: message = "Request failed"
        }
        return APIError(statusCode: status, message: message, code: object["code"] as? String)
    }

    private func encode(_ body: (some Encodable & Sendable)?) throws -> Data? {
        guard let body else { return nil }
        return try JSONEncoder().encode(body)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == Empty.self, let empty = Empty() as? T { return empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[API] decode \(T.self) failed: \(error)")
            print("[API]   payload: \(String(decoding: data.prefix(800), as: UTF8.self))")
            #endif
            throw APIError(statusCode: 200, message: "Réponse inattendue du serveur")
        }
    }
}

/// Placeholder for "no body" / "ignore the payload".
struct Empty: Codable, Sendable {}

private struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
}

import Foundation
import Security

/// Holds the app session tokens (our own, not SBC's — SBC tokens live only on
/// the backend). Abstracted so tests can swap in an in-memory implementation.
protocol TokenStorage: Sendable {
    func readAccess() async -> String?
    func readRefresh() async -> String?
    func save(access: String, refresh: String) async
    func clear() async
}

/// Keychain-backed storage, readable after first unlock.
struct KeychainTokenStorage: TokenStorage {
    private let service = "com.sbc.sbcContacts.session"
    private static let accessKey = "sbc_access"
    private static let refreshKey = "sbc_refresh"

    func readAccess() async -> String? { read(Self.accessKey) }
    func readRefresh() async -> String? { read(Self.refreshKey) }

    func save(access: String, refresh: String) async {
        write(Self.accessKey, access)
        write(Self.refreshKey, refresh)
    }

    func clear() async {
        delete(Self.accessKey)
        delete(Self.refreshKey)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery(key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}

/// Volatile store for tests and previews.
actor InMemoryTokenStorage: TokenStorage {
    private var access: String?
    private var refresh: String?

    init(access: String? = nil, refresh: String? = nil) {
        self.access = access
        self.refresh = refresh
    }

    func readAccess() -> String? { access }
    func readRefresh() -> String? { refresh }

    func save(access: String, refresh: String) {
        self.access = access
        self.refresh = refresh
    }

    func clear() {
        access = nil
        refresh = nil
    }
}

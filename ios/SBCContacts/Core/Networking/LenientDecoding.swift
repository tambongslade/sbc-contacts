import Foundation

/// Defensive JSON reads, matching the Flutter models: the SBC field set is not
/// fully frozen, so a missing or oddly-typed field falls back to a default
/// instead of failing the whole payload.
extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func int(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    func double(_ key: Key) -> Double? {
        try? decodeIfPresent(Double.self, forKey: key)
    }

    func bool(_ key: Key) -> Bool? {
        try? decodeIfPresent(Bool.self, forKey: key)
    }

    /// Any JSON array, each element stringified; anything else → `[]`.
    func strings(_ key: Key) -> [String] {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [String] = []
        while !list.isAtEnd {
            if let s = try? list.decode(String.self) {
                out.append(s)
            } else if let i = try? list.decode(Int.self) {
                out.append(String(i))
            } else if let d = try? list.decode(Double.self) {
                out.append(String(d))
            } else {
                _ = try? list.decode(Discard.self)
            }
        }
        return out
    }

    func date(_ key: Key) -> Date? {
        guard let raw = string(key) else { return nil }
        return ISO8601.parse(raw)
    }
}

enum ISO8601 {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parse(_ raw: String) -> Date? {
        (try? fractional.parse(raw)) ?? (try? plain.parse(raw))
    }
}

/// Consumes one JSON value of any shape (used to skip unusable elements).
struct Discard: Decodable {}

/// Decodes a `T`, or records that the element was unusable, without aborting
/// the surrounding array (Dart's `whereType<Map>().map(fromJson)`).
struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

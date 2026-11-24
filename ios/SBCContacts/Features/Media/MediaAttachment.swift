import Foundation

/// A photo, video or PDF sent with a request, a proposal or a message
/// (backend `AttachmentView`). `path` is a signed link below the API host,
/// resolved with `APIClient.mediaURL(_:)`.
struct MediaAttachment: Identifiable, Sendable, Hashable, Decodable {
    enum Kind: String, Sendable {
        case image = "IMAGE", video = "VIDEO", file = "FILE"
    }

    var id: String
    var kind: Kind
    var mimeType: String
    var size: Int
    var fileName: String?
    var width: Int?
    var height: Int?
    var durationSec: Double?
    var path: String

    private enum CodingKeys: String, CodingKey {
        case id, kind, mimeType, size, fileName, width, height, durationSec, url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? UUID().uuidString
        kind = Kind(rawValue: c.string(.kind) ?? "") ?? .file
        mimeType = c.string(.mimeType) ?? "application/octet-stream"
        size = c.int(.size) ?? 0
        fileName = c.string(.fileName)
        width = c.int(.width)
        height = c.int(.height)
        durationSec = c.double(.durationSec)
        path = c.string(.url) ?? ""
    }

    /// "1,2 Mo"
    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// "0:42"
    var durationLabel: String? {
        guard let durationSec, durationSec > 0 else { return nil }
        let total = Int(durationSec.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var displayName: String {
        fileName?.nilIfBlank ?? (kind == .file ? "Document.pdf" : kind == .video ? "Vidéo" : "Photo")
    }
}

extension KeyedDecodingContainer {
    /// The `attachments` array of a view; unusable elements are skipped.
    func attachments(_ key: Key) -> [MediaAttachment] {
        ((try? decodeIfPresent([Lossy<MediaAttachment>].self, forKey: key)) ?? []).compactMap(\.value)
    }
}

/// `/media`: uploads and "Signaler".
struct MediaRepository: Sendable {
    let api: APIClient

    struct Upload: Sendable {
        var data: Data
        var fileName: String
        var mimeType: String
        var width: Int?
        var height: Int?
        var durationSec: Double?
    }

    func upload(_ file: Upload) async throws -> MediaAttachment {
        var fields: [String: String] = ["fileName": file.fileName]
        if let w = file.width { fields["width"] = String(w) }
        if let h = file.height { fields["height"] = String(h) }
        if let d = file.durationSec { fields["durationSec"] = String(format: "%.2f", d) }
        return try await api.upload("/media", file: file.data, fileName: file.fileName, mimeType: file.mimeType, fields: fields)
    }

    private struct ReportBody: Encodable, Sendable { let reason: String? }

    func report(_ id: String, reason: String? = nil) async throws {
        try await api.post("/media/\(id)/report", body: ReportBody(reason: reason))
    }

    func url(_ attachment: MediaAttachment) -> URL? {
        api.mediaURL(attachment.path)
    }
}

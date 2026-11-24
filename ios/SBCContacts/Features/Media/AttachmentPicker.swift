import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The attachments being added to something not sent yet (a request, a
/// proposal, a message). Each file is uploaded as soon as it is picked, so
/// "Envoyer" only has to pass the ids along.
@MainActor
@Observable
final class AttachmentDraft {
    struct Item: Identifiable {
        enum State {
            case preparing
            case uploading
            case done(MediaAttachment)
            case failed(String)
        }

        let id = UUID()
        var kind: MediaAttachment.Kind
        var name: String
        var preview: UIImage?
        var state: State

        var attachment: MediaAttachment? {
            if case let .done(a) = state { return a }
            return nil
        }
    }

    /// What one request, proposal or message may carry (the server's rule too).
    static let limit = 5

    private(set) var items: [Item] = []
    /// The last thing that went wrong, shown under the row.
    var error: String?

    var canAdd: Bool { items.count < Self.limit }
    var remaining: Int { max(0, Self.limit - items.count) }
    var isBusy: Bool {
        items.contains {
            switch $0.state {
            case .preparing, .uploading: true
            default: false
            }
        }
    }

    /// Ids to send, in the order they were added.
    var ids: [String] { items.compactMap(\.attachment?.id) }
    var isEmpty: Bool { items.isEmpty }

    func remove(_ id: Item.ID) {
        items.removeAll { $0.id == id }
    }

    func reset() {
        items = []
        error = nil
    }

    /// Prepares (shrinks, converts) and uploads one picked file.
    func add(_ source: PickedSource, using media: MediaRepository) {
        guard canAdd else {
            error = "\(Self.limit) pièces jointes maximum."
            return
        }
        error = nil
        let item = Item(kind: source.kind, name: source.kind == .file ? "Document" : "", state: .preparing)
        items.append(item)
        let id = item.id
        Task {
            do {
                let prepared = try await MediaPreparation.prepare(source)
                update(id) {
                    $0.preview = prepared.preview
                    $0.name = prepared.upload.fileName
                    $0.state = .uploading
                }
                let attachment = try await media.upload(prepared.upload)
                update(id) { $0.state = .done(attachment) }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                update(id) { $0.state = .failed(message) }
                self.error = message
            }
        }
    }

    private func update(_ id: Item.ID, _ change: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return } // removed meanwhile
        change(&items[i])
    }
}

/// Something the member picked, before it is prepared for upload.
enum PickedSource: Sendable {
    case photo(Data)
    case cameraPhoto(UIImage)
    case video(URL)
    case pdf(URL)

    var kind: MediaAttachment.Kind {
        switch self {
        case .photo, .cameraPhoto: .image
        case .video: .video
        case .pdf: .file
        }
    }
}

struct MediaError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Turns a pick into what the server accepts: photos at most 2048 px as JPEG,
/// videos at most 60 s as 720p MP4 under 50 Mo, PDFs under 20 Mo.
enum MediaPreparation {
    struct Prepared: Sendable {
        var upload: MediaRepository.Upload
        var preview: UIImage?
    }

    static let maxPhotoSide: CGFloat = 2048
    static let maxVideoSeconds: Double = 60
    static let maxVideoBytes = 50 * 1024 * 1024
    static let maxPDFBytes = 20 * 1024 * 1024

    nonisolated static func prepare(_ source: PickedSource) async throws -> Prepared {
        switch source {
        case let .photo(data):
            guard let image = UIImage(data: data) else { throw MediaError("Cette photo ne peut pas être lue.") }
            return try photo(image)
        case let .cameraPhoto(image):
            return try photo(image)
        case let .video(url):
            return try await video(url)
        case let .pdf(url):
            return try pdf(url)
        }
    }

    nonisolated private static func photo(_ image: UIImage) throws -> Prepared {
        let scaled = downscaled(image, maxSide: maxPhotoSide)
        guard let data = scaled.jpegData(compressionQuality: 0.8) else {
            throw MediaError("Cette photo ne peut pas être préparée.")
        }
        let stamp = Int(Date().timeIntervalSince1970)
        return Prepared(
            upload: .init(
                data: data,
                fileName: "photo-\(stamp).jpg",
                mimeType: "image/jpeg",
                width: Int(scaled.size.width * scaled.scale),
                height: Int(scaled.size.height * scaled.scale)
            ),
            preview: downscaled(scaled, maxSide: 240)
        )
    }

    /// Redrawn upright at scale 1, so camera photos lose their EXIF rotation.
    nonisolated static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let ratio = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    nonisolated private static func video(_ url: URL) async throws -> Prepared {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MediaError("Cette vidéo ne peut pas être lue.") }
        guard duration <= maxVideoSeconds + 0.5 else {
            throw MediaError("Vidéo trop longue : 60 secondes maximum.")
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("video-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw MediaError("Cette vidéo ne peut pas être convertie.")
        }
        session.shouldOptimizeForNetworkUse = true
        if #available(iOS 18, *) {
            try await session.export(to: out, as: .mp4)
        } else {
            session.outputURL = out
            session.outputFileType = .mp4
            await session.export()
            if session.status != .completed {
                throw MediaError(session.error?.localizedDescription ?? "La conversion de la vidéo a échoué.")
            }
        }
        defer { try? FileManager.default.removeItem(at: out) }
        let data = try Data(contentsOf: out)
        guard data.count <= maxVideoBytes else { throw MediaError("Vidéo trop lourde : 50 Mo maximum.") }

        let converted = AVURLAsset(url: out)
        var width: Int?
        var height: Int?
        if let track = try? await converted.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            width = Int(abs(rect.width))
            height = Int(abs(rect.height))
        }
        let preview = await VideoFrames.first(of: converted)
        return Prepared(
            upload: .init(
                data: data,
                fileName: "video-\(Int(Date().timeIntervalSince1970)).mp4",
                mimeType: "video/mp4",
                width: width,
                height: height,
                durationSec: duration
            ),
            preview: preview
        )
    }

    nonisolated private static func pdf(_ url: URL) throws -> Prepared {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= maxPDFBytes else { throw MediaError("Fichier trop lourd : 20 Mo maximum.") }
        guard data.starts(with: Data("%PDF-".utf8)) else { throw MediaError("Seuls les fichiers PDF sont acceptés.") }
        return Prepared(
            upload: .init(data: data, fileName: url.lastPathComponent, mimeType: "application/pdf"),
            preview: nil
        )
    }
}

/// A still from a video, for its tile.
enum VideoFrames {
    nonisolated static func first(of asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        guard let frame = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image else {
            return nil
        }
        return UIImage(cgImage: frame)
    }
}

/// A movie from the photo library, copied out of the picker's temporary file.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// "📎": Caméra / Photos et vidéos / Fichier PDF. Each pick is prepared and
/// uploaded into `draft` right away.
struct AttachButton: View {
    let draft: AttachmentDraft
    var label: String = "Joindre"

    @Environment(\.services) private var services
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Menu {
            if cameraAvailable {
                Button { showCamera = true } label: { Label("Caméra", systemImage: "camera") }
            }
            Button { showLibrary = true } label: { Label("Photos et vidéos", systemImage: "photo.on.rectangle") }
            Button { showFiles = true } label: { Label("Fichier PDF", systemImage: "doc") }
        } label: {
            Label(label, systemImage: "paperclip")
                .font(.sbc(.labelLarge, weight: .semibold))
                .foregroundStyle(draft.canAdd ? SBCColors.primary : SBCColors.onSurfaceVariant)
        }
        .disabled(!draft.canAdd)
        .accessibilityLabel("Joindre une photo, une vidéo ou un PDF")
        .photosPicker(
            isPresented: $showLibrary,
            selection: $picked,
            maxSelectionCount: max(1, draft.remaining),
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .compatible
        )
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await load(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result { draft.add(.pdf(url), using: services.media) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { source in
                if let source { draft.add(source, using: services.media) }
            }
            .ignoresSafeArea()
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                if isVideo {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { continue }
                    draft.add(.video(movie.url), using: services.media)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    draft.add(.photo(data), using: services.media)
                }
            } catch {
                draft.error = "Ce fichier ne peut pas être ouvert."
            }
        }
    }
}

/// The system camera, for a photo or a video of 60 s at most.
private struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (PickedSource?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoMaximumDuration = MediaPreparation.maxVideoSeconds
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (PickedSource?) -> Void
        init(onDone: @escaping (PickedSource?) -> Void) { self.onDone = onDone }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                onDone(.video(url))
            } else if let image = info[.originalImage] as? UIImage {
                onDone(.cameraPhoto(image))
            } else {
                onDone(nil)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
            picker.dismiss(animated: true)
        }
    }
}

/// The picked files before sending: a thumbnail each, a spinner while it
/// uploads, a cross to remove it.
struct PendingAttachmentsRow: View {
    let draft: AttachmentDraft

    var body: some View {
        if !draft.isEmpty || draft.error != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !draft.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(draft.items) { item in
                                PendingTile(item: item) { draft.remove(item.id) }
                            }
                        }
                        .padding(.top, 6)
                        .padding(.trailing, 6)
                    }
                }
                if let error = draft.error {
                    Text(error)
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.error)
                }
            }
        }
    }
}

private struct PendingTile: View {
    let item: AttachmentDraft.Item
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SBCColors.primaryContainer)
                if let preview = item.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: item.kind == .file ? "doc.fill" : item.kind == .video ? "video.fill" : "photo")
                            .font(.system(size: 20))
                        if item.kind == .file, !item.name.isEmpty {
                            Text(item.name).font(.sbc(.labelSmall)).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(SBCColors.primary)
                    .padding(4)
                }
                if item.kind == .video, item.preview != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                switch item.state {
                case .preparing, .uploading:
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                case .failed:
                    Color.black.opacity(0.45)
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                case .done:
                    EmptyView()
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, SBCColors.onSurface.opacity(0.75))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Retirer")
        }
    }
}

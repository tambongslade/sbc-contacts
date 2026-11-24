import AVKit
import QuickLook
import SwiftUI

/// Attachments as tiles: photos and videos in a grid, PDFs as rows. A tap
/// opens the viewer; a long press offers "Signaler".
struct AttachmentGallery: View {
    let attachments: [MediaAttachment]
    /// Tile edge; bubbles use smaller ones.
    var tile: CGFloat = 96
    /// In a bubble: fixed tiles, two per row, so the gallery is only as wide
    /// as its tiles and lines up with its side of the conversation.
    var compact = false

    @Environment(\.services) private var services
    @Environment(ToastCenter.self) private var toasts
    @State private var viewing: MediaAttachment?
    @State private var reporting: MediaAttachment?

    private var visual: [MediaAttachment] { attachments.filter { $0.kind != .file } }
    private var files: [MediaAttachment] { attachments.filter { $0.kind == .file } }

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !visual.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(visual) { a in
                            Button { viewing = a } label: { VisualTile(attachment: a) }
                                .buttonStyle(.plain)
                                .aspectRatio(1, contentMode: .fit)
                                .contextMenu { reportButton(a) }
                        }
                    }
                }
                ForEach(files) { a in
                    Button { viewing = a } label: { FileRow(attachment: a) }
                        .buttonStyle(.plain)
                        .contextMenu { reportButton(a) }
                }
            }
            .fullScreenCover(item: $viewing) { a in
                MediaViewer(attachment: a) { reporting = a }
            }
            .confirmReport($reporting, services: services, toasts: toasts)
        }
    }

    private var columns: [GridItem] {
        compact
            ? Array(repeating: GridItem(.fixed(tile), spacing: 6), count: min(2, max(1, visual.count)))
            : [GridItem(.adaptive(minimum: tile, maximum: tile * 1.6), spacing: 6)]
    }

    private func reportButton(_ a: MediaAttachment) -> some View {
        Button(role: .destructive) { reporting = a } label: {
            Label("Signaler", systemImage: "exclamationmark.bubble")
        }
    }
}

extension View {
    /// "Signaler ce contenu ?" then the report call, with a toast either way.
    func confirmReport(_ target: Binding<MediaAttachment?>, services: AppServices, toasts: ToastCenter) -> some View {
        confirmationDialog(
            "Signaler ce contenu ?",
            isPresented: Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: target.wrappedValue
        ) { a in
            Button("Contenu inapproprié", role: .destructive) { report(a, "Contenu inapproprié", services, toasts) }
            Button("Arnaque ou spam", role: .destructive) { report(a, "Arnaque ou spam", services, toasts) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("L'équipe SBC Network examinera ce fichier.")
        }
    }

    private func report(_ a: MediaAttachment, _ reason: String, _ services: AppServices, _ toasts: ToastCenter) {
        Task {
            do {
                try await services.media.report(a.id, reason: reason)
                toasts.show("Merci, le contenu a été signalé.")
            } catch {
                toasts.show(error.localizedDescription)
            }
        }
    }
}

private struct VisualTile: View {
    let attachment: MediaAttachment
    @Environment(\.services) private var services

    var body: some View {
        Color.clear
            .overlay {
                switch attachment.kind {
                case .video:
                    VideoThumbnail(attachment: attachment)
                default:
                    AsyncImage(url: services.media.url(attachment)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            Image(systemName: "photo").foregroundStyle(SBCColors.onSurfaceVariant)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .background(SBCColors.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(attachment.kind == .video ? "Vidéo" : "Photo")
    }
}

/// A still from the remote video, with a play badge and its length.
private struct VideoThumbnail: View {
    let attachment: MediaAttachment
    @Environment(\.services) private var services
    @State private var frame: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let frame {
                Image(uiImage: frame).resizable().scaledToFill()
            } else {
                Color.black.opacity(0.75)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let duration = attachment.durationLabel {
                Text(duration)
                    .font(.sbc(.labelSmall, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(5)
            }
        }
        .task(id: attachment.id) {
            if let cached = ThumbnailCache.shared[attachment.id] {
                frame = cached
                return
            }
            guard let url = services.media.url(attachment) else { return }
            if let image = await VideoFrames.first(of: AVURLAsset(url: url)) {
                ThumbnailCache.shared[attachment.id] = image
                frame = image
            }
        }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()
    subscript(id: String) -> UIImage? {
        get { cache.object(forKey: id as NSString) }
        set { if let newValue { cache.setObject(newValue, forKey: id as NSString) } }
    }
}

private struct FileRow: View {
    let attachment: MediaAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 20))
                .foregroundStyle(SBCColors.error)
                .frame(width: 38, height: 38)
                .background(SBCColors.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(.sbc(.bodyMedium, weight: .semibold))
                    .foregroundStyle(SBCColors.onSurface)
                    .lineLimit(1)
                Text("PDF · \(attachment.sizeLabel)")
                    .font(.sbc(.labelSmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(SBCColors.onSurfaceVariant)
        }
        .padding(8)
        .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SBCColors.outlineVariant))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Full screen: a zoomable photo, the video player, or the PDF in QuickLook.
struct MediaViewer: View {
    let attachment: MediaAttachment
    let onReport: () -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = services.media.url(attachment) {
                    switch attachment.kind {
                    case .image: ZoomableImage(url: url)
                    case .video: VideoPlayerView(url: url)
                    case .file: PDFPreview(url: url, name: attachment.displayName)
                    }
                } else {
                    Text("Lien invalide").foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(attachment.kind == .file ? Color(.systemBackground) : .black)
            .navigationTitle(attachment.kind == .file ? attachment.displayName : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(attachment.kind == .file ? .automatic : .visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(attachment.kind == .file ? 0 : 0.6), for: .navigationBar)
            .toolbarColorScheme(attachment.kind == .file ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            dismiss()
                            // After the cover is gone, so the dialog can show.
                            Task {
                                try? await Task.sleep(for: .milliseconds(450))
                                onReport()
                            }
                        } label: {
                            Label("Signaler", systemImage: "exclamationmark.bubble")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Plus d'options")
                }
            }
        }
    }
}

private struct ZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, min(5, lastScale * $0.magnification)) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 { withAnimation { offset = .zero }; lastOffset = .zero }
                            }
                            .simultaneously(with: DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                                    height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset })
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            scale = scale > 1 ? 1 : 2.5
                            lastScale = scale
                            if scale == 1 { offset = .zero; lastOffset = .zero }
                        }
                    }
                    .accessibilityLabel("Photo")
            } else if phase.error != nil {
                Label("Impossible de charger la photo", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
    }
}

private struct VideoPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}

/// Downloads the PDF to a temporary file, then shows it with QuickLook.
private struct PDFPreview: View {
    let url: URL
    let name: String
    @State private var local: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let local {
                QuickLookView(url: local)
            } else if failed {
                EmptyStateView(systemImage: "doc", title: "Document indisponible", message: "Réessaie plus tard.")
            } else {
                ProgressView("Ouverture du document…")
            }
        }
        .task {
            do {
                let (temp, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MediaError("HTTP") }
                let safe = name.replacingOccurrences(of: "/", with: "-")
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent(safe.lowercased().hasSuffix(".pdf") ? safe : "\(safe).pdf")
                try FileManager.default.moveItem(at: temp, to: dest)
                local = dest
            } catch {
                failed = true
            }
        }
    }
}

private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

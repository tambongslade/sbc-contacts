import SwiftUI

/// Historique de synchronisation (cahier §17): date, nombre de contacts
/// synchronisés et résultat de l'opération.
struct SyncHistoryView: View {
    @Environment(\.services) private var services

    private enum LoadState {
        case loading
        case loaded([SyncRunEntry])
        case failed(Error)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        content
            .background(SBCColors.background)
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ListSkeleton(hasLeading: false)
        case let .failed(error):
            EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription) {
                Button("Réessayer") { Task { await load() } }
                    .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        case let .loaded(runs) where runs.isEmpty:
            EmptyStateView(
                systemImage: "clock.arrow.circlepath",
                title: "Aucune synchronisation",
                message: "Les synchronisations effectuées apparaîtront ici."
            )
        case let .loaded(runs):
            List(runs) { RunRow(run: $0).listRowBackground(SBCColors.surface) }
                .listStyle(.plain)
                .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await services.sync.history().items)
        } catch {
            state = .failed(error)
        }
    }
}

private struct RunRow: View {
    let run: SyncRunEntry

    private static let dateFormat = Date.FormatStyle()
        .day().month(.abbreviated).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        .locale(Locale(identifier: "fr_FR"))

    var body: some View {
        let (icon, colour): (String, Color) = switch run.status {
        case "COMPLETED": ("checkmark.circle.fill", SBCColors.secondary)
        case "FAILED": ("exclamationmark.circle", SBCColors.error)
        case "RUNNING": ("arrow.triangle.2.circlepath", SBCColors.primary)
        default: ("clock", SBCColors.accent)
        }
        let detail = [
            "\(run.syncedCount) synchronisé(s)",
            run.failedCount > 0 ? "\(run.failedCount) échec(s)" : nil,
            "sur \(run.matchCount) correspondance(s)",
        ].compactMap { $0 }.joined(separator: " · ")

        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(colour)
                .accessibilityLabel(run.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.startedAt?.formatted(Self.dateFormat) ?? "—")
                    .font(.sbc(.bodyLarge))
                    .foregroundStyle(SBCColors.onSurface)
                Text(detail)
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                if let error = run.error {
                    Text(error)
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.error)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

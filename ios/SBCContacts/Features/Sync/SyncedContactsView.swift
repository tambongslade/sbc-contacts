import SwiftUI

/// "Mes contacts SBC" (cahier §16): what has been written to the phone, and
/// with what outcome. Filterable by sync status.
struct SyncedContactsView: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    private enum LoadState {
        case loading
        case loaded([SyncedContact])
        case failed(Error)
    }

    private static let filters: [(status: String?, label: String)] = [
        (nil, "Tous"),
        ("SYNCED", "Synchronisés"),
        ("PENDING", "En attente"),
        ("FAILED", "Échecs"),
        ("STALE", "À mettre à jour"),
    ]

    @State private var status: String?
    @State private var state: LoadState = .loading

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.filters, id: \.label) { filter in
                        SelectableChip(label: filter.label, selected: status == filter.status) {
                            status = filter.status
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Divider()
            content.frame(maxHeight: .infinity)
        }
        .background(SBCColors.background)
        .navigationTitle("Mes contacts SBC")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: status) {
            state = .loading
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ListSkeleton()
        case let .failed(error):
            EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription) {
                Button("Réessayer") { Task { await load() } }
                    .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        // "Empty" means two different things: the chosen status matches nothing
        // (say so), or nothing was ever synced (say what to do about it).
        case let .loaded(items) where items.isEmpty && status != nil:
            let label = Self.filters.first { $0.status == status }?.label ?? ""
            EmptyStateView(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "Aucun contact « \(label) »",
                message: "Tes contacts enregistrés sont là, mais aucun n'a ce statut pour le moment."
            ) {
                Button("Voir tous les contacts") { status = nil }
                    .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        case let .loaded(items) where items.isEmpty:
            EmptyStateView(
                systemImage: "person.text.rectangle",
                title: "Aucun contact enregistré",
                message: "Cette liste se remplit après une synchronisation : choisis un critère, appuie sur « Synchroniser », et les membres écrits dans ton répertoire apparaîtront ici avec leur statut."
            ) {
                Button { dismiss() } label: {
                    Label("Aller aux critères", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        case let .loaded(items):
            List(items) { ContactRow(contact: $0).listRowBackground(SBCColors.surface) }
                .listStyle(.plain)
                .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            state = .loaded(try await services.sync.syncedContacts(status: status).items)
        } catch {
            state = .failed(error)
        }
    }
}

private struct ContactRow: View {
    let contact: SyncedContact

    var body: some View {
        let (icon, colour, label): (String, Color, String) = switch contact.status {
        case "SYNCED": ("checkmark.circle.fill", SBCColors.secondary, "Synchronisé")
        case "PENDING": ("clock", SBCColors.accent, "En attente")
        case "FAILED": ("exclamationmark.circle", SBCColors.error, "Échec")
        case "STALE": ("arrow.clockwise.circle", SBCColors.accent, "À mettre à jour")
        default: ("questionmark.circle", SBCColors.onSurfaceVariant, contact.status)
        }
        let subtitle = [contact.profession, contact.location]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        HStack(spacing: 16) {
            MemberAvatar(initials: initials(of: contact.displayName), avatarUrl: contact.avatarUrl, radius: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.sbc(.bodyLarge))
                    .foregroundStyle(SBCColors.onSurface)
                Text(subtitle.isEmpty ? label : "\(subtitle) · \(label)")
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(colour)
                .accessibilityLabel(label)
            WhatsAppButton(
                phoneNumber: contact.phoneNumber,
                contactName: contact.displayName,
                size: 36
            )
        }
        .padding(.vertical, 2)
    }
}

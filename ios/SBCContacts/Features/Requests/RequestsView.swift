import SwiftUI

/// The "Demandes" tab: the member describes a need and follows their requests;
/// a pro also finds here the requests routed to them.
struct RequestsView: View {
    enum Side: Hashable { case mine, received }

    @Environment(RequestsStore.self) private var store
    @State private var side: Side = .mine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Côté", selection: $side) {
                    Text("Mes demandes").tag(Side.mine)
                    Text("Reçues").tag(Side.received)
                }
                .pickerStyle(.segmented)

                switch side {
                case .mine: MineList()
                case .received: ReceivedList()
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 96, trailing: 16))
        }
        .refreshable { await store.load() }
        .background(SBCColors.background)
        .overlay(alignment: .bottomTrailing) {
            if side == .mine {
                NavigationLink(value: AppRoute.requestNew) {
                    Label("Nouvelle demande", systemImage: "plus")
                        .font(.montserrat(.body, .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(16)
            }
        }
        .navigationTitle("Demandes")
        .navigationBarTitleDisplayMode(.large)
        .task { await store.load() }
    }
}

// MARK: - Mine

private struct MineList: View {
    @Environment(RequestsStore.self) private var store
    @State private var deleting: ServiceRequestItem?

    var body: some View {
        Group {
            NeedPromptCard()

            switch store.mine {
            case .loading:
                CardListSkeleton(rows: 2)
            case let .failed(error):
                EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription) {
                    Button("Réessayer") { Task { await store.loadMine() } }.buttonStyle(.borderedProminent)
                }
            case let .loaded(list) where list.isEmpty:
                Text("Tes demandes apparaîtront ici. Les professionnels concernés te répondent, tu compares et tu choisis.")
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .padding(.horizontal, 4)
            case let .loaded(list):
                let open = list.filter { $0.status.isOpen }
                let closed = list.filter { !$0.status.isOpen }
                if !open.isEmpty {
                    RequestSectionLabel(text: "En cours")
                    ForEach(open) { RequestRow(request: $0, deleting: $deleting) }
                }
                if !closed.isEmpty {
                    RequestSectionLabel(text: "Terminées").padding(.top, 4)
                    ForEach(closed) { RequestRow(request: $0, deleting: $deleting) }
                }
            }
        }
        .confirmDeleteRequest($deleting)
    }
}

/// "De quoi avez-vous besoin ?" — the way in, always at the top.
private struct NeedPromptCard: View {
    var body: some View {
        NavigationLink(value: AppRoute.requestNew) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("De quoi avez-vous besoin ?")
                        .font(.sbc(.titleMedium, weight: .heavy))
                        .foregroundStyle(SBCColors.onSurface)
                    Text("Décris ton besoin, on trouve les pros.")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(SBCColors.primary)
                        Text("Ex. « réparer mes locks samedi »")
                            .font(.sbc(.bodyMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                        Spacer()
                    }
                    .padding(12)
                    .background(SBCColors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 10)
                }
                .padding(16)
                Rectangle().fill(SBCColors.brandArc).frame(height: 4)
            }
            .background(SBCColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SBCColors.outlineVariant.opacity(0.5)))
            .shadow(color: SBCColors.primary.opacity(0.06), radius: 9, y: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct RequestRow: View {
    let request: ServiceRequestItem
    @Binding var deleting: ServiceRequestItem?

    private var tag: (String, Color) {
        let answers = request.responses.filter { $0.status == .interested || $0.status == .question }.count
        if request.status == .responded, answers > 0 {
            return ("\(answers) réponse\(answers > 1 ? "s" : "")", SBCColors.primary)
        }
        return (request.status.label, tone(for: request.status))
    }

    var body: some View {
        NavigationLink(value: request.status == .draft ? AppRoute.requestReview(request) : AppRoute.request(id: request.id)) {
            RequestPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(request.title)
                            .font(.sbc(.titleMedium, weight: .bold))
                            .foregroundStyle(SBCColors.onSurface)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        StatusTag(text: tag.0, tone: tag.1)
                    }
                    if !request.subtitle.isEmpty {
                        Text(request.subtitle)
                            .font(.sbc(.bodyMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                    if request.status == .sent {
                        Label("Transmise à \(request.dispatchedCount) professionnel\(request.dispatchedCount > 1 ? "s" : "")", systemImage: "checkmark")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.secondaryDark)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if request.canDelete {
                Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = request }
            }
        }
    }
}

// MARK: - Received (pro)

private struct ReceivedList: View {
    @Environment(RequestsStore.self) private var store

    var body: some View {
        if let space = store.proSpace, space.profile != nil {
            ProSetupBanner(missing: space.missingSetup)
            ReceivingBanner(active: space.receivingActive, until: space.profile?.receivingUntil)
            switch store.inbox {
            case .loading:
                CardListSkeleton(rows: 2)
            case let .failed(error):
                EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error.localizedDescription)
            case let .loaded(items) where items.isEmpty:
                EmptyStateView(
                    systemImage: "tray",
                    title: "Aucune demande pour l'instant",
                    message: space.services.isEmpty
                        ? "Ajoute tes services pour recevoir les demandes qui te correspondent."
                        : "Les demandes qui correspondent à tes services arriveront ici."
                )
            case let .loaded(items):
                ForEach(items) { InboxRow(item: $0) }
            }
        } else if store.proSpace != nil {
            BecomeProCard()
        } else {
            CardListSkeleton(rows: 2)
        }
    }
}

private struct ReceivingBanner: View {
    let active: Bool
    let until: Date?

    var body: some View {
        NavigationLink(value: AppRoute.proSpace) {
            HStack(spacing: 10) {
                Image(systemName: active ? "checkmark.shield" : "pause.circle")
                Text(active
                    ? "Réception active\(until.map { " · jusqu'au \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? "")"
                    : "Réception en pause — abonnement Pro requis")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .font(.sbc(.bodySmall, weight: .semibold))
            .foregroundStyle(active ? SBCColors.onSecondaryContainer : SBCColors.accentDark)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? SBCColors.secondaryContainer : SBCColors.accent.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct BecomeProCard: View {
    var body: some View {
        RequestPanel {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "briefcase")
                    .font(.system(size: 22))
                    .foregroundStyle(SBCColors.primary)
                Text("Tu proposes un service ?")
                    .font(.sbc(.titleMedium, weight: .heavy))
                Text("Crée ton profil professionnel et décris ce que tu sais faire. Les membres qui en ont besoin t'envoient leurs demandes.")
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                NavigationLink(value: AppRoute.proProfileForm) {
                    Text("Créer mon profil pro")
                }
                .buttonStyle(FilledButtonStyle(minHeight: 46))
                .padding(.top, 4)
            }
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        NavigationLink(value: AppRoute.inbox(item)) {
            RequestPanel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if item.status == .sent {
                            Circle().fill(SBCColors.primary).frame(width: 8, height: 8)
                        }
                        Text(item.status.label.uppercased())
                            .font(.sbc(.labelSmall, weight: .bold))
                            .foregroundStyle(tone(for: item.status))
                        Text("· \(item.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.sbc(.labelSmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                    Text(item.request.title)
                        .font(.sbc(.titleMedium, weight: .heavy))
                        .foregroundStyle(SBCColors.onSurface)
                        .multilineTextAlignment(.leading)
                    FlowLayout(spacing: 12) {
                        if let city = item.request.city {
                            Label(city, systemImage: "mappin.and.ellipse")
                        }
                        if let mode = item.request.mode {
                            Label(mode.label, systemImage: mode.systemImage)
                        }
                        if let date = item.request.desiredDate {
                            Label(date, systemImage: "calendar")
                        }
                        if let budget = item.request.budget {
                            Label(fcfa(budget), systemImage: "banknote")
                        }
                    }
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurface)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

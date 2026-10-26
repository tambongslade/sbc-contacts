import SwiftUI

/// "Espace pro": reception status, statistics, services and profile
/// (Data §3, §4, §17, §18).
struct ProSpaceView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(AuthStore.self) private var auth

    @State private var stats: ProStats?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let space = store.proSpace, let profile = space.profile {
                    ProSetupBanner(missing: space.missingSetup)
                    SubscriptionCard(active: space.receivingActive, until: profile.receivingUntil)
                    LocationCard()
                    if let stats { StatsBlock(stats: stats) }
                    ServicesBlock(services: space.services)
                    ProfileBlock(profile: profile)
                } else if store.proSpace != nil, auth.user?.isNetworkAccount == true {
                    RequestPanel { ProMembersOnlyView() }
                } else if store.proSpace != nil {
                    EmptyStateView(systemImage: "briefcase", title: "Pas encore de profil pro") {
                        NavigationLink("Créer mon profil pro", value: AppRoute.proProfileForm)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
                if let error {
                    Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .background(SBCColors.background)
        .navigationTitle("Espace pro")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await store.loadPro()
        guard store.isPro else { return }
        do {
            stats = try await services.requests.stats()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SubscriptionCard: View {
    let active: Bool
    let until: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: active ? "checkmark.seal.fill" : "pause.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(active ? SBCColors.secondaryDark : SBCColors.accentDark)
            VStack(alignment: .leading, spacing: 2) {
                Text("Abonnement Pro · 2 000 FCFA/mois")
                    .font(.sbc(.titleSmall, weight: .heavy))
                Text(active
                    ? (until.map { "Réception active jusqu'au \($0.formatted(date: .long, time: .omitted))" } ?? "Réception des demandes active")
                    : "Réception en pause. Contacte SBC pour activer ton abonnement.")
                    .font(.sbc(.bodySmall))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? SBCColors.onSecondaryContainer : SBCColors.onSurface)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(active ? SBCColors.secondaryContainer : SBCColors.accent.opacity(0.12))
        )
    }
}

/// "Partager ma position": pros close to a request receive it first. Says
/// what iOS currently allows and offers the one next step.
private struct LocationCard: View {
    @Environment(ProLocationReporter.self) private var reporter
    @Environment(\.openURL) private var openURL

    var body: some View {
        RequestPanel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { reporter.isEnabled },
                    set: { on in Task { await reporter.setEnabled(on) } }
                )) {
                    Label("Partager ma position", systemImage: "location.fill")
                        .font(.sbc(.titleSmall, weight: .heavy))
                }
                .tint(SBCColors.primary)
                Text(detail)
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                if reporter.isEnabled, let action {
                    Button(action.label, action: action.run)
                        .font(.sbc(.labelLarge, weight: .semibold))
                }
            }
        }
        .task { reporter.readPermission() }
    }

    private var detail: String {
        guard reporter.isEnabled else {
            return "Les demandes te parviennent selon ta ville et tes zones uniquement."
        }
        return switch reporter.permission {
        case .always:
            "Les demandes près de toi te parviennent en premier, même app fermée. Le client ne voit qu'une distance approximative."
        case .whileInUse:
            "Ta position est mise à jour quand tu ouvres l'app. Le client ne voit qu'une distance approximative."
        case .denied:
            "La localisation est désactivée pour SBC Network dans Réglages."
        case .unknown:
            "Les demandes près de toi te parviennent en premier. Le client ne voit qu'une distance approximative."
        }
    }

    private var action: (label: String, run: () -> Void)? {
        switch reporter.permission {
        case .unknown:
            ("Activer la localisation", { Task { await reporter.refresh(prompt: true) } })
        case .whileInUse:
            ("Autoriser « Toujours »", { reporter.askForAlways() })
        case .denied:
            ("Ouvrir Réglages", {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            })
        case .always:
            nil
        }
    }
}

/// The Synchro dashboard's ring and tiles, reused for the pro's numbers.
private struct StatsBlock: View {
    let stats: ProStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RequestSectionLabel(text: "Mes statistiques")
            RequestPanel {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(SBCColors.outlineVariant.opacity(0.4), lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: stats.received == 0 ? 0 : CGFloat(stats.responded) / CGFloat(stats.received))
                            .stroke(SBCColors.brandArc, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(stats.responded)").font(.sbc(.headlineMedium, weight: .heavy))
                            Text("/\(stats.received) REÇUES")
                                .font(.sbc(.labelSmall, weight: .semibold))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                        }
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Demandes répondues").font(.sbc(.titleSmall, weight: .heavy))
                        Text("Réponds vite : les clients choisissent souvent parmi les premières réponses.")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Tile(value: "\(Int((stats.responseRate * 100).rounded())) %", label: "Taux de réponse", systemImage: "paperplane.fill", tint: SBCColors.primary)
                Tile(value: "\(stats.selected)", label: "Retenues", systemImage: "checkmark.circle.fill", tint: SBCColors.success)
                Tile(value: "\(Int((stats.conversionRate * 100).rounded())) %", label: "Conversion", systemImage: "chart.line.uptrend.xyaxis", tint: SBCColors.accentDark)
                Tile(value: "\(stats.completed)", label: "Terminées", systemImage: "flag.checkered", tint: SBCColors.secondaryDark)
            }
            if !stats.topServices.isEmpty {
                RequestPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Services les plus demandés").font(.sbc(.titleSmall, weight: .heavy))
                        let top = stats.topServices.map(\.count).max() ?? 1
                        ForEach(stats.topServices, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.name).font(.sbc(.bodySmall))
                                    Spacer()
                                    Text("\(item.count)").font(.sbc(.bodySmall, weight: .bold))
                                }
                                GeometryReader { geo in
                                    Capsule().fill(SBCColors.primary)
                                        .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(max(top, 1)))
                                }
                                .frame(height: 8)
                                .background(Capsule().fill(SBCColors.outlineVariant.opacity(0.35)))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct Tile: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(value).font(.sbc(.headlineSmall, weight: .heavy))
            Text(label).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.onSurfaceVariant)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ServicesBlock: View {
    let services: [ProServiceItem]

    @Environment(\.services) private var api
    @Environment(RequestsStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RequestSectionLabel(text: "Mes services")
                Spacer()
                NavigationLink(value: AppRoute.proAddServices) {
                    Label("Ajouter", systemImage: "plus")
                }
                .font(.sbc(.labelLarge, weight: .semibold))
            }
            if services.isEmpty {
                RequestPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aucun service").font(.sbc(.titleSmall, weight: .heavy))
                        Text("Décris ce que tu sais faire : l'IA le range en services que les clients trouvent.")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                        NavigationLink("Ajouter un service", value: AppRoute.proAddServices)
                            .buttonStyle(FilledButtonStyle(minHeight: 44))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(services) { service in
                        HStack {
                            NavigationLink(value: AppRoute.proServiceEdit(service)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(service.name).font(.sbc(.bodyMedium, weight: .bold))
                                            if !service.isActive { StatusTag(text: "En pause", tone: SBCColors.onSurfaceVariant) }
                                        }
                                        Text(serviceSummary(service))
                                            .font(.sbc(.bodySmall))
                                            .foregroundStyle(SBCColors.onSurfaceVariant)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(SBCColors.onSurfaceVariant)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                Task {
                                    if let space = try? await api.requests.deleteService(service.id) {
                                        store.setProSpace(space)
                                    }
                                }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 14))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Supprimer \(service.name)")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        if service.id != services.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct ProfileBlock: View {
    let profile: ProProfile
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RequestSectionLabel(text: "Mon profil pro")
                Spacer()
                NavigationLink("Modifier", value: AppRoute.proProfileForm)
                    .font(.sbc(.labelLarge, weight: .semibold))
            }
            RequestPanel(padding: 14) {
                VStack(spacing: 0) {
                    FactRow(label: "Métier", value: profile.profession)
                    Divider()
                    FactRow(label: "Ville", value: ([profile.city] + profile.zones).joined(separator: ", "))
                    Divider()
                    FactRow(label: "Prestation", value: profile.modes.map(\.label).joined(separator: ", ").nilIfBlank ?? "—")
                    Divider()
                    FactRow(label: "Disponibilité", value: profile.availability)
                    Divider()
                    Button {
                        if let url = URL(string: profile.shopUrl) { openURL(url) }
                    } label: {
                        HStack {
                            Label("Ma boutique SBC Shop", systemImage: "bag")
                                .font(.sbc(.bodyMedium, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SBCColors.primary)
                }
            }
        }
    }
}

/// "Coiffure · dès 5 000 FCFA · À domicile" — what a service row says at a glance.
private func serviceSummary(_ s: ProServiceItem) -> String {
    var parts = [s.category].filter { !$0.isEmpty }
    if let min = s.priceMin { parts.append("dès \(fcfa(min))") }
    if !s.modes.isEmpty { parts.append(s.modes.map(\.label).joined(separator: ", ")) }
    return parts.joined(separator: " · ")
}

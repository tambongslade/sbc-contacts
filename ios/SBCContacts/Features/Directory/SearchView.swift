import SwiftUI

/// "Recherche" — the directory.
///
/// The system search bar, the sort, and the active filters sit above the
/// results, so the member always knows what is being asked and what came back —
/// which matters because a new query costs ~2.5 s upstream.
struct SearchView: View {
    @Environment(DirectoryStore.self) private var store
    @Environment(\.services) private var services
    @State private var text = ""
    @State private var showFilters = false

    private var active: [ActiveFilter] { ActiveFilter.of(store.filters) }

    /// The title carries the directory size rather than the tab name: the
    /// member knows which tab they are on, and "47k membres" is the fact that
    /// makes the screen feel worth searching.
    private var title: String {
        store.total > 0 ? "\(Self.compact(store.total)) membres" : "Annuaire SBC"
    }

    static func compact(_ n: Int) -> String {
        let fr = Locale(identifier: "fr_FR")
        switch n {
        case 1_000_000...: return (Double(n) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(fr)) + "M"
        case 10_000...: return "\(Int((Double(n) / 1000).rounded()))k"
        case 1000...: return (Double(n) / 1000).formatted(.number.precision(.fractionLength(1)).locale(fr)) + "k"
        default: return "\(n)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            QueryPanel(
                filters: active,
                onRemove: { filter in apply(filter.removed(from: store.filters)) },
                onClearAll: clearAllFilters,
                sortByConfidence: Binding(
                    get: { store.filters.sortByConfidence },
                    set: { value in
                        var next = store.filters
                        next.sortByConfidence = value
                        apply(next)
                    }
                )
            )
            content
                .frame(maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        // Submit-driven: the upstream call is slow enough that firing per
        // keystroke would be worse than an explicit submit.
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Qui cherches-tu ?")
        .onSubmit(of: .search, submitSearch)
        .onChange(of: text) { _, new in
            if new.isEmpty, store.filters.search != nil { clearSearch() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FilterToolbarButton(count: active.count) { showFilters = true }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(
                initial: store.filters,
                countResults: { [directory = services.directory] filters in
                    try? await directory.search(filters, page: 1, limit: 1).total
                },
                onApply: { apply($0) }
            )
            .presentationDetents([.large])
        }
        .task {
            if !store.hasSearched { await store.search() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.loading {
            CardListSkeleton(rows: 6)
        } else if store.subscriptionRequired {
            SubscriptionGate { Task { await store.search() } }
        } else if let error = store.error {
            ErrorView(message: error) { Task { await store.search() } }
        } else if store.members.isEmpty {
            NoResultsView(
                filters: store.filters,
                onOpenFilters: { showFilters = true },
                onClearAll: clearAllFilters,
                onSuggestion: applyProfession,
                onRetry: { Task { await store.search() } }
            )
        } else {
            ResultsList()
        }
    }

    private func apply(_ filters: SearchFilters) {
        Task { await store.apply(filters) }
    }

    private func submitSearch() {
        let value = text.trimmingCharacters(in: .whitespaces)
        var next = store.filters
        next.search = value.isEmpty ? nil : value
        apply(next)
    }

    private func clearSearch() {
        text = ""
        var next = store.filters
        next.search = nil
        apply(next)
    }

    /// Clearing resets what is searched, not how it is ordered — the sort is a
    /// reading preference, so it survives.
    private func clearAllFilters() {
        apply(SearchFilters(search: store.filters.search, sortByConfidence: store.filters.sortByConfidence))
    }

    private func applyProfession(_ profession: String) {
        text = ""
        apply(SearchFilters(profession: profession, sortByConfidence: store.filters.sortByConfidence))
    }
}

// MARK: - Query zone

private struct QueryPanel: View {
    let filters: [ActiveFilter]
    let onRemove: (ActiveFilter) -> Void
    let onClearAll: () -> Void
    @Binding var sortByConfidence: Bool

    var body: some View {
        VStack(spacing: 10) {
            // Two visible options, not a menu: the order in force changes the
            // meaning of the list, so it must be readable without opening anything.
            Picker("Trier", selection: $sortByConfidence) {
                Text("Pertinence").tag(false)
                Text("Score de confiance").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if !filters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters) { filter in
                            ActiveFilterChip(filter: filter) { onRemove(filter) }
                        }
                        Button("Tout effacer", action: onClearAll)
                            .font(.montserrat(.subheadline))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, 16)
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .animation(.snappy, value: filters)
    }
}

/// A filter that is *on* is a filled brand pill, so the active set is legible
/// from across the screen; the whole pill removes it.
private struct ActiveFilterChip: View {
    let filter: ActiveFilter
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Image(systemName: filter.systemImage).font(.montserrat(.caption, .semibold))
                Text(filter.label)
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "xmark").font(.montserrat(.caption2, .bold))
            }
            .font(.montserrat(.subheadline, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SBCColors.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retirer le filtre \(filter.label)")
    }
}

/// Filter entry point. Carries its own count so "filtered" is never signalled
/// by colour alone.
private struct FilterToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                Text("Filtres")
                if count > 0 {
                    Text("\(count)")
                        .font(.montserrat(.caption2, .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(SBCColors.accent, in: Circle())
                }
            }
            .font(.montserrat(.body, .semibold))
        }
        .accessibilityLabel(count > 0 ? "Filtres, \(count) actif\(count > 1 ? "s" : "")" : "Filtres")
    }
}
// MARK: - Results

private struct ResultsList: View {
    @Environment(DirectoryStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let count = store.total > 0 ? store.total : store.members.count
                Text(count > 1 ? "\(count) membres trouvés" : "\(count) membre trouvé")
                    .font(.sbc(.labelMedium, weight: .semibold))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))

                ForEach(Array(store.members.enumerated()), id: \.element.id) { index, member in
                    MemberCard(member: member)
                        .modifier(StaggerIn(index: index))
                        .onAppear {
                            if index >= store.members.count - 5 {
                                Task { await store.loadMore() }
                            }
                        }
                }

                if store.hasMore {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Chargement des membres suivants…")
                            .font(.sbc(.labelMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding(.bottom, 28)
        }
        .refreshable { await store.search() }
    }
}

/// Only the first screenful is staggered — animating rows scrolled to would
/// fight the scroll.
private struct StaggerIn: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 6 {
            content.appearAnimation(delay: Double(index) * 0.03, offset: 8)
        } else {
            content
        }
    }
}

// MARK: - Empty states

/// No results: always offers the next move.
private struct NoResultsView: View {
    let filters: SearchFilters
    let onOpenFilters: () -> Void
    let onClearAll: () -> Void
    let onSuggestion: (String) -> Void
    let onRetry: () -> Void

    /// Verbatim values from the live SBC vocabulary.
    private let suggestions = ["Etudiant(e)", "Enseignant", "Electricien", "Vendeur/Vendeuse"]

    var body: some View {
        let search = filters.search ?? ""
        let hasFilters = !ActiveFilter.of(filters).isEmpty

        ScrollView {
            if search.isEmpty, !hasFilters {
                EmptyStateView(
                    systemImage: "person.2",
                    title: "Aucun membre à afficher",
                    message: "Le répertoire n’a rien renvoyé pour le moment."
                ) {
                    Button(action: onRetry) { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .buttonStyle(FilledButtonStyle(fullWidth: false))
                }
            } else {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Aucun membre trouvé",
                    message: search.isEmpty
                        ? "Aucun membre ne correspond à cette combinaison de filtres."
                        : "Aucun membre ne correspond à « \(search) ». Vérifie l’orthographe ou essaie un mot plus court."
                ) {
                    VStack(spacing: 4) {
                        if hasFilters {
                            Button(action: onClearAll) {
                                Label("Effacer les filtres", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .buttonStyle(FilledButtonStyle(fullWidth: false))
                        }
                        Button(action: onOpenFilters) {
                            Label("Modifier les filtres", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.text)

                        Text("Essaie une profession")
                            .font(.sbc(.labelMedium, weight: .bold))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                            .padding(.top, 12)
                        FlowLayout(spacing: 8, alignment: .center) {
                            ForEach(suggestions, id: \.self) { s in
                                Button { onSuggestion(s) } label: {
                                    Label(s, systemImage: "briefcase")
                                        .font(.sbc(.labelLarge))
                                        .foregroundStyle(SBCColors.onSurface)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SBCColors.outlineVariant))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

/// Errors are shown as a cause the member can act on; the raw API message is
/// never surfaced.
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    private var offline: Bool {
        let m = message.lowercased()
        return ["network", "socket", "timeout", "timed out", "connection", "connexion", "internet", "hors ligne", "offline"]
            .contains { m.contains($0) }
    }

    var body: some View {
        ScrollView {
            EmptyStateView(
                systemImage: offline ? "wifi.slash" : "icloud.slash",
                title: offline ? "Pas de connexion" : "Répertoire indisponible",
                message: offline
                    ? "Vérifie ta connexion internet, puis réessaie."
                    : "Impossible de joindre SBC pour le moment. Réessaie dans quelques instants."
            ) {
                Button(action: onRetry) { Label("Réessayer", systemImage: "arrow.clockwise") }
                    .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        }
    }
}

/// The paywall: it has to explain what is behind the lock, not just refuse.
private struct SubscriptionGate: View {
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(SBCColors.brandArc).frame(height: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "lock")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(SBCColors.accent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SBCColors.accent.opacity(0.12)))
                    Text("Réservé aux abonnés SBC")
                        .font(.sbc(.titleLarge, weight: .heavy))
                        .foregroundStyle(SBCColors.onSurface)
                        .padding(.top, 16)
                    Text("L’annuaire des membres est réservé aux abonnés SBC. Active ton abonnement, puis actualise cette page.")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .lineSpacing(4)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        benefit("person.3", "Tout le répertoire des membres SBC")
                        benefit("slider.horizontal.3", "Filtres par métier, région, âge et centres d’intérêt")
                        benefit("bubble.left", "Contact WhatsApp direct et ajout au répertoire")
                    }
                    .padding(.top, 18)
                    Button(action: onRetry) {
                        Label("J’ai activé mon abonnement", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(FilledButtonStyle(minHeight: 48))
                    .padding(.top, 20)
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 13))
                        Text("Ton abonnement se gère dans l’onglet Profil.").font(.sbc(.bodySmall))
                    }
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(SBCColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SBCColors.outlineVariant.opacity(0.6)))
            .padding(EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20))
            .appearAnimation(offset: 0)
        }
    }

    private func benefit(_ icon: String, _ label: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(SBCColors.primary)
                .frame(width: 20)
            Text(label)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurface)
        }
    }
}

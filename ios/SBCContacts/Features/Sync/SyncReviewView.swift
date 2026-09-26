import SwiftUI

/// Review the members a criteria matches, choose which to save, then write them
/// to the phone book (cahier §10). Selection is the point of this screen:
/// every write is confirmed by the member first (§11).
struct SyncReviewView: View {
    let criteriaId: String
    let label: String

    @Environment(\.services) private var services
    @Environment(SyncStore.self) private var syncStore
    @Environment(ToastCenter.self) private var toasts

    private enum LoadState {
        case loading
        case loaded(Paginated<Member>)
        case failed(Error)
    }

    @State private var state: LoadState = .loading
    @State private var selected: Set<String> = []
    @State private var runner: SyncRunner?
    @State private var loadingMore = false

    var body: some View {
        content
            .background(SBCColors.background)
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if runner == nil { runner = SyncRunner(repo: services.sync) }
                if case .loading = state { await load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ListSkeleton()
        case let .failed(error):
            EmptyStateView(
                systemImage: "exclamationmark.circle",
                title: "Impossible de charger les correspondances",
                message: error.localizedDescription
            ) {
                Button("Réessayer") {
                    state = .loading
                    Task { await load() }
                }
                .buttonStyle(FilledButtonStyle(fullWidth: false))
            }
        case let .loaded(page) where page.items.isEmpty:
            EmptyStateView(
                systemImage: "person.crop.circle.badge.questionmark",
                title: "Aucune correspondance",
                message: "Aucun membre ne correspond encore à ce critère."
            )
        case let .loaded(page):
            loaded(page)
        }
    }

    private func loaded(_ page: Paginated<Member>) -> some View {
        let running = runner?.running ?? false
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill").foregroundStyle(SBCColors.primary)
                Text("\(page.total) membre(s) correspondent · \(selected.count) sélectionné(s)")
                    .font(.sbc(.bodyMedium))
                Spacer()
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if let runner, runner.running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: runner.fraction)
                    Text("Enregistrement \(runner.done)/\(runner.total)…").font(.sbc(.bodySmall))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if let runner, runner.finished, !runner.running {
                let parts = [
                    runner.synced > 0 ? "\(runner.synced) ajouté(s)" : nil,
                    runner.skipped > 0 ? "\(runner.skipped) déjà présent(s)" : nil,
                    runner.failed > 0 ? "\(runner.failed) échec(s)" : nil,
                ].compactMap { $0 }
                Text(parts.isEmpty ? "Rien à synchroniser." : parts.joined(separator: " · "))
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSecondaryContainer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SBCColors.secondaryContainer)
            }

            Divider()

            List {
                ForEach(Array(page.items.enumerated()), id: \.element.id) { index, member in
                    TargetRow(
                        member: member,
                        selected: selected.contains(member.sbcId),
                        enabled: !running
                    ) { on in
                        if on { selected.insert(member.sbcId) } else { selected.remove(member.sbcId) }
                    }
                    .listRowBackground(SBCColors.surface)
                    // Same prefetch distance the annuaire uses: ask for the next
                    // page five rows out, so the list is already longer by the
                    // time the scroll reaches the end.
                    .onAppear {
                        if index >= page.items.count - 5 {
                            Task { await loadMore() }
                        }
                    }
                }

                if page.hasMore {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Chargement des membres suivants…")
                            .font(.sbc(.labelMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(SBCColors.surface)
                }
            }
            .listStyle(.plain)
        }
        .foregroundStyle(SBCColors.onSurface)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Tout / rien") {
                    let selectable = page.items.filter { !$0.isSynced }.map(\.sbcId)
                    if selected.count == selectable.count {
                        selected.removeAll()
                    } else {
                        selected = Set(selectable)
                    }
                }
                // Hugs its label. Both styles are full-width by default, and
                // the Synchroniser button's layoutPriority means it claims that
                // width first — leaving this one its padding and nothing else,
                // so "Tout / rien" wrapped into slivers too narrow to draw and
                // the button rendered as an empty box taller than the bar.
                .buttonStyle(OutlinedButtonStyle(minHeight: 48, fullWidth: false))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(running)

                Button {
                    Task { await sync() }
                } label: {
                    Label(
                        selected.isEmpty ? "Sélectionne des membres" : "Synchroniser (\(selected.count))",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .buttonStyle(FilledButtonStyle(minHeight: 48))
                .layoutPriority(1)
                .disabled(selected.isEmpty || running)
            }
            .padding(12)
            .background(.bar)
        }
    }

    /// Read-only matches: opening the screen to look must not create a SyncRun.
    private func load() async {
        do {
            let page = try await services.sync.matches(id: criteriaId)
            // Everything not already on the device starts selected — the
            // common case is "save them all", with opting out one tap away.
            selected = Set(page.items.filter { !$0.isSynced }.map(\.sbcId))
            state = .loaded(page)
        } catch {
            state = .failed(error)
        }
    }

    /// Next page, appended. The matches endpoint orders by `lastSeenAt`, which
    /// hydration moves, so a member can be pushed onto a page already loaded —
    /// appending blind would put duplicate ids in the ForEach. Dropped here
    /// rather than in Paginated.concat, which has no notion of identity.
    private func loadMore() async {
        guard case let .loaded(page) = state, page.hasMore, !loadingMore else { return }
        guard !(runner?.running ?? false) else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await services.sync.matches(id: criteriaId, page: page.page + 1)
            // State can have moved while the request was in flight.
            guard case let .loaded(current) = state else { return }
            var seen = Set(current.items.map(\.id))
            let fresh = next.items.filter { seen.insert($0.id).inserted }
            state = .loaded(
                Paginated(
                    items: current.items + fresh,
                    total: next.total,
                    page: next.page,
                    limit: next.limit,
                    totalPages: next.totalPages,
                    hasMore: next.hasMore
                )
            )
        } catch {
            // A failed page must not blank the members already on screen.
            toasts.show(error.localizedDescription)
        }
    }

    private func sync() async {
        guard let runner else { return }
        await runner.run(memberSbcIds: Array(selected), criteriaId: criteriaId)
        if let error = runner.error { toasts.show(error) }
        await syncStore.loadSummary()
    }
}

private struct TargetRow: View {
    let member: Member
    let selected: Bool
    let enabled: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        let name = member.displayName
        let subtitle = [member.profession, member.city, member.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        HStack(spacing: 16) {
            MemberAvatar(initials: initials(of: name), avatarUrl: member.avatarUrl, radius: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.sbc(.bodyLarge))
                Text(member.isSynced
                    ? (subtitle.isEmpty ? "Déjà synchronisé" : subtitle)
                    : ((member.phoneNumber?.isEmpty ?? true) ? "\(subtitle) · sans numéro" : subtitle))
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if member.isSynced {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SBCColors.secondary)
            } else {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? SBCColors.primary : SBCColors.onSurfaceVariant)
            }
        }
        .opacity(member.isSynced ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled, !member.isSynced else { return }
            onChange(!selected)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(member.isSynced ? [] : .isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

import SwiftUI

/// One member in the list (backend `StatusBoostEntry`).
struct StatusBoostEntry: Identifiable, Sendable, Equatable, Decodable {
    var id: String { sbcId }
    var sbcId: String
    var name: String?
    var phoneNumber: String
    var avatarUrl: String?
    var country: String?
    var subscriptionTypes: [String]
    var savedByMe: Bool
    var savedMe: Bool

    private enum CodingKeys: String, CodingKey {
        case sbcId, name, phoneNumber, avatarUrl, country, subscriptionTypes, savedByMe, savedMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sbcId = c.string(.sbcId) ?? ""
        name = c.string(.name)
        phoneNumber = c.string(.phoneNumber) ?? ""
        avatarUrl = c.string(.avatarUrl)
        country = c.string(.country)
        subscriptionTypes = c.strings(.subscriptionTypes)
        savedByMe = c.bool(.savedByMe) ?? false
        savedMe = c.bool(.savedMe) ?? false
    }

    var displayName: String { (name?.isEmpty ?? true) ? "Membre SBC" : name! }

    /// The shape the shared "add to phone" flow works with.
    var asMember: Member {
        Member(id: sbcId, sbcId: sbcId, name: name, country: country, avatarUrl: avatarUrl, phoneNumber: phoneNumber)
    }
}

struct StatusBoostPage: Decodable, Sendable {
    var items: [StatusBoostEntry]
    var total: Int
    var hasMore: Bool
    var subscriptionTypes: [String]

    private enum CodingKeys: String, CodingKey { case items, total, hasMore, subscriptionTypes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = ((try? c.decodeIfPresent([Lossy<StatusBoostEntry>].self, forKey: .items)) ?? []).compactMap(\.value)
        total = c.int(.total) ?? items.count
        hasMore = c.bool(.hasMore) ?? false
        subscriptionTypes = c.strings(.subscriptionTypes)
    }
}

struct StatusBoostMe: Decodable, Sendable {
    var optIn: Bool
    var participants: Int
    var hasPhone: Bool
    /// The member's "save the whole list" criteria: nil when never created,
    /// false when switched off (leaving the list does that).
    var criteriaActive: Bool?
    /// Which filters the SBC subscription opens on the list: "all" for Ciblé,
    /// "country" otherwise.
    var filterAccess: String

    var countryOnly: Bool { filterAccess != "all" }

    private enum CodingKeys: String, CodingKey { case optIn, participants, hasPhone, criteria, filterAccess }
    private struct CriteriaRef: Decodable { let isActive: Bool }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        optIn = c.bool(.optIn) ?? false
        participants = c.int(.participants) ?? 0
        hasPhone = c.bool(.hasPhone) ?? true
        criteriaActive = (try? c.decodeIfPresent(CriteriaRef.self, forKey: .criteria))?.isActive
        filterAccess = (try? c.decodeIfPresent(String.self, forKey: .filterAccess)) ?? "country"
    }
}

extension APIClient {
    private struct OptInBody: Encodable, Sendable { let optIn: Bool }

    func statusBoost(subscription: String?, search: String?, filters: CriteriaFilters, page: Int) async throws -> StatusBoostPage {
        var query: [URLQueryItem] = [.init(name: "page", value: String(page)), .init(name: "limit", value: "30")]
        query += filters.queryItems
        if let subscription { query.append(.init(name: "subscription", value: subscription)) }
        if let search, !search.isEmpty { query.append(.init(name: "search", value: search)) }
        return try await get("/status-boost", query: query)
    }

    func statusBoostMe() async throws -> StatusBoostMe { try await get("/status-boost/me") }

    func setStatusBoost(optIn: Bool) async throws -> StatusBoostMe {
        try await put("/status-boost/me", body: OptInBody(optIn: optIn))
    }
}

/// "Je veux augmenter mon nombre de vues en statut WhatsApp".
///
/// WhatsApp only shows a status to people who saved each other's number. Here
/// members who want more views opt in, and everyone saves one another straight
/// into the phone — one by one, or all at once. Saving someone tells them
/// "Quelqu'un t'a enregistré", which is what brings them to save back.
struct StatusBoostView: View {
    @Environment(\.services) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(DirectoryStore.self) private var directory
    @Environment(SyncStore.self) private var sync
    @Environment(RegionsStore.self) private var regionsStore

    @State private var me: StatusBoostMe?
    @State private var entries: [StatusBoostEntry] = []
    @State private var types: [String] = []
    @State private var subscription: String?
    @State private var search = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var total = 0
    @State private var loading = true
    @State private var saving: Set<String> = []
    @State private var bulk: (done: Int, of: Int)?
    @State private var error: String?
    @State private var creatingCriteria = false
    /// The criteria filters applied to the list, as the subscription allows.
    @State private var filters = CriteriaFilters()
    @State private var draft = CriteriaFilters()
    @State private var editingFilters = false

    private var countryOnly: Bool { me?.countryOnly ?? true }

    private var unsaved: [StatusBoostEntry] { entries.filter { !$0.savedByMe } }

    var body: some View {
        List {
            Section {
                OptInCard(me: me, busy: creatingCriteria, filtered: !filters.isEmpty) { optIn in
                    Task { await setOptIn(optIn) }
                } onCreateCriteria: {
                    Task { await createCriteria() }
                }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                FilterBar(labels: filters.labels, countryOnly: countryOnly) {
                    draft = filters
                    editingFilters = true
                } onClear: {
                    filters = CriteriaFilters()
                    Task { await reload() }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if !types.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            SelectableChip(label: "Tous", selected: subscription == nil) { pick(nil) }
                            ForEach(types, id: \.self) { type in
                                SelectableChip(label: type, selected: subscription == type) { pick(type) }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Filtrer par abonnement")
                }
            }

            Section {
                if loading && entries.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if entries.isEmpty {
                    Text(search.isEmpty && subscription == nil && filters.isEmpty
                        ? "Personne d'autre n'a encore rejoint la liste. Rejoins-la et partage l'app : chaque membre qui s'inscrit est un contact de plus."
                        : "Aucun membre ne correspond.")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                } else {
                    ForEach(entries) { entry in
                        Row(entry: entry, saving: saving.contains(entry.sbcId)) {
                            Task { await save(entry) }
                        }
                        .onAppear { if entry.id == entries.last?.id, hasMore { Task { await loadMore() } } }
                    }
                }
            } header: {
                HStack {
                    Text("\(total) membre\(total > 1 ? "s" : "")")
                    Spacer()
                    if !unsaved.isEmpty, bulk == nil {
                        Button("Tout enregistrer (\(unsaved.count))") { Task { await saveAll() } }
                            .font(.sbc(.labelLarge, weight: .bold))
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Nom ou numéro")
        .onSubmit(of: .search) { Task { await reload() } }
        .onChange(of: search) { _, value in if value.isEmpty { Task { await reload() } } }
        .refreshable { await reload() }
        .safeAreaInset(edge: .bottom) {
            if let bulk {
                HStack(spacing: 10) {
                    ProgressView(value: Double(bulk.done), total: Double(max(bulk.of, 1)))
                    Text("\(bulk.done)/\(bulk.of)").font(.sbc(.labelMedium, weight: .bold))
                }
                .padding(16)
                .background(.bar)
            }
        }
        .navigationTitle("Vues WhatsApp")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingFilters) {
            NavigationStack {
                ScrollView {
                    CriteriaFiltersForm(filters: $draft, countryOnly: countryOnly)
                        .foregroundStyle(SBCColors.onSurface)
                        .padding(16)
                }
                .background(SBCColors.background)
                .navigationTitle("Filtrer la liste")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annuler") { editingFilters = false }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Appliquer") {
                        filters = countryOnly ? draft.countryOnly : draft
                        editingFilters = false
                        Task { await reload() }
                    }
                    .buttonStyle(FilledButtonStyle(minHeight: 48))
                    .padding(12)
                    .background(.bar)
                }
            }
            .presentationDragIndicator(.visible)
        }
        .task {
            me = try? await services.api.statusBoostMe()
            await reload()
        }
    }

    private func pick(_ type: String?) {
        subscription = type
        Task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await services.api.statusBoost(subscription: subscription, search: search, filters: filters, page: 1)
            entries = result.items
            types = result.subscriptionTypes
            total = result.total
            hasMore = result.hasMore
            page = 1
        } catch {
            toasts.show(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if let next = try? await services.api.statusBoost(subscription: subscription, search: search, filters: filters, page: page + 1) {
            entries += next.items.filter { n in !entries.contains { $0.id == n.id } }
            hasMore = next.hasMore
            page += 1
        }
    }

    private func setOptIn(_ optIn: Bool) async {
        do {
            me = try await services.api.setStatusBoost(optIn: optIn)
            // Leaving switches the "save the list" criteria off.
            Task { await sync.loadCriteria() }
            toasts.show(optIn
                ? "Tu es dans la liste : les membres peuvent maintenant t'enregistrer."
                : "Tu n'apparais plus dans la liste.")
        } catch {
            toasts.show(error.localizedDescription)
        }
    }

    /// Adds "Vues WhatsApp" to "Mes critères", with the filters applied here:
    /// syncing it saves those members of the list, and the member hears about
    /// whoever joins next. Asking again updates the existing one and turns it
    /// back on.
    private func createCriteria() async {
        let existed = me?.criteriaActive != nil
        creatingCriteria = true
        defer { creatingCriteria = false }
        do {
            try await sync.create(filters.payload(
                label: "Vues WhatsApp", regionOrder: regionsStore.catalog.all, statusBoost: true
            ))
            me = try await services.api.statusBoostMe()
            toasts.show(existed
                ? "Critère « Vues WhatsApp » mis à jour dans Synchro."
                : "Critère « Vues WhatsApp » ajouté dans Synchro.")
        } catch {
            toasts.show(error.localizedDescription)
        }
    }

    @discardableResult
    private func save(_ entry: StatusBoostEntry, announce: Bool = true) async -> Bool {
        saving.insert(entry.sbcId)
        defer { saving.remove(entry.sbcId) }
        let ok = await addMemberToPhone(entry.asMember, services: services, toasts: toasts, directory: directory, sync: sync, announce: announce)
        if ok, let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].savedByMe = true }
        return ok
    }

    /// Saves everyone listed and not yet saved, one after the other.
    private func saveAll() async {
        let targets = unsaved
        bulk = (0, targets.count)
        var added = 0
        for entry in targets {
            if await save(entry, announce: false) { added += 1 }
            bulk = (bulk!.done + 1, targets.count)
        }
        bulk = nil
        toasts.show("\(added) contact\(added > 1 ? "s" : "") enregistré\(added > 1 ? "s" : "") dans ton téléphone.")
    }
}

/// "Je participe" — the opt-in, with what it means in one line.
private struct OptInCard: View {
    let me: StatusBoostMe?
    let busy: Bool
    /// Filters are applied to the list: the criteria takes them.
    let filtered: Bool
    let onChange: (Bool) -> Void
    let onCreateCriteria: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(SBCColors.whatsapp, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Je veux augmenter mon nombre de vues en statut WhatsApp")
                    .font(.sbc(.titleSmall, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Enregistre les membres de la liste : ils voient tes statuts, tu vois les leurs. Chaque membre que tu enregistres est prévenu, et peut t'enregistrer en retour.")
                .font(.sbc(.bodySmall))
                .foregroundStyle(SBCColors.onSurfaceVariant)
            if let me {
                Toggle(isOn: Binding(get: { me.optIn }, set: onChange)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Je participe").font(.sbc(.bodyMedium, weight: .bold))
                        Text("\(me.participants) membre\(me.participants > 1 ? "s" : "") dans la liste")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
                .tint(SBCColors.whatsapp)
                .disabled(!me.hasPhone && !me.optIn)
                if !me.hasPhone {
                    Text("Ajoute un numéro à ton compte SBC pour que les membres puissent t'enregistrer.")
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.error)
                }
                // Only for someone in the list: the deal is mutual.
                if me.optIn {
                    if me.criteriaActive == true {
                        Label {
                            Text("Critère « Vues WhatsApp » actif dans Synchro")
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SBCColors.whatsapp)
                        }
                        .font(.sbc(.bodySmall))
                        if filtered {
                            Button(action: onCreateCriteria) {
                                Label("Appliquer ces filtres à mon critère", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.borderless)
                            .font(.sbc(.labelLarge, weight: .bold))
                            .tint(SBCColors.whatsapp)
                            .disabled(busy)
                        }
                    } else {
                        Button(action: onCreateCriteria) {
                            Label(me.criteriaActive == false ? "Réactiver mon critère"
                                  : filtered ? "Créer un critère avec ces filtres" : "Créer un critère avec cette liste",
                                  systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(SBCColors.whatsapp)
                        .disabled(busy)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "Filtres" and what is applied, under the opt-in card.
private struct FilterBar: View {
    let labels: [String]
    let countryOnly: Bool
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    Label(labels.isEmpty ? "Filtres" : "Filtres (\(labels.count))", systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                if labels.isEmpty {
                    Text(countryOnly ? "Par pays avec ton abonnement" : "Pays, profession, intérêts, âge…")
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .lineLimit(1)
                } else {
                    Button("Effacer", action: onClear).buttonStyle(.borderless)
                }
                Spacer(minLength: 0)
            }
            if !labels.isEmpty {
                FlowLayout(spacing: 6, runSpacing: 6) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.sbc(.labelSmall, weight: .bold))
                            .foregroundStyle(SBCColors.whatsapp)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(SBCColors.whatsapp.opacity(0.12)))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Row: View {
    let entry: StatusBoostEntry
    let saving: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(initials: initials(of: entry.displayName), avatarUrl: entry.avatarUrl, radius: 22, rounded: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName).font(.sbc(.bodyMedium, weight: .bold)).lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(entry.subscriptionTypes, id: \.self) { type in
                        Text(type)
                            .font(.sbc(.labelSmall, weight: .bold))
                            .foregroundStyle(type.uppercased() == "CIBLE" ? SBCColors.accentDark : SBCColors.secondaryDark)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((type.uppercased() == "CIBLE" ? SBCColors.accent : SBCColors.secondary).opacity(0.14)))
                    }
                }
                // The one to save back first: they already see your statuses.
                if entry.savedMe {
                    Label("T'a déjà enregistré", systemImage: "arrow.uturn.left")
                        .font(.sbc(.labelSmall, weight: .semibold))
                        .foregroundStyle(SBCColors.primary)
                }
            }
            Spacer(minLength: 8)
            if entry.savedByMe {
                Label("Enregistré", systemImage: "checkmark.circle.fill")
                    .font(.sbc(.labelMedium, weight: .bold))
                    .foregroundStyle(SBCColors.success)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(action: onSave) {
                    if saving { ProgressView() } else { Text("Enregistrer") }
                }
                .buttonStyle(FilledButtonStyle(minHeight: 36, fullWidth: false))
                .disabled(saving)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

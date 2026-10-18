import SwiftUI

/// The filters a criteria narrows members by. Shared by the criteria screen
/// and "Augmenter mes vues WhatsApp", which filters its list the same way.
struct CriteriaFilters: Equatable {
    var countries: Set<String> = []
    var regions: Set<String> = []
    var professions: Set<String> = []
    var interests: Set<String> = []
    var sex: String?
    /// Off unless the criteria actually carries an age range. SBC does not give
    /// an age for every member, and a range drops every row whose age is null —
    /// a criterion never meant to filter by age would silently match nobody.
    var ageEnabled = false
    var ageMin: Double = 18
    var ageMax: Double = 65

    init() {}

    init(_ criteria: SyncCriteria?) {
        countries = Set(criteria?.countries ?? [])
        regions = Set(criteria?.cities ?? [])
        professions = Set(criteria?.professions ?? [])
        interests = Set(criteria?.interests ?? [])
        sex = criteria?.sex
        ageEnabled = criteria?.ageMin != nil || criteria?.ageMax != nil
        ageMin = Double(criteria?.ageMin ?? 18)
        ageMax = Double(criteria?.ageMax ?? 65)
    }

    /// Keeps the country only: what a subscription other than Ciblé may use.
    var countryOnly: CriteriaFilters {
        var only = CriteriaFilters()
        only.countries = countries
        return only
    }

    var isEmpty: Bool { countries.isEmpty && !hasAdvanced }

    /// Any filter besides the country.
    var hasAdvanced: Bool {
        !regions.isEmpty || !professions.isEmpty || !interests.isEmpty || sex != nil || ageEnabled
    }

    /// Keeps the vocabulary's order so the payload is stable; free values last.
    private func ordered(_ set: Set<String>, _ options: [String]) -> [String] {
        options.filter(set.contains) + set.subtracting(options).sorted()
    }

    func payload(label: String, regionOrder: [String], statusBoost: Bool? = nil) -> CriteriaPayload {
        CriteriaPayload(
            label: label,
            countries: ordered(countries, FilterOptions.countries.map(\.code)),
            // The backend mirrors SBC's `region` into Member.city.
            cities: ordered(regions, regionOrder),
            professions: ordered(professions, FilterOptions.professions),
            interests: ordered(interests, FilterOptions.interests),
            sex: sex,
            ageMin: ageEnabled ? Int(ageMin) : nil,
            ageMax: ageEnabled ? Int(ageMax) : nil,
            statusBoost: statusBoost
        )
    }

    /// Query items for a list endpoint: only what is set.
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        items += countries.sorted().map { .init(name: "countries", value: $0) }
        items += regions.sorted().map { .init(name: "cities", value: $0) }
        items += professions.sorted().map { .init(name: "professions", value: $0) }
        items += interests.sorted().map { .init(name: "interests", value: $0) }
        if let sex { items.append(.init(name: "sex", value: sex)) }
        if ageEnabled {
            items.append(.init(name: "ageMin", value: String(Int(ageMin))))
            items.append(.init(name: "ageMax", value: String(Int(ageMax))))
        }
        return items
    }

    /// Short labels for what is set, for a summary line.
    var labels: [String] {
        var out = countries.sorted().map(FilterOptions.countryLabel)
        out += regions.sorted() + professions.sorted() + interests.sorted()
        if let sex { out.append(FilterOptions.sexes.first { $0.code == sex }?.label ?? sex) }
        if ageEnabled { out.append("\(Int(ageMin))–\(Int(ageMax)) ans") }
        return out
    }
}

/// Pays, régions, professions, centres d'intérêt, sexe and âge. With
/// `countryOnly`, everything but the country is locked behind the Ciblé
/// subscription.
struct CriteriaFiltersForm: View {
    @Binding var filters: CriteriaFilters
    var countryOnly = false

    @Environment(RegionsStore.self) private var regionsStore

    private var regionHint: String? {
        guard !filters.countries.isEmpty else { return "Choisis d'abord un pays pour ne voir que ses régions." }
        let names = FilterOptions.countries.map(\.code).filter(filters.countries.contains).map(FilterOptions.countryLabel)
        if regionsStore.catalog.regions(for: filters.countries).isEmpty {
            return "Aucune région enregistrée pour \(names.joined(separator: ", "))."
        }
        return "Régions de \(names.joined(separator: ", "))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MultiSelect(title: "Pays", selected: $filters.countries, options: FilterOptions.countries.map(\.code),
                        labelFor: FilterOptions.countryLabel)
            if countryOnly {
                LockedFilters().padding(.top, 16)
            } else {
                VStack(spacing: 16) {
                    // Scoped to the chosen pays: a région from another country
                    // combined with it would match nobody.
                    MultiSelect(
                        title: "Régions",
                        selected: $filters.regions,
                        options: regionsStore.catalog.regions(for: filters.countries),
                        hint: regionHint
                    )
                    MultiSelect(title: "Professions", selected: $filters.professions, options: FilterOptions.professions)
                    MultiSelect(title: "Centres d'intérêt", selected: $filters.interests, options: FilterOptions.interests)
                }
                .padding(.top, 16)

                Text("Sexe").font(.sbc(.labelLarge)).padding(.top, 20)
                FlowLayout(spacing: 8) {
                    SelectableChip(label: "Tous", selected: filters.sex == nil) { filters.sex = nil }
                    ForEach(FilterOptions.sexes, id: \.code) { option in
                        SelectableChip(label: option.label, selected: filters.sex == option.code) { filters.sex = option.code }
                    }
                }
                .padding(.top, 6)

                Toggle(isOn: $filters.ageEnabled.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Filtrer par âge").font(.sbc(.labelLarge))
                        Text(filters.ageEnabled
                            ? "\(Int(filters.ageMin)) – \(Int(filters.ageMax)) ans"
                            : "Tous les âges — les membres dont l'âge est inconnu restent inclus")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
                .tint(SBCColors.secondary)
                .padding(.top, 20)
                if filters.ageEnabled {
                    RangeSlider(lower: $filters.ageMin, upper: $filters.ageMax, bounds: 16...80)
                }
            }
        }
        // Changing the pays drops régions that no longer belong to any of them.
        .onChange(of: filters.countries) { _, new in
            filters.regions = filters.regions.filter { regionsStore.catalog.region($0, belongsTo: new) }
        }
    }
}

/// Stands in for the filters a subscription other than Ciblé cannot use.
private struct LockedFilters: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill").foregroundStyle(SBCColors.accentDark)
            VStack(alignment: .leading, spacing: 2) {
                Text("Abonnement Ciblé requis").font(.sbc(.titleSmall, weight: .bold))
                Text("Régions, professions, centres d'intérêt, sexe et âge sont réservés à l'abonnement Ciblé. Ton abonnement filtre par pays.")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SBCColors.accent.opacity(0.1)))
    }
}

/// A labelled set of chips plus a searchable sheet, for choosing several values
/// out of a long vocabulary.
private struct MultiSelect: View {
    let title: String
    @Binding var selected: Set<String>
    let options: [String]
    var labelFor: (String) -> String = { $0 }
    var hint: String?

    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.sbc(.labelLarge))
                Spacer()
                Button { open = true } label: {
                    Label(selected.isEmpty ? "Choisir" : "Modifier", systemImage: "plus")
                }
                .buttonStyle(.text)
                .disabled(options.isEmpty && selected.isEmpty)
            }
            if let hint {
                Text(hint)
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            if selected.isEmpty {
                Text("Tous")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            } else {
                FlowLayout(spacing: 8, runSpacing: 6) {
                    ForEach(options.filter(selected.contains) + selected.subtracting(options).sorted(), id: \.self) { value in
                        RemovableChip(label: labelFor(value)) { selected.remove(value) }
                    }
                }
            }
        }
        .sheet(isPresented: $open) {
            MultiSelectSheet(title: title, options: options, initial: selected, labelFor: labelFor) { selected = $0 }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MultiSelectSheet: View {
    let title: String
    let options: [String]
    let labelFor: (String) -> String
    let onDone: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String>
    @State private var query = ""

    init(title: String, options: [String], initial: Set<String>, labelFor: @escaping (String) -> String, onDone: @escaping (Set<String>) -> Void) {
        self.title = title
        self.options = options
        self.labelFor = labelFor
        self.onDone = onDone
        _picked = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List(options.filter { query.isEmpty || labelFor($0).lowercased().contains(query.lowercased()) }, id: \.self) { option in
                Button {
                    if picked.contains(option) { picked.remove(option) } else { picked.insert(option) }
                } label: {
                    HStack {
                        Text(labelFor(option)).foregroundStyle(SBCColors.onSurface)
                        Spacer()
                        Image(systemName: picked.contains(option) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(picked.contains(option) ? SBCColors.primary : SBCColors.onSurfaceVariant)
                    }
                }
                .accessibilityAddTraits(picked.contains(option) ? .isSelected : [])
            }
            .font(.sbc(.bodyMedium))
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !picked.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Effacer") { picked.removeAll() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Valider (\(picked.count))") {
                    onDone(picked)
                    dismiss()
                }
                .buttonStyle(FilledButtonStyle(minHeight: 46))
                .padding(12)
                .background(.bar)
            }
        }
    }
}

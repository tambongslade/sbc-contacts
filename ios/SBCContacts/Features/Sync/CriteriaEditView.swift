import SwiftUI

/// Define which categories of members to save (cahier §10).
///
/// Values come from `FilterOptions` — the live SBC vocabularies — because
/// free typing silently matched nothing whenever the spelling or accent
/// differed ("Maçon" vs SBC's "Macon").
struct CriteriaEditView: View {
    let existing: SyncCriteria?

    @Environment(SyncStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionsStore.self) private var regionsStore

    @State private var label: String
    @State private var countries: Set<String>
    @State private var regions: Set<String>
    @State private var professions: Set<String>
    @State private var interests: Set<String>
    @State private var sex: String?
    @State private var ageMin: Double
    @State private var ageMax: Double
    /// Off unless the criteria actually carries an age range. SBC does not give
    /// an age for every member, and a range drops every row whose age is null —
    /// a criterion never meant to filter by age would silently match nobody.
    @State private var ageEnabled: Bool

    @State private var preview: Int?
    @State private var previewing = false
    @State private var saving = false
    @State private var confirmDelete = false

    init(existing: SyncCriteria?) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _countries = State(initialValue: Set(existing?.countries ?? []))
        _regions = State(initialValue: Set(existing?.cities ?? []))
        _professions = State(initialValue: Set(existing?.professions ?? []))
        _interests = State(initialValue: Set(existing?.interests ?? []))
        _sex = State(initialValue: existing?.sex)
        _ageMin = State(initialValue: Double(existing?.ageMin ?? 18))
        _ageMax = State(initialValue: Double(existing?.ageMax ?? 65))
        _ageEnabled = State(initialValue: existing?.ageMin != nil || existing?.ageMax != nil)
    }

    private var regionHint: String? {
        guard !countries.isEmpty else { return "Choisis d'abord un pays pour ne voir que ses régions." }
        let names = FilterOptions.countries.map(\.code).filter(countries.contains).map(FilterOptions.countryLabel)
        if regionsStore.catalog.regions(for: countries).isEmpty {
            return "Aucune région enregistrée pour \(names.joined(separator: ", "))."
        }
        return "Régions de \(names.joined(separator: ", "))"
    }

    /// Keeps the vocabulary's order so the payload is stable; free values last.
    private func ordered(_ set: Set<String>, _ options: [String]) -> [String] {
        options.filter(set.contains) + set.subtracting(options).sorted()
    }

    private var payload: CriteriaPayload {
        CriteriaPayload(
            label: label.trimmed.isEmpty ? "Sans titre" : label.trimmed,
            countries: ordered(countries, FilterOptions.countries.map(\.code)),
            // The backend mirrors SBC's `region` into Member.city.
            cities: ordered(regions, regionsStore.catalog.all),
            professions: ordered(professions, FilterOptions.professions),
            interests: ordered(interests, FilterOptions.interests),
            sex: sex,
            ageMin: ageEnabled ? Int(ageMin) : nil,
            ageMax: ageEnabled ? Int(ageMax) : nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OutlinedField(label: "Nom du critère", systemImage: "tag") {
                    TextField("Ex. Maçons de Douala", text: $label)
                        .font(.sbc(.bodyLarge))
                }

                VStack(spacing: 16) {
                    MultiSelect(title: "Pays", selected: $countries, options: FilterOptions.countries.map(\.code),
                                labelFor: FilterOptions.countryLabel)
                    // Scoped to the chosen pays: a région from another country
                    // combined with it would match nobody.
                    MultiSelect(
                        title: "Régions",
                        selected: $regions,
                        options: regionsStore.catalog.regions(for: countries),
                        hint: regionHint
                    )
                    MultiSelect(title: "Professions", selected: $professions, options: FilterOptions.professions)
                    MultiSelect(title: "Centres d'intérêt", selected: $interests, options: FilterOptions.interests)
                }
                .padding(.top, 20)

                Text("Sexe").font(.sbc(.labelLarge)).padding(.top, 20)
                FlowLayout(spacing: 8) {
                    SelectableChip(label: "Tous", selected: sex == nil) { sex = nil }
                    ForEach(FilterOptions.sexes, id: \.code) { option in
                        SelectableChip(label: option.label, selected: sex == option.code) { sex = option.code }
                    }
                }
                .padding(.top, 6)

                Toggle(isOn: $ageEnabled.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Filtrer par âge").font(.sbc(.labelLarge))
                        Text(ageEnabled
                            ? "\(Int(ageMin)) – \(Int(ageMax)) ans"
                            : "Tous les âges — les membres dont l'âge est inconnu restent inclus")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
                .tint(SBCColors.secondary)
                .padding(.top, 20)
                if ageEnabled {
                    RangeSlider(lower: $ageMin, upper: $ageMax, bounds: 16...80)
                }

                // §10: show how many members the criteria matches before saving.
                HStack(spacing: 16) {
                    Image(systemName: "person.2.fill").foregroundStyle(SBCColors.onSurfaceVariant)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.map { "\($0) membre(s) correspondent" } ?? "Combien de membres correspondent ?")
                            .font(.sbc(.titleSmall, weight: .bold))
                        // Shown up front, not as an afterthought: the count only
                        // covers members already mirrored, so it always reads
                        // well below the same filter in the annuaire.
                        Text("Compté parmi les membres déjà consultés dans l'annuaire, pas sur toute la base SBC.")
                            .font(.sbc(.bodySmall))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if previewing {
                        ProgressView()
                    } else {
                        Button("Calculer") { Task { await refreshPreview() } }
                            .buttonStyle(.text)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SBCColors.surface))
                .padding(.top, 20)
            }
            .foregroundStyle(SBCColors.onSurface)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SBCColors.background)
        .onChange(of: payload) { preview = nil }
        // Changing the pays drops régions that no longer belong to any of them.
        .onChange(of: countries) { _, new in
            regions = regions.filter { regionsStore.catalog.region($0, belongsTo: new) }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await save() }
            } label: {
                if saving { ProgressView().tint(.white) } else { Text("Enregistrer") }
            }
            .buttonStyle(FilledButtonStyle(minHeight: 50))
            .disabled(saving)
            .padding(12)
            .background(.bar)
        }
        .navigationTitle(existing == nil ? "Nouveau critère" : "Modifier le critère")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if existing != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Supprimer")
                }
            }
        }
        .alert("Supprimer ce critère ?", isPresented: $confirmDelete) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Les contacts déjà enregistrés dans votre téléphone ne seront pas supprimés.")
        }
    }

    private func refreshPreview() async {
        previewing = true
        defer { previewing = false }
        preview = try? await store.repo.previewAdhoc(payload)
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let existing {
                try await store.update(id: existing.id, payload)
            } else {
                try await store.create(payload)
            }
            dismiss()
        } catch {
            toasts.show("Échec : \(error.localizedDescription)")
        }
    }

    private func delete() async {
        guard let existing else { return }
        do {
            try await store.remove(id: existing.id)
            dismiss()
        } catch {
            toasts.show("Échec : \(error.localizedDescription)")
        }
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

import SwiftUI

/// Directory filters (cahier §6) as a three-step wizard: **où** (pays, région),
/// **qui** (sexe, âge, profession), **quoi** (centres d'intérêt).
///
/// One screen of eleven controls made every filter look equally mandatory and
/// buried the two that actually narrow the base. Split in three, each step asks
/// one question and the stepper says how much is left — while every step stays
/// skippable, because no filter is required to search.
///
/// Built from native components (navigation bar, segmented control, toggle,
/// steppers, searchable lists, grouped surfaces) set in Montserrat, with the
/// Flutter wizard as the layout reference.
struct FilterSheet: View {
    let initial: SearchFilters
    /// Live result count for the filters being edited; nil when unavailable.
    let countResults: (SearchFilters) async -> Int?
    let onApply: (SearchFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionsStore.self) private var regionsStore

    fileprivate enum PickerRoute: Hashable {
        case region, profession
    }

    private static let steps = ["Pays", "Profil", "Intérêts"]
    private static let ageBounds: ClosedRange<Double> = 16...80

    @State private var step = 0
    @State private var forward = true

    @State private var country: String?
    @State private var region: String?
    @State private var profession: String?
    @State private var sex: String?
    @State private var interests: Set<String>
    @State private var ageMin: Double
    @State private var ageMax: Double
    /// The age range is only sent once the member turns it on. Sending the
    /// 18–65 default unasked silently hid everyone outside it.
    @State private var ageEnabled: Bool
    @State private var interestQuery = ""

    @State private var liveCount: Int?
    @State private var counting = false

    init(
        initial: SearchFilters,
        countResults: @escaping (SearchFilters) async -> Int?,
        onApply: @escaping (SearchFilters) -> Void
    ) {
        self.initial = initial
        self.countResults = countResults
        self.onApply = onApply
        _country = State(initialValue: initial.country)
        _region = State(initialValue: initial.region)
        _profession = State(initialValue: initial.profession)
        _sex = State(initialValue: initial.sex)
        _interests = State(initialValue: Set(initial.interests))
        _ageMin = State(initialValue: Double(initial.ageMin ?? 18))
        _ageMax = State(initialValue: Double(initial.ageMax ?? 65))
        _ageEnabled = State(initialValue: initial.ageMin != nil || initial.ageMax != nil)
    }

    private var result: SearchFilters {
        SearchFilters(
            search: initial.search,
            country: country,
            region: region,
            city: initial.city,
            profession: profession,
            sex: sex,
            ageMin: ageEnabled ? Int(ageMin) : nil,
            ageMax: ageEnabled ? Int(ageMax) : nil,
            interests: FilterOptions.interests.filter(interests.contains),
            // Carried through: the sort is chosen on the results screen.
            sortByConfidence: initial.sortByConfidence
        )
    }

    private var activeCount: Int {
        [country, region, profession, sex].compactMap { $0 }.count
            + (interests.isEmpty ? 0 : 1) + (ageEnabled ? 1 : 0)
    }

    /// How many filters one step holds — shown on the stepper so step 3 still
    /// says that step 1 is carrying something.
    private func count(on step: Int) -> Int {
        switch step {
        case 0: [country, region].compactMap { $0 }.count
        case 1: [sex, profession].compactMap { $0 }.count + (ageEnabled ? 1 : 0)
        default: interests.count
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepIndicator(steps: Self.steps, current: step, countOf: count(on:), onSelect: goTo)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                ZStack {
                    Group {
                        switch step {
                        case 0: placeStep
                        case 1: profileStep
                        default: interestStep
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: forward ? 28 : -28)),
                        removal: .opacity
                    ))
                }
                .frame(maxHeight: .infinity)
                .clipped()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == 0 {
                        Button("Annuler") { dismiss() }
                    } else {
                        Button { goTo(step - 1) } label: {
                            Label("Retour", systemImage: "chevron.backward")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Effacer", action: clearAll)
                        .disabled(activeCount == 0)
                }
            }
            .navigationDestination(for: PickerRoute.self) { route in
                switch route {
                case .region:
                    ValuePickerList(
                        title: "Région",
                        allLabel: "Toutes les régions",
                        options: regionsStore.catalog.regions(for: country.map { [$0] } ?? []),
                        footer: country.map { "Régions les plus fréquentes au \(FilterOptions.countryLabel($0)). Tape un autre nom pour l'utiliser." }
                            ?? "Régions les plus fréquentes. Tape un autre nom pour l'utiliser.",
                        value: $region
                    )
                case .profession:
                    ValuePickerList(
                        title: "Profession",
                        allLabel: "Toutes les professions",
                        options: FilterOptions.professions,
                        footer: "Recherche partielle : « design » trouve « Designer graphique ».",
                        value: $profession
                    )
                }
            }
        }
        .font(.montserrat(.body))
        .tint(SBCColors.primary)
        .task(id: result) {
            // Debounced: the upstream directory takes ~2.5 s per new query.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            counting = true
            let value = await countResults(result)
            guard !Task.isCancelled else { return }
            liveCount = value
            counting = false
        }
    }

    // MARK: - Navigation

    private func goTo(_ target: Int) {
        let next = min(max(target, 0), Self.steps.count - 1)
        guard next != step else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        forward = next > step
        withAnimation(.snappy(duration: 0.28)) { step = next }
    }

    private func clearAll() {
        withAnimation {
            country = nil
            region = nil
            profession = nil
            sex = nil
            interests.removeAll()
            ageMin = 18
            ageMax = 65
            ageEnabled = false
            interestQuery = ""
        }
    }

    private func apply() {
        onApply(result)
        dismiss()
    }

    /// Changing the pays drops a région that cannot belong to it: the pair
    /// would match nothing, and a silent zero reads as a bug.
    private func selectCountry(_ code: String?) {
        country = code
        if let r = region, !regionsStore.catalog.region(r, belongsTo: code.map { [$0] } ?? []) {
            region = nil
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { goTo(step - 1) } label: {
                    Text("Retour").frame(minWidth: 72)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }

            Button {
                if step == Self.steps.count - 1 { apply() } else { goTo(step + 1) }
            } label: {
                HStack(spacing: 6) {
                    if step == Self.steps.count - 1 {
                        if counting, liveCount == nil {
                            ProgressView().tint(.white)
                        }
                        Text(resultsLabel)
                            .contentTransition(.numericText())
                    } else {
                        Text("Continuer")
                    }
                    Image(systemName: "chevron.forward").font(.montserrat(.body, .semibold))
                }
                .frame(maxWidth: .infinity)
                .font(.montserrat(.body, .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x10182B))
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .animation(.snappy, value: liveCount)
    }

    private var resultsLabel: String {
        guard let liveCount else { return "Voir les résultats" }
        let n = liveCount.formatted(.number.locale(Locale(identifier: "fr_FR")))
        return "Voir \(n) résultat\(liveCount > 1 ? "s" : "")"
    }

    // MARK: - Step 1 · où

    private var placeStep: some View {
        StepScroll {
            Text("Où cherches-tu ?")
                .font(.montserrat(.title2, .bold))

            CountryCard(flag: nil, name: "Tous les pays", subtitle: "Chercher dans toute la base", selected: country == nil) {
                selectCountry(nil)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(FilterOptions.countries, id: \.code) { option in
                    CountryCard(flag: flagEmoji(option.code), name: option.label, selected: country == option.code) {
                        selectCountry(country == option.code ? nil : option.code)
                    }
                }
            }

            GroupedSection {
                NavigationLink(value: PickerRoute.region) {
                    PickerRow(title: "Région", systemImage: "mappin.and.ellipse", value: region ?? "Toutes")
                }
                .buttonStyle(.plain)
            }

            TipRow(
                systemImage: "sparkles",
                title: "Astuce rapide",
                message: "Un seul pays à la fois. Laisse « Tous les pays » pour ratisser large, puis affine avec la région."
            )
        }
        .sensoryFeedback(.selection, trigger: country)
    }

    // MARK: - Step 2 · qui

    private var profileStep: some View {
        StepScroll {
            Text("Ton profil idéal")
                .font(.montserrat(.title2, .bold))

            SectionHeader("Sexe")
            Picker("Sexe", selection: $sex) {
                Text("Tous").tag(String?.none)
                ForEach(FilterOptions.sexes, id: \.code) { option in
                    Text(option.label).tag(Optional(option.code))
                }
            }
            .pickerStyle(.segmented)

            SectionHeader("Âge")
            GroupedSection {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $ageEnabled.animation(.snappy)) {
                        Label("Filtrer par âge", systemImage: "birthday.cake")
                    }
                    .tint(SBCColors.secondary)

                    if ageEnabled {
                        Divider()
                        Text("\(Int(ageMin)) – \(Int(ageMax)) ans")
                            .font(.montserrat(.title3, .bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity)
                        RangeSlider(lower: $ageMin, upper: $ageMax, bounds: Self.ageBounds, activeColor: SBCColors.secondary)
                        HStack(spacing: 8) {
                            ForEach([("18–25", 18.0, 25.0), ("26–35", 26.0, 35.0), ("36–50", 36.0, 50.0), ("50+", 50.0, 80.0)], id: \.0) { preset in
                                let on = ageMin == preset.1 && ageMax == preset.2
                                Button(preset.0) {
                                    withAnimation(.snappy) {
                                        ageMin = preset.1
                                        ageMax = preset.2
                                    }
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                                .tint(on ? SBCColors.secondary : .secondary)
                                .font(.montserrat(.subheadline, on ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Divider()
                        Stepper(value: $ageMin, in: Self.ageBounds.lowerBound...ageMax, step: 1) {
                            LabeledContent("Minimum", value: "\(Int(ageMin)) ans")
                        }
                        Stepper(value: $ageMax, in: ageMin...Self.ageBounds.upperBound, step: 1) {
                            LabeledContent("Maximum", value: "\(Int(ageMax)) ans")
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }

            SectionHeader("Profession")
            GroupedSection {
                NavigationLink(value: PickerRoute.profession) {
                    PickerRow(title: "Profession", systemImage: "briefcase", value: profession ?? "Toutes")
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: sex)
    }

    // MARK: - Step 3 · quoi

    private var interestStep: some View {
        let q = interestQuery.trimmed.lowercased()
        let matches = FilterOptions.interests.filter { q.isEmpty || $0.lowercased().contains(q) }
        // Chosen interests stay on top, so what is selected is never hunted for.
        let ordered = matches.filter(interests.contains) + matches.filter { !interests.contains($0) }
        let chosen = FilterOptions.interests.filter(interests.contains)

        return StepScroll {
            HStack(alignment: .firstTextBaseline) {
                Text("Centres d'intérêt")
                    .font(.montserrat(.title2, .bold))
                Spacer()
                if !interests.isEmpty {
                    Text("\(interests.count) sélectionné\(interests.count > 1 ? "s" : "")")
                        .font(.montserrat(.footnote, .semibold))
                        .foregroundStyle(SBCColors.secondaryDark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SBCColors.secondary.opacity(0.16), in: Capsule())
                        .contentTransition(.numericText())
                }
            }

            SystemSearchField(prompt: "Rechercher un intérêt", text: $interestQuery)

            if ordered.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "Aucun résultat",
                    message: "Aucun centre d'intérêt ne correspond à « \(interestQuery) »."
                )
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(ordered, id: \.self) { interest in
                        InterestChip(label: interest, selected: interests.contains(interest)) {
                            withAnimation(.snappy) {
                                if interests.contains(interest) { interests.remove(interest) } else { interests.insert(interest) }
                            }
                        }
                    }
                }
            }

            if chosen.isEmpty {
                TipRow(
                    systemImage: "sparkles",
                    title: "Astuce rapide",
                    message: "Deux ou trois centres d'intérêt suffisent : au-delà, la liste de résultats se resserre vite."
                )
            } else {
                MatchSummary(interests: chosen, activeCount: activeCount)
            }
        }
        .sensoryFeedback(.selection, trigger: interests)
    }

    private func flagEmoji(_ code: String) -> String {
        code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map(String.init)
            .joined()
    }
}

// MARK: - Step indicator

private struct StepIndicator: View {
    let steps: [String]
    let current: Int
    let countOf: (Int) -> Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(steps.indices, id: \.self) { i in
                if i > 0 {
                    Capsule()
                        .fill(i <= current ? SBCColors.secondary : Color(.systemFill))
                        .frame(height: 3)
                        .padding(.top, 13)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                }
                Button { onSelect(i) } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(i < current ? SBCColors.secondary : i == current ? Color(.label) : Color(.tertiarySystemFill))
                            if i < current {
                                Image(systemName: "checkmark").font(.montserrat(.footnote, .bold)).foregroundStyle(.white)
                            } else {
                                Text("\(i + 1)")
                                    .font(.montserrat(.subheadline, .semibold))
                                    .foregroundStyle(i == current ? Color(.systemBackground) : .secondary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        // "This step holds something" must never be colour alone.
                        .overlay(alignment: .topTrailing) {
                            let n = countOf(i)
                            if n > 0, i != current {
                                Text("\(n)")
                                    .font(SBCFontFixed.font(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .background(SBCColors.accent, in: Circle())
                                    .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 1.5))
                                    .offset(x: 4, y: -4)
                            }
                        }
                        Text(steps[i].uppercased())
                            .font(.montserrat(.caption2, .semibold))
                            .tracking(0.4)
                            .foregroundStyle(i == current ? .primary : .secondary)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Étape \(i + 1) sur \(steps.count), \(steps[i])")
                .accessibilityAddTraits(i == current ? .isSelected : [])
            }
        }
        .animation(.snappy, value: current)
    }
}

// MARK: - Building blocks

/// The scrolling body of one step, with the same gutters on all three.
private struct StepScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.montserrat(.footnote))
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.top, 6)
            .padding(.bottom, -6)
    }
}

/// An inset-grouped cell surface, like a `Form` section.
private struct GroupedSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A Settings-style disclosure row.
private struct PickerRow: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.montserrat(.body))
                .foregroundStyle(SBCColors.primary)
                .frame(width: 26)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.forward")
                .font(.montserrat(.footnote, .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

private struct CountryCard: View {
    let flag: String?
    let name: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let flag {
                    VStack(spacing: 6) {
                        Text(flag).font(.system(size: 30))
                        Text(name)
                            .font(.montserrat(.subheadline, .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.montserrat(.title2))
                            .foregroundStyle(SBCColors.primary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.montserrat(.headline))
                            if let subtitle {
                                Text(subtitle).font(.montserrat(.subheadline)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? SBCColors.secondary : Color(.separator).opacity(0.4), lineWidth: selected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SBCColors.secondary)
                        .font(.montserrat(.title3))
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.snappy(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(name), \($0)" } ?? name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TipRow: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        GroupedSection {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.montserrat(.title3))
                    .foregroundStyle(SBCColors.primary)
                    .frame(width: 40, height: 40)
                    .background(SBCColors.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.montserrat(.headline))
                    Text(message)
                        .font(.montserrat(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
    }
}

/// The selection echoed back once interests are chosen.
private struct MatchSummary: View {
    let interests: [String]
    let activeCount: Int

    var body: some View {
        GroupedSection {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(interests.prefix(4), id: \.self) { interest in
                        Text(FilterOptions.interestEmoji[interest] ?? "•")
                            .font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .background(Color(.systemBackground), in: Circle())
                            .overlay(Circle().stroke(Color(.separator).opacity(0.5)))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Parfait pour matcher").font(.montserrat(.subheadline, .semibold))
                    Text("\(activeCount) filtre\(activeCount > 1 ? "s" : "") combiné\(activeCount > 1 ? "s" : "")")
                        .font(.montserrat(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(SBCColors.secondary).frame(width: 8, height: 8)
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Looks and behaves like the system search bar.
private struct SystemSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Interest token: emoji first, so the list is scannable before it is read.
private struct InterestChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    /// "Musique (instruments, chant)" → "Musique"; only the display is trimmed.
    private var short: String {
        label.range(of: " (").map { String(label[..<$0.lowerBound]) } ?? label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji = FilterOptions.interestEmoji[label] {
                    Text(emoji)
                }
                Text(short)
                    .font(.montserrat(.subheadline, selected ? .semibold : .medium))
                    .lineLimit(2)
                if selected {
                    Image(systemName: "checkmark").font(.montserrat(.caption, .bold))
                }
            }
            .font(.montserrat(.subheadline))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(selected ? SBCColors.secondary : Color(.secondarySystemGroupedBackground))
            )
            .overlay(Capsule().strokeBorder(selected ? .clear : Color(.separator).opacity(0.4)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Searchable single-choice list pushed from a picker row. Suggestions come
/// from the live SBC vocabulary, but free text is allowed — profession matches
/// partially, and 598 of 658 régions are outside the suggestions.
private struct ValuePickerList: View {
    let title: String
    let allLabel: String
    let options: [String]
    let footer: String
    @Binding var value: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmed.lowercased()
        return q.isEmpty ? options : options.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section {
                row(allLabel, selected: value == nil) { value = nil }
            }

            let typed = query.trimmed
            if !typed.isEmpty, !options.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
                Section {
                    Button {
                        value = typed
                        dismiss()
                    } label: {
                        Label("Utiliser « \(typed) »", systemImage: "text.cursor")
                    }
                }
            }

            Section {
                ForEach(filtered, id: \.self) { option in
                    row(option, selected: value == option) { value = option }
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text(footer)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(SBCColors.primary)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Shared with the criteria editor

/// Outlined field shell.
struct OutlinedField<Content: View>: View {
    let label: String
    let systemImage: String
    var focused = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(SBCColors.onSurfaceVariant)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.sbc(.labelMedium))
                    .foregroundStyle(focused ? SBCColors.primary : SBCColors.onSurfaceVariant)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SBCColors.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? SBCColors.primary : SBCColors.outlineVariant, lineWidth: focused ? 2 : 1)
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

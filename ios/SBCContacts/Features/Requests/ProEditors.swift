import SwiftUI

/// Create or edit the pro profile. Name, photo and WhatsApp come from SBC —
/// only what SBC does not know is asked (Data §2, §3).
struct ProProfileFormView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var profession = ""
    @State private var description = ""
    @State private var city = ""
    @State private var zones = ""
    @State private var modes: Set<ServiceMode> = [.home]
    @State private var availability = ""
    @State private var priceMin = ""
    @State private var priceMax = ""
    @State private var shopUrl = ""
    @State private var whatsapp = ""
    @State private var saving = false
    @State private var error: String?

    private var valid: Bool {
        profession.nilIfBlank != nil && description.trimmingCharacters(in: .whitespaces).count >= 10
            && city.nilIfBlank != nil && !modes.isEmpty && availability.nilIfBlank != nil
            && URL(string: shopUrl.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
    }

    var body: some View {
        Form {
            Section {
                TextField("Métier (ex. Coiffeur)", text: $profession)
                TextField("Présente ton activité", text: $description, axis: .vertical).lineLimit(3...6)
            } header: {
                Text("Activité")
            } footer: {
                Text("Ton nom, ta photo et ton numéro viennent de ton compte SBC.")
            }
            Section("Où tu interviens") {
                TextField("Ville principale", text: $city)
                TextField("Autres quartiers ou villes, séparés par des virgules", text: $zones)
            }
            Section("Comment tu travailles") {
                ForEach(ServiceMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { modes.contains(mode) },
                        set: { if $0 { modes.insert(mode) } else { modes.remove(mode) } }
                    )) {
                        Label(mode.label, systemImage: mode.systemImage)
                    }
                }
                TextField("Disponibilité (ex. lun–sam 8h–18h)", text: $availability)
            }
            Section("Prix indicatifs (facultatif)") {
                TextField("À partir de (FCFA)", text: $priceMin).keyboardType(.numberPad)
                TextField("Jusqu'à (FCFA)", text: $priceMax).keyboardType(.numberPad)
            }
            Section {
                TextField("https://…", text: $shopUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Boutique SBC Shop")
            } footer: {
                Text("Tes photos et réalisations restent sur ta boutique : les clients l'ouvrent depuis ta réponse.")
            }
            Section("WhatsApp (facultatif)") {
                TextField(store.proSpace?.phoneNumber ?? "Numéro, si différent de ton compte SBC", text: $whatsapp)
                    .keyboardType(.phonePad)
            }
            if let error {
                Text(error).foregroundStyle(SBCColors.error)
            }
        }
        .font(.sbc(.bodyLarge))
        .navigationTitle(store.isPro ? "Mon profil pro" : "Devenir pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { Task { await save() } }
                    .disabled(!valid || saving)
            }
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let p = store.proSpace?.profile else { return }
        profession = p.profession
        description = p.description
        city = p.city
        zones = p.zones.joined(separator: ", ")
        modes = Set(p.modes)
        availability = p.availability
        priceMin = p.priceMin.map(String.init) ?? ""
        priceMax = p.priceMax.map(String.init) ?? ""
        shopUrl = p.shopUrl
        whatsapp = p.whatsapp ?? ""
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let space = try await services.requests.saveProfile(.init(
                profession: profession.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                city: city.trimmingCharacters(in: .whitespaces),
                zones: zones.split(separator: ",").compactMap { String($0).nilIfBlank },
                modes: ServiceMode.allCases.filter(modes.contains),
                availability: availability.trimmingCharacters(in: .whitespaces),
                priceMin: Int(priceMin.filter(\.isNumber)),
                priceMax: Int(priceMax.filter(\.isNumber)),
                shopUrl: shopUrl.trimmingCharacters(in: .whitespaces),
                whatsapp: whatsapp.nilIfBlank
            ))
            store.setProSpace(space)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Ajouter un service": free text → AI proposals → keep, rename or drop →
/// save (Data §4, §5).
struct AddServicesView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var proposals: [ServiceProposal] = []
    @State private var profession = ""
    @State private var analysing = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RequestPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        RequestSectionLabel(text: "Ce que tu proposes").padding(.leading, -4)
                        TextField("Ex. je fais les dreads, pose de locks, entretien et réparation", text: $text, axis: .vertical)
                            .font(.sbc(.bodyLarge))
                            .lineLimit(2...5)
                        Button {
                            Task { await analyse() }
                        } label: {
                            if analysing {
                                HStack(spacing: 8) { ProgressView().tint(.white); Text("Analyse…") }
                            } else {
                                Label("Analyser avec l'IA", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(FilledButtonStyle(minHeight: 46))
                        .disabled(text.trimmingCharacters(in: .whitespaces).count < 3 || analysing)
                    }
                }

                if !proposals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PROPOSITION DE L'IA · À VALIDER")
                            .font(.sbc(.labelSmall, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(SBCColors.primary)
                        if !profession.isEmpty {
                            (Text("Métier : ").foregroundStyle(SBCColors.onSurfaceVariant) + Text(profession).bold())
                                .font(.sbc(.bodyMedium))
                        }
                        ForEach($proposals) { $proposal in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(SBCColors.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                TextField("Nom du service", text: $proposal.name)
                                    .font(.sbc(.bodyMedium, weight: .semibold))
                                Button {
                                    proposals.removeAll { $0.id == proposal.id }
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 14))
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                                .accessibilityLabel("Retirer \(proposal.name)")
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                        let synonyms = Set(proposals.flatMap(\.synonyms)).sorted()
                        if !synonyms.isEmpty {
                            Text("Mots reconnus aussi : \(synonyms.prefix(8).joined(separator: ", "))")
                                .font(.sbc(.bodySmall))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                        }
                    }
                    .padding(16)
                    .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SBCColors.primary, lineWidth: 1.5))
                }

                if let error {
                    Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .background(SBCColors.background)
        .safeAreaInset(edge: .bottom) {
            if !proposals.isEmpty {
                BottomActionBar {
                    Button("Valider ces services") { Task { await save() } }
                        .buttonStyle(FilledButtonStyle(background: SBCColors.onSurface, minHeight: 52))
                        .disabled(saving || proposals.contains { $0.name.nilIfBlank == nil })
                }
            }
        }
        .navigationTitle("Ajouter un service")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func analyse() async {
        analysing = true
        error = nil
        defer { analysing = false }
        do {
            let result = try await services.requests.structure(text)
            profession = result.profession
            proposals = result.services
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            store.setProSpace(try await services.requests.addServices(proposals))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

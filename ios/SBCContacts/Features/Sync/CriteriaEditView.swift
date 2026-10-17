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
    @Environment(\.services) private var services

    @State private var label: String
    @State private var filters: CriteriaFilters
    /// Ciblé filters the list by everything; anyone else by country only.
    @State private var countryOnly = true

    @State private var preview: Int?
    @State private var previewing = false
    @State private var saving = false
    @State private var confirmDelete = false

    init(existing: SyncCriteria?) {
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _filters = State(initialValue: CriteriaFilters(existing))
    }

    /// Its members are the "Augmenter mes vues WhatsApp" list, narrowed by the
    /// filters the member's subscription allows.
    private var boost: Bool { existing?.statusBoost ?? false }

    private var limited: Bool { boost && countryOnly }

    private var payload: CriteriaPayload {
        // Sent as such, a filter the subscription does not allow would be refused.
        (limited ? filters.countryOnly : filters).payload(
            label: label.trimmed.isEmpty ? (boost ? "Vues WhatsApp" : "Sans titre") : label.trimmed,
            regionOrder: regionsStore.catalog.all
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OutlinedField(label: "Nom du critère", systemImage: "tag") {
                    TextField("Ex. Maçons de Douala", text: $label)
                        .font(.sbc(.bodyLarge))
                }

                if boost {
                    StatusBoostNote().padding(.top, 20)
                }
                CriteriaFiltersForm(filters: $filters, countryOnly: limited)
                    .padding(.top, 20)

                // §10: show how many members the criteria matches before saving.
                HStack(spacing: 16) {
                    Image(systemName: "person.2.fill").foregroundStyle(SBCColors.onSurfaceVariant)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.map { "\($0) membre(s) correspondent" } ?? "Combien de membres correspondent ?")
                            .font(.sbc(.titleSmall, weight: .bold))
                        // Shown up front, not as an afterthought: the count only
                        // covers members already mirrored, so it always reads
                        // well below the same filter in the annuaire.
                        Text(boost
                            ? "Compté parmi les membres de la liste."
                            : "Compté parmi les membres déjà consultés dans l'annuaire, pas sur toute la base SBC.")
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
        .task {
            guard boost else { return }
            if let me = try? await services.api.statusBoostMe() { countryOnly = me.countryOnly }
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
        var counted = payload
        // Counted among the members of the list, not the whole mirror.
        if boost { counted.statusBoost = true }
        preview = try? await store.repo.previewAdhoc(counted)
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

/// What a "Vues WhatsApp" criteria is, above its filters.
private struct StatusBoostNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "eye.fill").foregroundStyle(SBCColors.whatsapp)
            Text("Ce critère enregistre les membres de « Augmenter mes vues WhatsApp » qui correspondent aux filtres ci-dessous. Il suit la liste : tu es prévenu quand quelqu'un la rejoint, et il se désactive si tu la quittes.")
                .font(.sbc(.bodySmall))
                .foregroundStyle(SBCColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SBCColors.surface))
    }
}

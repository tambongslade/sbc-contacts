import SwiftUI

/// Step 1 — "De quoi avez-vous besoin ?" (Data §6). Deliberately one big text
/// field: the member does not pick a profession first. The optional details
/// only override what the AI reads from the text.
struct RequestComposerView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var city = ""
    @State private var date = ""
    @State private var budget = ""
    @State private var analysing = false
    @State private var error: String?
    @State private var draft: ServiceRequestItem?
    @FocusState private var focused: Bool

    private var canContinue: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 && !analysing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StepHeader(step: 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("De quoi avez-vous besoin ?")
                        .font(.sbc(.headlineMedium, weight: .heavy))
                    Text("Écris librement, comme à un ami. L'IA comprend et trouve les bons pros.")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                }

                RequestPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        RequestSectionLabel(text: "Ton besoin").padding(.leading, -4)
                        TextField(
                            "Ex. Je cherche quelqu'un pour réparer mes locks à domicile samedi à Yaoundé",
                            text: $text,
                            axis: .vertical
                        )
                        .font(.sbc(.bodyLarge))
                        .lineLimit(4...8)
                        .focused($focused)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    RequestSectionLabel(text: "Précisions (facultatif)")
                    VStack(spacing: 0) {
                        DetailField(systemImage: "mappin.and.ellipse", tint: SBCColors.primary, label: "Lieu", placeholder: "Ville ou quartier", text: $city)
                        Divider().padding(.leading, 56)
                        DetailField(systemImage: "calendar", tint: SBCColors.secondaryDark, label: "Date", placeholder: "Ex. samedi", text: $date)
                        Divider().padding(.leading, 56)
                        DetailField(systemImage: "banknote", tint: SBCColors.accentDark, label: "Budget", placeholder: "FCFA", text: $budget)
                            .keyboardType(.numberPad)
                    }
                    .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let error {
                    Text(error)
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SBCColors.background)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    Task { await analyse() }
                } label: {
                    if analysing {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("L'IA analyse ta demande…")
                        }
                    } else {
                        Text("Continuer")
                    }
                }
                .buttonStyle(.large)
                .disabled(!canContinue)
            }
        }
        .navigationTitle("Nouvelle demande")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $draft) { RequestReviewView(request: $0) }
        .onAppear { focused = true }
    }

    private func analyse() async {
        analysing = true
        error = nil
        defer { analysing = false }
        let digits = budget.filter(\.isNumber)
        do {
            let created = try await services.requests.create(.init(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                city: city.nilIfBlank,
                budget: Int(digits),
                desiredDate: date.nilIfBlank
            ))
            store.upsert(created)
            draft = created
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Step 2 — "Vérifie ta demande": the AI's reading, correctable, plus its
/// question when the need is ambiguous (Data §6, §7).
struct RequestReviewView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State var request: ServiceRequestItem
    @State private var busy = false
    @State private var error: String?
    @State private var editing = false
    @State private var sent: ServiceRequestItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StepHeader(step: 2)
                Text("Vérifie ta demande")
                    .font(.sbc(.headlineMedium, weight: .heavy))

                RequestPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(SBCColors.primary)
                                .frame(width: 30, height: 30)
                                .background(SBCColors.primaryContainer, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("L'IA a compris")
                                .font(.sbc(.titleSmall, weight: .bold))
                            Spacer()
                            Button("Modifier") { editing = true }
                                .font(.sbc(.labelLarge, weight: .semibold))
                        }
                        .padding(.bottom, 6)
                        FactRow(label: "Métier", value: request.profession ?? "—")
                        Divider()
                        FactRow(label: "Service", value: request.service ?? "—")
                        Divider()
                        FactRow(label: "Lieu", value: [request.district, request.city].compactMap { $0 }.joined(separator: ", ").nilIfBlank ?? "—")
                        Divider()
                        FactRow(label: "Prestation", value: request.mode?.label ?? "Indifférent")
                        Divider()
                        FactRow(label: "Date", value: [request.desiredDate, request.desiredTime].compactMap { $0 }.joined(separator: " à ").nilIfBlank ?? "Flexible")
                        Divider()
                        FactRow(label: "Budget", value: request.budget.map { "\(fcfa($0)) max" } ?? "Non précisé")
                        if !request.constraints.isEmpty {
                            Divider()
                            FactRow(label: "Conditions", value: request.constraints.joined(separator: ", "))
                        }
                    }
                }

                if let question = request.clarificationQuestion {
                    ClarificationCard(
                        question: question,
                        options: request.clarificationOptions,
                        answer: request.clarificationAnswer,
                        busy: busy
                    ) { answer in
                        Task { await answerQuestion(answer) }
                    }
                }

                PrivacyNote(text: "Ton numéro reste privé. Les pros voient seulement ta demande, jusqu'à ce que tu les contactes.")

                if let error {
                    Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .background(SBCColors.background)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button {
                    Task { await send() }
                } label: {
                    Label("Envoyer ma demande", systemImage: "paperplane")
                }
                .buttonStyle(.large)
                .disabled(busy || request.needsAnswer)
            }
        }
        .navigationTitle("Résumé")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            EditReadingSheet(request: request) { updated in
                request = updated
                store.upsert(updated)
            }
        }
        .navigationDestination(item: $sent) { RequestDetailView(requestId: $0.id) }
    }

    private func answerQuestion(_ answer: String) async {
        busy = true
        defer { busy = false }
        do {
            request = try await services.requests.update(request.id, .init(clarificationAnswer: answer))
            store.upsert(request)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await services.requests.send(request.id)
            store.upsert(updated)
            toasts.show("Demande envoyée. On la transmet aux professionnels concernés.")
            sent = updated
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Une petite question" — tappable answers, orange like the brand accent.
private struct ClarificationCard: View {
    let question: String
    let options: [String]
    let answer: String?
    let busy: Bool
    let onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UNE PETITE QUESTION")
                .font(.sbc(.labelSmall, weight: .bold))
                .tracking(1)
                .foregroundStyle(SBCColors.accentDark)
            Text(question)
                .font(.sbc(.titleMedium, weight: .bold))
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let chosen = answer == option
                    Button(option) { onAnswer(option) }
                        .font(.sbc(.labelLarge, weight: .semibold))
                        .foregroundStyle(chosen ? .white : SBCColors.onSurface)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(chosen ? SBCColors.accentDark : SBCColors.surface))
                        .overlay(Capsule().stroke(SBCColors.accent.opacity(chosen ? 0 : 0.5)))
                        .buttonStyle(.plain)
                        .disabled(busy)
                }
            }
            if busy {
                ProgressView().padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SBCColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SBCColors.accent.opacity(0.35)))
    }
}

/// Correct what the AI read before sending.
private struct EditReadingSheet: View {
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    let request: ServiceRequestItem
    let onSaved: (ServiceRequestItem) -> Void

    @State private var service = ""
    @State private var city = ""
    @State private var district = ""
    @State private var mode: ServiceMode?
    @State private var date = ""
    @State private var budget = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Ce que tu cherches", text: $service)
                }
                Section("Lieu") {
                    TextField("Ville", text: $city)
                    TextField("Quartier (facultatif)", text: $district)
                }
                Section("Prestation") {
                    Picker("Mode", selection: $mode) {
                        Text("Indifférent").tag(ServiceMode?.none)
                        ForEach(ServiceMode.allCases) { Text($0.label).tag(ServiceMode?.some($0)) }
                    }
                    TextField("Date souhaitée", text: $date)
                    TextField("Budget max (FCFA)", text: $budget).keyboardType(.numberPad)
                }
                if let error {
                    Text(error).foregroundStyle(SBCColors.error)
                }
            }
            .font(.sbc(.bodyLarge))
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { Task { await save() } }.disabled(saving)
                }
            }
            .onAppear {
                service = request.service ?? ""
                city = request.city ?? ""
                district = request.district ?? ""
                mode = request.mode
                date = request.desiredDate ?? ""
                budget = request.budget.map(String.init) ?? ""
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let updated = try await services.requests.update(request.id, .init(
                service: service.nilIfBlank,
                city: city.nilIfBlank,
                district: district.nilIfBlank,
                mode: mode,
                desiredDate: date.nilIfBlank,
                budget: Int(budget.filter(\.isNumber))
            ))
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct StepHeader: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Étape \(step)/2")
                .font(.sbc(.labelMedium, weight: .semibold))
                .foregroundStyle(SBCColors.onSurfaceVariant)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SBCColors.outlineVariant.opacity(0.5))
                    Capsule().fill(SBCColors.primary).frame(width: geo.size.width * CGFloat(step) / 2)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct DetailField: View {
    let systemImage: String
    let tint: Color
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(label)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(.sbc(.bodyMedium, weight: .bold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

extension String {
    /// Trimmed, or nil when nothing is left.
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

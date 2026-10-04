import SwiftUI

/// The profile being built by the setup conversation (backend `ProDraft`).
/// Sent back on every turn: the server keeps no state.
struct ProDraft: Codable, Sendable, Equatable {
    struct Profile: Codable, Sendable, Equatable {
        var profession: String?
        var description: String?
        var city: String?
        var zones: [String] = []
        var modes: [ServiceMode] = []
        var availability: String?
        var priceMin: Int?
        var priceMax: Int?
        var shopUrl: String?
    }

    struct Service: Codable, Sendable, Equatable {
        var name: String
        var category: String
        var profession: String
        var synonyms: [String]
        var specialties: [String]
    }

    var profile = Profile()
    var services: [Service] = []
}

/// One turn of the conversation (backend `AssistantTurn`).
struct AssistantTurn: Decodable, Sendable {
    var reply: String
    var options: [String]
    var draft: ProDraft
    var missing: [String]
    var complete: Bool
    var available: Bool
}

struct AssistantMessage: Codable, Sendable, Equatable, Identifiable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String

    private enum CodingKeys: String, CodingKey { case role, text }
}

extension RequestsRepository {
    private struct TurnBody: Encodable, Sendable {
        let messages: [AssistantMessage]
        let draft: ProDraft?
    }

    func assistantTurn(messages: [AssistantMessage], draft: ProDraft?) async throws -> AssistantTurn {
        try await api.post("/data/pro/assistant", body: TurnBody(messages: messages, draft: draft))
    }
}

/// Pro setup as a conversation: the AI asks, the member answers in their own
/// words, and the profile and services are filled in from the answers. Nothing
/// is saved until the member confirms the summary.
struct ProAssistantView: View {
    /// Called once the profile and services are saved.
    let onSaved: () -> Void
    /// "Remplir moi-même": the plain form instead.
    let onUseForm: () -> Void

    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store

    @State private var messages: [AssistantMessage] = []
    @State private var draft: ProDraft?
    @State private var options: [String] = []
    @State private var complete = false
    @State private var unavailable = false
    @State private var thinking = false
    @State private var saving = false
    @State private var input = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { Bubble(message: $0) }
                    if thinking { TypingBubble().id("typing") }
                    if complete, let draft {
                        DraftSummary(draft: draft, existingServices: store.proSpace?.services.map(\.name) ?? [])
                            .id("summary")
                            .padding(.top, 6)
                    }
                    if unavailable {
                        Button("Remplir moi-même", action: onUseForm)
                            .buttonStyle(FilledButtonStyle(minHeight: 46))
                    }
                    if let error {
                        Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: complete) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(SBCColors.background)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("Assistant pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Remplir moi-même", action: onUseForm)
                    .font(.sbc(.labelLarge, weight: .semibold))
            }
        }
        .task {
            guard messages.isEmpty else { return }
            await send(nil)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if complete {
                Button {
                    Task { await save() }
                } label: {
                    if saving {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text("Création…") }
                    } else {
                        Text("Créer mon profil")
                    }
                }
                .buttonStyle(.large)
                .disabled(saving)
                Text("Quelque chose à corriger ? Écris-le simplement ci-dessous.")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            if !options.isEmpty, !thinking {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button(option) { Task { await send(option) } }
                                .font(.sbc(.labelLarge, weight: .semibold))
                                .foregroundStyle(SBCColors.primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 38)
                                .background(Capsule().fill(SBCColors.primaryContainer))
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ta réponse…", text: $input, axis: .vertical)
                    .font(.sbc(.bodyLarge))
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    let text = input
                    input = ""
                    Task { await send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(input.nilIfBlank == nil || thinking ? SBCColors.outlineVariant : SBCColors.primary))
                }
                .buttonStyle(.plain)
                .disabled(input.nilIfBlank == nil || thinking)
                .accessibilityLabel("Envoyer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Adds the member's answer (none on the opening turn) and asks for the next question.
    private func send(_ text: String?) async {
        if let text = text?.nilIfBlank {
            messages.append(.init(role: .user, text: text))
        } else if !messages.isEmpty {
            return
        }
        thinking = true
        error = nil
        options = []
        defer { thinking = false }
        do {
            let turn = try await services.requests.assistantTurn(messages: messages, draft: draft)
            messages.append(.init(role: .assistant, text: turn.reply))
            draft = turn.draft
            options = turn.options
            complete = turn.complete
            unavailable = !turn.available
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let p = draft?.profile, let profession = p.profession, let description = p.description,
              let city = p.city, let availability = p.availability, let shopUrl = p.shopUrl
        else { return }
        saving = true
        defer { saving = false }
        do {
            var space = try await services.requests.saveProfile(.init(
                profession: profession,
                description: description,
                city: city,
                zones: p.zones,
                modes: p.modes,
                availability: availability,
                priceMin: p.priceMin,
                priceMax: p.priceMax,
                shopUrl: shopUrl,
                whatsapp: store.proSpace?.profile?.whatsapp
            ))
            if let new = draft?.services, !new.isEmpty {
                space = try await services.requests.addServices(new.map {
                    ServiceProposal(name: $0.name, category: $0.category, profession: $0.profession, synonyms: $0.synonyms, specialties: $0.specialties)
                })
            }
            store.setProSpace(space)
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct Bubble: View {
    let message: AssistantMessage

    var body: some View {
        let mine = message.role == .user
        HStack {
            if mine { Spacer(minLength: 48) }
            Text(message.text)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(mine ? .white : SBCColors.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(mine ? SBCColors.primary : SBCColors.surface)
                )
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 48) }
        }
    }
}

private struct TypingBubble: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(SBCColors.onSurfaceVariant)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SBCColors.surface))
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi }
        }
        .accessibilityLabel("L'assistant écrit")
    }
}

/// "Voici ton profil" — what will be saved, to check before confirming.
private struct DraftSummary: View {
    let draft: ProDraft
    let existingServices: [String]

    var body: some View {
        let p = draft.profile
        RequestPanel {
            VStack(alignment: .leading, spacing: 0) {
                Label("Voici ton profil", systemImage: "sparkles")
                    .font(.sbc(.titleSmall, weight: .heavy))
                    .foregroundStyle(SBCColors.primary)
                    .padding(.bottom, 6)
                FactRow(label: "Métier", value: p.profession ?? "—")
                Divider()
                FactRow(label: "Lieu", value: ([p.city].compactMap { $0 } + p.zones).joined(separator: ", "))
                Divider()
                FactRow(label: "Prestation", value: p.modes.map(\.label).joined(separator: ", "))
                Divider()
                FactRow(label: "Disponibilité", value: p.availability ?? "—")
                if p.priceMin != nil || p.priceMax != nil {
                    Divider()
                    FactRow(label: "Prix", value: [p.priceMin.map(fcfa), p.priceMax.map(fcfa)].compactMap { $0 }.joined(separator: " – "))
                }
                Divider()
                FactRow(label: "Boutique", value: p.shopUrl ?? "—")
                if let description = p.description {
                    Text(description)
                        .font(.sbc(.bodySmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .padding(.vertical, 10)
                }
                let names = existingServices + draft.services.map(\.name)
                if !names.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Services").font(.sbc(.bodyMedium)).foregroundStyle(SBCColors.onSurfaceVariant)
                        FlowLayout(spacing: 6) {
                            ForEach(names, id: \.self) { TagChip(label: $0) }
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }
}

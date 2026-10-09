import SwiftUI

/// A request as the pro sees it: the need, never who asked, and the four
/// answers (Data §10, §22). Opening it marks it seen.
struct InboxDetailView: View {
    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State var item: InboxItem
    @State private var proposing = false
    @State private var asking = false
    @State private var writing = false
    @State private var busy = false
    @State private var error: String?

    private var request: ServiceRequestItem { item.request }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.title)
                        .font(.sbc(.headlineSmall, weight: .heavy))
                    if let matched = item.matchedService {
                        Label("Correspond à ton service « \(matched) »", systemImage: "checkmark")
                            .font(.sbc(.labelMedium, weight: .bold))
                            .foregroundStyle(SBCColors.onPrimaryContainer)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(SBCColors.primaryContainer))
                    }
                }

                Text("« \(request.rawText) »")
                    .font(.sbc(.bodyLarge))
                    .foregroundStyle(SBCColors.onSurface)

                RequestPanel(padding: 14) {
                    VStack(spacing: 0) {
                        FactRow(label: "Lieu", value: [request.district, request.city].compactMap { $0 }.joined(separator: ", ").nilIfBlank ?? "Non précisé")
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

                PrivacyNote(text: "Les coordonnées du client s'affichent quand il choisit de te contacter.")

                if !item.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        RequestSectionLabel(text: "Conversation")
                        RequestPanel(padding: 14) {
                            VStack(alignment: .leading, spacing: 12) {
                                ConversationThread(messages: item.messages, me: .pro, otherName: "Le client")
                                if item.status.canTalk && !request.status.isClosed {
                                    Button {
                                        writing = true
                                    } label: {
                                        Label("Écrire au client", systemImage: "arrowshape.turn.up.left")
                                    }
                                    .buttonStyle(OutlinedButtonStyle(minHeight: 42))
                                }
                            }
                        }
                    }
                }

                ProTimeline(item: item)

                if !item.status.isOpen {
                    AnswerSummary(item: item)
                }
                if let error {
                    Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .background(SBCColors.background)
        .safeAreaInset(edge: .bottom) {
            if item.status.isOpen, request.status == .sent || request.status == .responded {
                BottomActionBar {
                    Button("Je suis intéressé") { proposing = true }
                        .buttonStyle(.large)
                    Button("Poser une question") { asking = true }
                        .buttonStyle(OutlinedButtonStyle(minHeight: 46))
                    HStack(spacing: 10) {
                        Button("Pas disponible") { Task { await respond(.init(action: .unavailable)) } }
                        Button("Je ne peux pas") { Task { await respond(.init(action: .declined)) } }
                    }
                    .buttonStyle(OutlinedButtonStyle(minHeight: 42))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                }
                .disabled(busy)
            }
        }
        .navigationTitle("Demande reçue")
        .navigationBarTitleDisplayMode(.inline)
        .task { await open() }
        .sheet(isPresented: $proposing) {
            ProposalSheet(budget: request.budget) { body in
                await respond(body)
            }
        }
        .sheet(isPresented: $writing) {
            MessageComposer(title: "Écrire au client", placeholder: "Ton message") { text in
                do {
                    item = try await services.requests.proSendMessage(requestId: request.id, text: text)
                    store.upsert(item)
                    return true
                } catch {
                    self.error = error.localizedDescription
                    return false
                }
            }
        }
        .sheet(isPresented: $asking) {
            QuestionSheet { question in
                await respond(.init(action: .question, message: question))
            }
        }
    }

    private func open() async {
        do {
            item = try await services.requests.open(requestId: request.id)
            store.upsert(item)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    private func respond(_ body: RequestsRepository.RespondBody) async -> Bool {
        busy = true
        defer { busy = false }
        do {
            item = try await services.requests.respond(requestId: request.id, body)
            store.upsert(item)
            switch body.action {
            case .interested: toasts.show("Proposition envoyée. Le client compare et choisit.")
            case .question: toasts.show("Question envoyée au client.")
            case .unavailable, .declined: toasts.show("C'est noté."); dismiss()
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// What the pro already answered, once they have.
private struct AnswerSummary: View {
    let item: InboxItem

    var body: some View {
        RequestPanel {
            VStack(alignment: .leading, spacing: 8) {
                StatusTag(text: item.status.label, tone: tone(for: item.status))
                if let price = item.price { FactRow(label: "Prix proposé", value: fcfa(price)) }
                if let availability = item.availability { FactRow(label: "Disponibilité", value: availability) }
                if let delay = item.delay { FactRow(label: "Durée", value: delay) }
                if let message = item.message {
                    Text("« \(message) »").font(.sbc(.bodyMedium))
                }
            }
        }
    }
}

/// "Ta proposition" — price, slot, duration, message (Data §10).
private struct ProposalSheet: View {
    let budget: Int?
    let onSend: (RequestsRepository.RespondBody) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var price = ""
    @State private var availability = ""
    @State private var delay = ""
    @State private var message = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Prix", text: $price).keyboardType(.numberPad)
                        Text("FCFA").foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                } header: {
                    Text("Prix proposé")
                } footer: {
                    if let budget { Text("Budget du client : \(fcfa(budget)) max") }
                }
                Section("Disponibilité") {
                    TextField("Ex. samedi 14h", text: $availability)
                }
                Section("Durée (facultatif)") {
                    TextField("Ex. 2 heures", text: $delay)
                }
                Section("Message (facultatif)") {
                    TextField("Précisions pour le client", text: $message, axis: .vertical).lineLimit(3...6)
                }
            }
            .font(.sbc(.bodyLarge))
            .navigationTitle("Ta proposition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        Task {
                            sending = true
                            let ok = await onSend(.init(
                                action: .interested,
                                price: Int(price.filter(\.isNumber)),
                                availability: availability.nilIfBlank,
                                delay: delay.nilIfBlank,
                                message: message.nilIfBlank
                            ))
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(availability.nilIfBlank == nil || sending)
                }
            }
        }
        .presentationDetents([.large])
    }
}

private struct QuestionSheet: View {
    let onSend: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex. Les locks sont-elles longues ?", text: $question, axis: .vertical).lineLimit(3...6)
                } footer: {
                    Text("Le client la voit avec ta réponse.")
                }
            }
            .font(.sbc(.bodyLarge))
            .navigationTitle("Poser une question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Envoyer") {
                        Task {
                            sending = true
                            let ok = await onSend(question.trimmingCharacters(in: .whitespacesAndNewlines))
                            sending = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(question.nilIfBlank == nil || sending)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// What happened to this request, from the pro's side (Data §18): received,
/// seen, answered, and how it ended.
private struct ProTimeline: View {
    let item: InboxItem

    private struct Step: Identifiable {
        let id: String
        let label: String
        let date: Date?
        let done: Bool
        var tone: Color = SBCColors.primary
    }

    private var outcome: Step {
        switch item.status {
        case .selected where item.request.status == .completed:
            Step(id: "end", label: "Prestation terminée", date: nil, done: true, tone: SBCColors.success)
        case .selected:
            Step(id: "end", label: "Tu as été retenu", date: nil, done: true, tone: SBCColors.success)
        case .lost:
            Step(id: "end", label: item.request.status == .cancelled ? "Demande annulée" : "Un autre professionnel a été retenu",
                 date: nil, done: true, tone: SBCColors.onSurfaceVariant)
        case .unavailable, .declined:
            Step(id: "end", label: "Tu as décliné", date: nil, done: true, tone: SBCColors.onSurfaceVariant)
        default:
            Step(id: "end", label: "En attente du choix du client", date: nil, done: false)
        }
    }

    private var steps: [Step] {
        [
            Step(id: "in", label: "Demande reçue", date: item.createdAt, done: true),
            Step(id: "seen", label: "Vue", date: item.viewedAt, done: item.viewedAt != nil),
            Step(id: "answer", label: item.status == .question ? "Question posée" : "Ta réponse", date: item.respondedAt, done: item.respondedAt != nil),
            outcome,
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RequestSectionLabel(text: "Suivi")
            RequestPanel(padding: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(step.done ? step.tone : SBCColors.surface)
                                    .overlay(Circle().stroke(step.done ? step.tone : SBCColors.outlineVariant, lineWidth: 2))
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 3)
                                if index < steps.count - 1 {
                                    Rectangle()
                                        .fill(steps[index + 1].done ? SBCColors.primary.opacity(0.4) : SBCColors.outlineVariant)
                                        .frame(width: 2)
                                        .frame(minHeight: 22)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.label)
                                    .font(.sbc(.bodyMedium, weight: step.done ? .bold : .medium))
                                    .foregroundStyle(step.done ? SBCColors.onSurface : SBCColors.onSurfaceVariant)
                                if let date = step.date {
                                    Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                        .font(.sbc(.labelSmall))
                                        .foregroundStyle(SBCColors.onSurfaceVariant)
                                }
                            }
                            .padding(.bottom, 10)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

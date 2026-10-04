import SwiftUI

/// One of the member's requests: where it stands, the answers as comparable
/// cards, choosing a pro, and closing it with a rating (Data §11–§16).
struct RequestDetailView: View {
    let requestId: String

    @Environment(\.services) private var services
    @Environment(RequestsStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    @State private var request: ServiceRequestItem?
    @State private var error: String?
    @State private var busy = false
    @State private var completing = false
    @State private var confirmCancel = false
    @State private var choosing: RequestResponse?
    @State private var deleting: ServiceRequestItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let request {
                content(request)
            } else if let error {
                EmptyStateView(systemImage: "exclamationmark.circle", title: "Erreur", message: error)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SBCColors.background)
        .navigationTitle("Demande")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let request { DeleteRequestButton(request: request, target: $deleting) }
            }
        }
        .confirmDeleteRequest($deleting) { dismiss() }
        .task { await load() }
        .task(id: request?.status == .matching) {
            // Matching runs on the server for a few seconds; follow it.
            while request?.status == .matching, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await load()
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ request: ServiceRequestItem) -> some View {
        let answers = request.responses.filter { $0.status != .unavailable && $0.status != .declined }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.sbc(.headlineSmall, weight: .heavy))
                    if !request.subtitle.isEmpty || request.budget != nil {
                        Text([request.subtitle.nilIfBlank, request.budget.map { "\(fcfa($0)) max" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.sbc(.bodyMedium))
                            .foregroundStyle(SBCColors.onSurfaceVariant)
                    }
                }
                StatusTimeline(status: request.status)

                switch request.status {
                case .matching:
                    InfoCard(systemImage: "sparkle.magnifyingglass", text: "On cherche les professionnels qui correspondent…", busy: true)
                case .sent where answers.isEmpty:
                    InfoCard(systemImage: "paperplane", text: "Transmise à \(request.dispatchedCount) professionnel\(request.dispatchedCount > 1 ? "s" : ""). Leurs réponses apparaîtront ici.")
                case .noMatch:
                    InfoCard(systemImage: "person.crop.circle.badge.questionmark", text: "Aucun professionnel ne correspond encore à cette demande. Essaie de la formuler autrement ou élargis le lieu.")
                case .cancelled:
                    InfoCard(systemImage: "xmark.circle", text: "Tu as annulé cette demande.")
                default:
                    EmptyView()
                }

                if !answers.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(answers.count) réponse\(answers.count > 1 ? "s" : "")")
                            .font(.sbc(.titleMedium, weight: .heavy))
                        Spacer()
                        if request.status == .responded || request.status == .sent {
                            Text("Compare et choisis")
                                .font(.sbc(.bodySmall))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                        }
                    }
                    ForEach(answers) { response in
                        ResponseCard(
                            response: response,
                            request: request,
                            canChoose: (request.status == .responded || request.status == .sent) && !busy
                        ) { choosing = response }
                    }
                }

                if let error {
                    Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if request.status == .selected {
                BottomActionBar {
                    Button("Prestation terminée ?") { completing = true }
                        .buttonStyle(.large)
                }
            } else if [.sent, .responded, .matching].contains(request.status) {
                Button("Annuler la demande", role: .destructive) { confirmCancel = true }
                    .font(.sbc(.labelLarge, weight: .semibold))
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $completing) {
            CompleteRequestSheet(request: request) { updated in
                self.request = updated
                store.upsert(updated)
            }
        }
        .alert("Retenir ce professionnel ?", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })) {
            Button("Annuler", role: .cancel) {}
            Button("Retenir") {
                if let choosing { Task { await select(choosing) } }
            }
        } message: {
            Text("\(choosing?.displayName ?? "") recevra une notification. Les autres verront que la demande est pourvue.")
        }
        .alert("Annuler la demande ?", isPresented: $confirmCancel) {
            Button("Non", role: .cancel) {}
            Button("Annuler la demande", role: .destructive) { Task { await cancel() } }
        }
    }

    private func load() async {
        do {
            let fresh = try await services.requests.get(requestId)
            request = fresh
            store.upsert(fresh)
        } catch {
            if request == nil { self.error = error.localizedDescription }
        }
    }

    private func select(_ response: RequestResponse) async {
        guard let request else { return }
        busy = true
        defer { busy = false }
        do {
            let updated = try await services.requests.select(request.id, dispatchId: response.id)
            self.request = updated
            store.upsert(updated)
            toasts.show("Choix enregistré. Écris à \(response.displayName) sur WhatsApp pour caler les détails.")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func cancel() async {
        guard let request else { return }
        do {
            let updated = try await services.requests.cancel(request.id)
            self.request = updated
            store.upsert(updated)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Envoyée → Réponses → Retenu → Terminée, the member's sense of progress.
private struct StatusTimeline: View {
    let status: RequestStatus

    private static let steps = ["Envoyée", "Réponses", "Retenu", "Terminée"]

    private var reached: Int {
        switch status {
        case .draft, .matching: 0
        case .sent, .noMatch, .noResponse, .cancelled, .unknown: 1
        case .responded: 2
        case .selected: 3
        case .completed: 4
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, label in
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Rectangle().fill(i == 0 ? .clear : (i < reached ? SBCColors.primary : SBCColors.outlineVariant)).frame(height: 2)
                        Circle()
                            .fill(i < reached ? SBCColors.primary : SBCColors.surface)
                            .overlay(Circle().stroke(i < reached ? SBCColors.primary : SBCColors.outlineVariant, lineWidth: 2))
                            .frame(width: 14, height: 14)
                        Rectangle().fill(i == Self.steps.count - 1 ? .clear : (i + 1 < reached ? SBCColors.primary : SBCColors.outlineVariant)).frame(height: 2)
                    }
                    Text(label)
                        .font(.sbc(.labelSmall, weight: i < reached ? .bold : .medium))
                        .foregroundStyle(i < reached ? SBCColors.onSurface : SBCColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Statut : \(status.label)")
    }
}

private struct InfoCard: View {
    let systemImage: String
    let text: String
    var busy = false

    var body: some View {
        RequestPanel {
            HStack(spacing: 12) {
                if busy { ProgressView() } else {
                    Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(SBCColors.primary)
                }
                Text(text)
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurface)
            }
        }
    }
}

/// One pro's answer: who, for what, at what price and when — plus WhatsApp,
/// their SBC Shop and "Retenir" (Data §11, §13, §14).
private struct ResponseCard: View {
    let response: RequestResponse
    let request: ServiceRequestItem
    let canChoose: Bool
    let onChoose: () -> Void

    @Environment(\.openURL) private var openURL

    /// Data §13: pre-filled, editable in WhatsApp before sending.
    private var whatsAppText: String {
        "Bonjour, je vous contacte via SBC Network concernant ma demande de \(request.service ?? "service")."
    }

    var body: some View {
        RequestPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MemberAvatar(initials: initials(of: response.displayName), avatarUrl: response.avatarUrl, radius: 26, rounded: true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(response.displayName)
                            .font(.sbc(.titleMedium, weight: .heavy))
                        HStack(spacing: 6) {
                            TagChip(label: response.profession)
                            ConfidenceScorePill(score: response.confidenceScore)
                        }
                    }
                    Spacer(minLength: 0)
                    switch response.status {
                    case .selected: StatusTag(text: "Retenu", tone: SBCColors.success)
                    case .lost: StatusTag(text: "Non retenu", tone: SBCColors.onSurfaceVariant)
                    case .question: StatusTag(text: "Question", tone: SBCColors.accentDark)
                    default: EmptyView()
                    }
                }

                if let service = response.serviceName {
                    (Text("Service : ").foregroundStyle(SBCColors.onSurfaceVariant) + Text(service).bold())
                        .font(.sbc(.bodySmall))
                }

                if response.price != nil || response.availability != nil || response.delay != nil {
                    HStack(spacing: 8) {
                        Fact(label: "Prix", value: response.price.map(fcfa) ?? "Sur devis")
                        Fact(label: "Dispo", value: response.availability ?? "—")
                        Fact(label: "Durée", value: response.delay ?? "—")
                    }
                }

                if let message = response.message, !message.isEmpty {
                    Text("« \(message) »")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurface)
                }

                HStack(spacing: 8) {
                    Button {
                        if let phone = response.whatsapp { openWhatsApp(phone, presetText: whatsAppText) }
                    } label: {
                        ZStack {
                            Circle().fill(SBCColors.whatsapp)
                            WhatsAppGlyph().foregroundStyle(.white).frame(width: 24, height: 24)
                        }
                        .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .disabled(response.whatsapp == nil)
                    .accessibilityLabel("Contacter sur WhatsApp")

                    if let url = URL(string: response.shopUrl), !response.shopUrl.isEmpty {
                        Button { openURL(url) } label: {
                            Label("Boutique", systemImage: "bag")
                        }
                        .buttonStyle(OutlinedButtonStyle(minHeight: 46, fullWidth: false))
                        .accessibilityLabel("Voir la boutique SBC Shop")
                    }

                    if canChoose, response.status == .interested || response.status == .question {
                        Button("Retenir", action: onChoose)
                            .buttonStyle(FilledButtonStyle(minHeight: 46))
                    }
                }
            }
        }
    }
}

private struct Fact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.sbc(.labelSmall, weight: .semibold))
                .foregroundStyle(SBCColors.onSurfaceVariant)
            Text(value)
                .font(.sbc(.bodyMedium, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SBCColors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// "Comment ça s'est passé ?" — done or not, stars, comment, or a report (Data §15).
struct CompleteRequestSheet: View {
    let request: ServiceRequestItem
    let onDone: (ServiceRequestItem) -> Void

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var performed = true
    @State private var stars = 0
    @State private var comment = ""
    @State private var saving = false
    @State private var error: String?

    private var chosen: RequestResponse? {
        request.responses.first { $0.status == .selected }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let chosen {
                        HStack(spacing: 12) {
                            MemberAvatar(initials: initials(of: chosen.displayName), avatarUrl: chosen.avatarUrl, radius: 24, rounded: true)
                            VStack(alignment: .leading) {
                                Text(chosen.displayName).font(.sbc(.titleMedium, weight: .heavy))
                                Text(request.title).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.onSurfaceVariant)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("La prestation a-t-elle été réalisée ?")
                            .font(.sbc(.titleSmall, weight: .bold))
                        Picker("Réalisée", selection: $performed) {
                            Text("Oui").tag(true)
                            Text("Non").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if performed {
                        VStack(spacing: 6) {
                            Text("Ta note").font(.sbc(.titleSmall, weight: .bold))
                            StarRatingInput(value: $stars)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        RequestSectionLabel(text: performed ? "Commentaire (facultatif)" : "Que s'est-il passé ?")
                        TextField(performed ? "Ton retour" : "Décris le problème", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !performed {
                        PrivacyNote(text: "Ton signalement est transmis à l'équipe SBC, pas au professionnel.")
                    }
                    if let error {
                        Text(error).font(.sbc(.bodySmall)).foregroundStyle(SBCColors.error)
                    }
                }
                .padding(16)
            }
            .background(SBCColors.background)
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button(performed ? "Terminer et publier mon avis" : "Signaler un problème") {
                        Task { await submit() }
                    }
                    .buttonStyle(FilledButtonStyle(background: performed ? SBCColors.primary : SBCColors.error, minHeight: 52))
                    .disabled(saving || (performed && stars == 0) || (!performed && comment.nilIfBlank == nil))
                }
            }
            .navigationTitle("Fin de prestation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func submit() async {
        saving = true
        defer { saving = false }
        do {
            let updated = try await services.requests.complete(request.id, .init(
                performed: performed,
                stars: performed ? stars : nil,
                comment: comment.nilIfBlank
            ))
            onDone(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

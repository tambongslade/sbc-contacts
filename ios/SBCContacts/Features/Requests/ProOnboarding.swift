import SwiftUI

/// The two prompts shown after login, and when each may show again.
///
/// A member who is not a pro is invited at most once a week. A pro whose
/// setup is incomplete is reminded daily: they may be paying for reception
/// and getting nothing, and should know why.
enum ProInvite: String, Identifiable {
    case becomePro
    case finishSetup

    var id: String { rawValue }

    private var snooze: TimeInterval {
        switch self {
        case .becomePro: 7 * 24 * 3600
        case .finishSetup: 24 * 3600
        }
    }

    /// The prompt this member should get, if any.
    static func kind(for space: ProSpace) -> ProInvite? {
        if space.profile == nil { return .becomePro }
        return space.missingSetup.isEmpty ? nil : .finishSetup
    }

    /// Debug builds launched with `-pro-invite` show the prompt on every
    /// launch, so the sheets can be checked on any account.
    static var forced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-pro-invite")
        #else
        false
        #endif
    }

    func isDue(userId: String, now: Date = .now) -> Bool {
        if Self.forced { return true }
        guard let last = UserDefaults.standard.object(forKey: key(userId)) as? Date else { return true }
        return now.timeIntervalSince(last) > snooze
    }

    func markShown(userId: String) {
        UserDefaults.standard.set(Date.now, forKey: key(userId))
    }

    private func key(_ userId: String) -> String { "\(rawValue).lastShown.\(userId)" }
}

/// The sheet shown after login: the invitation (or, for a pro, what is left
/// to set up), then the guided setup — profile, services, done.
struct ProOnboardingFlow: View {
    enum Step: Hashable { case assistant, profile, services, ready }

    let kind: ProInvite

    @Environment(\.dismiss) private var dismiss
    @Environment(RequestsStore.self) private var store
    @State private var path: [Step] = []
    @State private var detent: PresentationDetent = .medium

    private var missing: [ProSetupItem] { store.proSpace?.missingSetup ?? [] }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch kind {
                case .becomePro:
                    ProInvitationView(onStart: { start(at: .assistant) }, onLater: { dismiss() })
                case .finishSetup:
                    FinishSetupView(
                        missing: missing,
                        receivingActive: store.proSpace?.receivingActive == true,
                        onStart: { start(at: .assistant) },
                        onLater: { dismiss() }
                    )
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .assistant:
                    // The AI asks; the form stays one tap away.
                    ProAssistantView(
                        onSaved: { path.append(.ready) },
                        onUseForm: { path.append(missing.contains(.profile) || kind == .becomePro ? .profile : .services) }
                    )
                case .profile:
                    ProProfileFormView(onSaved: {
                        path.append(missing.contains(.services) || kind == .becomePro ? .services : .ready)
                    })
                case .services:
                    AddServicesView(onSaved: { path.append(.ready) })
                case .ready:
                    ProReadyView { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private func start(at step: Step) {
        detent = .large
        path.append(step)
    }
}

/// "Termine ton profil pro" — for a pro whose profile or services are not
/// there yet, saying plainly that nothing reaches them until they are.
private struct FinishSetupView: View {
    let missing: [ProSetupItem]
    let receivingActive: Bool
    let onStart: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(SBCColors.accentDark, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 8)

            Text("Termine ton profil pro")
                .font(.sbc(.headlineSmall, weight: .heavy))
                .padding(.top, 16)

            Text(receivingActive
                ? "Ton abonnement Pro est actif, mais aucune demande ne peut t'arriver tant que ton profil n'est pas complet."
                : "Aucune demande ne peut t'arriver tant que ton profil n'est pas complet.")
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(missing, id: \.self) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(SBCColors.accentDark)
                        Text(item.todo)
                            .font(.sbc(.bodyMedium, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SBCColors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 18)

            Spacer(minLength: 20)

            Button("Compléter mon profil", action: onStart)
                .buttonStyle(.large)
            Button("Plus tard", action: onLater)
                .buttonStyle(.text)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(SBCColors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// "Tu proposes un service ?" — what being a pro gets you, in three lines.
private struct ProInvitationView: View {
    let onStart: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(SBCColors.brandArc, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 8)

            Text("Tu proposes un service ?")
                .font(.sbc(.headlineSmall, weight: .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                Benefit(systemImage: "text.bubble", text: "Décris ce que tu sais faire, avec tes mots.")
                Benefit(systemImage: "tray.and.arrow.down", text: "Reçois les demandes des membres qui en ont besoin, près de chez toi.")
                Benefit(systemImage: "hand.thumbsup", text: "Réponds avec ton prix, le client te choisit et te contacte sur WhatsApp.")
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 20)

            Button("Devenir professionnel", action: onStart)
                .buttonStyle(.large)
            Button("Plus tard", action: onLater)
                .buttonStyle(.text)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(SBCColors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct Benefit: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SBCColors.primary)
                .frame(width: 32, height: 32)
                .background(SBCColors.primaryContainer, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The end of the setup. Reception is the paid part, so it says plainly that
/// requests start once the Pro subscription is active.
private struct ProReadyView: View {
    @Environment(RequestsStore.self) private var store
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(SBCColors.success)
            Text("Ton profil pro est prêt")
                .font(.sbc(.headlineSmall, weight: .heavy))
            Text(store.proSpace?.receivingActive == true
                ? "Tu recevras ici les demandes qui correspondent à tes services."
                : "Pour recevoir les demandes, active l'abonnement Pro (2 000 FCFA/mois) auprès de SBC. Tu retrouves tout dans Profil › Espace pro.")
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Terminer", action: onDone)
                .buttonStyle(.large)
        }
        .padding(24)
        .background(SBCColors.background)
        .navigationBarBackButtonHidden()
    }
}

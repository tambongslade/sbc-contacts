import SwiftUI

/// When the "become a pro" invitation may show again. Waving it away (or
/// swiping it down) snoozes it a week, per account, so a member who is not a
/// professional is asked from time to time, never at every launch.
enum ProInvite {
    static let snooze: TimeInterval = 7 * 24 * 3600

    /// Debug builds launched with `-pro-invite` show the invitation on every
    /// launch, pro or not, so the sheet can be checked on any account.
    static var forced: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-pro-invite")
        #else
        false
        #endif
    }

    static func isDue(userId: String, now: Date = .now) -> Bool {
        if forced { return true }
        guard let last = UserDefaults.standard.object(forKey: key(userId)) as? Date else { return true }
        return now.timeIntervalSince(last) > snooze
    }

    static func markShown(userId: String) {
        UserDefaults.standard.set(Date.now, forKey: key(userId))
    }

    private static func key(_ userId: String) -> String { "proInvite.lastShown.\(userId)" }
}

/// The sheet shown after login to members who are not pros yet: the
/// invitation, then the guided setup — profile, services, done.
struct ProOnboardingFlow: View {
    enum Step: Hashable { case profile, services, ready }

    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        NavigationStack(path: $path) {
            ProInvitationView(
                onStart: {
                    detent = .large
                    path.append(.profile)
                },
                onLater: { dismiss() }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .profile:
                    ProProfileFormView(onSaved: { path.append(.services) })
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

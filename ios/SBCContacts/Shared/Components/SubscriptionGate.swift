import SwiftUI

/// The paywall, on every screen an SBC account unlocks: it has to explain
/// what is behind the lock, not just refuse.
struct SubscriptionGate: View {
    /// An SBC Network account: it needs an SBC account, not a subscription,
    /// and has nothing to retry.
    var networkAccount = false
    var onRetry: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(SBCColors.brandArc).frame(height: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "lock")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(SBCColors.accent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SBCColors.accent.opacity(0.12)))
                    Text(networkAccount ? "Réservé aux membres SBC" : "Réservé aux abonnés SBC")
                        .font(.sbc(.titleLarge, weight: .heavy))
                        .foregroundStyle(SBCColors.onSurface)
                        .padding(.top, 16)
                    Text(networkAccount
                        ? "Active ton compte SBC et profite de toutes les fonctionnalités réservées aux membres SBC pour développer ta visibilité sur WhatsApp."
                        : "L’annuaire des membres est réservé aux abonnés SBC. Active ton abonnement, puis actualise cette page.")
                        .font(.sbc(.bodyMedium))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .lineSpacing(4)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        if networkAccount {
                            benefit("eye", "Augmente tes vues WhatsApp : plus de visibilité pour tes statuts, rapidement")
                            benefit("person.3", "Tout l’annuaire des membres SBC : des milliers de contacts qualifiés")
                            benefit("slider.horizontal.3", "Filtres avancés : par métier, région, âge, centres d’intérêt…")
                            benefit("bubble.left", "Contact WhatsApp direct : discute et ajoute facilement au répertoire")
                        } else {
                            benefit("person.3", "Tout le répertoire des membres SBC")
                            benefit("slider.horizontal.3", "Filtres par métier, région, âge et centres d’intérêt")
                            benefit("bubble.left", "Contact WhatsApp direct et ajout au répertoire")
                        }
                    }
                    .padding(.top, 18)
                    if let onRetry {
                        Button(action: onRetry) {
                            Label("J’ai activé mon abonnement", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(FilledButtonStyle(minHeight: 48))
                        .padding(.top, 20)
                    }
                    if !networkAccount {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 13))
                            Text("Ton abonnement se gère dans l’onglet Profil.").font(.sbc(.bodySmall))
                        }
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                        .padding(.top, 10)
                    }
                }
                .padding(20)
            }
            .background(SBCColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SBCColors.outlineVariant.opacity(0.6)))
            .padding(EdgeInsets(top: 24, leading: 20, bottom: 32, trailing: 20))
            .appearAnimation(offset: 0)
        }
    }

    private func benefit(_ icon: String, _ label: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(SBCColors.primary)
                .frame(width: 20)
            Text(label)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurface)
        }
    }
}

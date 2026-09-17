import SwiftUI

/// "Mon profil" — identity, subscription status and the sign-out affordance.
///
/// The subscription is the gate to the whole directory, so it is presented as a
/// status badge (and, when missing, as an explicit upsell block) rather than as
/// a quiet list row.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        ScrollView {
            if let user = auth.user {
                VStack(alignment: .leading, spacing: 20) {
                    ProfileHeader(user: user)
                        .appearAnimation()
                    SubscriptionBlock(user: user)
                        .appearAnimation(delay: 0.06)
                    InfoBlock(user: user)
                        .appearAnimation(delay: 0.12)
                    LogoutButton()
                        .padding(.top, 8)
                }
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 32, trailing: 16))
            }
        }
        .refreshable { await auth.refreshProfile() }
        .background(SBCColors.background)
        .navigationTitle("Mon profil")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Header

private struct ProfileHeader: View {
    let user: AppUser

    private let bandHeight: CGFloat = 88
    private let avatarRadius: CGFloat = 42
    private let ringWidth: CGFloat = 4
    private let ringGap: CGFloat = 3
    private var ringDiameter: CGFloat { (avatarRadius + ringWidth + ringGap) * 2 }

    var body: some View {
        SurfaceCard(padding: 0) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Signature brand arc: blue → green → orange.
                    Rectangle()
                        .fill(SBCColors.brandArc)
                        .frame(height: bandHeight)

                    VStack(spacing: 0) {
                        Text(user.displayName)
                            .font(.sbc(.titleLarge, weight: .heavy))
                            .foregroundStyle(SBCColors.onSurface)
                            .multilineTextAlignment(.center)
                        if let email = user.email, !email.isEmpty {
                            Text(email)
                                .font(.sbc(.bodyMedium))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        SubscriptionBadges(user: user)
                            .padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(EdgeInsets(top: ringDiameter / 2 + 12, leading: 20, bottom: 20, trailing: 20))
                }

                GradientAvatarRing(
                    initials: initials(of: user.displayName),
                    avatarUrl: user.avatarUrl,
                    radius: avatarRadius,
                    ringWidth: ringWidth,
                    ringGap: ringGap
                )
                .offset(y: bandHeight - ringDiameter / 2)
            }
        }
    }
}

/// Avatar wrapped in a brand-arc ring, separated from the artwork by a thin
/// surface-coloured gap so the gradient reads as a ring and not as a halo.
private struct GradientAvatarRing: View {
    let initials: String
    let avatarUrl: String?
    let radius: CGFloat
    let ringWidth: CGFloat
    let ringGap: CGFloat

    var body: some View {
        MemberAvatar(initials: initials, avatarUrl: avatarUrl, radius: radius)
            .padding(ringGap)
            .background(Circle().fill(SBCColors.surface))
            .padding(ringWidth)
            .background(Circle().fill(SBCColors.brandArc))
    }
}

/// The tier pills (CIBLE / CLASSIQUE / …), or a muted "no subscription" pill.
private struct SubscriptionBadges: View {
    let user: AppUser

    var body: some View {
        if user.hasActiveSubscription {
            FlowLayout(spacing: 8, alignment: .center) {
                ForEach(user.subscriptionTypes, id: \.self) { type in
                    StatusPill(label: Tier.label(type), systemImage: Tier.icon(type), tone: Tier.tone(type))
                }
            }
        } else {
            StatusPill(label: "Sans abonnement", systemImage: "lock", tone: SBCColors.error)
        }
    }
}

private struct StatusPill: View {
    let label: String
    let systemImage: String
    let tone: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(label)
                .font(.sbc(.labelLarge, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(tone.opacity(0.12)))
        .overlay(Capsule().stroke(tone.opacity(0.32)))
    }
}

// MARK: - Subscription block

private struct SubscriptionBlock: View {
    @Environment(AuthStore.self) private var auth
    let user: AppUser

    var body: some View {
        let active = user.hasActiveSubscription
        let tone = active ? Tier.tone(user.subscriptionTypes[0]) : SBCColors.accent

        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Abonnement")
            SurfaceCard(background: tone.opacity(0.06), border: tone.opacity(0.22)) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        IconTile(systemImage: active ? "checkmark.seal.fill" : "lock", tone: tone)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(active ? "Abonnement actif" : "Aucun abonnement actif")
                                .font(.sbc(.titleSmall, weight: .bold))
                                .foregroundStyle(SBCColors.onSurface)
                            Text(active
                                ? "Ton offre \(user.subscriptionTypes.joined(separator: " · ")) te donne accès à l'annuaire des membres SBC."
                                : "L'annuaire des membres est réservé aux abonnés SBC. Active ton abonnement sur SBC, puis actualise ton profil.")
                                .font(.sbc(.bodySmall))
                                .foregroundStyle(SBCColors.onSurfaceVariant)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !active {
                        // Brand blue (not the card's orange tint) so the label
                        // keeps an accessible contrast ratio on the fill.
                        Button {
                            Task { await auth.refreshProfile() }
                        } label: {
                            Label("Actualiser mon statut", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(FilledButtonStyle(minHeight: 46))
                    }
                }
            }
        }
    }
}

// MARK: - Information block

private struct InfoBlock: View {
    let user: AppUser

    private struct Row: Identifiable {
        let systemImage: String
        let label: String
        let value: String
        var id: String { label }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let country = user.country, !country.isEmpty {
            rows.append(Row(systemImage: "globe", label: "Pays", value: country))
        }
        if let phone = user.phoneNumber, !phone.isEmpty {
            rows.append(Row(systemImage: "phone", label: "Téléphone", value: phone))
        }
        if let email = user.email, !email.isEmpty {
            rows.append(Row(systemImage: "at", label: "Adresse e-mail", value: email))
        }
        if !user.role.isEmpty, user.role != "USER" {
            rows.append(Row(systemImage: "shield", label: "Rôle", value: user.role))
        }
        return rows
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Informations")
                SurfaceCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().padding(.leading, 68).padding(.trailing, 16)
                            }
                            HStack(spacing: 12) {
                                IconTile(systemImage: row.systemImage, tone: SBCColors.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label)
                                        .font(.sbc(.labelMedium))
                                        .foregroundStyle(SBCColors.onSurfaceVariant)
                                    Text(row.value)
                                        .font(.sbc(.bodyLarge, weight: .semibold))
                                        .foregroundStyle(SBCColors.onSurface)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Sign out

private struct LogoutButton: View {
    @Environment(AuthStore.self) private var auth
    @State private var confirming = false

    var body: some View {
        Button {
            confirming = true
        } label: {
            Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.sbc(.labelLarge, weight: .bold))
                .foregroundStyle(SBCColors.error)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SBCColors.error.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .alert("Se déconnecter ?", isPresented: $confirming) {
            Button("Annuler", role: .cancel) {}
            Button("Se déconnecter", role: .destructive) {
                Task { await auth.logout() }
            }
        } message: {
            Text("Tu devras te reconnecter avec ton compte SBC pour retrouver l'annuaire.")
        }
    }
}

// MARK: - Shared pieces

/// White, softly-shadowed panel — the surface rhythm used across the screen.
private struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    var background: Color = SBCColors.surface
    var border: Color = SBCColors.outlineVariant.opacity(0.5)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .background(SBCColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: SBCColors.primary.opacity(0.06), radius: 9, y: 8)
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.sbc(.labelSmall, weight: .bold))
            .tracking(1)
            .foregroundStyle(SBCColors.onSurfaceVariant)
            .padding(.leading, 4)
    }
}

/// 40×40 tinted square holding a section icon — keeps the iconography aligned
/// on one vertical rhythm across every row.
private struct IconTile: View {
    let systemImage: String
    let tone: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tone)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tone.opacity(0.12)))
    }
}

// MARK: - Tier presentation helpers

/// CIBLE is the premium tier (orange), CLASSIQUE the standard one (green);
/// anything the backend adds later falls back to brand blue.
private enum Tier {
    static func tone(_ type: String) -> Color {
        switch type.uppercased() {
        case "CIBLE": SBCColors.accent
        case "CLASSIQUE": SBCColors.secondary
        default: SBCColors.primary
        }
    }

    static func icon(_ type: String) -> String {
        switch type.uppercased() {
        case "CIBLE": "rosette"
        case "CLASSIQUE": "checkmark.seal.fill"
        default: "creditcard"
        }
    }

    static func label(_ type: String) -> String {
        type.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

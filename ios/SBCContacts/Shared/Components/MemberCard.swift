import SwiftUI

/// One member in a directory list (recherche, favoris).
///
/// The **name** is the only strong type in the row; the facts under it are
/// small pills, so the row is scannable rather than parsed. Of the two actions
/// WhatsApp takes the top slot at full saturation — it is what the member came
/// to do — and the favourite star tucks under it. The row opens the profile.
struct MemberCard: View {
    let member: Member

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: AppRoute.profile(sbcId: member.sbcId)) {
                HStack(spacing: 13) {
                    AvatarBlock(member: member)
                    Identity(member: member)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityLabel(member.displayName)

            VStack(spacing: 2) {
                WhatsAppButton(
                    phoneNumber: member.phoneNumber,
                    contactName: member.displayName,
                    size: 46
                )
                FavoriteButton(member: member)
            }
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 9, trailing: 12))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

/// Just enough scale to acknowledge the touch; anything bigger reads as a bug.
private struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

/// Avatar, with "already in your phone contacts" as a badge on the avatar
/// rather than an icon competing with the name.
private struct AvatarBlock: View {
    let member: Member

    var body: some View {
        MemberAvatar(initials: member.initials, avatarUrl: member.avatarUrl, radius: 27, rounded: true)
            .overlay(alignment: .bottomTrailing) {
                if member.isSynced {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, SBCColors.success)
                        .font(.system(size: 16))
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(-2))
                        .offset(x: 3, y: 3)
                        .accessibilityLabel("Déjà dans tes contacts")
                }
            }
    }
}

/// Name + fact pills. Many members have neither profession nor région, so the
/// pill row simply disappears — no "non renseigné" filler.
private struct Identity: View {
    let member: Member

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(member.displayName)
                .font(.montserrat(.headline, .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Clipped to one line: a long profession and a long city must not
            // grow the row to twice its height.
            ViewThatFits(in: .horizontal) {
                pills(includeProfession: true)
                pills(includeProfession: false)
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func pills(includeProfession: Bool) -> some View {
        let location = member.location
        let profession = member.profession ?? ""
        HStack(spacing: 6) {
            if !location.isEmpty { MetaPill(label: location, systemImage: "mappin") }
            if includeProfession, !profession.isEmpty { MetaPill(label: profession) }
            // Only once rated: an unrated "50" on every row would be noise.
            if member.reviewCount > 0 { ConfidenceScorePill(score: member.confidenceScore) }
        }
        .fixedSize()
    }
}

private struct MetaPill: View {
    let label: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 110, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.montserrat(.caption, .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

private struct FavoriteButton: View {
    let member: Member

    @Environment(DirectoryStore.self) private var directory
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        // State is carried by the glyph (filled vs outline) as well as colour.
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: member.isFavorite ? "star.fill" : "star")
                .font(.system(size: 19))
                .foregroundStyle(member.isFavorite ? SBCColors.accent : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: member.isFavorite)
        .accessibilityLabel(member.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
    }

    private func toggle() async {
        let next = !member.isFavorite
        directory.setFavoriteLocal(sbcId: member.sbcId, isFavorite: next)
        do {
            if next {
                try await favorites.add(member.sbcId)
            } else {
                try await favorites.remove(member.sbcId)
            }
        } catch {
            directory.setFavoriteLocal(sbcId: member.sbcId, isFavorite: !next) // revert
        }
    }
}

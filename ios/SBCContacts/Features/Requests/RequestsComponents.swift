import SwiftUI

/// White, softly-shadowed panel — the same surface as the profile screen.
struct RequestPanel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SBCColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(SBCColors.outlineVariant.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: SBCColors.primary.opacity(0.06), radius: 9, y: 8)
    }
}

/// Small uppercase section heading ("EN COURS").
struct RequestSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.sbc(.labelSmall, weight: .bold))
            .tracking(1)
            .foregroundStyle(SBCColors.onSurfaceVariant)
            .padding(.leading, 4)
    }
}

/// Tinted capsule for a status ("3 réponses", "Terminée").
struct StatusTag: View {
    let text: String
    let tone: Color

    var body: some View {
        Text(text)
            .font(.sbc(.labelMedium, weight: .bold))
            .foregroundStyle(tone)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tone.opacity(0.12)))
    }
}

/// Label + value line in a summary card.
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.sbc(.bodyMedium))
                .foregroundStyle(SBCColors.onSurfaceVariant)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .font(.sbc(.bodyMedium, weight: .bold))
                .foregroundStyle(SBCColors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// "Ton numéro reste privé…" — said wherever a member might worry about it.
struct PrivacyNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "lock")
        }
        .font(.sbc(.bodySmall))
        .foregroundStyle(SBCColors.onSurfaceVariant)
    }
}

/// Tone for a request's status tag.
func tone(for status: RequestStatus) -> Color {
    switch status {
    case .responded, .selected: SBCColors.primary
    case .completed: SBCColors.success
    case .sent, .matching, .draft: SBCColors.accentDark
    case .cancelled, .noMatch, .noResponse, .unknown: SBCColors.onSurfaceVariant
    }
}

func tone(for status: DispatchStatus) -> Color {
    switch status {
    case .sent: SBCColors.primary
    case .interested, .question: SBCColors.accentDark
    case .selected: SBCColors.success
    default: SBCColors.onSurfaceVariant
    }
}

/// Full-width primary action pinned above the home indicator.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    /// The tall primary button used at the bottom of a flow.
    static var large: FilledButtonStyle { FilledButtonStyle(minHeight: 52) }
}

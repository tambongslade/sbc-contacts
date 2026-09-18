import SwiftUI

/// Colour tier for a 0-100 confidence score.
func confidenceColor(_ score: Int) -> Color {
    switch score {
    case 80...: SBCColors.success
    case 60..<80: SBCColors.secondary
    case 40..<60: SBCColors.warning
    default: SBCColors.error
    }
}

/// Compact score chip ("72") for list rows — trust at a glance while scanning.
struct ConfidenceScorePill: View {
    let score: Int

    var body: some View {
        let c = confidenceColor(score)
        HStack(spacing: 4) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11))
            Text("\(score)")
                .font(SBCFontFixed.bold(size: 12.5))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(c.opacity(0.12)))
        .accessibilityLabel("Score de confiance \(score)")
    }
}

/// Full score card for the profile: big number out of 100, tier label and the
/// review count.
struct ConfidenceScoreCard: View {
    let score: Int
    let reviewCount: Int

    private var label: String {
        switch score {
        case 80...: "Très fiable"
        case 60..<80: "Fiable"
        case 40..<60: "Neutre"
        case 20..<40: "Prudence"
        default: "Peu fiable"
        }
    }

    var body: some View {
        let c = confidenceColor(score)
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(c)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(score)")
                        .font(.sbc(.headlineMedium, weight: .heavy))
                        .foregroundStyle(c)
                    Text(" / 100")
                        .font(.sbc(.titleSmall))
                        .foregroundStyle(SBCColors.onSurfaceVariant)
                }
                Text("Score de confiance · \(label)")
                    .font(.sbc(.bodySmall))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Text(reviewCount == 0 ? "Aucun avis" : "\(reviewCount) avis")
                .font(.sbc(.bodySmall))
                .foregroundStyle(SBCColors.onSurfaceVariant)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(c.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(c.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// Material ChoiceChip / FilterChip: selectable, 8pt radius.
struct SelectableChip: View {
    let label: String
    let selected: Bool
    var showsCheckmark = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected, showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(label)
                    .font(.sbc(.labelLarge))
            }
            .foregroundStyle(selected ? SBCColors.onPrimaryContainer : SBCColors.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? SBCColors.primaryContainer : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? .clear : SBCColors.outlineVariant)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Material InputChip with a trailing ×; the whole chip removes it.
struct RemovableChip: View {
    let label: String
    var systemImage: String?
    var tinted = false
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(SBCColors.primary)
                }
                Text(label)
                    .font(.sbc(.labelLarge, weight: tinted ? .semibold : .medium))
                    .foregroundStyle(SBCColors.onSurface)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tinted ? SBCColors.primaryContainer.opacity(0.35) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tinted ? SBCColors.primary.opacity(0.28) : SBCColors.outlineVariant)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retirer \(label)")
    }
}

/// Plain read-only chip (skills, interests on a profile).
struct TagChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.sbc(.labelLarge))
            .foregroundStyle(SBCColors.onSurface)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SBCColors.outlineVariant)
            )
    }
}

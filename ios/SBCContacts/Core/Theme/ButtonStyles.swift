import SwiftUI

/// Material 3 FilledButton: brand fill, 12pt radius.
struct FilledButtonStyle: ButtonStyle {
    var background: Color = SBCColors.primary
    var foreground: Color = .white
    var minHeight: CGFloat = 40
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbc(.labelLarge, weight: .semibold))
            .foregroundStyle(isEnabled ? foreground : SBCColors.onSurface.opacity(0.38))
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? background : SBCColors.onSurface.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Material 3 OutlinedButton.
struct OutlinedButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 40
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbc(.labelLarge, weight: .semibold))
            .foregroundStyle(isEnabled ? SBCColors.primary : SBCColors.onSurface.opacity(0.38))
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? SBCColors.primary.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SBCColors.outlineVariant, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Material 3 TextButton.
struct TextButtonStyle: ButtonStyle {
    var foreground: Color = SBCColors.primary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbc(.labelLarge, weight: .semibold))
            .foregroundStyle(isEnabled ? foreground : SBCColors.onSurface.opacity(0.38))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(
                Capsule().fill(configuration.isPressed ? foreground.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var filled: FilledButtonStyle { FilledButtonStyle() }
}

extension ButtonStyle where Self == OutlinedButtonStyle {
    static var outlined: OutlinedButtonStyle { OutlinedButtonStyle() }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var text: TextButtonStyle { TextButtonStyle() }
}

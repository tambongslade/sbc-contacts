import SwiftUI

/// SBC (Sniper Business Center) brand palette, taken from the production
/// `sbcprecom` and `sbc-live` web projects.
enum SBCColors {
    // Primary — blue
    static let primary = Color(hex: 0x1862F0)
    static let primaryLight = Color(hex: 0x4285F4)
    static let primaryDark = Color(hex: 0x0F4FB3)

    // Secondary — green
    static let secondary = Color(hex: 0x92B127)
    static let secondaryLight = Color(hex: 0xA5C142)
    static let secondaryDark = Color(hex: 0x7A951F)

    // Accent — orange (Material "tertiary")
    static let accent = Color(hex: 0xF49101)
    static let accentLight = Color(hex: 0xFFA726)
    static let accentDark = Color(hex: 0xE57C00)

    // Semantic
    static let success = Color(hex: 0x10B981)
    static let warning = Color(hex: 0xF59E0B)
    static let error = Color(hex: 0xEF4444)
    static let info = Color(hex: 0x3B82F6)
    static let live = Color(hex: 0xE5484D)

    /// WhatsApp brand green — used only for the "contacter sur WhatsApp"
    /// affordance, so the action is recognisable at a glance (cahier §8).
    static let whatsapp = Color(hex: 0x25D366)

    // Surfaces
    /// System grouped surfaces, so every screen sits on the same native ground
    /// as the grouped lists, sheets and search bar.
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfaceTint = Color(hex: 0xEDF2FB)

    // Material-role equivalents used by the Flutter theme
    static let onSurface = Color(hex: 0x1A1C22)
    static let onSurfaceVariant = Color(hex: 0x5B6170)
    static let outlineVariant = Color(hex: 0xC6CBD6)
    static let primaryContainer = Color(hex: 0xD9E4FD)
    static let onPrimaryContainer = Color(hex: 0x0A2E73)
    static let secondaryContainer = Color(hex: 0xE7F0C8)
    static let onSecondaryContainer = Color(hex: 0x2F3A08)

    /// Signature 3-stop brand arc: blue → green → orange.
    static let brandArc = LinearGradient(
        stops: [
            .init(color: primary, location: 0),
            .init(color: secondary, location: 0.55),
            .init(color: accent, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

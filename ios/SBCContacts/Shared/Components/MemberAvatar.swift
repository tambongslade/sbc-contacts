import SwiftUI

/// Avatar with network image + initials fallback.
///
/// The fallback is a saturated tile, not a grey placeholder: most members have
/// no photo, so it is the common case. Its colour is derived from the initials,
/// so a member keeps the same colour on every screen and a scanned list gains a
/// second, non-textual cue.
struct MemberAvatar: View {
    let initials: String
    var avatarUrl: String?
    var radius: CGFloat = 24
    /// A rounded square instead of a circle (directory lists).
    var rounded = false

    private static let palette: [Color] = [
        SBCColors.primary,
        SBCColors.secondaryDark,
        SBCColors.accentDark,
        Color(hex: 0x5B5BD6), // indigo
        Color(hex: 0x0E9384), // teal
        Color(hex: 0xD1495B), // coral
        Color(hex: 0x7A5AF8), // violet
        Color(hex: 0xEA7317), // amber
    ]

    static func color(for seed: String) -> Color {
        guard !seed.isEmpty else { return palette[0] }
        var hash = 0
        for unit in seed.utf16 {
            hash = (hash &* 31 &+ Int(unit)) & 0x7FFF_FFFF
        }
        return palette[hash % palette.count]
    }

    private var shape: AnyShape {
        rounded
            ? AnyShape(RoundedRectangle(cornerRadius: radius * 0.62, style: .continuous))
            : AnyShape(Circle())
    }

    var body: some View {
        Group {
            if let avatarUrl, !avatarUrl.isEmpty, let url = URL(string: avatarUrl) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            Self.color(for: initials)
            Text(initials)
                .font(SBCFontFixed.font(size: radius * 0.72, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(.white)
        }
    }
}

/// Fixed-size Montserrat, for glyphs sized from their container (not Dynamic Type).
enum SBCFontFixed {
    static func bold(size: CGFloat) -> Font {
        Font(SBCFont.uiFont(size: size, weight: .bold))
    }

    static func font(size: CGFloat, weight: Font.Weight) -> Font {
        Font(SBCFont.uiFont(size: size, weight: weight))
    }
}

/// Up to two initials from a display name ("Jean Paul Mbarga" → "JP").
func initials(of name: String) -> String {
    let parts = name.split(whereSeparator: \.isWhitespace)
    guard let first = parts.first?.first else { return "?" }
    guard parts.count > 1, let second = parts[1].first else { return String(first).uppercased() }
    return (String(first) + String(second)).uppercased()
}

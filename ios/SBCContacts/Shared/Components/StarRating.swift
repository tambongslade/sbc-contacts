import SwiftUI

private let amber = Color(hex: 0xF59E0B)

/// Read-only row of 1-5 stars (supports halves), for displaying a rating.
struct StarRatingDisplay: View {
    let value: Double
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: value >= Double(i) ? "star.fill"
                    : value >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(amber)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(value.formatted(.number.precision(.fractionLength(0...1)))) étoiles sur 5")
    }
}

/// Tappable 1-5 star input.
struct StarRatingInput: View {
    @Binding var value: Int
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    value = i
                } label: {
                    Image(systemName: value >= i ? "star.fill" : "star")
                        .font(.system(size: size * 0.8))
                        .foregroundStyle(value >= i ? amber : SBCColors.onSurfaceVariant)
                        .frame(width: size + 8, height: size + 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) étoile\(i > 1 ? "s" : "")")
                .accessibilityAddTraits(value == i ? .isSelected : [])
            }
        }
    }
}

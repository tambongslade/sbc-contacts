import SwiftUI

/// Skeleton placeholders for list-shaped screens: they show the shape of the
/// result so nothing jumps when data lands.
private struct Pulsing: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .opacity(dim ? 0.45 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Chargement")
    }
}

extension View {
    func skeleton() -> some View { modifier(Pulsing()) }
}

struct ListSkeleton: View {
    var rows = 7
    var hasLeading = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 16) {
                    if hasLeading { Circle().frame(width: 44, height: 44) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nom du membre SBC").font(.sbc(.bodyLarge))
                        Text("Profession · Région").font(.sbc(.bodyMedium))
                    }
                    Spacer()
                    Circle().frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(hex: 0xE3E6EC))
        .skeleton()
    }
}

/// Mirrors the member-card geometry — same margins, avatar and trailing actions.
struct CardListSkeleton: View {
    var rows = 5

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: 0xE3E6EC)).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nom du membre SBC").font(.sbc(.titleMedium))
                        Text("Profession · Région").font(.sbc(.bodySmall))
                    }
                    Spacer()
                    Circle().fill(Color(hex: 0xE3E6EC)).frame(width: 24, height: 24)
                    Circle().fill(Color(hex: 0xE3E6EC)).frame(width: 46, height: 46)
                }
                .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 12))
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SBCColors.surface))
                .padding(.horizontal, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .skeleton()
    }
}

struct SummarySkeleton: View {
    var body: some View {
        HStack {
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle().frame(width: 22, height: 22)
                    Text("12").font(.sbc(.titleLarge))
                    Text("Libellé").font(.sbc(.labelSmall))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color(hex: 0xE3E6EC))
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SBCColors.surface))
        .padding(16)
        .skeleton()
    }
}

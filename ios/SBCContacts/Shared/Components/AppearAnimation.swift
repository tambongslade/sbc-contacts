import SwiftUI

/// Fade + small upward slide on first appearance — the Flutter
/// `.animate().fadeIn().slideY(begin: 0.04)` used across the screens.
private struct AppearAnimation: ViewModifier {
    let delay: Double
    var offset: CGFloat = 12

    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : offset)
            .onAppear {
                withAnimation(.easeOut(duration: 0.26).delay(delay)) { visible = true }
            }
    }
}

extension View {
    func appearAnimation(delay: Double = 0, offset: CGFloat = 12) -> some View {
        modifier(AppearAnimation(delay: delay, offset: offset))
    }
}

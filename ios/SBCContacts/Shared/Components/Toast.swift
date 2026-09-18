import SwiftUI
import Observation

/// App-wide transient message — the Material SnackBar equivalent.
@MainActor
@Observable
final class ToastCenter {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    private(set) var current: Message?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String) {
        dismissTask?.cancel()
        let message = Message(text: text)
        withAnimation(.easeOut(duration: 0.2)) { current = message }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismiss(message)
        }
    }

    func dismiss(_ message: Message? = nil) {
        guard message == nil || message == current else { return }
        withAnimation(.easeIn(duration: 0.2)) { current = nil }
    }
}

private struct ToastHost: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = toasts.current {
                Text(message.text)
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: 0x2F3033))
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { toasts.dismiss() }
                    .id(message.id)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}

extension View {
    func toastHost() -> some View { modifier(ToastHost()) }
}

import SwiftUI

/// A designed empty/error state (no results, no subscription, permission
/// denied, offline, no favorites).
struct EmptyStateView<Action: View>: View {
    let systemImage: String
    let title: String
    var message: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(SBCColors.primary.opacity(0.6))
            Text(title)
                .font(.sbc(.titleMedium))
                .foregroundStyle(SBCColors.onSurface)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            if let message {
                Text(message)
                    .font(.sbc(.bodyMedium))
                    .foregroundStyle(SBCColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            action()
                .padding(.top, 20)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(systemImage: String, title: String, message: String? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

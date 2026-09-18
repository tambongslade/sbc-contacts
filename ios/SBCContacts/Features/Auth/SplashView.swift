import SwiftUI

/// Shown while the stored session is being restored.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 28) {
            SBCLogo(height: 110)
            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    SplashView()
}

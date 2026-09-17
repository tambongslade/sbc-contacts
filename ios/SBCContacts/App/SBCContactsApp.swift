import SwiftUI

@main
struct SBCContactsApp: App {
    private let services: AppServices
    @State private var auth: AuthStore
    @State private var toasts = ToastCenter()

    init() {
        #if DEBUG
        let services = DemoMode.isEnabled
            ? AppServices(storage: InMemoryTokenStorage(access: "demo", refresh: "demo"), session: DemoMode.session())
            : AppServices()
        #else
        let services = AppServices()
        #endif
        self.services = services
        // Navigation and tab bars are left to the system (Liquid Glass on
        // iOS 26); custom UIKit appearances would switch that off.
        _auth = State(initialValue: AuthStore(repo: services.auth))
        FontAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .toastHost()
                .environment(\.services, services)
                .environment(auth)
                .environment(toasts)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .font(.sbc(.bodyMedium))
                .tint(SBCColors.primary)
                // SBC Network is a light-ground product: the brand lockup and
                // the directory cards are designed on the light surface.
                .preferredColorScheme(.light)
                .onOpenURL { auth.handleDeepLink($0) }
        }
    }
}

/// Splash while the session restores, then login or the app.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.services) private var services

    var body: some View {
        ZStack {
            switch auth.phase {
            case .restoring:
                SplashView().transition(.opacity)
            case .signedOut:
                LoginView().transition(.opacity)
            case .signedIn:
                HomeShell(services: services).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phaseKey)
        .task { await auth.restore() }
    }

    /// Animate between phases, not on every profile refresh.
    private var phaseKey: Int {
        switch auth.phase {
        case .restoring: 0
        case .signedOut: 1
        case .signedIn: 2
        }
    }
}

private struct ServicesKey: EnvironmentKey {
    static let defaultValue = AppServices(storage: InMemoryTokenStorage())
}

extension EnvironmentValues {
    var services: AppServices {
        get { self[ServicesKey.self] }
        set { self[ServicesKey.self] = newValue }
    }
}

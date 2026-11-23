import SwiftUI

/// The five-tab shell. Per-session stores live here, so signing out and back
/// in starts them fresh.
struct HomeShell: View {
    enum Tab: Hashable {
        case search, sync, requests, notifications, account

        /// Always `.search`, except in a debug build launched with `-tab`.
        static var initial: Tab {
            #if DEBUG
            switch DemoMode.initialTab {
            case "synchro", "sync": return .sync
            case "demandes", "requests": return .requests
            case "alertes", "notifications": return .notifications
            case "profil", "account": return .account
            default: return AppConfig.sbcLoginEnabled ? .search : .sync
            }
            #else
            // Without SBC sign-in there is no directory: Synchro opens first.
            return AppConfig.sbcLoginEnabled ? .search : .sync
            #endif
        }
    }

    @State private var tab: Tab = Tab.initial
    /// Seeded from `-route` in debug builds, empty otherwise — lets a pushed
    /// screen be opened straight from the command line.
    @State private var searchPath = NavigationPath()
    @State private var syncPath = NavigationPath()
    /// Where a tapped notification opens its screen, above the list of alerts.
    @State private var alertsPath = NavigationPath()
    @State private var directory: DirectoryStore
    @State private var favorites: FavoritesStore
    @State private var sync: SyncStore
    @State private var regions: RegionsStore
    @State private var notifications: NotificationsStore
    @State private var requests: RequestsStore
    @State private var contactsSettled = false
    @State private var proPrompt: ProInvite?
    @State private var proLocation: ProLocationReporter
    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    private let push = PushCenter.shared
    private let notificationsRepo: NotificationsRepository

    init(services: AppServices) {
        notificationsRepo = services.notifications
        _directory = State(initialValue: DirectoryStore(repo: services.directory))
        _favorites = State(initialValue: FavoritesStore(repo: services.favorites))
        _sync = State(initialValue: SyncStore(repo: services.sync))
        _regions = State(initialValue: RegionsStore(repo: services.directory))
        _notifications = State(initialValue: NotificationsStore(repo: services.notifications))
        _requests = State(initialValue: RequestsStore(repo: services.requests))
        _proLocation = State(initialValue: ProLocationReporter(repo: services.requests))
        #if DEBUG
        let path = DemoMode.initialPath()
        switch Tab.initial {
        case .sync: _syncPath = State(initialValue: path)
        default: _searchPath = State(initialValue: path)
        }
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            // The directory is SBC's: only an SBC account can search it.
            if AppConfig.sbcLoginEnabled {
                NavigationStack(path: $searchPath) { SearchView().appRoutes() }
                    .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                    .tag(Tab.search)
            }

            NavigationStack(path: $syncPath) { SyncView().appRoutes() }
                .tabItem { Label("Synchro", systemImage: "arrow.triangle.2.circlepath") }
                .tag(Tab.sync)

            // "Demandes" took the Favoris slot: a member describes a need
            // here and pros receive the matching requests. Favoris moved to
            // the profile, which reaches it in one tap.
            NavigationStack { RequestsView().appRoutes() }
                .tabItem { Label("Demandes", systemImage: "doc.text") }
                .badge(requests.unopenedCount)
                .tag(Tab.requests)

            NavigationStack(path: $alertsPath) {
                NotificationsView(store: notifications) { alertsPath.append($0) }.appRoutes()
            }
                .tabItem { Label("Alertes", systemImage: "bell") }
                .badge(notifications.unreadCount)
                .tag(Tab.notifications)

            NavigationStack { AccountView().appRoutes() }
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(Tab.account)
        }
        .environment(directory)
        .environment(favorites)
        .environment(sync)
        .environment(regions)
        .environment(requests)
        .environment(proLocation)
        // Ask for contacts access once the shell is on screen, so the member
        // sees the app behind the explanation rather than a bare system dialog.
        // Then for notifications, one system dialog at a time.
        .contactsPermissionGate {
            Task {
                await push.start(repo: notificationsRepo)
                contactsSettled = true
                inviteToBecomeProIfDue()
            }
        }
        // After login: a member who is not a pro is invited to become one, a
        // pro with an incomplete setup is told what is missing.
        .sheet(item: $proPrompt) { kind in
            ProOnboardingFlow(kind: kind).environment(requests).environment(auth)
        }
        .task { await notifications.refreshUnreadCount() }
        // A tapped notification, including the one that launched the app.
        .task { openTappedNotification() }
        .onChange(of: push.pendingTap) { openTappedNotification() }
        // A push while the app is open: the badge and the list catch up.
        .onChange(of: push.arrivals) {
            Task {
                await notifications.refreshUnreadCount()
                await notifications.load()
            }
        }
        .onChange(of: notifications.unreadCount) { _, count in push.setBadge(count) }
        .task { await regions.loadIfNeeded() }
        .task {
            await requests.load()
            inviteToBecomeProIfDue()
            await reportProLocation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await reportProLocation() }
                Task { await notifications.refreshUnreadCount() }
            }
        }
    }

    /// Opens the screen a tapped notification points to, on the Alertes tab so
    /// Back lands on the list of alerts.
    private func openTappedNotification() {
        guard let tap = push.consumeTap() else { return }
        var path = NavigationPath()
        if let route = PushCenter.route(for: tap.link) { path.append(route) }
        tab = .notifications
        alertsPath = path
        Task { await notifications.load() }
    }

    /// A pro's position, so requests close by reach them first.
    private func reportProLocation() async {
        guard requests.isPro else { return }
        await proLocation.refresh()
    }

    /// Both the pro profile and the contacts prompt must be settled first:
    /// the profile to know which prompt applies, the contacts prompt because
    /// iOS would drop a sheet raised on top of an alert.
    private func inviteToBecomeProIfDue() {
        // Becoming a pro takes an SBC account.
        guard AppConfig.sbcLoginEnabled, contactsSettled, proPrompt == nil, let user = auth.user,
              let space = requests.proSpace, let kind = ProInvite.kind(for: space),
              kind.isDue(userId: user.id)
        else { return }
        kind.markShown(userId: user.id)
        proPrompt = kind
    }
}

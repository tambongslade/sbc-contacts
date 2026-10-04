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
            default: return .search
            }
            #else
            return .search
            #endif
        }
    }

    @State private var tab: Tab = Tab.initial
    /// Seeded from `-route` in debug builds, empty otherwise — lets a pushed
    /// screen be opened straight from the command line.
    @State private var searchPath = NavigationPath()
    @State private var syncPath = NavigationPath()
    @State private var directory: DirectoryStore
    @State private var favorites: FavoritesStore
    @State private var sync: SyncStore
    @State private var regions: RegionsStore
    @State private var notifications: NotificationsStore
    @State private var requests: RequestsStore
    @State private var contactsSettled = false
    @State private var invitingPro = false
    @Environment(AuthStore.self) private var auth

    init(services: AppServices) {
        _directory = State(initialValue: DirectoryStore(repo: services.directory))
        _favorites = State(initialValue: FavoritesStore(repo: services.favorites))
        _sync = State(initialValue: SyncStore(repo: services.sync))
        _regions = State(initialValue: RegionsStore(repo: services.directory))
        _notifications = State(initialValue: NotificationsStore(repo: services.notifications))
        _requests = State(initialValue: RequestsStore(repo: services.requests))
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
            NavigationStack(path: $searchPath) { SearchView().appRoutes() }
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                .tag(Tab.search)

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

            NavigationStack { NotificationsView(store: notifications).appRoutes() }
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
        // Ask for contacts access once the shell is on screen, so the member
        // sees the app behind the explanation rather than a bare system dialog.
        .contactsPermissionGate {
            contactsSettled = true
            inviteToBecomeProIfDue()
        }
        // After login, a member who is not a pro yet is invited to become one.
        .sheet(isPresented: $invitingPro) {
            ProOnboardingFlow().environment(requests)
        }
        .task { await notifications.refreshUnreadCount() }
        .task { await regions.loadIfNeeded() }
        .task {
            await requests.load()
            inviteToBecomeProIfDue()
        }
    }

    /// Both the pro profile and the contacts prompt must be settled first:
    /// the profile to know whether they are a pro, the prompt because iOS
    /// would drop a sheet raised on top of an alert.
    private func inviteToBecomeProIfDue() {
        guard contactsSettled, !invitingPro, let user = auth.user,
              requests.proSpace != nil, !requests.isPro || ProInvite.forced,
              ProInvite.isDue(userId: user.id)
        else { return }
        ProInvite.markShown(userId: user.id)
        invitingPro = true
    }
}

import SwiftUI

/// The five-tab shell. Per-session stores live here, so signing out and back
/// in starts them fresh.
struct HomeShell: View {
    enum Tab: Hashable {
        case search, sync, favorites, notifications, account

        /// Always `.search`, except in a debug build launched with `-tab`.
        static var initial: Tab {
            #if DEBUG
            switch DemoMode.initialTab {
            case "synchro", "sync": return .sync
            case "favoris", "favorites": return .favorites
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
    @State private var directory: DirectoryStore
    @State private var favorites: FavoritesStore
    @State private var sync: SyncStore
    @State private var regions: RegionsStore
    @State private var notifications: NotificationsStore

    init(services: AppServices) {
        _directory = State(initialValue: DirectoryStore(repo: services.directory))
        _favorites = State(initialValue: FavoritesStore(repo: services.favorites))
        _sync = State(initialValue: SyncStore(repo: services.sync))
        _regions = State(initialValue: RegionsStore(repo: services.directory))
        _notifications = State(initialValue: NotificationsStore(repo: services.notifications))
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { SearchView().appRoutes() }
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack { SyncView().appRoutes() }
                .tabItem { Label("Synchro", systemImage: "arrow.triangle.2.circlepath") }
                .tag(Tab.sync)

            NavigationStack { FavoritesView().appRoutes() }
                .tabItem { Label("Favoris", systemImage: "star") }
                .tag(Tab.favorites)

            NavigationStack { NotificationsView(store: notifications).appRoutes() }
                .tabItem { Label("Alertes", systemImage: "bell") }
                .badge(notifications.unreadCount)
                .tag(Tab.notifications)

            NavigationStack { AccountView() }
                .tabItem { Label("Profil", systemImage: "person") }
                .tag(Tab.account)
        }
        .environment(directory)
        .environment(favorites)
        .environment(sync)
        .environment(regions)
        // Ask for contacts access once the shell is on screen, so the member
        // sees the app behind the explanation rather than a bare system dialog.
        .contactsPermissionGate()
        .task { await notifications.refreshUnreadCount() }
        .task { await regions.loadIfNeeded() }
    }
}

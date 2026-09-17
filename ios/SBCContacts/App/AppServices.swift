import Foundation

/// The dependency graph (the Riverpod `core_providers.dart` equivalent): one
/// API client and one repository per backend area, shared app-wide.
struct AppServices: Sendable {
    let storage: TokenStorage
    let api: APIClient
    let auth: AuthRepository
    let directory: DirectoryRepository
    let favorites: FavoritesRepository
    let reviews: ReviewsRepository
    let sync: SyncRepository
    let notifications: NotificationsRepository

    init(storage: TokenStorage = KeychainTokenStorage(), baseURL: URL = AppConfig.apiBaseURL, session: URLSession = .shared) {
        let api = APIClient(baseURL: baseURL, storage: storage, session: session)
        self.storage = storage
        self.api = api
        auth = AuthRepository(api: api, storage: storage)
        directory = DirectoryRepository(api: api)
        favorites = FavoritesRepository(api: api)
        reviews = ReviewsRepository(api: api)
        sync = SyncRepository(api: api)
        notifications = NotificationsRepository(api: api)
    }
}

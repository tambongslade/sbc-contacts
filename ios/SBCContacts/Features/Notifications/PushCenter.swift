import SwiftUI
import UIKit
import UserNotifications

/// Push notifications: permission, the APNs device token, and the screen a
/// tapped notification should open.
///
/// The backend sends each push with a `link`, an app path shared with the
/// Flutter app ("/requests/<id>", "/inbox/<id>", "/profile/<sbcId>",
/// "/sync/saved-me"). A tap records it here; the home shell picks it up,
/// switches to Alertes and pushes the matching screen, so Back returns to the
/// list of alerts. A tap with no link just opens Alertes.
@MainActor
@Observable
final class PushCenter {
    static let shared = PushCenter()

    struct Tap: Equatable {
        let id = UUID()
        let link: String?
    }

    /// A tapped notification the shell has not opened yet. Survives a cold
    /// start: the tap arrives before the session is restored.
    private(set) var pendingTap: Tap?
    /// Bumped when a push arrives while the app is open, so the shell can
    /// refresh its unread count and list.
    private(set) var arrivals = 0

    private var deviceToken: String?
    private var repo: NotificationsRepository?
    private var registered: (token: String, deviceId: String?)?

    private init() {}

    // MARK: - Session

    /// Called once the member is signed in and the contacts prompt is out of
    /// the way: asks for permission (only the first time shows a dialog) and
    /// registers this phone with the backend.
    func start(repo: NotificationsRepository) async {
        self.repo = repo
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await registerIfReady()
    }

    /// Before signing out: this phone stops receiving the account's pushes.
    func signOut() async {
        if let id = registered?.deviceId, let repo {
            try? await repo.removeDevice(id: id)
        }
        registered = nil
        repo = nil
        pendingTap = nil
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func setBadge(_ count: Int) {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    // MARK: - From the app delegate

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerIfReady() }
    }

    func tapped(link: String?) {
        let trimmed = link?.trimmingCharacters(in: .whitespaces) ?? ""
        pendingTap = Tap(link: trimmed.isEmpty ? nil : trimmed)
    }

    func arrived() {
        arrivals += 1
    }

    /// Hands the pending tap to the shell, once.
    func consumeTap() -> Tap? {
        defer { pendingTap = nil }
        return pendingTap
    }

    private func registerIfReady() async {
        guard let repo, let token = deviceToken, registered?.token != token else { return }
        do {
            let id = try await repo.registerDevice(platform: "IOS", pushToken: token)
            registered = (token, id)
        } catch {
            // Retried on the next launch, when iOS hands the token over again.
        }
    }

    // MARK: - Links

    /// The screen an app path opens; nil for the Alertes list itself.
    static func route(for link: String?) -> AppRoute? {
        guard let link else { return nil }
        let parts = link.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        switch parts.count {
        case 2 where parts[0] == "profile": return .profile(sbcId: parts[1])
        case 2 where parts[0] == "requests": return .request(id: parts[1])
        case 2 where parts[0] == "inbox": return .inboxRequest(id: parts[1])
        case 2 where parts == ["sync", "saved-me"]: return .savedMe
        case 2 where parts == ["sync", "status-boost"]: return .statusBoost
        default: return nil
        }
    }
}

/// Receives the APNs token and the notification callbacks, which SwiftUI has
/// no API for.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushCenter.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("APNs registration failed: %@", error.localizedDescription)
    }

    /// A push while the app is open still shows its banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { PushCenter.shared.arrived() }
        return [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo["link"] as? String
        await MainActor.run { PushCenter.shared.tapped(link: link) }
    }
}

/// "/inbox/<id>" from a notification: the pro's view of a request, loaded by
/// id since a push carries no more than that.
struct InboxRequestLoader: View {
    let requestId: String

    @Environment(\.services) private var services
    @State private var item: InboxItem?
    @State private var failed = false

    var body: some View {
        if let item {
            InboxDetailView(item: item)
        } else if failed {
            EmptyStateView(
                systemImage: "tray",
                title: "Demande introuvable",
                message: "Elle a peut-être été supprimée par le client."
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    do {
                        item = try await services.requests.open(requestId: requestId)
                    } catch {
                        failed = true
                    }
                }
        }
    }
}

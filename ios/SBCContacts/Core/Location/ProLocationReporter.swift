import Foundation
import Observation

/// Keeps a pro's position fresh on the server so requests close by reach
/// them first. Reports when the app comes to the foreground and, with
/// "Toujours", on significant moves in the background. The server ignores a
/// position older than three days, so a pro who stops opening the app falls
/// back to the zones they named.
@MainActor
@Observable
final class ProLocationReporter {
    private static let enabledKey = "pro.shareLocation"
    /// A pro barely moves in a quarter of an hour; no need to report more.
    private static let minInterval: TimeInterval = 15 * 60

    private let repo: RequestsRepository
    private let location = LocationProvider.shared
    private var lastSent: Date?

    /// The pro's choice, on by default; kept on this phone.
    private(set) var isEnabled: Bool
    /// iOS permission as last read, for the pro space to explain.
    private(set) var permission: Permission = .unknown

    enum Permission { case unknown, denied, whileInUse, always }

    init(repo: RequestsRepository) {
        self.repo = repo
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        location.onSignificantMove = { [weak self] point in
            Task { await self?.send(point) }
        }
    }

    /// The app is active and the user is a pro. Only [prompt] lets iOS ask
    /// for permission: on launch the question would come out of nowhere.
    func refresh(prompt: Bool = false) async {
        readPermission()
        guard isEnabled, prompt || permission != .unknown else { return }
        if let lastSent, Date.now.timeIntervalSince(lastSent) < Self.minInterval { return }
        if let point = await location.current() { await send(point) }
        readPermission()
        location.startSignificantChanges()
    }

    func setEnabled(_ on: Bool) async {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            lastSent = nil
            await refresh(prompt: true)
        } else {
            location.stopSignificantChanges()
            lastSent = nil
            try? await repo.clearProLocation()
        }
    }

    /// "Toujours" lets requests find the pro while the app is closed.
    func askForAlways() {
        location.requestAlways()
    }

    func readPermission() {
        permission = if location.isDenied {
            .denied
        } else if location.hasAlways {
            .always
        } else if location.status == .notDetermined {
            .unknown
        } else {
            .whileInUse
        }
    }

    private func send(_ point: Coordinates) async {
        guard isEnabled else { return }
        do {
            try await repo.updateProLocation(point)
            lastSent = .now
        } catch {
            // Next foreground retries; matching falls back to zones meanwhile.
        }
    }
}

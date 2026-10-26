import CoreLocation
import Foundation

/// A position as the backend takes it (`LocationDto`).
struct Coordinates: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
}

/// The phone's position for "Près de moi". Never throws at the UI: no
/// permission, location off or no fix all come back as nil, and the feature
/// simply falls back to the city.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<Coordinates?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []
    /// Called on each significant move while the pro shares in the background.
    var onSignificantMove: ((Coordinates) -> Void)?

    override private init() {
        super.init()
        manager.delegate = self
        // A street is precise enough to rank pros, and it is cheaper.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var isDenied: Bool { status == .denied || status == .restricted }
    var hasAlways: Bool { status == .authorizedAlways }

    /// The current position, asking for "Lorsque l'app est active" the first time.
    func current() async -> Coordinates? {
        if status == .notDetermined {
            await withCheckedContinuation { cont in
                authWaiters.append(cont)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        if let last = manager.location, last.timestamp.timeIntervalSinceNow > -120 {
            return Coordinates(last.coordinate)
        }
        return await withCheckedContinuation { cont in
            fixWaiters.append(cont)
            if fixWaiters.count == 1 { manager.requestLocation() }
        }
    }

    /// iOS asks for "Toujours" only once a "Lorsque l'app est active" grant
    /// exists. Not awaited: when the pro keeps "Lorsque l'app est active",
    /// iOS reports nothing, so callers re-read [status] when the app is back.
    func requestAlways() {
        guard status == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    /// Wakes the app on moves of ~500 m, even in the background, with
    /// "Toujours". Uses the cell network, not GPS, so it costs little battery.
    func startSignificantChanges() {
        guard hasAlways, CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopSignificantChanges() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let waiters = authWaiters
            authWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let point = Coordinates(last.coordinate)
        Task { @MainActor in
            if fixWaiters.isEmpty {
                onSignificantMove?(point)
            } else {
                finish(point)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }

    private func finish(_ point: Coordinates?) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: point) }
    }
}

private extension Coordinates {
    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }
}

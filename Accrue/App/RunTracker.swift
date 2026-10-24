import AccrueKit
import CoreLocation
import Foundation
import Observation

/// Follows GPS during an outdoor cardio workout and adds up the distance. It keeps running with
/// the screen off (background location), and leaves out the time the workout is paused.
@Observable
@MainActor
final class RunTracker {
    private(set) var sessionID: UUID?
    /// "Waiting for GPS" until the first good fix; nil once it is tracking.
    private(set) var status: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var service: CLServiceSession?
    @ObservationIgnored private var background: CLBackgroundActivitySession?

    /// Starts following a workout, carrying on from `meters` already covered.
    func start(sessionID: UUID, from meters: Double, isPaused: @escaping @MainActor () -> Bool,
               onDistance: @escaping @MainActor (Double) -> Void) {
        guard self.sessionID != sessionID else { return }
        stop()
        self.sessionID = sessionID
        status = "Waiting for GPS"
        service = CLServiceSession(authorization: .whenInUse)
        background = CLBackgroundActivitySession()
        task = Task { [weak self] in
            var route = RouteDistance(meters: meters)
            var reported = meters
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        self.status = "Location is off, so no distance"
                        continue
                    }
                    guard let location = update.location else { continue }
                    let point = RouteDistance.Point(latitude: location.coordinate.latitude,
                                                    longitude: location.coordinate.longitude)
                    route.add(point, accuracy: location.horizontalAccuracy, paused: isPaused())
                    if location.horizontalAccuracy <= RouteDistance.worstAccuracy { self.status = nil }
                    // Save every few metres, not on every fix.
                    if route.meters - reported >= 5 {
                        reported = route.meters
                        onDistance(route.meters)
                    }
                }
            } catch {
                self?.status = "GPS stopped"
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        background?.invalidate()
        background = nil
        service?.invalidate()
        service = nil
        sessionID = nil
        status = nil
    }
}

@preconcurrency import HealthKit
import SwiftUI
import WatchKit

@main
struct AccrueWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchDelegate

    var body: some Scene {
        WindowGroup {
            WorkoutView()
                .environment(WorkoutManager.shared)
        }
    }
}

/// The phone starts a workout with `startWatchApp`; watchOS hands it to us here.
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutManager.shared.start(workoutConfiguration) }
    }
}

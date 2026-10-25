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
                .task {
                    // Screenshots: -demoWorkout run|strength|cycle, -demoPage controls|metrics|zones|summary.
                    let defaults = UserDefaults.standard
                    if let kind = defaults.string(forKey: "demoWorkout"), kind != "NO" {
                        WorkoutManager.shared.showDemo(kind, ended: defaults.string(forKey: "demoPage") == "summary")
                    }
                }
        }
    }
}

/// The phone starts a workout with `startWatchApp`; watchOS hands it to us here.
final class WatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutManager.shared.start(workoutConfiguration) }
    }
}

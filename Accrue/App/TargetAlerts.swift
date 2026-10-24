import AccrueKit
import Foundation
import UserNotifications

/// Tells you when a cardio workout reaches its target (last time's mark, or your own). The
/// workout keeps going; this is only a sound and a banner, on the lock screen too.
@MainActor
enum TargetAlerts {
    private static let id = "cardio-target"
    private static let presenter = Presenter()

    /// Lets the banner and sound show while Accrue is open, as well as in the background.
    static func install() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    static func requestPermission() {
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    /// A time goal: schedule the alert for when the clock gets there. Called on start, pause,
    /// resume and when the target changes; anything else clears it.
    static func sync(_ session: WorkoutSession?, name: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        // Time in a zone depends on heart rate, so that alert comes from the readings, not a clock.
        guard let session, session.isActive, !session.isPaused, session.goalZone == nil,
              let goal = session.goalSeconds else { return }
        let left = TimeInterval(goal) - session.activeSeconds(at: Date())
        guard left > 0.5 else { return }
        let content = message(session, name: name)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false)))
    }

    /// A distance or time-in-zone goal: a GPS or heart-rate reading just crossed it.
    static func reachedNow(_ session: WorkoutSession, name: String) {
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: message(session, name: name), trigger: nil))
    }

    private static func message(_ session: WorkoutSession, name: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: SettingsKey.weightUnit) ?? "") ?? .lb
        let zone = session.goalZone.map { " in Zone \($0)" } ?? ""
        let mark = session.goalSeconds.map { DurationFormat.clock(TimeInterval($0)) + zone }
            ?? session.goalMeters.map { "\(unit.formatDistance(meters: $0)) \(unit.distanceLabel)" } ?? ""
        content.title = session.goalIsLastTime == true ? "You've matched last time" : "Target reached"
        content.body = "\(name): \(mark). Keep going, or stop when you're ready."
        content.sound = .default
        return content
    }

    private final class Presenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .sound, .list]
        }
    }
}

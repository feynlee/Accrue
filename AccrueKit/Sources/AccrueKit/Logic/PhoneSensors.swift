import Foundation

/// The Bluetooth Heart Rate Measurement characteristic (0x2A37) that chest straps and armbands
/// (Polar, Garmin, Wahoo and others) send about once a second.
public enum HeartRateMeasurement {
    /// The bpm in one notification: the first byte's lowest bit says whether it is one byte or two.
    public static func bpm(from bytes: [UInt8]) -> Int? {
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 == 0 {
            guard bytes.count >= 2 else { return nil }
            return bytes[1] == 0 ? nil : Int(bytes[1])
        }
        guard bytes.count >= 3 else { return nil }
        let value = Int(bytes[1]) | Int(bytes[2]) << 8
        return value == 0 ? nil : value
    }
}

/// Active calories when no watch measures them: METs for the activity (from speed for runs and
/// walks with a distance) times body weight and time. Resting burn is left out, as in Health's
/// active energy.
public enum CalorieEstimate {
    public static let defaultBodyKg = 75.0

    /// - Parameters:
    ///   - activity: the exercise's Health activity name ("running", "cycling"...), nil for lifting.
    ///   - timed: a timed circuit (counted as HIIT).
    public static func activeKcal(activity: String?, timed: Bool, seconds: TimeInterval, meters: Double?,
                                  bodyKg: Double) -> Double {
        guard seconds > 0, bodyKg > 0 else { return 0 }
        let met = timed ? 8.0 : self.met(activity: activity, metersPerMinute: meters.map { $0 / (seconds / 60) })
        return max(0, met - 1) * bodyKg * seconds / 3600
    }

    /// Gross METs. Runs and walks with a speed use the ACSM equations (VO₂ = 3.5 + 0.2 or 0.1 ×
    /// metres a minute); the rest come from the Compendium of Physical Activities.
    public static func met(activity: String?, metersPerMinute: Double?) -> Double {
        let speed = metersPerMinute.flatMap { $0 > 0 ? $0 : nil }
        switch activity {
        case "running": return speed.map { (3.5 + 0.2 * $0) / 3.5 } ?? 9.8
        case "walking": return speed.map { (3.5 + 0.1 * $0) / 3.5 } ?? 3.5
        case "hiking": return 6.0
        case "cycling": return 7.5
        case "rowing": return 7.0
        case "elliptical": return 5.0
        case "stairClimbing": return 9.0
        case "stairs": return 8.8
        case "swimming": return 7.0
        case "highIntensityIntervalTraining", "crossTraining", "boxing", "kickboxing": return 8.0
        case "jumpRope": return 11.0
        case nil: return 5.0  // lifting
        default: return 6.0
        }
    }
}

import Foundation

/// What the phone and the Accrue Watch app tell each other during a workout. The watch runs the
/// workout (heart rate, calories, Apple Health); the phone shows it and can pause or end it.
public enum WorkoutLink {
    /// Phone to watch, once the workout starts: what to show and which zone to keep.
    public struct Setup: Codable, Hashable, Sendable {
        public var title: String
        public var maxHR: Int
        public var targetZone: Int?
        public var goalSeconds: Int?
        public var goalZone: Int?

        public init(title: String, maxHR: Int, targetZone: Int?, goalSeconds: Int? = nil, goalZone: Int? = nil) {
            self.title = title
            self.maxHR = maxHR
            self.targetZone = targetZone
            self.goalSeconds = goalSeconds
            self.goalZone = goalZone
        }
    }

    /// Watch to phone, every few seconds.
    public struct Reading: Codable, Hashable, Sendable {
        public var heartRate: Int?
        public var activeKcal: Double?
        public var meters: Double?
        public var at: Date

        public init(heartRate: Int?, activeKcal: Double?, meters: Double?, at: Date) {
            self.heartRate = heartRate
            self.activeKcal = activeKcal
            self.meters = meters
            self.at = at
        }
    }

    /// Phone to watch: the buttons on the live bar.
    public enum Command: String, Codable, Sendable { case pause, resume, end }

    public enum Message: Codable, Hashable, Sendable {
        case setup(Setup)
        case reading(Reading)
        case command(Command)
    }

    public static func encode(_ message: Message) -> Data {
        (try? JSONEncoder().encode(message)) ?? Data()
    }

    /// Messages that do not decode (an older or newer app on the other side) are skipped.
    public static func decode(_ data: Data) -> Message? {
        try? JSONDecoder().decode(Message.self, from: data)
    }
}

extension WorkoutSession {
    /// Takes a reading from the watch: heart rate (and time in zone), calories, and distance
    /// when the watch has more than the phone's GPS (a treadmill, or GPS off).
    public mutating func apply(_ reading: WorkoutLink.Reading, zones: HeartZones) {
        if let bpm = reading.heartRate { recordHeartRate(bpm, at: reading.at, zones: zones) }
        if let kcal = reading.activeKcal { activeKcal = kcal }
        if let meters = reading.meters, meters > (distanceMeters ?? 0) { distanceMeters = meters }
    }
}

import Foundation

extension WeightUnit {
    /// Distances follow the weight unit: miles with pounds, kilometres with kilograms.
    public var distanceLabel: String { self == .lb ? "mi" : "km" }
    public var metersPerDistance: Double { self == .lb ? 1609.344 : 1000 }

    /// "2.87"
    public func formatDistance(meters: Double) -> String {
        String(format: "%.2f", meters / metersPerDistance)
    }

    /// Pace per mile or km as m'ss", or nil until there is some distance.
    public func formatPace(seconds: TimeInterval, meters: Double) -> String? {
        guard meters >= 10, seconds > 0 else { return nil }
        let pace = Int((seconds / (meters / metersPerDistance)).rounded())
        guard pace < 60 * 60 else { return nil }
        return String(format: "%d'%02d\"", pace / 60, pace % 60)
    }
}

/// Heart-rate zones as shares of the maximum heart rate: Z1 50–60 %, Z2 60–70 %, Z3 70–80 %,
/// Z4 80–90 %, Z5 90–100 %.
public struct HeartZones: Hashable, Sendable {
    public var maxHR: Int

    public init(maxHR: Int = 190) {
        self.maxHR = maxHR
    }

    public static let defaultMax = 190

    /// Beats per minute for a zone (1…5).
    public func range(_ zone: Int) -> ClosedRange<Int> {
        let z = min(5, max(1, zone))
        let low = Int((Double(maxHR) * (0.4 + 0.1 * Double(z))).rounded())
        let high = Int((Double(maxHR) * (0.5 + 0.1 * Double(z))).rounded()) - (z == 5 ? 0 : 1)
        return low...high
    }

    /// The zone a heart rate is in; below Z1 counts as Z1.
    public func zone(for bpm: Int) -> Int {
        for z in stride(from: 5, through: 2, by: -1) where bpm >= range(z).lowerBound { return z }
        return 1
    }
}

/// Distance along GPS points. Rough fixes, and anything while paused, are left out.
public struct RouteDistance: Hashable, Sendable {
    public private(set) var meters: Double = 0
    private var last: Point?

    public struct Point: Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public init(meters: Double = 0) {
        self.meters = meters
    }

    /// Fixes worse than this many metres are ignored.
    public static let worstAccuracy = 25.0

    public mutating func add(_ point: Point, accuracy: Double, paused: Bool) {
        guard accuracy >= 0, accuracy <= Self.worstAccuracy else { return }
        if paused {
            // Start again from where the run picks up, so the walk to a café does not count.
            last = nil
            return
        }
        if let last {
            let step = Self.meters(from: last, to: point)
            // A jump faster than ~12 m/s between fixes is GPS noise, not running.
            if step < 60 { meters += step }
        }
        last = point
    }

    /// Great-circle distance.
    public static func meters(from a: Point, to b: Point) -> Double {
        let r = 6_371_000.0
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dp = p2 - p1, dl = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}

extension Tracking {
    /// Cardio that covers ground, so it can have a distance and a pace.
    public var usesDistance: Bool { self == .distanceTimeHR }
}

/// What a cardio workout aims for: a time or a distance. Reaching it beeps and notifies; the
/// workout keeps going until you stop it.
public struct CardioTarget: Codable, Hashable, Sendable {
    public enum Metric: String, Codable, Sendable { case time, distance }

    public var metric: Metric
    /// Seconds or metres; nil means "what I did last time".
    public var value: Double?

    public init(metric: Metric, value: Double? = nil) {
        self.metric = metric
        self.value = value
    }

    public static let lastTime = CardioTarget(metric: .time)

    public var isLastTime: Bool { value == nil }

    /// The goal in seconds or metres: the set value, else last time's, else (time only) the plan.
    public func goal(last: DaySummary?, plannedMinutes: Int?) -> Double? {
        if let value { return value }
        switch metric {
        case .time: return last?.durationSeconds.map(Double.init) ?? plannedMinutes.map { Double($0 * 60) }
        case .distance: return last?.distanceMeters
        }
    }

    /// Whether the goal comes from last time (not set, and there is a last time to match).
    public func usesLastTime(last: DaySummary?) -> Bool {
        guard value == nil else { return false }
        return metric == .time ? last?.durationSeconds != nil : last?.distanceMeters != nil
    }
}

extension WorkoutSession {
    /// Sets the goal from a target; a distance goal needs a distance to aim for.
    public mutating func setGoal(_ target: CardioTarget, last: DaySummary?, plannedMinutes: Int?) {
        let goal = target.goal(last: last, plannedMinutes: plannedMinutes)
        goalSeconds = target.metric == .time ? goal.map { Int($0.rounded()) } : nil
        goalMeters = target.metric == .distance ? goal : nil
        goalIsLastTime = target.usesLastTime(last: last)
    }

    /// Whether the goal is reached, `active` seconds in.
    public func reachedGoal(active: TimeInterval) -> Bool {
        if let goalSeconds { return active >= TimeInterval(goalSeconds) }
        if let goalMeters { return (distanceMeters ?? 0) >= goalMeters }
        return false
    }

    /// How far toward the goal, 0…1.
    public func goalProgress(active: TimeInterval) -> Double {
        if let goalSeconds, goalSeconds > 0 { return min(1, active / TimeInterval(goalSeconds)) }
        if let goalMeters, goalMeters > 0 { return min(1, (distanceMeters ?? 0) / goalMeters) }
        return 0
    }
}

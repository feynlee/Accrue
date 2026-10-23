import Foundation

/// One logged set (or one cardio entry). Logging never needs a started workout,
/// so `sessionID` is only set when a workout was running.
public struct LoggedSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var day: DayKey
    public var exerciseID: String
    public var partID: UUID?
    public var sessionID: UUID?
    /// Kilograms. For bodyweight moves, the added weight (nil or 0 = bodyweight only).
    public var weightKg: Double?
    public var reps: Int?
    public var holdSeconds: Int?
    public var distanceMeters: Double?
    public var durationSeconds: Int?
    public var pauseSeconds: Int
    public var isWarmup: Bool
    public var loggedAt: Date

    public init(id: UUID = UUID(), day: DayKey, exerciseID: String, partID: UUID? = nil, sessionID: UUID? = nil,
                weightKg: Double? = nil, reps: Int? = nil, holdSeconds: Int? = nil,
                distanceMeters: Double? = nil, durationSeconds: Int? = nil,
                pauseSeconds: Int = 0, isWarmup: Bool = false, loggedAt: Date = Date()) {
        self.id = id
        self.day = day
        self.exerciseID = exerciseID
        self.partID = partID
        self.sessionID = sessionID
        self.weightKg = weightKg
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.pauseSeconds = pauseSeconds
        self.isWarmup = isWarmup
        self.loggedAt = loggedAt
    }
}

/// One started part of a day. Later this maps to one HKWorkoutSession.
public struct WorkoutSession: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var day: DayKey
    public var partID: UUID?
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    /// Paused time already finished.
    public var pausedSeconds: TimeInterval
    /// Set while paused right now.
    public var pausedAt: Date?

    public init(id: UUID = UUID(), day: DayKey, partID: UUID?, title: String, startedAt: Date) {
        self.id = id
        self.day = day
        self.partID = partID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.pausedSeconds = 0
        self.pausedAt = nil
    }

    public var isActive: Bool { endedAt == nil }
    public var isPaused: Bool { pausedAt != nil }

    /// Time from start, paused time left out.
    public func activeSeconds(at now: Date) -> TimeInterval {
        let end = endedAt ?? now
        var paused = pausedSeconds
        if let p = pausedAt { paused += max(0, end.timeIntervalSince(p)) }
        return max(0, end.timeIntervalSince(startedAt) - paused)
    }

    public func totalSeconds(at now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }
}

import Foundation

/// One exercise in a preset or a day, with its targets.
public struct PlannedExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseID: String
    public var sets: Int
    public var reps: Int?
    public var holdSeconds: Int?
    /// Starting weight. Kilograms; for bodyweight moves this is the added weight.
    public var weightKg: Double?
    /// Pause at the top of each rep, in seconds (0 = none).
    public var pauseSeconds: Int
    public var restSeconds: Int
    /// For time-based cardio: the planned minutes.
    public var minutes: Int?

    public init(id: UUID = UUID(), exerciseID: String, sets: Int = 3, reps: Int? = 10, holdSeconds: Int? = nil,
                weightKg: Double? = nil, pauseSeconds: Int = 0, restSeconds: Int = 120, minutes: Int? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.weightKg = weightKg
        self.pauseSeconds = pauseSeconds
        self.restSeconds = restSeconds
        self.minutes = minutes
    }
}

/// A named, ordered list of exercises ("Push", "Pull").
public struct Preset: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var items: [PlannedExercise]

    public init(id: UUID = UUID(), name: String, items: [PlannedExercise] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// One part of a day: a preset, or one exercise on its own. Each part is started and saved as its own workout.
public struct DayPart: Codable, Hashable, Sendable, Identifiable {
    public enum Content: Codable, Hashable, Sendable {
        case preset(UUID)
        case exercise(PlannedExercise)
    }

    public var id: UUID
    public var content: Content

    public init(id: UUID = UUID(), _ content: Content) {
        self.id = id
        self.content = content
    }

    public static func preset(_ id: UUID) -> DayPart { DayPart(.preset(id)) }
    public static func exercise(_ item: PlannedExercise) -> DayPart { DayPart(.exercise(item)) }
}

/// The weekly routine: the parts of each weekday, Monday first.
public struct WeekRoutine: Codable, Hashable, Sendable {
    public var days: [[DayPart]]

    public init(days: [[DayPart]] = Array(repeating: [], count: 7)) {
        var days = days
        while days.count < 7 { days.append([]) }
        self.days = Array(days.prefix(7))
    }

    public subscript(day: Weekday) -> [DayPart] {
        get { days[day.rawValue - 1] }
        set { days[day.rawValue - 1] = newValue }
    }
}

/// A change to one date only ("Today only"); the routine itself stays as it is.
public struct DayOverride: Codable, Hashable, Sendable {
    public var day: DayKey
    public var parts: [DayPart]

    public init(day: DayKey, parts: [DayPart]) {
        self.day = day
        self.parts = parts
    }
}

/// Where a change to a day's parts goes.
public enum EditScope: Sendable {
    case thisDayOnly
    case everyWeek
}

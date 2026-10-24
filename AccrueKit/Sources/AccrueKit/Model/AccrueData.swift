import Foundation

/// Everything the user creates: plans, the routine, and the log. Saved as one document.
public struct AccrueData: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var presets: [Preset]
    public var routine: WeekRoutine
    public var overrides: [DayOverride]
    public var sets: [LoggedSet]
    public var sessions: [WorkoutSession]
    /// Exercise ids, in the order they were starred.
    public var favorites: [String]
    /// Timed exercises the user made (7-minute, HIIT …).
    public var timed: [TimedExercise]
    /// What each cardio exercise aims for, when the user changed it from "last time".
    public var cardioTargets: [String: CardioTarget]

    public init(presets: [Preset] = [], routine: WeekRoutine = WeekRoutine(), overrides: [DayOverride] = [],
                sets: [LoggedSet] = [], sessions: [WorkoutSession] = [], favorites: [String] = [],
                timed: [TimedExercise] = []) {
        self.version = AccrueData.currentVersion
        self.timed = timed
        self.cardioTargets = [:]
        self.presets = presets
        self.routine = routine
        self.overrides = overrides
        self.sets = sets
        self.sessions = sessions
        self.favorites = favorites
    }

    private enum CodingKeys: String, CodingKey {
        case version, presets, routine, overrides, sets, sessions, favorites, timed, cardioTargets
    }

    /// Files saved before timed exercises or cardio targets existed have neither.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        presets = try c.decode([Preset].self, forKey: .presets)
        routine = try c.decode(WeekRoutine.self, forKey: .routine)
        overrides = try c.decode([DayOverride].self, forKey: .overrides)
        sets = try c.decode([LoggedSet].self, forKey: .sets)
        sessions = try c.decode([WorkoutSession].self, forKey: .sessions)
        favorites = try c.decode([String].self, forKey: .favorites)
        timed = try c.decodeIfPresent([TimedExercise].self, forKey: .timed) ?? []
        cardioTargets = try c.decodeIfPresent([String: CardioTarget].self, forKey: .cardioTargets) ?? [:]
    }

    // MARK: Plans

    public func preset(_ id: UUID) -> Preset? {
        presets.first { $0.id == id }
    }

    /// The day's parts: its "today only" override if it has one, else the routine for its weekday.
    public func parts(on day: DayKey, calendar: Calendar = .current) -> [DayPart] {
        if let o = overrides.first(where: { $0.day == day }) { return o.parts }
        return routine[day.weekday(calendar: calendar)]
    }

    public func hasOverride(on day: DayKey) -> Bool {
        overrides.contains { $0.day == day }
    }

    /// The exercises a part asks for, in order. A deleted preset gives none.
    public func items(in part: DayPart) -> [PlannedExercise] {
        switch part.content {
        case .preset(let id): preset(id)?.items ?? []
        case .exercise(let item): [item]
        case .timed: []
        }
    }

    public func timedExercise(_ id: UUID) -> TimedExercise? {
        timed.first { $0.id == id }
    }

    /// The timed exercise a part runs, if it is one.
    public func timedExercise(in part: DayPart) -> TimedExercise? {
        part.timedID.flatMap(timedExercise)
    }

    public mutating func upsert(_ exercise: TimedExercise) {
        if let i = timed.firstIndex(where: { $0.id == exercise.id }) {
            timed[i] = exercise
        } else {
            timed.append(exercise)
        }
    }

    /// Removes a timed exercise and every day part that runs it.
    public mutating func deleteTimed(_ id: UUID) {
        timed.removeAll { $0.id == id }
        let keep: (DayPart) -> Bool = { $0.timedID != id }
        routine.days = routine.days.map { $0.filter(keep) }
        overrides = overrides.map { DayOverride(day: $0.day, parts: $0.parts.filter(keep)) }
    }

    public func title(of part: DayPart, catalog: Catalog) -> String {
        switch part.content {
        case .preset(let id):
            return preset(id)?.name ?? "Removed preset"
        case .exercise(let item):
            return catalog.exercise(item.exerciseID)?.displayName ?? "Exercise"
        case .timed(let id):
            return timedExercise(id)?.name ?? "Removed timed exercise"
        }
    }

    public mutating func setParts(_ parts: [DayPart], on day: DayKey, scope: EditScope, calendar: Calendar = .current) {
        switch scope {
        case .thisDayOnly:
            overrides.removeAll { $0.day == day }
            overrides.append(DayOverride(day: day, parts: parts))
        case .everyWeek:
            overrides.removeAll { $0.day == day }
            routine[day.weekday(calendar: calendar)] = parts
        }
    }

    /// Drops a "today only" change so the day follows the routine again.
    public mutating func clearOverride(on day: DayKey) {
        overrides.removeAll { $0.day == day }
    }

    public mutating func upsert(_ preset: Preset) {
        if let i = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[i] = preset
        } else {
            presets.append(preset)
        }
    }

    /// Removes a preset and every day part that points to it.
    public mutating func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        let keep: (DayPart) -> Bool = { if case .preset(id) = $0.content { false } else { true } }
        routine.days = routine.days.map { $0.filter(keep) }
        overrides = overrides.map { DayOverride(day: $0.day, parts: $0.parts.filter(keep)) }
    }

    /// Weekdays whose routine includes the preset.
    public func weekdays(using presetID: UUID) -> [Weekday] {
        Weekday.allCases.filter { day in
            routine[day].contains { if case .preset(presetID) = $0.content { true } else { false } }
        }
    }

    /// Puts the preset on, or takes it off, a weekday of the routine.
    public mutating func schedule(_ presetID: UUID, on weekday: Weekday, _ on: Bool) {
        let isIt: (DayPart) -> Bool = { if case .preset(presetID) = $0.content { true } else { false } }
        if on {
            if !routine[weekday].contains(where: isIt) { routine[weekday].append(.preset(presetID)) }
        } else {
            routine[weekday].removeAll(where: isIt)
        }
    }

    // MARK: Favorites

    public func isFavorite(_ exerciseID: String) -> Bool { favorites.contains(exerciseID) }

    public mutating func toggleFavorite(_ exerciseID: String) {
        if let i = favorites.firstIndex(of: exerciseID) {
            favorites.remove(at: i)
        } else {
            favorites.append(exerciseID)
        }
    }

    // MARK: Log

    public mutating func log(_ set: LoggedSet) {
        sets.append(set)
    }

    public mutating func deleteSet(_ id: UUID) {
        sets.removeAll { $0.id == id }
    }

    public mutating func updateSet(_ set: LoggedSet) {
        if let i = sets.firstIndex(where: { $0.id == set.id }) { sets[i] = set }
    }

    /// Sets of one exercise on one day, oldest first. With `partID`, only those logged in that part.
    public func sets(of exerciseID: String, on day: DayKey, partID: UUID? = nil) -> [LoggedSet] {
        sets.filter { $0.exerciseID == exerciseID && $0.day == day && (partID == nil || $0.partID == partID) }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    public func sets(on day: DayKey) -> [LoggedSet] {
        sets.filter { $0.day == day }.sorted { $0.loggedAt < $1.loggedAt }
    }

    public func history(of exerciseID: String) -> [LoggedSet] {
        sets.filter { $0.exerciseID == exerciseID }
    }

    // MARK: Workouts

    public var activeSession: WorkoutSession? {
        sessions.last { $0.isActive }
    }

    /// Starts a workout for a part. Any other running workout ends first.
    @discardableResult
    public mutating func startSession(day: DayKey, partID: UUID?, title: String, at now: Date = Date()) -> WorkoutSession {
        if let active = activeSession { endSession(active.id, at: now) }
        var session = WorkoutSession(day: day, partID: partID, title: title, startedAt: now)
        if let part = parts(on: day).first(where: { $0.id == partID }) {
            if let plan = timedExercise(in: part) { session.timer = TimedTimer(rounds: plan.rounds) }
            if case .exercise(let item) = part.content, let minutes = item.minutes { session.goalSeconds = minutes * 60 }
        }
        sessions.append(session)
        return session
    }

    public mutating func togglePause(_ id: UUID, at now: Date = Date()) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].isActive else { return }
        if let p = sessions[i].pausedAt {
            sessions[i].pausedSeconds += max(0, now.timeIntervalSince(p))
            sessions[i].pausedAt = nil
        } else {
            sessions[i].pausedAt = now
        }
    }

    public mutating func endSession(_ id: UUID, at now: Date = Date()) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].isActive else { return }
        if let p = sessions[i].pausedAt {
            sessions[i].pausedSeconds += max(0, now.timeIntervalSince(p))
            sessions[i].pausedAt = nil
        }
        sessions[i].endedAt = now
    }

    /// The target for a cardio exercise; beating last time's time unless the user changed it.
    public func cardioTarget(for exerciseID: String) -> CardioTarget {
        cardioTargets[exerciseID] ?? .lastTime
    }

    public mutating func setCardioTarget(_ target: CardioTarget, for exerciseID: String) {
        cardioTargets[exerciseID] = target == .lastTime ? nil : target
    }

    /// Changes a workout in place (distance so far, the goal).
    public mutating func updateSession(_ id: UUID, _ change: (inout WorkoutSession) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[i])
    }

    /// Changes a timed workout's timer (Skip, Back, +10 s, + 1 round).
    public mutating func updateTimer(_ sessionID: UUID, _ change: (inout TimedTimer) -> Void) {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }), var timer = sessions[i].timer else { return }
        change(&timer)
        sessions[i].timer = timer
    }

    public func sessions(on day: DayKey) -> [WorkoutSession] {
        sessions.filter { $0.day == day }
    }

    public func sets(in sessionID: UUID) -> [LoggedSet] {
        sets.filter { $0.sessionID == sessionID }.sorted { $0.loggedAt < $1.loggedAt }
    }
}

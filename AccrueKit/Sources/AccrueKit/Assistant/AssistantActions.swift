import Foundation

/// Changes Siri and Shortcuts can make, kept here so they behave like the screens and can be
/// tested: which part to start, adding and swapping exercises, and undoing the last set.
extension AccrueData {
    /// The part "start my workout" means: the one asked for, or the first part of the day that
    /// has nothing logged yet.
    public func partToStart(on day: DayKey, calendar: Calendar = .current) -> DayPart? {
        let parts = self.parts(on: day, calendar: calendar)
        let done = Set(sets(on: day).compactMap(\.partID)).union(sessions(on: day).compactMap(\.partID))
        return parts.first { !done.contains($0.id) }
    }

    /// The part on a day that is this exercise on its own, or adds one ("this day only" unless
    /// `scope` says every week). Used to start or plan an exercise that isn't on the day yet.
    @discardableResult
    public mutating func add(_ item: PlannedExercise, on day: DayKey, scope: EditScope = .thisDayOnly,
                             calendar: Calendar = .current) -> DayPart {
        let parts = self.parts(on: day, calendar: calendar)
        if let existing = parts.first(where: { if case .exercise(let e) = $0.content { e.exerciseID == item.exerciseID } else { false } }) {
            return existing
        }
        let part = DayPart.exercise(item)
        setParts(parts + [part], on: day, scope: scope, calendar: calendar)
        return part
    }

    /// Adds a preset or timed exercise to a day.
    @discardableResult
    public mutating func add(_ part: DayPart, on day: DayKey, scope: EditScope = .thisDayOnly,
                             calendar: Calendar = .current) -> DayPart {
        setParts(self.parts(on: day, calendar: calendar) + [part], on: day, scope: scope, calendar: calendar)
        return part
    }

    public enum SwapResult: Equatable, Sendable {
        /// Swapped in the day's plan (this day, or the weekly routine).
        case day
        /// The exercise was in a preset, so the preset itself changed (every day that uses it).
        case preset(String)
    }

    /// Replaces an exercise on a day's plan with another, keeping its sets, reps and rest.
    public mutating func swap(_ oldID: String, for newID: String, on day: DayKey, scope: EditScope = .thisDayOnly,
                              calendar: Calendar = .current) -> SwapResult? {
        var parts = self.parts(on: day, calendar: calendar)
        for (i, part) in parts.enumerated() {
            switch part.content {
            case .exercise(var item) where item.exerciseID == oldID:
                item.exerciseID = newID
                parts[i] = DayPart(id: part.id, .exercise(item))
                setParts(parts, on: day, scope: scope, calendar: calendar)
                return .day
            case .preset(let id):
                guard var preset = preset(id), let j = preset.items.firstIndex(where: { $0.exerciseID == oldID }) else { continue }
                preset.items[j].exerciseID = newID
                upsert(preset)
                return .preset(preset.name)
            default:
                continue
            }
        }
        return nil
    }

    /// Removes an exercise from a day's plan, or from the preset it is in.
    public mutating func remove(_ exerciseID: String, from day: DayKey, scope: EditScope = .thisDayOnly,
                                calendar: Calendar = .current) -> SwapResult? {
        var parts = self.parts(on: day, calendar: calendar)
        for (i, part) in parts.enumerated() {
            switch part.content {
            case .exercise(let item) where item.exerciseID == exerciseID:
                parts.remove(at: i)
                setParts(parts, on: day, scope: scope, calendar: calendar)
                return .day
            case .preset(let id):
                guard var preset = preset(id), preset.items.contains(where: { $0.exerciseID == exerciseID }) else { continue }
                preset.items.removeAll { $0.exerciseID == exerciseID }
                upsert(preset)
                return .preset(preset.name)
            default:
                continue
            }
        }
        return nil
    }

    /// Deletes the most recently logged set (of one exercise, if given) and returns it.
    public mutating func undoLastSet(of exerciseID: String? = nil) -> LoggedSet? {
        guard let last = sets.filter({ exerciseID == nil || $0.exerciseID == exerciseID }).max(by: { $0.loggedAt < $1.loggedAt })
        else { return nil }
        deleteSet(last.id)
        return last
    }
}

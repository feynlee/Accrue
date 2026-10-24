import Foundation

/// The "vs" chips on Progress: which earlier session to compare with.
public enum Comparison: Int, CaseIterable, Identifiable, Sendable {
    case lastTime, fourWeeks, threeMonths, oneYear

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .lastTime: "Last time"
        case .fourWeeks: "4 wk ago"
        case .threeMonths: "3 mo ago"
        case .oneYear: "1 yr ago"
        }
    }

    /// Nil for Last time, which is the previous session whatever its date.
    public var daysBack: Int? {
        switch self {
        case .lastTime: nil
        case .fourWeeks: 28
        case .threeMonths: 91
        case .oneYear: 365
        }
    }
}

extension ExerciseHistory {
    /// The session to compare `day` with: the one before it for Last time, otherwise the
    /// latest one on or before that many days earlier.
    public func compared(_ comparison: Comparison, to day: DayKey, calendar: Calendar = .current) -> DaySummary? {
        guard let back = comparison.daysBack else { return lastTime(before: day) }
        return summary(daysBefore: back, from: day, calendar: calendar)
    }

    /// Working-set volume per Monday-first week, oldest first, for the `weeks` weeks ending
    /// with the week of `day`. Weeks with no sets are 0.
    public func weeklyVolume(weeks: Int, endingOn day: DayKey, calendar: Calendar = .current) -> [(week: DayKey, volumeKg: Double)] {
        let lastMonday = day.startOfWeek(calendar: calendar)
        return (0..<weeks).reversed().map { back in
            let monday = lastMonday.adding(days: -7 * back, calendar: calendar)
            let sunday = monday.adding(days: 6, calendar: calendar)
            let total = days.filter { $0.day >= monday && $0.day <= sunday }.reduce(0) { $0 + $1.volumeKg }
            return (monday, total)
        }
    }

    /// Volume of the Monday-first week that holds `day`.
    public func volume(inWeekOf day: DayKey, calendar: Calendar = .current) -> Double {
        weeklyVolume(weeks: 1, endingOn: day, calendar: calendar).first?.volumeKg ?? 0
    }
}

/// What one day added up to, for the Progress week bars and the calendar.
public struct DayTotals: Hashable, Sendable {
    public var day: DayKey
    /// Weight × reps over working sets of weighted strength moves.
    public var volumeKg: Double = 0
    public var workingSets = 0
    public var cardioSeconds = 0
    public var cardioMeters: Double = 0
    /// Exercises with working sets, in the order they were first logged.
    public var strengthExercises: [String] = []
    public var cardioExercises: [String] = []

    public var hasStrength: Bool { workingSets > 0 }
    public var hasCardio: Bool { cardioSeconds > 0 || cardioMeters > 0 }
    public var isEmpty: Bool { !hasStrength && !hasCardio }

    public init(day: DayKey) { self.day = day }
}

extension AccrueData {
    public func totals(on day: DayKey, catalog: Catalog) -> DayTotals {
        Self.totals(of: self.sets(on: day), on: day, catalog: catalog)
    }

    /// Totals for every day that has sets, in one pass (the calendar's year view).
    public func totalsByDay(catalog: Catalog) -> [DayKey: DayTotals] {
        Dictionary(grouping: sets, by: \.day).reduce(into: [:]) { result, entry in
            let totals = Self.totals(of: entry.value, on: entry.key, catalog: catalog)
            if !totals.isEmpty { result[entry.key] = totals }
        }
    }

    static func totals(of daySets: [LoggedSet], on day: DayKey, catalog: Catalog) -> DayTotals {
        var totals = DayTotals(day: day)
        let sets = daySets.sorted { $0.loggedAt < $1.loggedAt }
        var order: [String] = []
        for set in sets where !order.contains(set.exerciseID) { order.append(set.exerciseID) }
        for id in order {
            let tracking = catalog.exercise(id).map { catalog.tracking(for: $0) } ?? .weightReps
            let mine = sets.filter { $0.exerciseID == id }
            let working = TrainingMath.workingSets(mine, tracking: tracking)
            guard !working.isEmpty else { continue }
            if tracking.isSetBased {
                totals.workingSets += working.count
                totals.volumeKg += TrainingMath.volume(mine, tracking: tracking)
                totals.strengthExercises.append(id)
            } else {
                totals.cardioSeconds += working.compactMap(\.durationSeconds).reduce(0, +)
                totals.cardioMeters += working.compactMap(\.distanceMeters).reduce(0, +)
                totals.cardioExercises.append(id)
            }
        }
        return totals
    }
}

/// Calendar shading: how bright a strength day is, from 1 (light) to 3 (heaviest), against the
/// heaviest day in view. 0 means no strength that day.
public enum IntensityLevel {
    public static func level(volumeKg: Double, hadStrength: Bool, maxVolumeKg: Double) -> Int {
        guard hadStrength else { return 0 }
        guard maxVolumeKg > 0, volumeKg > 0 else { return 1 }
        let share = volumeKg / maxVolumeKg
        return share > 0.66 ? 3 : share > 0.33 ? 2 : 1
    }
}

import Foundation

/// What one exercise looked like on one day.
public struct DaySummary: Hashable, Sendable {
    public var day: DayKey
    public var workingSets: Int
    /// Heaviest working weight, kg (nil for unweighted moves).
    public var topWeightKg: Double?
    /// Reps most often done at the top weight (or across sets when unweighted).
    public var typicalReps: Int?
    public var longestHoldSeconds: Int?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var strength: Double?
    public var volumeKg: Double
    public var totalReps: Int

    public init(day: DayKey, sets: [LoggedSet], tracking: Tracking) {
        let working = TrainingMath.workingSets(sets, tracking: tracking)
        self.day = day
        workingSets = working.count
        let top = working.compactMap(\.weightKg).filter { $0 > 0 }.max()
        topWeightKg = top
        let repSource = top.map { t in working.filter { ($0.weightKg ?? 0) == t } } ?? working
        typicalReps = DaySummary.mostCommon(repSource.compactMap(\.reps))
        longestHoldSeconds = working.compactMap(\.holdSeconds).max()
        durationSeconds = working.compactMap(\.durationSeconds).reduce(nil) { ($0 ?? 0) + $1 }
        distanceMeters = working.compactMap(\.distanceMeters).reduce(nil) { ($0 ?? 0) + $1 }
        strength = TrainingMath.strength(sets, tracking: tracking)
        volumeKg = TrainingMath.volume(sets, tracking: tracking)
        totalReps = TrainingMath.totalReps(sets, tracking: tracking)
    }

    /// Ties go to the higher count.
    static func mostCommon(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value == b.value ? a.key < b.key : a.value < b.value }?.key
    }

    /// The "Last time" line: "100 × 9 × 5", "BW × 12 × 3", "0:52 × 3", "30:00 · 5.2 km".
    public func line(unit: WeightUnit, tracking: Tracking) -> String {
        switch tracking {
        case .weightReps, .reps:
            let w = topWeightKg.map { unit.format(kg: $0) } ?? "BW"
            let shownWeight = tracking == .reps && topWeightKg != nil ? "BW+\(w)" : w
            return "\(shownWeight) × \(typicalReps ?? 0) × \(workingSets)"
        case .hold, .weightHold:
            let hold = DurationFormat.clock(TimeInterval(longestHoldSeconds ?? 0))
            if let w = topWeightKg, tracking == .weightHold { return "\(unit.format(kg: w)) × \(hold) × \(workingSets)" }
            return "\(hold) × \(workingSets)"
        case .weightDistance:
            let w = topWeightKg.map { unit.format(kg: $0) } ?? "BW"
            let d = distanceMeters.map { "\(Int($0)) m" } ?? ""
            return "\(w) × \(workingSets)" + (d.isEmpty ? "" : " · \(d)")
        case .time, .timeHR, .distanceTimeHR:
            let t = DurationFormat.clock(TimeInterval(durationSeconds ?? 0))
            if let d = distanceMeters, d > 0 { return "\(t) · \(String(format: "%.1f", d / 1000)) km" }
            return t
        }
    }
}

/// One exercise's logged days, newest last.
public struct ExerciseHistory: Sendable {
    public let exerciseID: String
    public let tracking: Tracking
    public let days: [DaySummary]

    public init(exerciseID: String, tracking: Tracking, sets: [LoggedSet]) {
        self.exerciseID = exerciseID
        self.tracking = tracking
        let mine = sets.filter { $0.exerciseID == exerciseID }
        let byDay = Dictionary(grouping: mine, by: \.day)
        days = byDay.keys.sorted().map { DaySummary(day: $0, sets: byDay[$0] ?? [], tracking: tracking) }
            .filter { $0.workingSets > 0 }
    }

    public func summary(on day: DayKey) -> DaySummary? {
        days.first { $0.day == day }
    }

    /// The last day with working sets before `day`.
    public func lastTime(before day: DayKey) -> DaySummary? {
        days.last { $0.day < day }
    }

    /// The closest logged day on or before `day` minus `daysBack`, for "vs 4 wk ago".
    public func summary(daysBefore daysBack: Int, from day: DayKey, calendar: Calendar = .current) -> DaySummary? {
        let target = day.adding(days: -daysBack, calendar: calendar)
        return days.last { $0.day <= target }
    }

    /// Strength change in percent from `daysBack` days earlier to `day`.
    public func strengthChange(on day: DayKey, daysBack: Int = 28, calendar: Calendar = .current) -> Double? {
        let now = summary(on: day) ?? lastTime(before: day.adding(days: 1, calendar: calendar))
        let before = summary(daysBefore: daysBack, from: day, calendar: calendar)
        guard let now, let before, now.day != before.day else { return nil }
        return TrainingMath.change(from: before.strength, to: now.strength)
    }
}

/// What the Train card's steppers start at.
public struct SetSuggestion: Hashable, Sendable {
    public var weightKg: Double?
    public var reps: Int?
    public var holdSeconds: Int?

    /// Today's last working set if there is one, else last time's top set, else the plan.
    public init(plan: PlannedExercise?, today: [LoggedSet], lastTime: DaySummary?, tracking: Tracking) {
        if let last = today.last(where: { !$0.isWarmup }) ?? today.last {
            weightKg = last.weightKg
            reps = last.reps
            holdSeconds = last.holdSeconds
        } else if let lastTime {
            weightKg = lastTime.topWeightKg ?? plan?.weightKg
            reps = lastTime.typicalReps ?? plan?.reps
            holdSeconds = lastTime.longestHoldSeconds ?? plan?.holdSeconds
        } else {
            weightKg = plan?.weightKg
            reps = plan?.reps
            holdSeconds = plan?.holdSeconds
        }
        if tracking.usesWeight, weightKg == nil { weightKg = 20 }
        if !tracking.usesHold, reps == nil, tracking.isSetBased { reps = 10 }
        if tracking.usesHold, holdSeconds == nil { holdSeconds = 30 }
    }
}

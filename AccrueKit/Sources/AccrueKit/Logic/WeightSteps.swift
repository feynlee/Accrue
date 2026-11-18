import Foundation

/// One day's work at its top weight, as the weight-steps chart counts it.
public struct StepSession: Hashable, Sendable, Identifiable {
    public var day: DayKey
    /// Reps of each working set at the day's top weight, in the order logged (seconds for holds).
    public var values: [Int]
    /// Every planned set was done at this weight and reached the target.
    public var hitTarget: Bool

    public var id: DayKey { day }
    public var total: Int { values.reduce(0, +) }
}

/// A run of sessions in a row at the same weight and pause.
public struct WeightStep: Hashable, Sendable, Identifiable {
    /// Kilograms; nil is bodyweight only. For bodyweight moves this is the added weight.
    public var weightKg: Double?
    public var pauseSeconds: Int
    public var sessions: [StepSession]

    public var start: DayKey { sessions[0].day }
    public var id: DayKey { start }
}

/// How long an exercise has stayed at each weight, and whether it is time to go up.
///
/// A step ends when the working weight (or the pause) changes. "Ready" needs no judgement from
/// the lifter: every planned set reached the target reps in the last two sessions at the weight.
public struct WeightSteps: Sendable {
    public enum Verdict: Hashable, Sendable {
        /// The last two sessions at this weight hit every set.
        case ready
        /// Six weeks or more at this weight, and total reps no higher in the last four.
        case stalled
        /// Still working up to the target; `clean` of the two sessions needed are in.
        case building(clean: Int)
        /// The weight is new today.
        case new
    }

    public static let sessionsNeeded = 2
    public static let stalledAfterDays = 42
    public static let stalledWindowDays = 28

    public let tracking: Tracking
    public let steps: [WeightStep]
    public let today: DayKey
    /// False when the exercise has no rep or hold target to judge against.
    public let hasTarget: Bool
    private let calendar: Calendar

    /// Whether an exercise tracked this way has weight steps at all (cardio does not).
    public static func applies(to tracking: Tracking) -> Bool { tracking.isSetBased }

    public init(sets: [LoggedSet], tracking: Tracking, targetSets: Int, targetReps: Int?, targetHold: Int?,
                today: DayKey, calendar: Calendar = .current) {
        self.tracking = tracking
        self.today = today
        self.calendar = calendar
        let target = tracking.usesHold ? targetHold : targetReps
        hasTarget = target != nil && tracking != .weightDistance

        var steps: [WeightStep] = []
        let byDay = Dictionary(grouping: sets.filter { $0.day <= today }, by: \.day)
        for day in byDay.keys.sorted() {
            let working = TrainingMath.workingSets(byDay[day] ?? [], tracking: tracking).sorted { $0.loggedAt < $1.loggedAt }
            guard !working.isEmpty else { continue }
            let top = working.compactMap(\.weightKg).filter { $0 > 0 }.max()
            let atTop = top.map { t in working.filter { WeightSteps.same($0.weightKg, t) } } ?? working
            let pause = DaySummary.mostCommon(atTop.map(\.pauseSeconds)) ?? 0
            let values = atTop.compactMap { tracking.usesHold ? $0.holdSeconds : $0.reps }
            // The same lift can sit in two presets with different set counts (5 on Tuesday, 4 on
            // Friday), so a long plan allows one set fewer; three sets or less must all be done.
            let needed = targetSets <= 3 ? max(1, targetSets) : targetSets - 1
            let hit = target.map { t in
                tracking != .weightDistance && values.count >= needed && values.allSatisfy { $0 >= t }
            } ?? false
            let session = StepSession(day: day, values: values, hitTarget: hit)
            if let last = steps.last, WeightSteps.same(last.weightKg, top), last.pauseSeconds == pause {
                steps[steps.count - 1].sessions.append(session)
            } else {
                steps.append(WeightStep(weightKg: top, pauseSeconds: pause, sessions: [session]))
            }
        }
        self.steps = steps
    }

    /// Weights are stored in kilograms but entered in either unit; a tenth of a kilo apart is the same plate.
    static func same(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a - b) < 0.05
        case let (a?, nil), let (nil, a?): a <= 0
        }
    }

    public var current: WeightStep? { steps.last }

    /// Days from the first session of a step to the next step's first (to today for the current one).
    public func days(in step: WeightStep) -> Int {
        let end = steps.first { $0.start > step.start }?.start ?? today
        return WeightSteps.days(from: step.start, to: end, calendar: calendar)
    }

    public var daysAtCurrent: Int { current.map(days(in:)) ?? 0 }

    public static func days(from a: DayKey, to b: DayKey, calendar: Calendar = .current) -> Int {
        Int((b.date(calendar: calendar).timeIntervalSince(a.date(calendar: calendar)) / 86_400).rounded())
    }

    /// Sessions that count toward the verdict: today's is left out until it hits the target, so
    /// "Ready" does not flicker off after the first set of the day.
    public var judgedSessions: [StepSession] {
        guard let current else { return [] }
        return current.sessions.filter { $0.day < today || $0.hitTarget }
    }

    /// How many of the last two judged sessions hit every set.
    public var cleanStreak: Int {
        var n = 0
        for session in judgedSessions.suffix(WeightSteps.sessionsNeeded).reversed() {
            if session.hitTarget { n += 1 } else { break }
        }
        return n
    }

    public var verdict: Verdict? {
        guard let current else { return nil }
        guard hasTarget else { return current.start == today ? .new : nil }
        let judged = judgedSessions
        if cleanStreak >= WeightSteps.sessionsNeeded { return .ready }
        if current.start == today { return .new }
        if daysAtCurrent >= WeightSteps.stalledAfterDays {
            let cut = today.adding(days: -WeightSteps.stalledWindowDays, calendar: calendar)
            let recent = judged.filter { $0.day > cut }.map(\.total).max()
            let earlier = judged.filter { $0.day <= cut }.map(\.total).max()
            if let recent, let earlier, recent <= earlier { return .stalled }
        }
        return .building(clean: cleanStreak)
    }

    /// The mean length of the steps before the current one, in days.
    public var usualDays: Int? {
        let past = steps.dropLast()
        guard !past.isEmpty else { return nil }
        return Int((Double(past.map(days(in:)).reduce(0, +)) / Double(past.count)).rounded())
    }

    /// Each step's height on the chart: 0 for the lightest, one more for each heavier weight
    /// (or longer pause at the same weight). Going back down lands on the old level.
    public func level(of step: WeightStep) -> Int {
        var keys: [(Double, Int)] = []
        for s in steps where !keys.contains(where: { WeightSteps.same($0.0, s.weightKg) && $0.1 == s.pauseSeconds }) {
            keys.append((s.weightKg ?? 0, s.pauseSeconds))
        }
        keys.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        return keys.firstIndex { WeightSteps.same($0.0, step.weightKg) && $0.1 == step.pauseSeconds } ?? 0
    }

    public var levelCount: Int { Set(steps.map(level(of:))).count }

    /// "110", "BW", "+10", with " · 2 s" when the reps are paused.
    public func label(for step: WeightStep, unit: WeightUnit, short: Bool = false) -> String {
        let weight: String
        if let kg = step.weightKg, kg > 0 {
            let shown = unit.format(kg: kg)
            weight = tracking.usesWeight ? (short ? shown : "\(shown) \(unit.label)") : (short ? "+\(shown)" : "BW + \(shown) \(unit.label)")
        } else {
            weight = short ? "BW" : "Bodyweight"
        }
        return step.pauseSeconds > 0 ? "\(weight) · \(step.pauseSeconds) s\(short ? "" : " pause")" : weight
    }
}

/// Lengths of time on the weight-steps chart.
public enum SpanFormat {
    /// 33 -> "4 wk 5 d", 28 -> "4 wk", 5 -> "5 d", 0 -> "today".
    public static func exact(days: Int) -> String {
        if days <= 0 { return "today" }
        let weeks = days / 7, rest = days % 7
        if weeks == 0 { return "\(rest) d" }
        return rest == 0 ? "\(weeks) wk" : "\(weeks) wk \(rest) d"
    }

    /// To the nearest half week: 21 -> "3 wk", 24 -> "3½ wk", 4 -> "4 d".
    public static func rough(days: Int) -> String {
        if days < 7 { return days <= 0 ? "1 d" : "\(days) d" }
        let halves = Int((Double(days) / 3.5).rounded())
        return "\(halves / 2)\(halves % 2 == 1 ? "½" : "") wk"
    }
}

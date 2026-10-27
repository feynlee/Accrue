import Foundation

/// What Siri and Shortcuts say about the user's training: the plan, what was done, progress
/// and the week. Every answer is built from the user's own data, in plain sentences that read
/// well aloud and in a Shortcuts result.
public struct Assistant: Sendable {
    public let catalog: Catalog
    public let data: AccrueData
    public let unit: WeightUnit
    public let today: DayKey
    public let calendar: Calendar
    public let locale: Locale

    public init(catalog: Catalog, data: AccrueData, unit: WeightUnit, today: DayKey = .today(),
                calendar: Calendar = .current, locale: Locale = .current) {
        self.catalog = catalog
        self.data = data
        self.unit = unit
        self.today = today
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: Plan

    /// "Today's plan is Pull: cable pulldown 3 × 10 (last time 100 × 10 × 3), seated row 3 × 10."
    public func plan(on day: DayKey) -> String {
        let parts = data.parts(on: day, calendar: calendar)
        let when = dayName(day)
        guard !parts.isEmpty else { return "\(when.capitalizedFirst) is a rest day. Nothing is planned." }
        let lines = parts.map { describe($0, on: day) }
        let verb = day < today ? "was" : "is"
        return "\(when.capitalizedFirst)'s plan \(verb) " + Self.list(lines) + "."
    }

    func describe(_ part: DayPart, on day: DayKey) -> String {
        let title = data.title(of: part, catalog: catalog)
        switch part.content {
        case .timed(let id):
            let timed = data.timedExercise(id)
            let minutes = timed.map { max(1, Int((Double($0.totalSeconds()) / 60).rounded())) }
            return title + (minutes.map { ", about \($0) minutes" } ?? "")
        case .exercise(let item):
            return target(item, on: day, named: title)
        case .preset:
            let items = data.items(in: part).map { target($0, on: day, named: name(of: $0.exerciseID).lowercased()) }
            return items.isEmpty ? title : "\(title): " + items.joined(separator: "; ")
        }
    }

    /// "bench press 3 × 8 (last time 155 × 8 × 3)", "run, 30 minutes in zone 2".
    func target(_ item: PlannedExercise, on day: DayKey, named name: String) -> String {
        let tracking = self.tracking(of: item.exerciseID)
        var text: String
        switch tracking {
        case .weightReps, .reps:
            text = "\(name) \(item.sets) × \(item.reps ?? 10)"
        case .hold, .weightHold:
            text = "\(name) \(item.sets) × \(item.holdSeconds ?? 30) seconds"
        case .weightDistance:
            text = "\(name) \(item.sets) sets"
        case .time, .timeHR, .distanceTimeHR:
            text = name
            if let minutes = item.minutes { text += ", \(minutes) minutes" }
            if let zone = item.targetZone { text += " in zone \(zone)" }
        }
        if tracking.isSetBased, let last = history(of: item.exerciseID).lastTime(before: day) {
            text += " (last time \(last.line(unit: unit, tracking: tracking)))"
        }
        return text
    }

    // MARK: What was done

    /// "Yesterday you did bench press 155 × 8 × 3 and a run, 30:00 · 5.0 km. 6 working sets, 3,720 lb lifted."
    public func log(on day: DayKey) -> String {
        let when = dayName(day)
        let sets = data.sets(on: day).sorted { $0.loggedAt < $1.loggedAt }
        var order: [String] = []
        for set in sets where !order.contains(set.exerciseID) { order.append(set.exerciseID) }
        let done: [String] = order.compactMap { id in
            let tracking = self.tracking(of: id)
            let summary = DaySummary(day: day, sets: sets.filter { $0.exerciseID == id }, tracking: tracking)
            guard summary.workingSets > 0 else { return nil }
            return "\(name(of: id).lowercased()) \(summary.line(unit: unit, tracking: tracking))"
        }
        guard !done.isEmpty else { return "Nothing is logged \(when == "today" || when == "yesterday" ? when : "on \(when)")." }
        let totals = data.totals(on: day, catalog: catalog)
        var text = "\(when.capitalizedFirst) you did " + Self.list(done) + "."
        if totals.hasStrength {
            text += " \(totals.workingSets) working \(totals.workingSets == 1 ? "set" : "sets")"
            text += totals.volumeKg > 0 ? ", \(weight(totals.volumeKg)) lifted." : "."
        }
        return text
    }

    /// The most recent day with anything logged, up to today.
    public var lastTrainingDay: DayKey? {
        data.sets.map(\.day).filter { $0 <= today }.max()
    }

    public func lastWorkout() -> String {
        guard let day = lastTrainingDay else { return "Nothing is logged yet." }
        return log(on: day)
    }

    // MARK: Progress

    /// "Bench press: last time, Monday, Oct 20, 155 × 8 × 3. Estimated max 196 lb, up 4% from 4 weeks ago. Best 200 lb on Sep 2."
    public func progress(of exerciseID: String) -> String {
        let history = history(of: exerciseID)
        let tracking = history.tracking
        let name = self.name(of: exerciseID)
        guard let last = history.days.last(where: { $0.day <= today }) else { return "\(name) isn't logged yet." }
        var text = "\(name): last time, \(dayName(last.day)), \(last.line(unit: unit, tracking: tracking))."
        if let value = last.strength {
            text += " \(strengthLabel(tracking).capitalizedFirst) \(format(value, tracking))"
            if let change = history.strengthChange(on: today, calendar: calendar) {
                let percent = Int(change.rounded())
                text += percent == 0 ? ", the same as 4 weeks ago."
                    : ", \(percent > 0 ? "up" : "down") \(abs(percent))% from 4 weeks ago."
            } else {
                text += "."
            }
        }
        if let best = personalBestDay(history), best.day != last.day, let value = best.strength {
            text += " Best \(format(value, tracking)), \(dayName(best.day))."
        }
        return text
    }

    /// "Your best bench press: estimated max 200 lb, Tuesday, Sep 2 (185 × 5 × 3)."
    public func personalBest(of exerciseID: String) -> String {
        let history = history(of: exerciseID)
        let name = self.name(of: exerciseID).lowercased()
        guard let best = personalBestDay(history), let value = best.strength else {
            return "There's no \(name) logged yet."
        }
        return "Your best \(name): \(strengthLabel(history.tracking)) \(format(value, history.tracking)), "
            + "\(dayName(best.day)) (\(best.line(unit: unit, tracking: history.tracking)))."
    }

    func personalBestDay(_ history: ExerciseHistory) -> DaySummary? {
        history.days.filter { $0.day <= today && $0.strength != nil }.max { ($0.strength ?? 0) < ($1.strength ?? 0) }
    }

    func strengthLabel(_ tracking: Tracking) -> String {
        switch tracking {
        case .weightReps: "estimated max"
        case .reps: "best set"
        case .hold, .weightHold: "longest hold"
        case .weightDistance: "top weight"
        case .time, .timeHR, .distanceTimeHR: "longest session"
        }
    }

    func format(_ strength: Double, _ tracking: Tracking) -> String {
        switch tracking {
        case .weightReps, .weightDistance: "\(unit.format(kg: strength)) \(unit.label)"
        case .reps: "\(Int(strength)) reps"
        case .hold, .weightHold, .time, .timeHR, .distanceTimeHR: DurationFormat.clock(strength)
        }
    }

    // MARK: Week

    /// "This week: 3 workouts (Mon, Tue, Thu), 42 working sets, 18,400 lb lifted, and 65 minutes of cardio over 9.2 km. 2 planned days are left: Fri and Sat."
    public func week(of day: DayKey) -> String {
        let start = day.startOfWeek(calendar: calendar)
        let days = (0..<7).map { start.adding(days: $0, calendar: calendar) }
        let thisWeek = days.contains(today)
        let label = thisWeek ? "This week" : "The week of \(dayName(start))"
        let totals = days.map { data.totals(on: $0, catalog: catalog) }
        let trained = days.indices.filter { !totals[$0].isEmpty }
        guard !trained.isEmpty else {
            return "\(label): nothing logged yet." + plannedLeft(days)
        }
        var parts = ["\(trained.count) \(trained.count == 1 ? "workout day" : "workout days") ("
            + trained.map { days[$0].weekday(calendar: calendar).short }.joined(separator: ", ") + ")"]
        let sets = totals.map(\.workingSets).reduce(0, +)
        let volume = totals.map(\.volumeKg).reduce(0, +)
        if sets > 0 { parts.append("\(sets) working sets") }
        if volume > 0 { parts.append("\(weight(volume)) lifted") }
        let seconds = totals.map(\.cardioSeconds).reduce(0, +)
        let meters = totals.map(\.cardioMeters).reduce(0, +)
        if seconds > 0 || meters > 0 {
            var cardio = "\(Int((Double(seconds) / 60).rounded())) minutes of cardio"
            if meters > 0 { cardio += " over \(unit.formatDistance(meters: meters)) \(unit.distanceLabel)" }
            parts.append(cardio)
        }
        return "\(label): " + Self.list(parts) + "." + (thisWeek ? plannedLeft(days) : "")
    }

    /// " 2 planned days are left: Fri and Sat."
    func plannedLeft(_ days: [DayKey]) -> String {
        let left = days.filter { $0 >= today && !data.parts(on: $0, calendar: calendar).isEmpty && data.sets(on: $0).isEmpty }
        guard !left.isEmpty else { return "" }
        let names = left.map { $0 == today ? "today" : $0.weekday(calendar: calendar).short }
        return " \(left.count) planned \(left.count == 1 ? "day is" : "days are") left: " + Self.list(names) + "."
    }

    // MARK: During a workout

    /// What to do next in the workout that is recording, or today's first part to start.
    public func nextUp() -> String {
        if let session = data.activeSession {
            let parts = data.parts(on: session.day, calendar: calendar)
            if let part = parts.first(where: { $0.id == session.partID }) {
                for item in data.items(in: part) {
                    let done = data.sets(of: item.exerciseID, on: session.day, partID: part.id).filter { !$0.isWarmup }.count
                    if done < item.sets {
                        let left = item.sets - done
                        return "Next is " + target(item, on: session.day, named: name(of: item.exerciseID).lowercased())
                            + ", \(left) \(left == 1 ? "set" : "sets") to go."
                    }
                }
                if let i = parts.firstIndex(where: { $0.id == part.id }), i + 1 < parts.count {
                    return "\(session.title) is done. Next is \(describe(parts[i + 1], on: session.day))."
                }
                return "\(session.title) is done. End the workout when you're ready."
            }
            return "\(session.title) is recording."
        }
        let parts = data.parts(on: today, calendar: calendar)
        let done = Set(data.sets(on: today).compactMap(\.partID))
        guard let next = parts.first(where: { !done.contains($0.id) }) else {
            return parts.isEmpty ? "Today is a rest day." : "Everything planned for today is done."
        }
        return "Next is \(describe(next, on: today))."
    }

    // MARK: Words

    func name(of exerciseID: String) -> String {
        catalog.exercise(exerciseID)?.displayName ?? "Exercise"
    }

    func tracking(of exerciseID: String) -> Tracking {
        catalog.exercise(exerciseID).map { catalog.tracking(for: $0) } ?? .weightReps
    }

    func history(of exerciseID: String) -> ExerciseHistory {
        ExerciseHistory(exerciseID: exerciseID, tracking: tracking(of: exerciseID), sets: data.history(of: exerciseID))
    }

    /// "3,720 lb"
    func weight(_ kg: Double) -> String {
        let value = Int(unit.fromKg(kg).rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " \(unit.label)"
    }

    /// "today", "yesterday", "tomorrow", or "Monday, Oct 20".
    public func dayName(_ day: DayKey) -> String {
        switch day {
        case today: return "today"
        case today.adding(days: -1, calendar: calendar): return "yesterday"
        case today.adding(days: 1, calendar: calendar): return "tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
            return formatter.string(from: day.date(calendar: calendar))
        }
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}

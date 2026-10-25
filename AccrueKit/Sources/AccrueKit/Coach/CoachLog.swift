import Foundation

/// Finds the exercise a person means and logs it: the coach's "log what I just did".
public struct CoachLog: Sendable {
    public let catalog: Catalog
    public let day: DayKey

    public init(catalog: Catalog, day: DayKey) {
        self.catalog = catalog
        self.day = day
    }

    private static let aliases: [String: String] = [
        "ohp": "military press", "rdl": "romanian deadlift", "rdls": "romanian deadlift", "db": "dumbbell",
        "bb": "barbell", "pullups": "pull up", "chinups": "chin up", "pushups": "push up", "situps": "sit up",
        "lat": "pulldown", "lats": "pulldown",
    ]

    /// The exercise for "pulls", "bench", "pull-ups": today's plan first (in its order), then
    /// favorites, then what was logged lately, then the whole catalog.
    public func exercise(named words: String, in data: AccrueData) -> Exercise? {
        let query = Self.words(words)
        guard !query.isEmpty else { return nil }
        var candidates: [String] = data.parts(on: day).flatMap { data.items(in: $0).map(\.exerciseID) }
        candidates += data.favorites
        candidates += data.sets.sorted { $0.loggedAt > $1.loggedAt }.prefix(300).map(\.exerciseID)
        var seen = Set<String>()
        for id in candidates where seen.insert(id).inserted {
            guard let exercise = catalog.exercise(id) else { continue }
            let name = Self.words(exercise.name)
            if query.allSatisfy({ q in name.contains { Self.matches(q, $0) } }) { return exercise }
        }
        return catalog.search(query.joined(separator: " ")).first
            ?? catalog.search(query.map(Self.stem).joined(separator: " ")).first
    }

    /// Logs it: one row per set, in the user's unit unless they said one. Sets on today's plan
    /// belong to that part (so the Train card counts them) and to the workout that is recording.
    public func log(_ entry: QuickLog, exercise: Exercise, unit: WeightUnit, into data: inout AccrueData,
                    at now: Date = Date()) -> [LoggedSet] {
        let part = data.parts(on: day).first { data.items(in: $0).contains { $0.exerciseID == exercise.id } }
        let session = data.activeSession.flatMap { $0.day == day ? $0 : nil }
        let tracking = catalog.tracking(for: exercise)
        let kg = entry.weight.map { (entry.unit ?? unit).toKg($0) }
        var logged: [LoggedSet] = []
        let count = tracking.isSetBased ? max(1, entry.sets ?? 1) : 1
        for n in 0..<count {
            var set = LoggedSet(day: day, exerciseID: exercise.id, partID: part?.id, sessionID: session?.id,
                                loggedAt: now.addingTimeInterval(Double(n)))
            switch tracking {
            case .weightReps, .reps, .weightDistance:
                set.weightKg = kg.flatMap { $0 > 0 ? $0 : nil }
                set.reps = entry.reps
            case .hold, .weightHold:
                set.weightKg = kg.flatMap { $0 > 0 ? $0 : nil }
                set.holdSeconds = entry.holdSeconds ?? entry.seconds ?? entry.reps
            case .time, .distanceTimeHR, .timeHR:
                set.distanceMeters = entry.meters
                set.durationSeconds = entry.seconds
            }
            data.log(set)
            logged.append(set)
        }
        return logged
    }

    /// "Logged: cable pulldown, 100 lb, 6 × 10."
    public func confirmation(_ sets: [LoggedSet], exercise: Exercise, unit: WeightUnit) -> String {
        guard let first = sets.first else { return "Nothing to log." }
        var parts = [exercise.displayName.lowercased()]
        if let kg = first.weightKg { parts.append("\(unit.format(kg: kg)) \(unit.label)") }
        if let reps = first.reps { parts.append(sets.count > 1 ? "\(sets.count) × \(reps)" : "\(reps) reps") }
        if let hold = first.holdSeconds { parts.append(sets.count > 1 ? "\(sets.count) × \(hold) s" : "\(hold) s") }
        if let meters = first.distanceMeters { parts.append(unit == .lb ? String(format: "%.2f mi", meters / 1609.344) : String(format: "%.2f km", meters / 1000)) }
        if let seconds = first.durationSeconds { parts.append(DurationFormat.clock(TimeInterval(seconds))) }
        return "Logged: " + parts.joined(separator: ", ") + "."
    }

    /// "Seated row is next at 90 lb." The next exercise in the same part, with last time's weight.
    public func nextUp(after exerciseID: String, in data: AccrueData, unit: WeightUnit) -> String? {
        for part in data.parts(on: day) {
            let items = data.items(in: part)
            guard let i = items.firstIndex(where: { $0.exerciseID == exerciseID }), i + 1 < items.count,
                  let next = catalog.exercise(items[i + 1].exerciseID) else { continue }
            let last = data.history(of: next.id).last { !$0.isWarmup && $0.day < day }
            if let kg = last?.weightKg ?? items[i + 1].weightKg {
                return "\(next.displayName) is next at \(unit.format(kg: kg)) \(unit.label)."
            }
            return "\(next.displayName) is next."
        }
        return nil
    }

    static func words(_ text: String) -> [String] {
        Catalog.normalize(text).split(separator: " ").flatMap { word -> [String] in
            let w = String(word)
            return aliases[w].map { $0.split(separator: " ").map(String.init) } ?? [w]
        }
    }

    static func stem(_ word: String) -> String {
        if word.hasSuffix("es"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 2 { return String(word.dropLast()) }
        return word
    }

    /// "pulls" matches "pulldown" and "pull"; "bench" matches "bench".
    static func matches(_ query: String, _ name: String) -> Bool {
        let q = stem(query)
        guard q.count >= 3 || q == name else { return false }
        return name.hasPrefix(q) || stem(name) == q
    }
}

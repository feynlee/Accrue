import Foundation

/// A workout told in plain words, read without any AI: "pulls 100, six by ten",
/// "3 sets of pull-ups, 8 each", "squat 185 x 5 x 3", "ran 5k in 28:30", "plank 45 sec".
/// The coach uses it to log straight away, offline, and hands anything else to the model.
public struct QuickLog: Equatable, Sendable {
    /// The words that name the exercise ("pulls", "pull ups").
    public var name: String
    public var weight: Double?
    public var unit: WeightUnit?
    public var reps: Int?
    public var sets: Int?
    public var holdSeconds: Int?
    public var meters: Double?
    public var seconds: Int?

    public init(name: String, weight: Double? = nil, unit: WeightUnit? = nil, reps: Int? = nil, sets: Int? = nil,
                holdSeconds: Int? = nil, meters: Double? = nil, seconds: Int? = nil) {
        self.name = name
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.sets = sets
        self.holdSeconds = holdSeconds
        self.meters = meters
        self.seconds = seconds
    }

    private enum Token: Equatable {
        case number(Double)
        case clock(Int)
        case word(String)
    }

    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100,
    ]
    private static let pounds: Set<String> = ["lb", "lbs", "pound", "pounds"]
    private static let kilos: Set<String> = ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"]
    private static let times: Set<String> = ["x", "by", "times"]
    private static let filler: Set<String> = Set<String>([
        "i", "did", "just", "done", "finished", "of", "set", "sets", "rep", "reps", "each", "for", "at", "with", "and",
        "in", "on", "the", "my", "a", "an", "log", "logged", "please", "then", "today", "went", "ran", "jogged", "walked",
        "minutes", "minute", "min", "mins", "seconds", "second", "sec", "secs", "s", "k", "km", "mi", "mile", "miles",
        "m", "meters", "metres", "x", "by", "times", "bodyweight", "bw",
    ]).union(pounds).union(kilos)

    /// nil when the text names no exercise or has no numbers: that is a question for the model.
    public static func parse(_ text: String) -> QuickLog? {
        let tokens = tokenize(text)
        guard tokens.contains(where: { if case .word = $0 { false } else { true } }) else { return nil }
        var log = QuickLog(name: "")
        var used = Set<Int>()
        var loose: [Double] = []
        var pair: (Double, Double)?
        var triple: (Double, Double, Double)?
        var nameWords: [String] = []

        func word(_ i: Int) -> String? {
            guard i < tokens.count, case .word(let w) = tokens[i] else { return nil }
            return w
        }
        func number(_ i: Int) -> Double? {
            guard i < tokens.count, case .number(let n) = tokens[i] else { return nil }
            return n
        }

        if let w = word(0), ["ran", "run", "jogged"].contains(w) { nameWords.append("run") }
        if let w = word(0), ["walked", "walk"].contains(w) { nameWords.append("walk") }

        var i = 0
        while i < tokens.count {
            defer { i += 1 }
            guard !used.contains(i) else { continue }
            switch tokens[i] {
            case .clock(let seconds):
                log.seconds = seconds
            case .word(let w):
                if !filler.contains(w), Double(w) == nil { nameWords.append(w) }
            case .number(let n):
                let next = word(i + 1)
                if let next, pounds.contains(next) { log.weight = n; log.unit = .lb; used.insert(i + 1) }
                else if let next, kilos.contains(next) { log.weight = n; log.unit = .kg; used.insert(i + 1) }
                else if let next, times.contains(next), let b = number(i + 2) {
                    used.formUnion([i + 1, i + 2])
                    if let x = word(i + 3), times.contains(x), let c = number(i + 4) {
                        triple = (n, b, c)
                        used.formUnion([i + 3, i + 4])
                    } else {
                        pair = (n, b)
                    }
                }
                else if next == "sets" || next == "set" { log.sets = Int(n); used.insert(i + 1) }
                else if next == "reps" || next == "rep" || next == "each" { log.reps = Int(n); used.insert(i + 1) }
                else if let next, ["min", "mins", "minute", "minutes"].contains(next) { log.seconds = Int(n * 60); used.insert(i + 1) }
                else if let next, ["s", "sec", "secs", "second", "seconds"].contains(next) { log.holdSeconds = Int(n); used.insert(i + 1) }
                else if let next, ["k", "km"].contains(next) { log.meters = n * 1000; used.insert(i + 1) }
                else if let next, ["mi", "mile", "miles"].contains(next) { log.meters = n * 1609.344; used.insert(i + 1) }
                else if let next, ["m", "meters", "metres"].contains(next) { log.meters = n; used.insert(i + 1) }
                else if word(i - 1) == "for", log.weight != nil || !loose.isEmpty { log.reps = Int(n) }
                else { loose.append(n) }
            }
        }

        if let (w, r, s) = triple {
            log.weight = log.weight ?? w
            log.reps = Int(r)
            log.sets = Int(s)
        }
        if log.weight == nil, let first = loose.first, pair != nil || log.reps != nil || loose.count > 1 {
            log.weight = first
            loose.removeFirst()
        }
        if let (a, b) = pair {
            if log.weight == nil, a > 30 {
                // "100x10": weight by reps.
                log.weight = a
                log.reps = Int(b)
            } else {
                log.sets = log.sets ?? Int(a)
                log.reps = Int(b)
            }
        }
        if let n = loose.first {
            if log.reps == nil, n <= 30, log.holdSeconds == nil { log.reps = Int(n) } else if log.weight == nil { log.weight = n }
        }
        // "the pull-ups were done at bodyweight": weight 0 means no added weight.
        if text.lowercased().contains("bodyweight") { log.weight = log.weight ?? 0 }

        log.name = nameWords.joined(separator: " ")
        guard !log.name.isEmpty,
              log.reps != nil || log.holdSeconds != nil || log.meters != nil || log.seconds != nil else { return nil }
        return log
    }

    private static func tokenize(_ text: String) -> [Token] {
        var spaced = ""
        let lower = text.lowercased().replacingOccurrences(of: "×", with: " x ")
        var previous: Character = " "
        for c in lower {
            // "100x10" → "100 x 10", "5k" → "5 k", "185lb" → "185 lb".
            if c.isLetter && previous.isNumber || c.isNumber && previous.isLetter { spaced.append(" ") }
            spaced.append(c.isLetter || c.isNumber || c == ":" || c == "." ? c : " ")
            previous = c
        }
        var tokens: [Token] = []
        for raw in spaced.split(separator: " ") {
            let part = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if part.isEmpty { continue }
            if part.contains(":") {
                let bits = part.split(separator: ":").compactMap { Int($0) }
                if bits.count == 2 { tokens.append(.clock(bits[0] * 60 + bits[1])) }
                else if bits.count == 3 { tokens.append(.clock(bits[0] * 3600 + bits[1] * 60 + bits[2])) }
                continue
            }
            if let n = Double(part) { tokens.append(.number(n)) }
            else if let n = numberWords[part] { tokens.append(.number(n)) }
            else { tokens.append(.word(part.replacingOccurrences(of: ".", with: ""))) }
        }
        return tokens
    }
}

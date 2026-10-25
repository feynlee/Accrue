import Foundation

/// One sourced statement the coach may give as training or health information.
public struct Guideline: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var topic: String
    public var tags: [String]
    public var text: String
    public var source: String
}

/// What the coach knows besides the catalog's how-to notes: short guideline statements, each
/// paraphrasing a published source (WHO, ACSM, meta-analyses). The coach answers training and
/// health questions from these and names the source, instead of from a model's memory.
public struct CoachKnowledge: Sendable {
    public let guidelines: [Guideline]

    struct File: Codable {
        var facts: [Guideline]
    }

    public init(guidelines: [Guideline]) {
        self.guidelines = guidelines
    }

    public init(data: Data) throws {
        guidelines = try JSONDecoder().decode(File.self, from: data).facts
    }

    /// The guidelines bundled with AccrueKit.
    public static func bundled() throws -> CoachKnowledge {
        guard let url = Bundle.module.url(forResource: "coach-guidelines", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try CoachKnowledge(data: Data(contentsOf: url))
    }

    public static let empty = CoachKnowledge(guidelines: [])

    /// Tags that say little alone ("how much", "week"): they help rank but can't pick a topic.
    private static let weakTags: Set<String> = [
        "how much", "how many", "how long", "how often", "week", "weekly", "before", "after", "start", "when",
        "some", "health", "muscle", "minutes", "days", "safe", "age", "maximum", "hold", "hard", "easy",
    ]

    /// The guidelines a question is about, best first: at most `limit`, and only ones that
    /// score close to the best.
    public func guidelines(for question: String, limit: Int = 2) -> [Guideline] {
        let words = CoachLog.words(question).map(CoachLog.stem)
        let phrase = " " + words.joined(separator: " ") + " "
        var scored: [(score: Double, index: Int)] = []
        for (index, fact) in guidelines.enumerated() {
            var score = 0.0
            for tag in fact.tags {
                let tagWords = CoachLog.words(tag).map(CoachLog.stem)
                guard !tagWords.isEmpty else { continue }
                let hit = tagWords.count == 1
                    ? words.contains(tagWords[0])
                    : phrase.contains(" " + tagWords.joined(separator: " ") + " ")
                guard hit else { continue }
                score += Self.weakTags.contains(tag) ? 0.5 : Double(tagWords.count)
            }
            if score >= 1 { scored.append((score, index)) }
        }
        scored.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        guard let best = scored.first?.score else { return [] }
        return scored.prefix(limit).filter { $0.score >= best * 0.75 }.map { guidelines[$0.index] }
    }

    /// The reply for guideline facts: the statements, then where they come from.
    public static func answer(_ facts: [Guideline]) -> String {
        facts.map(\.text).joined(separator: "\n\n")
    }
}

// MARK: Form questions

/// "How do I squat?", "bench press form", "posture on rows": answered from the exercise's
/// how-to notes, which come from the catalog's sourced families.
public struct FormAnswer: Sendable, Equatable {
    public var exerciseID: String
    public var text: String
}

extension CoachLog {
    private static let formSignals = [
        "how do i", "how to", "how should i", "how can i", "form", "posture", "technique", "cue", "cues",
        "properly", "correctly", "right way", "tips", "safely", "position",
    ]

    private static let questionWords: Set<String> = [
        "how", "do", "does", "i", "should", "can", "my", "the", "a", "an", "to", "for", "on", "in", "with", "of",
        "form", "posture", "technique", "correct", "correctly", "proper", "properly", "what", "is", "are", "doing",
        "keep", "cue", "cues", "tip", "tips", "right", "way", "good", "safe", "safely", "when", "during", "me",
        "you", "it", "get", "better", "improve", "fix", "check", "perform", "look", "like", "position", "best",
        "please", "tell", "about", "give", "any",
    ]

    /// The form answer when the text asks how to do an exercise the catalog has notes for.
    public func formAnswer(to question: String, in data: AccrueData) -> FormAnswer? {
        let lower = " " + Catalog.normalize(question) + " "
        guard Self.formSignals.contains(where: { lower.contains(" \($0) ") }) else { return nil }
        let rest = Self.words(question).filter { !Self.questionWords.contains($0) }
        guard !rest.isEmpty, let exercise = exercise(named: rest.joined(separator: " "), in: data),
              Self.names(exercise, closely: rest),
              let family = catalog.family(for: exercise) else { return nil }
        return FormAnswer(exerciseID: exercise.id, text: Self.formText(exercise.displayName, family: family))
    }

    /// Every asked word is a word of the name, give or take a plural ("squats", "pullup"), so
    /// "sleep" doesn't find "sleepers stretch".
    static func names(_ exercise: Exercise, closely asked: [String]) -> Bool {
        let name = words(exercise.name)
        let pairs = zip(name, name.dropFirst()).map { stem($0 + $1) }
        return asked.allSatisfy { q in
            pairs.contains(stem(q)) || name.contains { n in
                stem(n) == stem(q) || (n.hasPrefix(q) && n.count - q.count <= 2)
            }
        }
    }

    static func formText(_ name: String, family: Family) -> String {
        var lines = ["\(name), the short version:"]
        if let setup = family.setup.first { lines.append("• Set up: \(setup)") }
        for cue in family.cues.prefix(3) { lines.append("• \(cue.cue)") }
        if !family.breathing.isEmpty { lines.append("• Breathing: \(family.breathing)") }
        if let mistake = family.mistakes.first { lines.append("• Watch for \(mistake.name.lowercased()): \(mistake.fix)") }
        if let safety = family.safety.first { lines.append("• \(safety)") }
        lines.append("Open How to for the step-by-step demo.")
        return lines.joined(separator: "\n")
    }
}

// MARK: Safety

/// Words that mean the coach must not give training advice and should send the person to a
/// professional. Checked before anything else the coach does.
public struct SafetyCheck: Sendable, Equatable {
    public enum Level: Sendable, Equatable {
        /// Possible heart or breathing problem: stop now, get urgent help if it's severe.
        case stopNow
        /// Pain that isn't ordinary soreness, or an injury: stop that move, see a doctor or physio.
        case injury
        /// A condition, pregnancy or medicine: their doctor decides what is safe.
        case medical
        /// Doses of medicine, supplements or drugs: a doctor or pharmacist.
        case dose
    }

    public var level: Level
    public var reply: String

    private static let signals: [(Level, [String])] = [
        (.stopNow, ["chest pain", "pain in my chest", "chest hurts", "chest tight", "tight chest", "chest pressure",
                    "faint", "fainted", "fainting", "passed out", "blacked out", "black out", "dizzy", "dizziness",
                    "lightheaded", "light headed", "short of breath", "shortness of breath", "can t breathe",
                    "cant breathe", "cannot breathe", "palpitation", "palpitations", "heart racing",
                    "irregular heartbeat", "heart skipping", "arm pain", "jaw pain"]),
        (.injury, ["sharp pain", "shooting pain", "stabbing pain", "numb", "numbness", "tingling", "pins and needles",
                   "swollen", "swelling", "injury", "injured", "injure", "torn", "tear", "sprain", "sprained",
                   "fracture", "dislocated", "hurt my", "pulled a muscle", "pulled my", "herniated", "slipped disc",
                   "sciatica", "concussion", "after surgery", "surgery", "operation", "physio"]),
        (.dose, ["dose", "dosage", "how much creatine", "steroid", "steroids", "sarms", "testosterone",
                 "peptide", "medication dose", "how many mg", "mg of"]),
        (.medical, ["pregnant", "pregnancy", "heart condition", "heart disease", "heart attack", "high blood pressure",
                    "hypertension", "low blood pressure", "diabetes", "diabetic", "insulin", "asthma", "epilepsy",
                    "seizure", "medication", "medications", "blood thinner", "kidney", "osteoporosis",
                    "eating disorder", "postpartum", "cancer", "had a stroke", "arrhythmia"]),
    ]

    public static func check(_ text: String) -> SafetyCheck? {
        let lower = " " + Catalog.normalize(text) + " "
        for (level, phrases) in signals where phrases.contains(where: { lower.contains(" \($0) ") }) {
            return SafetyCheck(level: level, reply: reply(for: level))
        }
        return nil
    }

    static func reply(for level: Level) -> String {
        switch level {
        case .stopNow:
            "Please stop exercising now. Chest pain or pressure, fainting, dizziness, a racing or irregular heartbeat or unusual breathlessness can be signs of a heart problem. If it is severe or doesn't ease within a few minutes of rest, call emergency services. Even if it passes, see a doctor before you train again."
        case .injury:
            "Stop the move that causes it. Sharp or shooting pain, numbness, tingling or swelling are not normal training soreness, and I can't tell what's wrong from here. A doctor or physiotherapist can, and can say what's safe to load. Once you're cleared, I can plan around it."
        case .dose:
            "I can't advise on doses of medicine, supplements, or drugs. A doctor or pharmacist can tell you what is safe for you."
        case .medical:
            "That depends on your health, so your doctor should say what's safe for you. Once they have, I can help you plan training that fits."
        }
    }
}

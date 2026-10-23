import Foundation

/// The exercise catalog the app ships: 104 families, every openGym exercise mapped to one,
/// and Accrue's own cardio sessions. Immutable after loading.
public struct Catalog: Sendable {
    public let families: [String: Family]
    public let exercises: [Exercise]
    public let muscles: [String: MuscleGroup]
    public let props: [String: Prop]
    private let byID: [String: Int]
    private let searchKeys: [String]
    private let membersByFamily: [String: [Int]]

    struct File: Codable {
        var version: Int
        var families: [Family]
        var exercises: [Exercise]
        var muscles: [String: MuscleGroup]
        var props: [String: Prop]
    }

    public init(families: [Family], exercises: [Exercise],
                muscles: [String: MuscleGroup] = [:], props: [String: Prop] = [:]) {
        self.families = Dictionary(families.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.exercises = exercises
        self.muscles = muscles
        self.props = props
        self.byID = Dictionary(exercises.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.searchKeys = exercises.map { Catalog.normalize($0.name) }
        var members: [String: [Int]] = [:]
        for (index, exercise) in exercises.enumerated() where !exercise.hidden {
            if let family = exercise.familyID { members[family, default: []].append(index) }
        }
        self.membersByFamily = members
    }

    /// Decodes a catalog file in the format `Catalog/tools/build-app-catalog.py` writes.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(families: file.families, exercises: file.exercises, muscles: file.muscles, props: file.props)
    }

    /// The catalog bundled with AccrueKit. Decoding takes a moment, so call it off the main actor.
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try Catalog(data: Data(contentsOf: url))
    }

    public static let empty = Catalog(families: [], exercises: [])

    // MARK: Lookup

    public func exercise(_ id: String) -> Exercise? {
        byID[id].map { exercises[$0] }
    }

    public func family(for exercise: Exercise) -> Family? {
        exercise.familyID.flatMap { families[$0] }
    }

    public func subtype(for exercise: Exercise) -> Subtype? {
        guard let family = family(for: exercise) else { return nil }
        if let id = exercise.subtypeID, let sub = family.subtypes.first(where: { $0.id == id }) {
            return sub
        }
        return family.subtype(matching: exercise.name)
    }

    /// How sets of this exercise are logged: its own setting, its subtype's, or its family's.
    public func tracking(for exercise: Exercise) -> Tracking {
        if let t = exercise.tracking { return t }
        if let t = subtype(for: exercise)?.tracking { return t }
        if let family = family(for: exercise) {
            // A loaded version of a bodyweight move ("weighted pull-up") is logged with weight.
            if family.tracking == .reps, exercise.equipment == "weighted" || exercise.name.contains("weighted") {
                return .weightReps
            }
            if family.tracking == .hold, exercise.name.contains("weighted") {
                return .weightHold
            }
            return family.tracking
        }
        return .reps
    }

    public func muscles(for exercise: Exercise) -> MuscleSet {
        subtype(for: exercise)?.muscles ?? family(for: exercise)?.muscles ?? MuscleSet()
    }

    public func muscleLabel(_ id: String) -> String {
        muscles[id]?.label ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// The body region of the exercise's first primary muscle ("back", "chest"...), for grouping favorites.
    public func region(for exercise: Exercise) -> String {
        if exercise.isSession || family(for: exercise)?.kind == .cardio { return "cardio" }
        return muscles(for: exercise).primary.first.flatMap { muscles[$0]?.region } ?? "other"
    }

    public func members(of familyID: String) -> [Exercise] {
        (membersByFamily[familyID] ?? []).map { exercises[$0] }
    }

    // MARK: Search

    /// Exercises whose names contain every word of the query, best match first:
    /// whole-name matches, then names that start with the query, then shorter names.
    public func search(_ query: String, limit: Int = 60) -> [Exercise] {
        let words = Catalog.normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var hits: [(score: Int, index: Int)] = []
        for (index, key) in searchKeys.enumerated() where !exercises[index].hidden {
            // "pullup" finds "pull-up": each word may also match the name without spaces.
            let compact = key.replacingOccurrences(of: " ", with: "")
            guard words.allSatisfy({ key.contains($0) || compact.contains($0) }) else { continue }
            var score = key.count
            if key == phrase { score -= 1000 }
            else if key.hasPrefix(phrase) { score -= 500 }
            else if key.contains(phrase) { score -= 200 }
            if exercises[index].isSession { score -= 50 }
            hits.append((score, index))
        }
        hits.sort { $0.score == $1.score ? $0.index < $1.index : $0.score < $1.score }
        return hits.prefix(limit).map { exercises[$0.index] }
    }

    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}

public enum CatalogError: Error {
    case missingResource
}

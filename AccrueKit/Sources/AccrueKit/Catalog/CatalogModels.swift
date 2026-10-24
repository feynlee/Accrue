import Foundation

/// How an exercise is logged. Matches `tracking` in the family files.
public enum Tracking: String, Codable, Sendable, CaseIterable {
    case weightReps = "weight_reps"
    case reps
    case hold
    case weightHold = "weight_hold"
    case weightDistance = "weight_distance"
    case time
    case distanceTimeHR = "distance_time_hr"
    case timeHR = "time_hr"

    /// Logged per set with steppers on the Train card.
    public var isSetBased: Bool {
        switch self {
        case .weightReps, .reps, .hold, .weightHold, .weightDistance: true
        case .time, .distanceTimeHR, .timeHR: false
        }
    }

    public var usesWeight: Bool {
        switch self {
        case .weightReps, .weightHold, .weightDistance: true
        default: false
        }
    }

    public var usesHold: Bool {
        self == .hold || self == .weightHold
    }
}

/// The kind of a family: strength, cardio, stretch and so on.
public struct FamilyKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let strength = FamilyKind(rawValue: "strength")
    public static let bodyweight = FamilyKind(rawValue: "bodyweight")
    public static let power = FamilyKind(rawValue: "power")
    public static let cardio = FamilyKind(rawValue: "cardio")
    public static let core = FamilyKind(rawValue: "core")
    public static let mobility = FamilyKind(rawValue: "mobility")
    public static let stretch = FamilyKind(rawValue: "stretch")
    public static let balance = FamilyKind(rawValue: "balance")
    public static let rehab = FamilyKind(rawValue: "rehab")
    public static let skill = FamilyKind(rawValue: "skill")
    public static let sport = FamilyKind(rawValue: "sport")

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MuscleSet: Codable, Hashable, Sendable {
    public var primary: [String]
    public var secondary: [String]

    public init(primary: [String] = [], secondary: [String] = []) {
        self.primary = primary
        self.secondary = secondary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try c.decodeIfPresent([String].self, forKey: .primary) ?? []
        secondary = try c.decodeIfPresent([String].self, forKey: .secondary) ?? []
    }
}

public struct Step: Codable, Hashable, Sendable {
    public var phase: String
    public var text: String
}

public struct Cue: Codable, Hashable, Sendable {
    public var joint: String
    public var cue: String
    public var why: String
    public var refs: [String]?
}

public struct Tempo: Codable, Hashable, Sendable {
    public var down: Double?
    public var pause: Double?
    public var up: Double?
    public var hold: Double?
    public var note: String?
}

/// Shoulder blade position in a key pose.
public struct Scapula: Codable, Hashable, Sendable {
    public var protraction: Double?
    public var elevation: Double?
    public var upRot: Double?
}

/// Joint angles in degrees, by the names in Catalog/families/README.md.
public struct JointPose: Codable, Hashable, Sendable {
    public var angles: [String: Double]
    public var scapula: Scapula?

    public init(angles: [String: Double] = [:], scapula: Scapula? = nil) {
        self.angles = angles
        self.scapula = scapula
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        var angles: [String: Double] = [:]
        for key in c.allKeys where key.stringValue != "scapula" {
            if let value = try? c.decode(Double.self, forKey: key) {
                angles[key.stringValue] = value
            }
        }
        self.angles = angles
        scapula = try c.decodeIfPresent(Scapula.self, forKey: AnyKey("scapula"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in angles { try c.encode(value, forKey: AnyKey(key)) }
        try c.encodeIfPresent(scapula, forKey: AnyKey("scapula"))
    }
}

public struct Keyframe: Codable, Hashable, Sendable {
    public var t: Double
    public var phase: String?
    public var pose: JointPose

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        t = try c.decode(Double.self, forKey: AnyKey("t"))
        phase = try c.decodeIfPresent(String.self, forKey: AnyKey("phase"))
        var pose = try JointPose(from: decoder)
        pose.angles["t"] = nil
        self.pose = pose
    }

    public func encode(to encoder: Encoder) throws {
        try pose.encode(to: encoder)
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(t, forKey: AnyKey("t"))
        try c.encodeIfPresent(phase, forKey: AnyKey("phase"))
    }
}

public struct Detect: Codable, Hashable, Sendable {
    public var metric: String
    public var bad: String
}

public struct Mistake: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var looks: String
    public var fix: String
    public var why: String
    public var pose: JointPose?
    public var detect: Detect?
}

public struct Variant: Codable, Hashable, Sendable {
    public var when: String
    public var change: String
    public var met: Double?
}

public struct Subtype: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Case-insensitive regular expression on the exercise name.
    public var match: String
    public var change: String
    public var muscles: MuscleSet?
    public var tracking: Tracking?
    public var healthKit: String?
    public var met: Double?
    public var loop: String?
    public var seconds: Double?
    public var keyframes: [Keyframe]?
}

public struct MotionMetric: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var good: String
}

public struct Motion: Codable, Hashable, Sendable {
    /// rep, cycle, hold or flow.
    public var loop: String
    public var seconds: Double
    public var views: [String]
    public var keyframes: [Keyframe]
    public var contacts: [String]
    public var metrics: [MotionMetric]
    public var basis: String
}

/// One movement family: shared how-to, cues, mistakes and animation for its member exercises.
public struct Family: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: FamilyKind
    /// "anatomy" shows muscles; "skin" shows only the body outline.
    public var bodyModel: String
    public var tracking: Tracking
    public var healthKit: String?
    public var pattern: String
    public var muscles: MuscleSet
    public var equipment: [String]
    public var setup: [String]
    public var steps: [Step]
    public var cues: [Cue]
    public var breathing: String
    public var tempo: Tempo?
    public var mistakes: [Mistake]
    public var safety: [String]
    public var variants: [Variant]
    public var subtypes: [Subtype]
    public var easier: [String]
    public var harder: [String]
    public var met: Double?
    public var motion: Motion
    public var confidence: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(FamilyKind.self, forKey: .kind)
        bodyModel = try c.decode(String.self, forKey: .bodyModel)
        tracking = try c.decode(Tracking.self, forKey: .tracking)
        healthKit = try c.decodeIfPresent(String.self, forKey: .healthKit)
        pattern = try c.decode(String.self, forKey: .pattern)
        muscles = try c.decode(MuscleSet.self, forKey: .muscles)
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        setup = try c.decodeIfPresent([String].self, forKey: .setup) ?? []
        steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
        cues = try c.decodeIfPresent([Cue].self, forKey: .cues) ?? []
        breathing = try c.decodeIfPresent(String.self, forKey: .breathing) ?? ""
        tempo = try c.decodeIfPresent(Tempo.self, forKey: .tempo)
        mistakes = try c.decodeIfPresent([Mistake].self, forKey: .mistakes) ?? []
        safety = try c.decodeIfPresent([String].self, forKey: .safety) ?? []
        variants = try c.decodeIfPresent([Variant].self, forKey: .variants) ?? []
        subtypes = try c.decodeIfPresent([Subtype].self, forKey: .subtypes) ?? []
        easier = try c.decodeIfPresent([String].self, forKey: .easier) ?? []
        harder = try c.decodeIfPresent([String].self, forKey: .harder) ?? []
        met = try c.decodeIfPresent(Double.self, forKey: .met)
        motion = try c.decode(Motion.self, forKey: .motion)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence) ?? "low"
    }

    /// The first subtype whose pattern matches the exercise name, as the family files define.
    public func subtype(matching name: String) -> Subtype? {
        subtypes.first { sub in
            guard let regex = try? NSRegularExpression(pattern: sub.match, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
    }
}

/// One exercise the user can pick: an openGym entry, or one of Accrue's own cardio sessions (`s:` ids).
public struct Exercise: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// openGym names are lower case; use `displayName` on screen.
    public var name: String
    public var familyID: String?
    public var subtypeID: String?
    public var equipment: String?
    public var mods: [String: String]?
    /// Camera-angle or version duplicates; kept so old logs resolve, left out of search.
    public var hidden: Bool
    public var tracking: Tracking?
    public var healthKit: String?
    public var group: String?
    /// "outdoor" or "indoor" for Accrue's cardio sessions, so Apple Watch starts the right
    /// workout and outdoor ones measure distance with GPS.
    public var location: String?

    enum CodingKeys: String, CodingKey {
        case id, name, family, subtype, equipment, mods, hidden, tracking, healthKit, group, location
    }

    public init(id: String, name: String, familyID: String?, subtypeID: String? = nil,
                equipment: String? = nil, tracking: Tracking? = nil, location: String? = nil) {
        self.id = id
        self.name = name
        self.familyID = familyID
        self.subtypeID = subtypeID
        self.equipment = equipment
        self.mods = nil
        self.hidden = false
        self.tracking = tracking
        self.healthKit = nil
        self.group = nil
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        familyID = try c.decodeIfPresent(String.self, forKey: .family)
        subtypeID = try c.decodeIfPresent(String.self, forKey: .subtype)
        equipment = try c.decodeIfPresent(String.self, forKey: .equipment)
        mods = try c.decodeIfPresent([String: String].self, forKey: .mods)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        tracking = try c.decodeIfPresent(Tracking.self, forKey: .tracking)
        healthKit = try c.decodeIfPresent(String.self, forKey: .healthKit)
        group = try c.decodeIfPresent(String.self, forKey: .group)
        location = try c.decodeIfPresent(String.self, forKey: .location)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(familyID, forKey: .family)
        try c.encodeIfPresent(subtypeID, forKey: .subtype)
        try c.encodeIfPresent(equipment, forKey: .equipment)
        try c.encodeIfPresent(mods, forKey: .mods)
        if hidden { try c.encode(hidden, forKey: .hidden) }
        try c.encodeIfPresent(tracking, forKey: .tracking)
        try c.encodeIfPresent(healthKit, forKey: .healthKit)
        try c.encodeIfPresent(group, forKey: .group)
        try c.encodeIfPresent(location, forKey: .location)
    }

    /// "barbell bench press" -> "Barbell bench press".
    public var displayName: String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    public var isSession: Bool { id.hasPrefix("s:") }
    public var isOutdoor: Bool { location == "outdoor" }
}

public struct MuscleGroup: Codable, Hashable, Sendable {
    public var label: String
    public var region: String
}

public struct Prop: Codable, Hashable, Sendable {
    public var label: String
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

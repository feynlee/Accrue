import Foundation

/// One screen of the step-by-step how-to.
public struct HowToStep: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case setup, phase, mistakes }

    public var id: Int
    public var kind: Kind
    /// "SET UP", "LOWER", "CHECK YOUR FORM".
    public var kicker: String
    public var title: String
    public var body: String
    public var breath: String?
    public var cues: [Cue]
    public var mistakes: [Mistake]
    /// The part of the loop the demo plays on this step; a single point holds that pose.
    public var window: ClosedRange<Double>
}

/// Everything the how-to shows for one exercise: its family's steps with the subtype's motion.
public struct HowToGuide: Hashable, Sendable {
    public var name: String
    /// The exercise's catalog id.
    public var exerciseID: String = ""
    /// The exercise's catalog name in lower case ("cable bar lateral pulldown"), its own
    /// equipment, its family, subtype and the family's camera views ("side", "front", ...).
    public var exerciseName: String = ""
    public var equipment: String?
    public var familyID: String = ""
    public var subtypeID: String?
    public var familyEquipment: [String] = []
    public var views: [String] = []
    public var keyframes: [Keyframe]
    public var seconds: Double
    public var loop: String
    public var contacts: [String]
    public var muscles: MuscleSet
    /// "anatomy" or "skin" (cardio and general moves show no muscles).
    public var bodyModel: String
    public var steps: [HowToStep]

    /// The family motion's middle keyframe, where most mistakes show.
    public var faultT: Double {
        keyframes.isEmpty ? 0 : keyframes[keyframes.count / 2].t
    }
}

extension Catalog {
    public func howTo(for exercise: Exercise) -> HowToGuide? {
        guard let family = family(for: exercise) else { return nil }
        let sub = subtype(for: exercise)
        let keys = (sub?.keyframes ?? family.motion.keyframes).sorted { $0.t < $1.t }
        return HowToGuide(
            name: exercise.displayName,
            exerciseID: exercise.id,
            exerciseName: exercise.name.lowercased(),
            equipment: exercise.equipment,
            familyID: family.id,
            subtypeID: sub?.id,
            familyEquipment: family.equipment,
            views: family.motion.views,
            keyframes: keys,
            seconds: sub?.seconds ?? family.motion.seconds,
            loop: sub?.loop ?? family.motion.loop,
            contacts: Self.contacts(family.motion.contacts, family: family.id, name: exercise.name.lowercased()),
            muscles: muscles(for: exercise),
            bodyModel: family.bodyModel,
            steps: HowToGuide.steps(for: family, subtype: sub, keyframes: keys))
    }
}

extension Catalog {
    /// A bridge or floor version of a bench move lies on the floor, not the bench. A hip thrust
    /// keeps its shoulders on the bench, so only the feet touch the floor.
    static func contacts(_ contacts: [String], family: String, name: String) -> [String] {
        // A bridge rests on the shoulders and feet, with the hips up.
        if name.contains("bridge"), contacts.contains("hips") {
            return contacts.map { $0 == "hips" ? "feet" : $0 }
        }
        guard contacts.contains("bench") else { return contacts }
        if !name.contains("bench"), name.contains("bridge") || name.contains("floor") {
            return contacts.filter { $0 != "bench" }
        }
        if family == "hip-thrust-bridge" { return contacts.filter { $0 != "back" } }
        return contacts
    }
}

extension HowToGuide {
    static func steps(for family: Family, subtype: Subtype? = nil, keyframes keys: [Keyframe]) -> [HowToStep] {
        let setup = subtype?.setup ?? family.setup
        let phaseSteps = subtype?.steps ?? family.steps
        let cues = subtype?.cues ?? family.cues
        let start: ClosedRange<Double> = (keys.first?.t ?? 0)...(keys.first?.t ?? 0)
        // A step plays from the named keyframe before its own up to its own; keyframes without
        // a name only shape the movement in between.
        let phases = phaseSteps.map { step -> ClosedRange<Double> in
            guard let i = keys.firstIndex(where: { $0.phase?.lowercased() == step.phase.lowercased() }) else { return 0...1 }
            guard i > 0 else { return keys[0].t...keys[0].t }
            let before = keys[..<i].last { $0.phase != nil } ?? keys[i - 1]
            return before.t...keys[i].t
        }

        // Each cue goes with the step it talks about most; the rest stay with the set-up.
        var cuesFor = Array(repeating: [Cue](), count: phaseSteps.count + 1)
        for cue in cues {
            let words = Self.words(cue.joint + " " + cue.cue)
            let scores = phaseSteps.map { Self.words($0.phase + " " + $0.text).intersection(words).count }
            if let best = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[best] > 0 {
                cuesFor[best + 1].append(cue)
            } else {
                cuesFor[0].append(cue)
            }
        }

        var steps: [HowToStep] = []
        if !setup.isEmpty {
            steps.append(HowToStep(id: 0, kind: .setup, kicker: "SET UP", title: "Get in position",
                                   body: setup.joined(separator: " "),
                                   breath: "Breathe normally while you set up.",
                                   cues: cuesFor[0], mistakes: [], window: start))
        }
        for (i, step) in phaseSteps.enumerated() {
            steps.append(HowToStep(id: steps.count, kind: .phase, kicker: step.phase.uppercased(), title: step.phase,
                                   body: step.text, breath: family.breathing.isEmpty ? nil : family.breathing,
                                   cues: cuesFor[i + 1] + (setup.isEmpty && i == 0 ? cuesFor[0] : []),
                                   mistakes: [], window: phases[i]))
        }
        if !family.mistakes.isEmpty {
            let t = keys.isEmpty ? 0 : keys[keys.count / 2].t
            steps.append(HowToStep(id: steps.count, kind: .mistakes, kicker: "CHECK YOUR FORM", title: "Common mistakes",
                                   body: "If any of these happen, make it easier or lighter and redo the set.",
                                   breath: nil, cues: [], mistakes: family.mistakes, window: t...t))
        }
        return steps
    }

    /// Lower-case words of four letters or more, for matching cues to steps.
    static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["your", "with", "from", "that", "this", "then", "they", "them", "than",
                                 "into", "onto", "over", "keep", "about", "each", "while", "until", "when"]
        let parts = text.lowercased().split { !$0.isLetter }.map(String.init)
        return Set(parts.filter { $0.count >= 4 && !stop.contains($0) }.map { word in
            // "elbows" and "elbow" should match.
            word.hasSuffix("s") ? String(word.dropLast()) : String(word)
        })
    }
}

import Foundation

// MARK: - One arm at a time, and holds

/// An exercise of an upright family whose name says the arms do not work together: one arm
/// only ("one arm", "single arm", "unilateral"), the arms in turn ("alternate"), or no rep at
/// all ("hold", "isometric"). The family's keyframes move both arms as one, so the picture
/// underneath is drawn as it would be anyway (sat on its bench, a weight in each hand) from a
/// pose in which each arm is given its own angles:
/// - one arm: the working arm follows the keyframes and holds the weight; the other hangs at
///   the side with nothing in it;
/// - in turn: the right arm does a whole rep in the first half of the loop while the left waits
///   where the rep starts, then the left does one;
/// - a hold: the body stays at the working position, moving only a breath.
struct FreeWeightArmsStaging: LoopStaging {
    typealias V = Body3D.V

    enum Turn: Sendable, Equatable {
        /// Only the arm on this side works.
        case one(String)
        case inTurn
        case hold
    }

    /// What draws the picture underneath: a later group's staging (a seat, the floor), or the
    /// plain equipment.
    enum Under: Sendable {
        case staged(any BodyStaging)
        case plain(PropPlan)
    }

    /// The angles that pose one arm. The left arm's own are these with an "L" after them.
    static let armKeys = ["shoulderFlex", "shoulderAbd", "shoulderRot", "elbowFlex", "forearm", "wristExt"]
    /// An arm with nothing to do: hanging at the side, a little out and a little bent, palm in.
    static let hanging = JointPose(angles: ["shoulderAbd": 6, "elbowFlex": 10])
    /// How far either side of the working position a hold drifts, as a part of the loop.
    static let breath = 0.006
    /// Families whose keyframes stand upright and move only the arms.
    static let families: Set<String> = ["biceps-curl", "front-raise", "lateral-raise", "overhead-press", "triceps-extension",
                                        "shrug", "upright-row"]
    /// Each hand has a weight of its own.
    static let handWeights: Set<String> = ["dumbbell", "kettlebell", "weighted"]
    /// Words for versions done lying, bent over or with the arm on a pad, where an arm left to
    /// hang at the side would be wrong. Kneeling versions stay as the posture group stages them.
    static let elsewhere: Set<String> = ["lying", "prone", "supine", "incline", "decline", "side", "bent", "leaning", "lean",
                                         "support", "supported", "preacher", "spider", "concentration", "kickback", "renegade",
                                         "plank", "over", "blaster", "landmine", "handstand", "cross", "raised", "z", "kneeling"]
    static let lyingSubtypes: Set<String> = ["preacher", "concentration", "prone", "chest-supported", "lying", "side-lying",
                                             "kickback", "incline", "landmine", "handstand", "inverted"]

    let turn: Turn
    let under: Under
    let keys: [Keyframe]
    /// The arms where a rep starts, and the part of the loop where the working position is.
    let start: JointPose
    let peak: Double
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard Self.families.contains(guide.familyID), let turn = Self.turn(for: guide), !guide.keyframes.isEmpty else { return nil }
        // The plain triceps extension's keyframes push down in front of the body, as on a
        // cable: with a dumbbell that is another movement, whichever arm does it.
        if guide.familyID == "triceps-extension", guide.subtypeID == nil { return nil }
        let keys = guide.keyframes
        // The trunk stays up, and the keyframes do not already give the arms different work.
        let own = Set(Self.armKeys.map { $0 + "L" })
        guard keys.allSatisfy({ abs($0.pose.angles["trunk"] ?? 0) <= 30 && own.isDisjoint(with: $0.pose.angles.keys) }) else { return nil }
        self.turn = turn
        self.keys = keys
        start = Figure.smooth(keys, at: 0)
        // A raise is held at its top. A curl is held half way: the moment of the way up when
        // the forearms are level.
        var peak = guide.faultT
        if guide.familyID == "biceps-curl" {
            let way = (0...40).map { peak * Double($0) / 40 }
            func tilt(_ t: Double) -> Double {
                let a = Figure.smooth(keys, at: t).angles
                return abs((a["elbowFlex"] ?? 0) + (a["shoulderFlex"] ?? 0) - 90)
            }
            peak = way.min { tilt($0) < tilt($1) } ?? peak
        }
        self.peak = peak

        let later: [(HowToGuide, Body3D) -> (any BodyStaging)?] = [FloorStagings.make, CardioStagings.make, PostureStagings.make]
        if let staging = later.lazy.compactMap({ $0(guide, body) }).first {
            under = .staged(staging)
            kinds = staging.kinds
            fixed = staging.fixed
        } else {
            let plan = PropPlan(guide: guide, body: body, plain: true)
            // Arms that take turns need a weight in each hand.
            if turn != .hold { guard let hands = plan.hands, hands.each, hands.bar == nil else { return nil } }
            under = .plain(plan)
            kinds = plan.kinds
            fixed = plan.fixed
        }
    }

    /// What the name says about the arms, for the exercises this staging can draw.
    static func turn(for guide: HowToGuide) -> Turn? {
        let name = guide.exerciseName
        let words = LegLoad.words(guide)
        func has(_ phrases: String...) -> Bool { phrases.contains { name.contains($0) } }
        if has("hold", "isometric") && !has("one arm", "single arm", "unilateral") {
            // A hold is drawn whatever is held, where it stands or sits.
            return words.isDisjoint(with: elsewhere) && !lyingSubtypes.contains(guide.subtypeID ?? "") ? .hold : nil
        }
        guard let equipment = guide.equipment, handWeights.contains(equipment),
              words.isDisjoint(with: elsewhere), !lyingSubtypes.contains(guide.subtypeID ?? "") else { return nil }
        if has("one arm", "single arm", "one hand", "single hand", "unilateral") { return .one(words.contains("left") ? "l" : "r") }
        if has("alternate", "alternating") { return .inTurn }
        return nil
    }

    // MARK: Poses

    private static func angle(_ pose: JointPose, _ key: String, _ side: String) -> Double {
        pose.angles[key + side] ?? pose.angles[key] ?? 0
    }

    /// `pose` with the right arm as it is in `right` and the left arm as it is in `left`.
    static func posed(_ pose: JointPose, right: JointPose, left: JointPose) -> JointPose {
        var p = pose
        // Each shoulder blade turns as far as its own arm is raised, not as the keyframes
        // turn both.
        p.scapula?.upRot = nil
        for key in armKeys {
            p.angles[key] = angle(right, key, "")
            p.angles[key + "L"] = angle(left, key, "L")
        }
        return p
    }

    /// What a mistake adds to the clean pose at `t`: nothing when `pose` is the clean one.
    private func mistake(_ pose: JointPose, at t: Double) -> JointPose? {
        let clean = Figure.smooth(keys, at: t)
        var extra = JointPose()
        for (key, value) in pose.angles where abs(value - (clean.angles[key] ?? 0)) > 1e-9 {
            extra.angles[key] = value - (clean.angles[key] ?? 0)
        }
        func less(_ a: Double?, _ b: Double?) -> Double? {
            guard let a, abs(a - (b ?? 0)) > 1e-9 else { return nil }
            return a - (b ?? 0)
        }
        let blade = Scapula(protraction: less(pose.scapula?.protraction, clean.scapula?.protraction),
                            elevation: less(pose.scapula?.elevation, clean.scapula?.elevation),
                            upRot: less(pose.scapula?.upRot, clean.scapula?.upRot))
        if blade.protraction != nil || blade.elevation != nil || blade.upRot != nil { extra.scapula = blade }
        return extra.angles.isEmpty && extra.scapula == nil ? nil : extra
    }

    /// The pose to draw at `t`, each arm with its own angles, and the side with nothing in its
    /// hand.
    func arms(_ pose: JointPose, at t: Double?) -> (pose: JointPose, empty: String?, at: Double, extra: JointPose?) {
        switch turn {
        case .one(let side):
            let p = side == "r" ? Self.posed(pose, right: pose, left: Self.hanging) : Self.posed(pose, right: Self.hanging, left: pose)
            return (p, side == "r" ? "l" : "r", t ?? 0, nil)
        case .inTurn:
            // A mistake is shown where the how-to shows it, in the right arm.
            guard let t, mistake(pose, at: t) == nil else { return (Self.posed(pose, right: pose, left: start), nil, t ?? 0, nil) }
            let part = t < 0.5 ? t * 2 : t * 2 - 1
            let work = Figure.smooth(keys, at: part)
            return (t < 0.5 ? Self.posed(work, right: work, left: start) : Self.posed(work, right: start, left: work), nil, part, nil)
        case .hold:
            let now = peak + Self.breath * sin(2 * .pi * (t ?? 0))
            var p = Figure.smooth(keys, at: now)
            let extra = t.flatMap { mistake(pose, at: $0) }
            if let extra { p = Figure.applying(extra, to: p) }
            return (p, nil, now, extra)
        }
    }

    // MARK: Frames

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) { drawn(arms(pose, at: nil)) }

    func frame(_ pose: JointPose, at t: Double) -> (body: BodyFrame, props: [PropPiece]) { drawn(arms(pose, at: t)) }

    private func drawn(_ made: (pose: JointPose, empty: String?, at: Double, extra: JointPose?)) -> (body: BodyFrame, props: [PropPiece]) {
        switch under {
        case .staged(let staging):
            let (frame, props) = staging.frame(made.pose, in: made.at)
            guard let empty = made.empty else { return (frame, props) }
            // The weight the other staging drew in the empty hand is left out: every piece
            // nearer that hand than the working one.
            func hand(_ s: String) -> V? { (frame.heads["f3a.\(s)"] ?? frame.heads["hand.\(s)"]).map { V($0) } }
            guard let idle = hand(empty), let working = hand(empty == "r" ? "l" : "r") else { return (frame, props) }
            return (frame, props.filter { piece in
                let c = V(piece.center)
                return (c - idle).length > 0.3 || (c - working).length <= (c - idle).length
            })
        case .plain(let plan):
            guard let hands = plan.hands else {
                // Nothing in the hands: the plain body as it is at that moment.
                let (frame, props) = plan.frame(at: made.at, fault: made.extra)
                return (frame, Array(props.dropFirst(plan.fixed.count)))
            }
            var (frame, held) = hands.frame(made.pose, at: made.at)
            if let empty = made.empty { held.grips[empty] = nil }
            return (frame, plan.moving(frame, held))
        }
    }
}

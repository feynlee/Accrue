import Foundation

/// A body face down over the floor on straight arms: the high plank and its shoulder taps, the
/// bear plank, the bird dog, the mountain climber and the cat and cow stretches. The palms lie flat under the shoulders
/// and stay where they are, the shoulders are held an arm's length above them, and the feet
/// (or the knees) the body rests on never slide. A hand or a leg leaves the floor only when
/// the keyframes lift it.
struct FloorProneStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    enum Kind: Sendable, Equatable {
        /// One line from head to heels, on the toes or on the knees. With `taps`, each hand in
        /// turn comes up to the other shoulder.
        case plank(onKnees: Bool, taps: Bool)
        /// On hands and toes with the knees bent under the hips, just off the floor.
        case bear
        /// On hands and knees: the right arm reaches forward as the left leg reaches back.
        case birdDog
        /// A high plank with the knees driven to the chest in turn.
        case climber
        /// On hands and knees, held there while the back rounds or hollows.
        case allFours
    }

    /// How far the wrists are in front of the shoulders, how far a hovering knee is off the
    /// floor, and how far the skin of a resting knee presses into it.
    static let ahead = 0.03, hover = 0.13, sink = 0.004
    /// How high a climber's hips are carried.
    static let hips = 0.5
    /// The leg a bird dog rests on.
    static let support = ["femur.r", "shin.r"]

    let body: Body3D
    let kind: Kind
    let line: ProneLine
    let hands: [String: HandPress]
    /// The pose the loop starts from: what is more or less than it is a mistake.
    let first: JointPose
    /// How high the shoulders are held, and the arm's length from shoulder to wrist.
    let height, reach: Double
    /// Where the middle knuckle of each hand rests, and its wrist then.
    private(set) var spots: [String: V] = [:]
    private(set) var wrists: [String: V] = [:]
    /// How far the foot of a kneeling leg is pointed so its top lies on the floor (degrees),
    /// and how low the skin of a planted toe sits.
    let pointed: Double
    private(set) var toeLow = 0.0
    /// How far a climber's hips are bent to carry them that high (degrees).
    private(set) var pike = 0.0
    /// How high the mat lifts the body, when the pose is done on one.
    let lift: Double
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D, _ kind: Kind, mat: Bool = false) {
        guard let r = body.flatHand("r", spread: 1.5), let l = body.flatHand("l", spread: 1.5),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.kind = kind
        self.first = first
        hands = ["r": r, "l": l]
        lift = mat ? FloorRestStaging.matTop : 0
        kinds = mat ? [.mat] : []
        var onKnees = false
        if case .plank(true, _) = kind { onKnees = true }
        line = ProneLine(body: body, onKnees: onKnees)
        let wrist = body.pressWrist(r, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
        let reach = body.armSpan("r", bend: 7)
        self.reach = reach
        height = wrist.z + (reach * reach - Self.ahead * Self.ahead).squareRoot()

        // The top of a kneeling foot comes down onto the floor behind the shin.
        var kneeling = JointPose(angles: ["trunk": 90, "hipFlex": 90, "kneeFlex": 91])
        let shinLow = body.floorLow(["shin.r"], body.rotations(kneeling), body.heads(body.rotations(kneeling)))
        pointed = floorCross(40...90) { d in
            kneeling.angles["ankleDorsi"] = -d
            let g = body.rotations(kneeling)
            return body.floorLow(["foot.r", "toes.r"], g, body.heads(g)) - shinLow
        }
        if kind == .climber {
            let found = floorCross(0...45) { over in
                (climberLine(first, over: over, shoulders: height).h["femur.r"]?.z ?? 0) - Self.hips
            }
            pike = found
        }
        let start = trunk(first, lean: 0)
        toeLow = min(0, body.floorLow(["toes.r", "toes.l"], start.g, start.h))
        var spots: [String: V] = [:]
        for s in ["r", "l"] {
            guard let hand = hands[s], let shoulder = start.h["humerus.\(s)"] else { return nil }
            let rest = body.pressWrist(hand, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
            spots[s] = V(shoulder.x - rest.x, shoulder.y - Self.ahead - rest.y, 0)
            wrists[s] = V(shoulder.x, shoulder.y - Self.ahead, rest.z)
        }
        self.spots = spots
        if mat {
            // Lengthways under the hands, knees and feet.
            let on = ["neck", "pelvis", "toes.r", "toes.l"].compactMap { start.h[$0] }
            let c = on.reduce(V(0, 0, 0), +) * (1 / Double(max(1, on.count)))
            fixed = [PropPlan.box(V(c.x, c.y, lift / 2), (0.66, 1.85, lift), x: V(1, 0, 0), .accent)]
        }
    }

    /// 0 to 1, easing in and out.
    static func ease(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    static func angle(_ pose: JointPose, _ key: String, _ s: String = "r") -> Double {
        (s == "l" ? pose.angles[key + "L"] : nil) ?? pose.angles[key] ?? 0
    }

    // MARK: The body before its arms

    /// The trunk and legs for `pose`, resting on the feet or the knees with the shoulders at
    /// arm's length above the floor. `lean` (degrees) is how far the arms slope back from the
    /// hands to the shoulders.
    func trunk(_ pose: JointPose, lean: Double) -> (g: [String: M], h: [String: V]) {
        let wrist = height - (reach * reach - Self.ahead * Self.ahead).squareRoot()
        var shoulders = wrist + (height - wrist) * cos(lean * .pi / 180)
        var out = rested(pose, shoulders: shoulders)
        guard lean == 0, let planted = wrists["r"] else { return out }
        // A mistake that carries the shoulders away from over the hands brings them down as
        // far as the straight arms then reach.
        for _ in 0..<3 {
            guard let shoulder = out.h["humerus.r"] else { break }
            let off = shoulder.y - planted.y
            let able = wrist + max(0.01, reach * reach - off * off).squareRoot()
            if able > shoulders - 0.0005 { break }
            shoulders = able
            out = rested(pose, shoulders: shoulders)
        }
        return out
    }

    private func rested(_ pose: JointPose, shoulders: Double) -> (g: [String: M], h: [String: V]) {
        switch kind {
        case .plank(let onKnees, let taps):
            var p = pose
            // Feet set a little apart, and left there while a hand is off the floor.
            let apart = taps ? 6.0 : 2.0
            p.angles["hipAbd"] = apart
            p.angles["hipAbdL"] = apart
            // The shoulders stay level whichever hand is up: the arms are fitted afterwards.
            for key in ["shoulderFlex", "shoulderAbd", "elbowFlex"] {
                p.angles[key] = first.angles[key]
                p.angles[key + "L"] = first.angles[key + "L"]
            }
            var out = line.place(p, shoulders: shoulders)
            if onKnees {
                // The knees rest on their skin, not in it.
                let lift = -Self.sink - body.floorLow(["femur.r", "femur.l", "shin.r", "shin.l"], out.g, out.h)
                if lift > 0 {
                    out = line.place(p, shoulders: shoulders - lift)
                    out.h = out.h.mapValues { $0 + V(0, 0, lift) }
                }
            }
            return out
        case .bear: return bear(pose, shoulders: shoulders)
        case .birdDog, .allFours: return birdDog(pose, shoulders: shoulders)
        case .climber: return climber(pose, shoulders: shoulders)
        }
    }

    /// Thighs upright under the hips, knees off the floor, toes tucked under as in a plank. Hips
    /// pushed up (a pike) straighten the legs and lift the knees.
    private func bear(_ pose: JointPose, shoulders: Double) -> (g: [String: M], h: [String: V]) {
        let over = Self.angle(pose, "hipFlex") - Self.angle(first, "hipFlex")
        let knee = Self.hover + 0.006 * max(0, over)
        // The foot stands on its toes, heel up; the shin slopes from the knee to the ankle.
        let foot = M.x(82), toes = M.x(ProneLine.toesTip)
        var ankle = 0.17, shin = 0.42
        if let a = body.head["foot.r"], let t = body.head["toes.r"], let k = body.head["shin.r"] {
            ankle = line.pivot.z + (foot * (a - t)).z
            shin = (a - k).length
        }
        let slope = asin(min(1, max(-1, (ankle - knee) / shin))) * 180 / .pi
        let lumbar = Self.angle(pose, "lumbar")

        func placed(_ rise: Double) -> (g: [String: M], h: [String: V]) {
            var p = pose
            p.angles["trunk"] = 90 - rise
            for side in ["", "L"] {
                p.angles["hipFlex" + side] = 90 - rise - lumbar / 2 + min(0, over)
                p.angles["kneeFlex" + side] = 90 + slope + min(0, over)
                p.angles["hipAbd" + side] = 3
            }
            var g = body.rotations(p)
            for s in ["r", "l"] {
                g["foot.\(s)"] = foot
                g["toes.\(s)"] = toes
            }
            var h = body.heads(g)
            if let a = h["toes.r"], let b = h["toes.l"] {
                let shift = line.pivot - (a + b) * 0.5
                for (k, v) in h { h[k] = v + shift }
            }
            return (g, h)
        }
        let rise = floorCross(-40...45) { (placed($0).h["humerus.r"]?.z ?? 0) - shoulders }
        return placed(rise)
    }

    /// On the right knee and shin, the thigh upright under the hip; the left leg lies the same
    /// way until the keyframes send it back.
    private func birdDog(_ pose: JointPose, shoulders: Double) -> (g: [String: M], h: [String: V]) {
        let lumbar = Self.angle(pose, "lumbar")
        // Held on all fours, the left leg kneels like the right whatever the pose does at the hips.
        let hip = kind == .allFours ? 90 : Self.angle(pose, "hipFlex", "l")
        let knee = kind == .allFours ? 90 : Self.angle(pose, "kneeFlex", "l")
        let back = min(1, max(0, 1 - hip / 90))
        let bent = kind == .allFours ? (r: kneeling(pose, "r"), l: kneeling(pose, "l")) : (r: 91, l: 91)

        func placed(_ rise: Double) -> (g: [String: M], h: [String: V]) {
            var p = pose
            let upright = 90 - rise - lumbar / 2
            p.angles["trunk"] = 90 - rise
            p.angles["hipFlex"] = upright
            p.angles["kneeFlex"] = bent.r
            p.angles["ankleDorsi"] = -pointed
            p.angles["hipFlexL"] = upright + hip - 90
            p.angles["kneeFlexL"] = knee * bent.l / 90
            p.angles["ankleDorsiL"] = -pointed + (pointed - 15) * back
            let g = body.rotations(p)
            var h = body.heads(g)
            if let low = body.floorLowest(Self.support, g, h), let at = h["shin.r"] {
                let shift = V(0, -at.y, -Self.sink - low.at.z)
                for (k, v) in h { h[k] = v + shift }
            }
            return (g, h)
        }
        let rise = floorCross(-20...45) { (placed($0).h["humerus.l"]?.z ?? 0) - shoulders }
        return placed(rise)
    }

    /// How far a kneeling knee is bent (degrees) so its shin lies level. A mistake that turns
    /// the thigh out or in under the hip would tip the shin and push the foot into the floor.
    private func kneeling(_ pose: JointPose, _ s: String) -> Double {
        guard let knee = body.head["shin.\(s)"], let ankle = body.head["foot.\(s)"] else { return 91 }
        let m = s == "r" ? 1.0 : -1.0
        let turn = M.y(m * Self.angle(pose, "hipAbd", s)) * M.z(-m * Self.angle(pose, "hipRot", s))
        let level = (M.x(91) * (ankle - knee)).z
        return floorCross(60...120) { ((turn * M.x($0)) * (ankle - knee)).z - level }
    }

    /// A climber's plank with the hips bent `over` degrees, both legs long.
    private func climberLine(_ pose: JointPose, over: Double, shoulders: Double) -> (pose: JointPose, g: [String: M], h: [String: V]) {
        var flat = pose
        for side in ["", "L"] {
            flat.angles["hipFlex" + side] = over
            flat.angles["kneeFlex" + side] = 0
        }
        let placed = line.place(flat, shoulders: shoulders)
        return (flat, placed.g, placed.h)
    }

    /// The plank the climber runs in, hips about level with the shoulders so a knee can pass
    /// under them, then each leg as the keyframes bend it. A knee coming in folds until its
    /// toes just touch down; the other leg stays long with its toes planted.
    private func climber(_ pose: JointPose, shoulders: Double) -> (g: [String: M], h: [String: V]) {
        // Both hips bent more than the run asks for is a pike.
        let run = Self.angle(first, "hipFlex") + Self.angle(first, "hipFlex", "l")
        let extra = max(0, (Self.angle(pose, "hipFlex") + Self.angle(pose, "hipFlex", "l") - run) / 2)
        var tuck: [String: Double] = [:]
        for s in ["r", "l"] { tuck[s] = Self.ease((Self.angle(pose, "hipFlex", s) - extra) / 90) }
        // With both feet in the air at the switch, the hips hop a little.
        let hop = 6 * Self.ease(2 * min(tuck["r"] ?? 0, tuck["l"] ?? 0))
        let base = climberLine(pose, over: pike + extra + hop, shoulders: shoulders)
        guard let pelvis = base.g["pelvis"], let root = base.h["pelvis"], let stood = body.rotations(base.pose)["pelvis"] else { return (base.g, base.h) }
        let turn = pelvis * stood.t

        var p = pose
        for (s, side) in [("r", ""), ("l", "L")] {
            let share = tuck[s] ?? 0
            p.angles["hipFlex" + side] = max(Self.angle(pose, "hipFlex", s), extra) + pike + hop
            p.angles["kneeFlex" + side] = max(0, Self.angle(pose, "kneeFlex", s))
            p.angles["ankleDorsi" + side] = -ProneLine.ankleOut + (Self.angle(pose, "ankleDorsi", s) + ProneLine.ankleOut) * share
        }
        func placed(_ p: JointPose) -> (g: [String: M], h: [String: V]) {
            var g = body.rotations(p).mapValues { turn * $0 }
            for s in ["r", "l"] {
                guard let toes = g["toes.\(s)"] else { continue }
                g["toes.\(s)"] = body.part(from: M.x(ProneLine.toesTip), to: toes, share: tuck[s] ?? 0)
            }
            return (g, body.place(g, root: root))
        }
        for (s, side) in [("r", ""), ("l", "L")] {
            guard let share = tuck[s], share > 0.01 else { continue }
            let near = Self.ease(share / 0.3)
            let knee = p.angles["kneeFlex" + side] ?? 0
            p.angles["kneeFlex" + side] = floorCross(knee...max(knee, 155)) { bent in
                var q = p
                q.angles["kneeFlex" + side] = bent
                let (g, h) = placed(q)
                return body.floorLow(["shin.\(s)", "foot.\(s)", "toes.\(s)"], g, h) - toeLow * (1 - near)
            }
        }
        return placed(p)
    }

    // MARK: Arms

    /// How far each hand is off the floor, 0 to 1, and where it is carried to.
    private func lifted(_ s: String, _ pose: JointPose, _ g: [String: M], _ h: [String: V])
        -> (share: Double, wrist: V, hand: M, pole: V, fingers: [String: M]?)? {
        let m = s == "r" ? 1.0 : -1.0
        switch kind {
        case .plank(_, true):
            // The palm comes up onto the front of the other shoulder.
            let o = s == "r" ? "l" : "r"
            guard let press = hands[s], let chest = g["thorax"], let shoulder = h["humerus.\(o)"] else { return nil }
            let share = Self.ease(Self.angle(pose, "elbowFlex", s) / 140)
            let at = shoulder + chest * V(-m * 0.015, -0.085, -0.02)
            let normal = chest * V(m * 0.3, -1, 0), fingers = chest * V(m, 0, 0.45)
            return (share, body.pressWrist(press, at: at, fingers: fingers, normal: normal),
                    body.pressTurn(press, fingers: fingers, normal: normal), V(-m * 0.5, 0.3, -1), nil)
        case .birdDog where s == "r":
            // The arm goes forward as the keyframes swing it, the hand open.
            guard let wrist = h["hand.r"], let hand = g["hand.r"] else { return nil }
            let start = Self.angle(first, "shoulderFlex")
            let share = Self.ease((Self.angle(pose, "shoulderFlex") - start) / max(1, 175 - start))
            var fingers: [String: M] = [:]
            for bone in hands[s]?.turns.keys.map({ $0 }) ?? [] { fingers[bone] = g[bone] }
            return (share, wrist, hand, V(-m * 0.6, 0, -1), fingers)
        default:
            return nil
        }
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        // Shoulders that drift back behind the hands (a climber's mistake) slope the arms.
        var lean = 0.0
        if kind == .climber { lean = min(40, max(0, Self.angle(pose, "shoulderFlex") - Self.angle(first, "shoulderFlex"))) }
        var (g, h) = trunk(pose, lean: lean)
        let root = h["pelvis"] ?? V(0, 0, 0)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let press = hands[s], var spot = spots[s] else { continue }
            if lean > 0, let shoulder = h["humerus.\(s)"] {
                let rest = body.pressWrist(press, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
                spot.y = shoulder.y - reach * sin(lean * .pi / 180) - rest.y
            }
            let down = body.pressWrist(press, at: spot, fingers: Body3D.forward, normal: Body3D.up)
            let flat = body.pressTurn(press, fingers: Body3D.forward, normal: Body3D.up)
            let pole = V(-m * 0.3, 1, 0.35)
            guard let up = lifted(s, pose, g, h), up.share > 0.001 else {
                body.arm(s, wrist: down, hand: flat, pole: pole, &g, h)
                for (bone, turn) in press.turns { g[bone] = flat * turn }
                continue
            }
            let f = up.share
            let hand = body.part(from: flat, to: up.hand, share: f)
            // The fingers stay open, or go from flat to however the keyframes hold them.
            var fingers: [String: M] = [:]
            for (bone, turn) in press.turns {
                if let free = up.fingers?[bone] {
                    fingers[bone] = hand * body.part(from: turn, to: up.hand.t * free, share: f)
                } else {
                    fingers[bone] = hand * turn
                }
            }
            body.arm(s, wrist: down + (up.wrist - down) * f, hand: hand, pole: pole * (1 - f) + up.pole * f, &g, h)
            for (bone, turn) in fingers { g[bone] = turn }
        }
        h = body.place(g, root: root + V(0, 0, lift))
        return (body.made(g, h, floor: 0), [])
    }
}

// MARK: - Reverse plank

/// A reverse plank: face up in one line on the heels and on straight arms, the palms flat
/// under the shoulders with the fingers toward the feet.
struct FloorReversePlankStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far the wrists are behind the shoulders, toward the head.
    static let behind = 0.03, sink = 0.004
    static let feet = ["shin.r", "shin.l", "foot.r", "foot.l", "toes.r", "toes.l"]

    let body: Body3D
    let hands: [String: HandPress]
    let first: JointPose
    let height, reach: Double
    private(set) var spots: [String: V] = [:]
    private(set) var wrists: [String: V] = [:]
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let r = body.flatHand("r", spread: 1.4), let l = body.flatHand("l", spread: 1.4),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.first = first
        hands = ["r": r, "l": l]
        let wrist = body.pressWrist(r, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
        let reach = body.armSpan("r", bend: 6)
        self.reach = reach
        height = wrist.z + (reach * reach - Self.behind * Self.behind).squareRoot()
        let start = trunk(first)
        var spots: [String: V] = [:]
        for s in ["r", "l"] {
            guard let hand = hands[s], let shoulder = start.h["humerus.\(s)"] else { return nil }
            let rest = body.pressWrist(hand, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
            spots[s] = V(shoulder.x - rest.x, shoulder.y + Self.behind - rest.y, 0)
            wrists[s] = V(shoulder.x, shoulder.y + Self.behind, rest.z)
        }
        self.spots = spots
    }

    /// The body turned about its heels until the shoulders are at arm's length above the floor.
    func trunk(_ pose: JointPose) -> (g: [String: M], h: [String: V]) {
        var p = pose
        // The family's mistakes are drawn for a body facing down. Facing up, hips that sag
        // bend the other way, and so do hips pushed too high.
        for key in ["hipFlex", "lumbar"] {
            let rest = first.angles[key] ?? 0
            p.angles[key] = rest - ((pose.angles[key] ?? 0) - rest)
        }
        let posed = body.rotations(p)
        let heads = body.heads(posed)
        func placed(_ rise: Double) -> (g: [String: M], h: [String: V]) {
            let turn = M.x(rise)
            let g = posed.mapValues { turn * $0 }
            var h = heads.mapValues { turn * $0 }
            if let low = body.floorLowest(Self.feet, g, h) {
                let shift = V(0, -low.at.y, -Self.sink - low.at.z)
                for (k, v) in h { h[k] = v + shift }
            }
            return (g, h)
        }
        func held(_ shoulders: Double) -> (g: [String: M], h: [String: V]) {
            placed(floorCross(-30...30) { (placed($0).h["humerus.r"]?.z ?? 0) - shoulders })
        }
        var shoulders = height
        var out = held(shoulders)
        guard let planted = wrists["r"] else { return out }
        // Hips that sag or rise carry the shoulders along the floor, and the straight arms
        // then hold them a little lower.
        let wrist = height - (reach * reach - Self.behind * Self.behind).squareRoot()
        for _ in 0..<3 {
            guard let shoulder = out.h["humerus.r"] else { break }
            let off = shoulder.y - planted.y
            let able = wrist + max(0.01, reach * reach - off * off).squareRoot()
            if able > shoulders - 0.0005 { break }
            shoulders = able
            out = held(shoulders)
        }
        return out
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h) = trunk(pose)
        let root = h["pelvis"] ?? V(0, 0, 0)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = hands[s], let spot = spots[s] else { continue }
            body.press(s, hand, at: spot, fingers: Body3D.forward, pole: V(-m * 0.15, 1, 0.2), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), [])
    }
}

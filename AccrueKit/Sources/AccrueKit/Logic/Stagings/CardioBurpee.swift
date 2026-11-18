import Foundation

/// A burpee: squat, hands to the floor, feet jumped back to a plank and in again, then a jump.
/// The feet stand on one spot for the squat and the jump. While the hands are down they lie
/// flat on the floor where the squat put them, and the plank is fitted between them and the
/// toes: the shoulders over the hands at arm's length, the feet on the floor behind.
///
/// The variations change how it ends: with no jump, with a jack in the air, with a jump that
/// travels (a long jump, sideways over a dumbbell, up onto a box), or with nothing but the
/// feet jumping in from the plank and back.
struct CardioBurpeeStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How a burpee ends after the feet come back in.
    enum Ending: Sendable {
        /// The keyframes' jump.
        case jump
        /// Standing up the way the body went down, with no jump.
        case stand
        /// No standing up at all: from the plank the feet jump in to the squat and back.
        case hands
    }

    static let sides: [(String, Double)] = [("r", 1.0), ("l", -1.0)]
    /// How long the hands take to reach the floor and to leave it, as a share of the loop.
    static let reach = 0.08
    /// How high a jump on the spot is, and how long before the "Jump" keyframe the feet leave the floor.
    static let height = 0.15, before = 0.03
    /// How far the legs swing out in the air of a jack burpee, in degrees.
    static let jack = 25.0
    /// How long after the "Jump" keyframe the feet come down: most of the way to the loop's end.
    var after: Double { (1 - jump) * 0.7 }
    /// How much deeper than the keyframes the knees and hips fold in the squat, in degrees,
    /// and how long the arms are from shoulder to wrist as a share of their full length.
    static let deeper = 25.0, long = 0.97
    /// How high the feet skim as they jump back and in.
    static let skim = 0.05

    let body: Body3D
    let loop: CardioLoop
    /// The moments of the first squat, the return to a squat, and the jump.
    let squat: Double, back: Double, jump: Double
    /// How far the hips are bent in the squat, in degrees.
    let deep: Double
    /// Where the balls of the feet stand for the squat and the jump.
    let spot: V
    let ending: Ending
    /// Whether the legs open and close in the air of the jump.
    let jacks: Bool
    /// How high the jump rises over a straight line to where it lands, and where that is: the
    /// spot it left, or further on, or the top of a box.
    private(set) var rise = Self.height
    private(set) var landing = V(0, 0, 0)
    /// The middle and the size of a box the jump lands on.
    private(set) var box: (centre: V, size: V)?
    let presses: [String: HandPress]
    /// Where each hand's middle knuckle lies on the floor.
    private(set) var hands: [String: V] = [:]
    /// How much further the squat's trunk leans for the hands to reach the floor, in degrees.
    private(set) var lean = 0.0
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "burpee" else { return nil }
        let words = CardioStagings.words(guide)
        var ending = Ending.jump, jacks = false
        /// What the jump does besides going up.
        enum Travel { case none, long, overDumbbell, ontoBox }
        var travel = Travel.none
        switch guide.subtypeID {
        case nil:
            if words == ["burpee"] {
            } else if words.isSubset(of: ["jack", "burpee", "v", "2"]), words.contains("jack") {
                jacks = true
            } else if words == ["squat", "thrust"] {
                // A burpee with no jump.
                ending = .stand
            } else if words == ["frogger"] || words == ["plank", "jump", "in", "squat"] {
                ending = .hands
            } else if words == ["burpee", "over", "the", "dumbbell"] {
                travel = .overDumbbell
            } else if words == ["burpee", "jump", "box"] {
                travel = .ontoBox
            } else {
                return nil
            }
        case "push-up":
            if words == ["burpee", "with", "push", "up"] {
            } else if words == ["jack", "burpee", "with", "push", "up"] {
                jacks = true
            } else if words == ["burpee", "long", "jump", "with", "push", "up"] {
                travel = .long
            } else {
                return nil
            }
        case "no-jump":
            guard words == ["burpee", "squat"] || words == ["silent", "burpee"] else { return nil }
            ending = .stand
        default: return nil
        }
        guard guide.equipment == nil || guide.equipment == "none" || (travel == .overDumbbell && guide.equipment == "dumbbell")
        else { return nil }
        guard let squat = guide.keyframes.first(where: { $0.phase == "Squat" }),
              let back = guide.keyframes.first(where: { $0.phase == "Return" })?.t,
              let jump = guide.keyframes.first(where: { $0.phase == "Jump" })?.t,
              squat.t > Self.reach, squat.t < back, back + Self.reach < jump - Self.before, jump < 1,
              let r = body.flatHand("r"), let l = body.flatHand("l"),
              let ball = body.head["toes.r"], let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        self.squat = squat.t
        self.back = back
        self.jump = jump
        self.ending = ending
        self.jacks = jacks
        kinds = travel == .overDumbbell ? [.dumbbell] : travel == .ontoBox ? [.box] : []
        deep = max(30, CardioStagings.angle(squat.pose, "hipFlex"))
        loop = CardioLoop(guide, steps: 384)
        spot = V(0, ball.y - pelvis.y, 0)
        presses = ["r": r, "l": l]

        landing = spot
        guard let spots = spots(nil) else { return nil }
        hands = spots.hands
        lean = spots.lean

        switch travel {
        case .none: break
        case .long:
            (landing, rise) = (spot + V(0, -0.9, 0), 0.25)
        case .overDumbbell:
            // The dumbbell lies beside the body, clear of the hand that goes down next to it.
            let side = (hands["l"]?.x ?? 0.2) + 0.22
            fixed = LegWeights.dumbbell(V(side, spot.y, 0.06), along: V(0, 1, 0))
            (landing, rise) = (spot + V(2 * side, 0, 0), 0.25)
        case .ontoBox:
            guard let tip = body.tail["toes.r"], let ankle = body.head["foot.r"] else { return nil }
            // The box stands beyond where the fingers reach on the floor.
            let top = CardioBoxJumpStaging.low, deep = CardioBoxJumpStaging.deep
            let face = (hands.values.map(\.y).min() ?? spot.y) - 0.2
            let centre = V(0, face - deep / 2, top / 2)
            box = (centre, V(CardioBoxJumpStaging.wide, deep, top))
            fixed = [Plan.box(centre, (CardioBoxJumpStaging.wide, deep, top), .wood)]
            // Lands with the feet in the middle of the top.
            let ahead = ball.y - tip.y, behind = ankle.y + 0.045 - ball.y
            landing = V(0, centre.y - (behind - ahead) / 2, top)
            rise = 0.2
            let faults: [JointPose?] = [nil] + loop.faults.map { Optional($0) }
            while rise < 0.8, !faults.allSatisfy(clears) { rise += 0.025 }
        }
    }

    /// The feet stay out of the box through the whole jump onto it.
    func clears(_ fault: JointPose?) -> Bool {
        guard let box else { return true }
        for i in 1..<32 {
            let t = jump - Self.before + (Self.before + after) * Double(i) / 32
            let placed = solve(at: t, fault: fault, hands: hands)
            let h = body.place(placed.g, root: placed.root)
            for (p, skin) in body.contactPoints("feet", placed.g, h) + body.contactPoints("toes", placed.g, h) {
                let d = p - box.centre
                guard abs(d.x) < box.size.x / 2 + 0.03, abs(d.y) < box.size.y / 2 + 0.04 else { continue }
                if p.z - skin < box.size.z - 0.001 { return false }
            }
        }
        return true
    }

    /// The moment of the keyframes that is shown at `t` of the loop.
    func clock(_ t: Double) -> Double {
        switch ending {
        case .jump: return t
        case .stand:
            // After the feet come in, the way down is run backward to standing.
            return t <= back ? t : squat * (1 - (t - back) / (1 - back))
        case .hands:
            // The stretch from squat to plank to squat as it is, and the rest of the loop
            // (the standing up, the jump and the going down) spent on the same again.
            if t >= squat, t <= back { return t }
            let share = (t > back ? t - back : t + 1 - back) / (1 - back + squat)
            return squat + (back - squat) * share
        }
    }

    /// Where each hand's middle knuckle goes down, under the shoulders of the squat, and how
    /// far the squat's trunk leans to get them there. A mistake changes the squat, and so both.
    func spots(_ fault: JointPose?) -> (hands: [String: V], lean: Double)? {
        let low = solve(at: squat, fault: fault, hands: nil)
        let h = body.place(low.g, root: low.root)
        var out: [String: V] = [:]
        for (s, _) in Self.sides {
            guard let shoulder = h["humerus.\(s)"], let press = presses[s] else { return nil }
            let fromKnuckle = body.pressWrist(press, at: V(0, 0, 0), fingers: V(0, -1, 0), normal: V(0, 0, 1))
            out[s] = V(shoulder.x, shoulder.y - fromKnuckle.y, 0)
        }
        return (out, low.tilt)
    }

    /// How far the body is laid out into the plank at `t`: 0 in the squat, 1 in the plank.
    func plank(at t: Double) -> Double {
        guard t > squat, t < back else { return 0 }
        let hip = CardioStagings.angle(Figure.smooth(loop.closed, at: t), "hipFlex")
        return CardioStagings.ease(1 - hip / deep, from: 0, to: 1)
    }

    /// How far the hands are down on the floor at `t`.
    func down(at t: Double) -> Double {
        t <= squat ? CardioStagings.ease(t, from: squat - Self.reach, to: squat) : 1 - CardioStagings.ease(t, from: back, to: back + Self.reach)
    }

    /// The jump at `t`: where the balls of the feet are over, how high the feet are above
    /// the floor, how high the surface they stand on is, how far into the air they are, and
    /// how far through the jump (0 before it and after).
    func hop(at t: Double) -> (ball: V, height: Double, floor: Double, air: Double, share: Double) {
        guard ending == .jump else { return (spot, 0, 0, 0, 0) }
        let u = (t - jump + Self.before) / (Self.before + after)
        if u <= 0 { return (spot, 0, 0, 0, 0) }
        if u >= 1 { return (landing, landing.z, landing.z, 0, 0) }
        // Onto a box the feet rise first and cross later, as in a box jump.
        let up = landing.z > 0
        let height = landing.z * (1 - (1 - u) * (1 - u)) + 4 * rise * u * (1 - u)
        return (mix(spot, landing, up ? u * u : u), height, height, CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.25), u)
    }

    /// The loop's pose at `t` with a mistake on it. A knee stops at straight.
    func pose(at t: Double, fault: JointPose?) -> JointPose {
        var pose = Figure.smooth(loop.closed, at: t)
        if jacks {
            // The legs open as the body goes up and are together again to land.
            let u = hop(at: t).share
            let out = Self.jack * CardioStagings.ease(4 * u * (1 - u), from: 0, to: 1)
            for key in ["hipAbd", "hipAbdL"] { pose.angles[key] = CardioStagings.angle(pose, key) + out }
        }
        if let fault { pose = CardioStagings.applying(fault, to: pose) }
        for key in ["kneeFlex", "kneeFlexL"] { if let v = pose.angles[key] { pose.angles[key] = max(0, v) } }
        // Nor do the hips bend back further than a sagging plank's.
        for key in ["hipFlex", "hipFlexL"] { if let v = pose.angles[key] { pose.angles[key] = max(-15, v) } }
        return pose
    }

    /// The middle of the shoulders, for a body whose pelvis is at `root`.
    func shoulders(_ g: [String: M], root: V) -> V {
        let rel = body.place(g, root: V(0, 0, 0))
        return root + ((rel["humerus.r"] ?? V(0, 0, 0)) + (rel["humerus.l"] ?? V(0, 0, 0))) * 0.5
    }

    /// Where the wrists are, taken together, when the hands lie on the floor at `hands`.
    func wrists(_ hands: [String: V]?) -> V? {
        guard let press = presses["r"], let r = hands?["r"], let l = hands?["l"] else { return nil }
        return body.pressWrist(press, at: (r + l) * 0.5, fingers: V(0, -1, 0), normal: V(0, 0, 1))
    }

    /// The body at `t` before the arms are fitted. Standing, it is on its spot. With the hands
    /// down, the squat is folded deeper than the keyframes draw it, and the trunk leans until
    /// the shoulders are an arm's length from the wrists: in the squat the trunk folds onto
    /// legs that stay as they are, and toward the plank the legs go with it, so the whole
    /// body turns about its toes. All the while the shoulders stay over the wrists, which is
    /// what sends the feet back. `hands` nil is for finding where the hands go down.
    func solve(at t: Double, fault: JointPose?, hands: [String: V]?, lean squatLean: Double? = nil) -> (g: [String: M], root: V, tilt: Double) {
        var pose = pose(at: t, fault: fault)
        let down = down(at: t), share = plank(at: t)
        let crouch = down * (1 - share)
        if crouch > 0 {
            for key in ["kneeFlex", "kneeFlexL", "hipFlex", "hipFlexL"] where pose.angles[key] != nil || !key.hasSuffix("L") {
                pose.angles[key] = CardioStagings.angle(pose, key) + Self.deeper * crouch
            }
        }
        guard down > 0 else {
            var g = body.rotations(pose)
            CardioFooting.steadyArms(body, &g, pose)
            let hop = hop(at: t)
            g = CardioFooting.settle(g, air: ["r": hop.air, "l": hop.air])
            return (g, CardioFooting.root(body, g, ball: hop.ball, floor: hop.height), 0)
        }
        // The feet skim the floor on their way back and in.
        let air = 4 * share * (1 - share)
        let wrists = wrists(hands)
        let elbow = (CardioStagings.angle(pose, "elbowFlex") + CardioStagings.angle(pose, "elbowFlexL")) / 2
        let arm = Self.long * body.armSpan("r", bend: min(140, max(5, elbow)))
        func leaning(_ lean: Double) -> (g: [String: M], root: V) {
            var bent = pose
            bent.angles["trunk"] = CardioStagings.angle(pose, "trunk") + lean
            for key in ["hipFlex", "hipFlexL"] where pose.angles[key] != nil || !key.hasSuffix("L") {
                bent.angles[key] = CardioStagings.angle(pose, key) + lean * (1 - share)
            }
            var g = body.rotations(bent)
            CardioFooting.steadyArms(body, &g, bent)
            g = CardioFooting.settle(g, air: ["r": air, "l": air])
            var root = CardioFooting.root(body, g, ball: spot, floor: Self.skim * air)
            if down >= 1, let wrists { root.y = wrists.y - shoulders(g, root: V(0, 0, 0)).y }
            return (g, root)
        }
        /// How much further the shoulders are from the wrists than the arms are long.
        func gap(_ lean: Double) -> Double {
            let placed = leaning(lean)
            let at = shoulders(placed.g, root: placed.root)
            guard let wrists else { return at.z - (presses["r"]?.wristLift ?? 0.03) - arm }
            return V(0, at.y - wrists.y, at.z - wrists.z).length - arm
        }
        var lean = (squatLean ?? self.lean) * down
        if down >= 1 || wrists == nil {
            // Leaning further forward brings the shoulders down, whether the body squats or lies out.
            var low = -40.0, top = 80.0
            for _ in 0..<16 {
                let mid = (low + top) / 2
                if gap(mid) > 0 { low = mid } else { top = mid }
            }
            lean = (low + top) / 2
        }
        let placed = leaning(lean)
        return (placed.g, placed.root, lean)
    }

    /// A turn `share` of the way from `a` to `b`.
    static func between(_ a: M, _ b: M, _ share: Double) -> M {
        guard share < 1 else { return b }
        let q = (b * a.t).quat
        let sign = q.w < 0 ? -1.0 : 1.0
        let axis = V(q.x, q.y, q.z) * sign
        let angle = 2 * atan2(axis.length, abs(q.w)) * 180 / .pi
        guard axis.length > 1e-9 else { return b }
        return M.axis(axis.unit, angle * share) * a
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        let t = clock(found.t)
        // A mistake changes the squat, and with it where the hands go down.
        let spots = found.fault == nil ? (hands: hands, lean: lean) : (spots(found.fault) ?? (hands: hands, lean: lean))
        let hands = spots.hands
        let solved = solve(at: t, fault: found.fault, hands: hands, lean: spots.lean)
        var g = solved.g
        var h = body.place(g, root: solved.root)
        let down = down(at: t)
        if down > 0 {
            // The hands leave the keyframes' swing for their places on the floor, and lie flat there.
            let given = g
            for (s, m) in Self.sides {
                guard let press = presses[s], let spot = hands[s], let wrist = h["hand.\(s)"], let hand = given["hand.\(s)"] else { continue }
                let flat = body.pressTurn(press, fingers: V(0, -1, 0), normal: V(0, 0, 1))
                let turned = Self.between(hand, flat, down)
                let target = mix(wrist, body.pressWrist(press, at: spot, fingers: V(0, -1, 0), normal: V(0, 0, 1)), down)
                body.arm(s, wrist: target, hand: turned, pole: V(-m * 0.5, 1, 0.3), &g, h)
                for (bone, turn) in press.turns {
                    let carried = turned * (hand.t * (given[bone] ?? hand))
                    g[bone] = Self.between(carried, turned * turn, down)
                }
            }
            h = body.place(g, root: solved.root)
        }
        return (body.made(g, h, floor: 0), [])
    }
}

import Foundation

/// A place a foot can stand: where its ankle is with the foot flat, how far its toes turn out,
/// and the height of what it stands on.
struct LegSpot: Sendable, Equatable {
    var x, y, turnout: Double
    var floor = 0.0

    static func between(_ a: LegSpot, _ b: LegSpot, _ t: Double) -> LegSpot {
        LegSpot(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, turnout: a.turnout + (b.turnout - a.turnout) * t,
                floor: a.floor + (b.floor - a.floor) * t)
    }
}

extension Body3D {
    func footprint(_ s: String, _ spot: LegSpot) -> LegFootprint? {
        footprint(s, x: spot.x, y: spot.y, turnout: spot.turnout, floor: spot.floor)
    }

    /// A foot on its way from one spot to another: `way` is 0 on the first and 1 on the second,
    /// and between them the foot is carried in an arc `rise` high. Its heel is up on the ball
    /// by `heel` degrees, and by `tip` degrees more at the top of the arc (less, for toes that
    /// lead). On the floor the toes lie flat under a raised heel; in the air they go with the foot.
    func stepping(_ s: String, from a: LegSpot, to b: LegSpot, way: Double, heel: Double, rise: Double = 0, tip: Double = 0)
        -> (ankle: V, foot: M, toes: M)? {
        guard let print = footprint(s, .between(a, b, way)) else { return nil }
        let air = rise > 0 ? 4 * way * (1 - way) : 0
        let pitch = heel + tip * air
        var (ankle, foot) = lifted(print, heel: pitch)
        ankle.z += rise * air
        let toes = M.axis(V(0, 0, 1).cross(print.toe), pitch * min(1, 2 * air)) * print.turn
        return (ankle, foot, toes)
    }

    /// As `apex`, in the plane the body moves sideways in: x and z are used and y is ignored.
    static func apexAcross(_ a: V, _ r1: Double, _ b: V, _ r2: Double) -> V {
        let p = apex(V(0, a.x, a.z), r1, V(0, b.x, b.z), r2)
        return V(p.y, 0, p.z)
    }
}

/// Lunges and split squats. The keyframes show every one of them as a split squat held in
/// place, so the feet are placed here: a split squat keeps both where they are; a forward lunge
/// steps the front foot out and back; a reverse lunge steps the rear foot back and returns; a
/// walking lunge steps out and then brings the rear foot through to stand a stride further on;
/// a side lunge steps out to the side and sits back over the bent leg; a curtsy steps behind
/// and across. A foot on the floor never slides: it stays on its spot, or turns on its ball as
/// its heel comes up. A stepping foot is lifted and carried over. The right leg is the one the
/// keyframes bend most: the front leg, or the leg a side lunge sits over.
struct LungeStaging: LoopStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    enum Move: Sendable, Equatable {
        /// Both feet stay in the split stance.
        case held
        case forward, reverse, walking
        /// `step` false is a squat from side to side in a wide stance, with no step.
        case side(step: Bool)
        case curtsy
        /// The rear foot rests on a bench, laces down.
        case bulgarian
    }

    /// The top of the bench a rear foot rests on, and how far behind the front ankle that foot's ankle is.
    static let benchTop = 0.42, benchBack = 0.7
    /// How high a stepping foot is carried.
    static let rise = 0.07
    /// The low step a front foot is raised on, or a reverse lunge steps down from.
    static let step = 0.1

    let body: Body3D
    let carry: LegLoad
    let depth: LegDepth
    let grips: [String: HandGrip]
    let move: Move
    /// Where the feet stand tall before the step, where they are in the lunge, and where they
    /// stand tall after it (the same place again, except for a walking lunge).
    let home: [String: LegSpot], lunge: [String: LegSpot], onward: [String: LegSpot]
    /// How far the knees have bent, 0 to 1, when the stepping foot comes down, and in a walking
    /// lunge how far they are still bent when the rear foot leaves the floor.
    let landed: Double, leaves = 0.8
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let (move, carry, raised) = Self.plan(for: guide), let grips = carry.grips(body),
              let hip = body.head["femur.l"], let knee = body.head["shin.l"], let ankle = body.head["foot.l"],
              let ball = body.head["toes.l"] else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        self.move = move
        depth = LegDepth(guide.keyframes)
        // A stride that lets the front shin stand upright over a level thigh while the back
        // thigh hangs straight down: a little less than a leg's length from ankle to toes.
        let stride = 0.94 * ((knee - hip).length + (ankle - knee).length)
        // The feet stand on two rails, not a tightrope. The ball of a foot is `toes` ahead of its ankle.
        let rail = hip.x + 0.025, toes = ankle.y - ball.y
        let stand = ["r": LegSpot(x: -rail, y: 0, turnout: 6), "l": LegSpot(x: rail, y: 0, turnout: 4)]
        var home = stand, lunge = stand, onward = stand
        var kinds = carry.kinds
        var pieces: [PropPiece] = []
        var landed = 0.38
        switch move {
        case .held:
            lunge["l"]?.y = stride + toes
            (home, onward) = (lunge, lunge)
        case .forward:
            lunge["r"]?.y = -stride
        case .reverse:
            lunge["l"]?.y = stride + toes
        case .walking:
            // Half the stride is behind the middle of the floor and half ahead of it.
            for s in ["r", "l"] {
                home[s]?.y = stride / 2
                lunge[s]?.y = stride / 2
                onward[s]?.y = -stride / 2
            }
            lunge["r"]?.y = -stride / 2
        case .side(let step):
            // Feet wide enough for the hips to sit down beside a leg that stays straight.
            let wide = 1.12 * stride
            if step {
                for s in ["r", "l"] {
                    home[s]?.turnout = 8
                    lunge[s]?.turnout = 8
                }
                lunge["r"] = LegSpot(x: rail - wide, y: 0, turnout: 14)
                onward = home
                landed = 0.3
            } else {
                lunge = ["r": LegSpot(x: -wide / 2, y: 0, turnout: 16), "l": LegSpot(x: wide / 2, y: 0, turnout: 16)]
                (home, onward) = (lunge, lunge)
            }
        case .curtsy:
            lunge["l"] = LegSpot(x: -rail - 0.15, y: 0.72 * stride + toes, turnout: -8)
        case .bulgarian:
            lunge["l"] = LegSpot(x: rail, y: Self.benchBack, turnout: 0, floor: Self.benchTop)
            (home, onward) = (lunge, lunge)
            kinds.append(.bench)
            // A flat bench across behind the lifter, its near edge under the shin.
            let near = Self.benchBack - 0.07, top = Self.benchTop
            pieces.append(PropPlan.box(V(0, near + 0.15, top - 0.04), (1.1, 0.3, 0.08), .pad))
            for x in [-0.43, 0.43] {
                pieces.append(PropPlan.box(V(x, near + 0.15, (top - 0.08) / 2), (0.05, 0.24, top - 0.08), .metal))
            }
        }
        if raised {
            // The front foot's step, and both feet's before a step back off it. Its back edge
            // is just behind the heel.
            lunge["r"]?.floor = Self.step
            for s in ["r", "l"] {
                home[s]?.floor = move == .held ? lunge[s]?.floor ?? 0 : Self.step
                onward[s]?.floor = home[s]?.floor ?? 0
            }
            kinds.append(.step)
            pieces.append(PropPlan.box(V(0, -0.07, Self.step / 2), (0.6, 0.4, Self.step), .wood))
        }
        self.home = home
        self.lunge = lunge
        self.onward = onward
        self.landed = landed
        self.kinds = kinds
        fixed = pieces
    }

    /// Which lunge this is and what is carried, or nil for one this staging does not show
    /// honestly. Every word of the name must be one this staging knows the meaning of.
    static func plan(for guide: HowToGuide) -> (move: Move, carry: LegLoad, raised: Bool)? {
        var words = LegLoad.words(guide)
        var plain: Set<String> = []
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        /// The usual loads: nothing, a dumbbell in each hand or one at the chest, a kettlebell
        /// at the chest, a bar on the back.
        func usual(sides: Bool = true) -> LegLoad? {
            switch guide.equipment {
            case nil: return only("bodyweight") ? .free : nil
            case "dumbbell":
                if words.contains("goblet") { return only("dumbbell", "goblet") ? .goblet(kettlebell: false) : nil }
                return sides && only("dumbbell") ? .sides : nil
            case "kettlebell": return words.contains("goblet") && only("kettlebell", "goblet") ? .goblet(kettlebell: true) : nil
            case "barbell":
                if words.contains("front") { return only("barbell", "front", "rack") ? .front : nil }
                return only("barbell") ? .back : nil
            default: return nil
            }
        }
        switch guide.subtypeID {
        case nil:
            plain = ["lunge", "lunges", "split", "squat", "squats", "static", "forward", "rear", "reverse", "backward",
                     "walking", "v", "2", "3", "male", "low"]
            // A split squat with the front foot on a low step, or a step back down off one.
            var raised = false
            for phrase in [["front", "foot", "elevated"], ["from", "deficit"], ["from", "step"]]
            where words.isSuperset(of: phrase) && guide.equipment != "barbell" {
                words.subtract(phrase)
                raised = true
            }
            guard let carry = usual() else { return nil }
            let held = !words.isDisjoint(with: ["split", "static"]), back = !words.isDisjoint(with: ["rear", "reverse", "backward"])
            if raised { return held != back ? (held ? .held : .reverse, carry, true) : nil }
            if words.contains("walking") { return (.walking, carry, false) }
            if held { return (.held, carry, false) }
            return (back ? .reverse : .forward, carry, false)
        case "lateral":
            plain = ["side", "lateral", "lunge", "lunges", "squat", "squats", "split", "cossack"]
            // One weight is held at the chest, where it is clear of the bent knee.
            var carry = usual(sides: false)
            if carry == nil, guide.equipment == "kettlebell", only("kettlebell") { carry = .goblet(kettlebell: true) }
            if carry == nil, guide.equipment == "dumbbell", only("dumbbell") { carry = .goblet(kettlebell: false) }
            guard let carry else { return nil }
            return (.side(step: !words.isDisjoint(with: ["lunge", "lunges"])), carry, false)
        case "curtsy":
            plain = ["curtsy", "curtsey", "lunge", "lunges", "squat", "crossover", "reverse", "single"]
            return usual().map { (.curtsy, $0, false) }
        case "bulgarian":
            plain = ["bulgarian", "split", "squat", "elevated"]
            guard let carry = usual(), carry != .front else { return nil }
            return (.bulgarian, carry, false)
        default: return nil
        }
    }

    private static func ease(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    /// With no moment of the loop to go by, the way down.
    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) { frame(pose, at: 0) }

    func frame(_ pose: JointPose, at t: Double) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose, at: t)
        return (frame, carry.props(held))
    }

    /// The body at moment `t` of the loop, and where its weights are.
    func solve(_ pose: JointPose, at t: Double) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        let u = depth(pose)
        let sideways = if case .side = move { true } else { false }
        // Empty hands come forward to balance hips that sit back.
        carry.ready(&pose, reach: sideways ? 0.7 * u : nil)
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let carried = carry.load(g, rel)
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let hipF = rel["femur.r"], let hipB = rel["femur.l"], let leadSpot = lunge["r"], let trailSpot = lunge["l"]
        else { return (body.made(g, rel, floor: 0), []) }
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length

        // Which foot is in the air, where it comes from, and how far into the lunge the feet
        // and hips are: all the way once the stepping foot is down.
        let rising = move == .walking && t > 0.5
        let from = rising ? onward : home
        var way = 1.0
        var swing: String?
        switch move {
        case .held, .side(step: false), .bulgarian: break
        case .forward, .side(step: true): (swing, way) = ("r", Self.ease(u / landed))
        case .reverse, .curtsy: (swing, way) = ("l", Self.ease(u / landed))
        case .walking: (swing, way) = rising ? ("l", Self.ease(u / leaves)) : ("r", Self.ease(u / landed))
        }

        // The front foot stays flat unless its heel lifts by mistake; the rear heel is up, and
        // comes further up as the knee under it goes down. Beside a side lunge it stays flat.
        let slip = min(30, max(0, -depth.off("ankleDorsi", pose) - 3) * 1.5)
        let up = sideways ? 0 : 40 + 25 * u
        guard let front = body.footprint("r", leadSpot), let back = body.footprint("l", trailSpot) else {
            return (body.made(g, rel, floor: 0), [])
        }
        let lead = body.lifted(front, heel: slip)
        var trail = body.lifted(back, heel: up)
        if move == .bulgarian {
            // The top of the foot lies on the pad, toes pointing back.
            trail = (V(trailSpot.x, trailSpot.y, trailSpot.floor + 0.05), M.x(172))
        }

        // In the lunge the hips are where both knees have the bend the keyframes give them.
        func reach(_ key: String) -> Double { Body3D.span(thigh, shin, bend: max(1, pose.angles[key] ?? 0)) }
        func within(_ r: Double, _ gap: Double) -> Double { max(0.05, r * r - gap * gap).squareRoot() }
        let a = lead.ankle - hipF, b = trail.ankle - hipB
        var low: V
        if sideways {
            // Side by side: the hips sit as far back as keeps the weight over the feet.
            let middle = lead.ankle.y - 0.055
            var y = middle
            low = V(0, y, 0)
            for _ in 0..<5 {
                let p = Body3D.apexAcross(a, within(reach("kneeFlex"), y - a.y), b, within(reach("kneeFlexL"), y - b.y))
                low = V(p.x, y, p.z)
                var trial = g
                let h = body.place(trial, root: low)
                body.plant("r", ankle: lead.ankle, foot: lead.foot, pole: front.toe, &trial, h)
                body.plant("l", ankle: trail.ankle, foot: trail.foot, pole: back.toe, &trial, h)
                var weight = body.balance(trial, body.place(trial, root: low))
                if let carried { weight = (weight + (low + carried.at) * carried.mass) * (1 / (1 + carried.mass)) }
                y = min(middle + 0.35, max(middle - 0.2, y - (weight.y - middle)))
            }
        } else {
            // One behind the other: the hips stay between the rails, a little toward a foot that crosses over.
            let x = move == .curtsy ? -0.03 : 0
            let p = Body3D.apex(a, within(reach("kneeFlex"), x - a.x), b, within(reach("kneeFlexL"), x - b.x))
            low = V(x, p.y, p.z)
        }

        // Before the step, and after it, the body stands tall over both feet.
        var root = low
        if way < 1, let r = from["r"].flatMap({ body.footprint("r", $0) }), let l = from["l"].flatMap({ body.footprint("l", $0) }) {
            var trial = g
            let tall = body.stand(&trial, on: [r, l], knee: 4, kneeTurn: 6, load: carried)["pelvis"] ?? low
            root = mix(tall, low, way)
        }

        guard let leadSpot0 = from["r"], let trailSpot0 = from["l"],
              let right = body.stepping("r", from: leadSpot0, to: leadSpot, way: way, heel: slip * way,
                                        rise: swing == "r" ? Self.rise : 0, tip: -10),
              var left = body.stepping("l", from: trailSpot0, to: trailSpot, way: way, heel: up * way,
                                       rise: swing == "l" ? (rising ? 1.4 : 1) * Self.rise : 0)
        else { return (body.made(g, rel, floor: 0), []) }
        if move == .bulgarian { left = (trail.ankle, trail.foot, trail.foot) }

        // Hips never further from a foot than its leg is long, so no foot is pulled off its spot.
        let most = Body3D.span(thigh, shin, bend: 2)
        for _ in 0..<4 {
            for (hip, ankle) in [(root + hipF, right.ankle), (root + hipB, left.ankle)] {
                let d = (hip - ankle).length
                if d > most { root.z -= (d * d - most * most) / (2 * max(0.2, hip.z - ankle.z)) }
            }
        }

        var h = body.place(g, root: root)
        // A front knee that caves in points inside its toes.
        let turn = (leadSpot.turnout + depth.off("hipAbd", pose) + depth.off("hipRot", pose)) * .pi / 180
        body.plant("r", ankle: right.ankle, foot: right.foot, pole: V(-sin(turn), -cos(turn), 0), &g, h)
        // A rear knee points forward, and down from a foot that rests as high as the hips.
        let rearKnee = sideways ? back.toe : move == .bulgarian ? V(0, -0.35, -1) : V(0, -1, 0)
        body.plant("l", ankle: left.ankle, foot: left.foot, pole: rearKnee, &g, h)
        g["toes.r"] = right.toes
        g["toes.l"] = left.toes
        h = body.place(g, root: root)
        let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }
}

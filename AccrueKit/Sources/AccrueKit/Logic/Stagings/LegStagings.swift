import Foundation

/// Leg work under a bar or with weights in the hands: squat, one-leg squat, jump squat, lunge, step-up,
/// standing and seated calf raise, good morning.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum LegStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        switch guide.familyID {
        case "squat", "back-extension": return SquatStaging(guide, body)
        case "calf-raise": return guide.subtypeID == "seated" ? SeatedCalfRaiseStaging(guide, body) : CalfRaiseStaging(guide, body)
        case "lunge-split-squat": return LungeStaging(guide, body)
        case "step-up": return guide.subtypeID == "lateral" ? SideStepUpStaging(guide, body) : StepUpStaging(guide, body)
        case "single-leg-squat": return SingleLegSquatStaging(guide, body)
        case "jump-squat-tuck": return JumpSquatStaging(guide, body)
        default: return nil
        }
    }
}

// MARK: - Feet on the floor

/// Where one foot stands: the ankle joint with the foot flat, the ball of the foot (the joint
/// the toes bend at, which a rising heel turns on), and the foot's turn about the vertical.
struct LegFootprint: Sendable {
    let side: String
    let ankle: Body3D.V
    let ball: Body3D.V
    let turn: Body3D.M
    /// Along the floor from heel to toe.
    let toe: Body3D.V
}

/// How far a leg movement has gone, read from the knee bend the keyframes give: 0 with the legs
/// long, 1 at the bottom. It also knows what the hips and ankles do at each depth when the
/// movement is done well, so a mistake that changes them can be told from the movement itself.
struct LegDepth: Sendable {
    let low, high: Double
    private let top: JointPose, bottom: JointPose

    init(_ keys: [Keyframe]) {
        let bends = keys.map { $0.pose.angles["kneeFlex"] ?? 0 }
        low = bends.min() ?? 0
        high = max(bends.max() ?? 100, low + 1)
        top = keys.min { ($0.pose.angles["kneeFlex"] ?? 0) < ($1.pose.angles["kneeFlex"] ?? 0) }?.pose ?? JointPose()
        bottom = keys.max { ($0.pose.angles["kneeFlex"] ?? 0) < ($1.pose.angles["kneeFlex"] ?? 0) }?.pose ?? JointPose()
    }

    func callAsFunction(_ pose: JointPose) -> Double {
        min(1, max(0, ((pose.angles["kneeFlex"] ?? 0) - low) / (high - low)))
    }

    /// How far the pose's `key` is from where good form has it at this depth, in degrees.
    func off(_ key: String, _ pose: JointPose) -> Double {
        let a = top.angles[key] ?? 0, b = bottom.angles[key] ?? 0
        return (pose.angles[key] ?? 0) - (a + (b - a) * self(pose))
    }
}

extension Body3D {
    /// A foot standing at (`x`, `y`) on the floor with its toes turned out by `turnout` degrees.
    func footprint(_ s: String, x: Double, y: Double, turnout: Double, floor: Double = 0) -> LegFootprint? {
        guard let a = head["foot.\(s)"], let b = head["toes.\(s)"], let t = tail["toes.\(s)"] else { return nil }
        let m = s == "r" ? 1.0 : -1.0
        // The foot already points a little outward at rest.
        let rest = atan2(-m * (t.x - a.x), -(t.y - a.y)) * 180 / .pi
        let turn = M.z(-m * (turnout - rest))
        let ankle = V(x, y, floor + ankleHeight)
        return LegFootprint(side: s, ankle: ankle, ball: ankle + turn * (b - a), turn: turn, toe: (turn * (t - a)).flat.unit)
    }

    /// The ankle and the foot's rotation when the heel has risen by `degrees` on the ball of the foot.
    func lifted(_ f: LegFootprint, heel degrees: Double) -> (ankle: V, foot: M) {
        guard degrees != 0, let a = head["foot.\(f.side)"], let b = head["toes.\(f.side)"] else { return (f.ankle, f.turn) }
        let foot = M.axis(V(0, 0, 1).cross(f.toe), degrees) * f.turn
        return (f.ball + foot * (a - b), foot)
    }

    /// Stands a posed body on its two planted feet. The trunk keeps the lean the pose gives it;
    /// the knees bend by `knee` degrees and point `kneeTurn` degrees outward; the hips go where
    /// that leaves the weight of the body and its `load` (a point from the pelvis, and its mass
    /// as a share of the body's) over the middle of the feet, as a lifter who is not falling
    /// over must have it: `over` is where along the feet that is, when it is not their middle,
    /// and `sitBack` how far behind it the hips may go. Returns the bone heads.
    func stand(_ g: inout [String: M], on feet: [LegFootprint], knee: Double, kneeTurn: Double, heel: Double = 0,
               load: (at: V, mass: Double)? = nil, over: Double? = nil, sitBack: Double = 0.35) -> [String: V] {
        let rel = place(g, root: V(0, 0, 0))
        guard let rHip = head["femur.r"], let rKnee = head["shin.r"], let rAnkle = head["foot.r"], !feet.isEmpty else { return rel }
        let leg = Self.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: max(1, knee))
        let stood = feet.map { (print: $0, at: lifted($0, heel: heel)) }
        // The middle of the foot is a little in front of the ankle.
        let middle = over ?? stood.map { $0.print.ankle.y - 0.055 * abs($0.print.toe.y) }.reduce(0, +) / Double(stood.count)

        func root(_ y: Double) -> V {
            var z = 0.0
            for f in stood {
                guard let hip = rel["femur.\(f.print.side)"] else { continue }
                let dx = hip.x - f.at.ankle.x, dy = y + hip.y - f.at.ankle.y
                z += f.at.ankle.z + max(0, leg * leg - dx * dx - dy * dy).squareRoot() - hip.z
            }
            return V(0, y, z / Double(stood.count))
        }
        func legs(_ root: V, _ g: inout [String: M]) -> [String: V] {
            let h = place(g, root: root)
            for f in stood {
                let m = f.print.side == "r" ? 1.0 : -1.0, a = kneeTurn * .pi / 180
                plant(f.print.side, ankle: f.at.ankle, foot: f.at.foot, pole: V(-m * sin(a), -cos(a), 0), &g, h)
                g["toes.\(f.print.side)"] = f.print.turn
            }
            return place(g, root: root)
        }
        var y = middle
        for _ in 0..<6 {
            let r = root(y)
            let h = legs(r, &g)
            var weight = balance(g, h)
            if let load { weight = (weight + (r + load.at) * load.mass) * (1 / (1 + load.mass)) }
            y = min(middle + sitBack, max(middle - 0.25, y - (weight.y - middle)))
        }
        return legs(root(y), &g)
    }
}

extension Body3D {
    /// As `hold`, for a hand whose fingers point a set way whatever the forearm does: a bar that
    /// lies in the fingers of a wrist bent back, or a weight cupped from the side. The wrist
    /// takes up the difference between the hand and the forearm.
    func clasp(_ s: String, _ grip: HandGrip, at point: V, across: V, fingers: V, pole: V,
               _ g: inout [String: M], _ h: [String: V]) {
        let m = s == "r" ? 1.0 : -1.0
        guard let shoulder = h["humerus.\(s)"], let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"],
              let rRadius = head["radius.\(s)"], let rWrist = head["hand.\(s)"] else { return }
        let upper = rElbow - rShoulder
        let hinge = hingeAxis(s), axis = pronationAxis(s)
        let toRadius = rRadius - rElbow, toWrist = rWrist - rRadius
        let hand = Self.frameMap(grip.across, grip.along, to: across, fingers)
        let target = point - hand * grip.centre
        var pronation = 90.0
        var ulna = M.identity
        var elbow = shoulder
        var k = hinge
        for _ in 0..<6 {
            let v = toRadius + M.axis(axis, -m * pronation) * toWrist
            let solved = Self.bend(root: shoulder, target: target, upper: upper.length, lower: v.length, pole: pole)
            elbow = solved.joint
            let n = pole.cross(solved.end - shoulder)
            if n.length > 1e-9 { k = n.unit }
            ulna = Self.frameMap(v, hinge, to: solved.end - elbow, k)
            // The forearm's turn is the part of the hand's rotation about the forearm's own line.
            let q = (ulna.t * hand).quat
            var p = -m * 2 * atan2(q.x * axis.x + q.y * axis.y + q.z * axis.z, q.w) * 180 / .pi
            if p < -90 { p += 360 }
            pronation = min(175, max(0, p))
        }
        g["humerus.\(s)"] = Self.frameMap(upper, hinge, to: elbow - shoulder, k)
        g["ulna.\(s)"] = ulna
        turnForearm(s, ulna: ulna, pronation: pronation, into: &g)
        g["hand.\(s)"] = hand
        for (bone, turn) in grip.turns { g[bone] = hand * turn }
    }
}

// MARK: - Weights

/// The free weights of leg day, drawn to the sizes PropPlan gives them everywhere else.
enum LegWeights {
    typealias V = Body3D.V
    typealias Plan = PropPlan

    static let barRadius = 0.014, plateRadius = 0.225, dumbbellGrip = 0.016

    /// An Olympic bar with a plate on each end, its middle at `mid`, lying along `axis`.
    static func barbell(_ mid: V, along axis: V = V(1, 0, 0)) -> [PropPiece] {
        let a = axis.unit
        var p = [Plan.rod(mid - a, mid + a, barRadius, .metal)]
        for side in [-1.0, 1.0] {
            p.append(Plan.disc(mid + a * (side * 0.8), axis: a, radius: plateRadius, thickness: 0.07, .plate))
            p.append(Plan.disc(mid + a * (side * 0.73), axis: a, radius: 0.03, thickness: 0.03, .metal))
        }
        return p
    }

    /// A pair of squat stands behind the lifter: two uprights at `y` with hooks for the bar at
    /// `height`, each on its own foot that runs back from under the hooks and ends in a cross
    /// piece. The uprights are inside the plates and outside the hands. Every piece is out at
    /// the sides, so a lift that has no use for the stands can leave them out by where they are.
    static func rack(y: Double, height: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        for x in [-0.56, 0.56] {
            p.append(Plan.box(V(x, y, (height + 0.25) / 2), (0.05, 0.05, height + 0.25), .metal))
            p.append(Plan.box(V(x, y + 0.2, 0.02), (0.07, 0.7, 0.04), .metal))
            p.append(Plan.box(V(x, y + 0.52, 0.02), (0.4, 0.07, 0.04), .metal))
            // The hook: a ledge the bar sits on, with a lip in front.
            p.append(Plan.box(V(x, y - 0.06, height - 0.012), (0.05, 0.07, 0.016), .metal))
            p.append(Plan.box(V(x, y - 0.09, height + 0.008), (0.05, 0.012, 0.04), .metal))
        }
        return p
    }

    /// A dumbbell with the middle of its handle at `mid`.
    static func dumbbell(_ mid: V, along axis: V) -> [PropPiece] {
        let a = axis.unit
        var p = [Plan.rod(mid - a * 0.13, mid + a * 0.13, dumbbellGrip, .metal)]
        for side in [-1.0, 1.0] {
            p.append(Plan.disc(mid + a * (side * 0.1), axis: a, radius: 0.06, thickness: 0.07, .dark))
        }
        return p
    }

    /// A kettlebell hanging upright under its handle: the horns the hands close on are
    /// `halfHorns` either side of `handle`, the middle of the handle's height.
    static func kettlebell(handle: V, halfHorns: Double, radius: Double) -> [PropPiece] {
        let ball = handle - V(0, 0, 0.14)
        var p = [Plan.ball(ball, 0.1, .dark)]
        let top = handle + V(0, 0, 0.055)
        for side in [-1.0, 1.0] {
            let corner = top + V(side * halfHorns, 0, 0)
            p.append(Plan.rod(ball + V(side * 0.045, 0, 0.08), corner, radius, .dark))
            p.append(Plan.ball(corner, radius, .dark))
        }
        p.append(Plan.rod(top - V(halfHorns, 0, 0), top + V(halfHorns, 0, 0), radius, .dark))
        return p
    }
}

// MARK: - What the lifter carries

/// What a lifter holds up over the head on straight arms.
enum LegOverhead: Sendable, Equatable {
    case bar, dumbbells, hands
}

/// What a standing lifter carries and where: a bar on the upper back or on the front of the
/// shoulders, one weight held at the chest, a dumbbell in each hand at the sides, a bar or
/// dumbbells (or just the hands) held up overhead, or nothing.
enum LegLoad: Sendable, Equatable {
    case back, front, goblet(kettlebell: Bool), sides, overhead(LegOverhead), free

    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The bar's centre from the joint at the base of the neck, in the rib cage's own axes. On
    /// the back it lies on the trapezius just under the bone that sticks out at the bottom of
    /// the neck; in front it lies in the hollow between the shoulders and the throat.
    static let onBack = V(0, 0.079, 0.004), onFront = V(0, -0.105, -0.012)
    static let backGrip = 0.37, frontGrip = 0.3
    /// Between the hands of a goblet hold: the middle of a kettlebell's handle, or of a
    /// dumbbell's upper head.
    static let atChest = V(0, -0.28, -0.105), headAtChest = V(0, -0.24, -0.085)
    static let hornRadius = 0.012, halfHorns = 0.058, headRadius = 0.06
    /// How far from the middle of a bar held overhead each hand is: the wide grip of a snatch.
    static let overheadGrip = 0.5

    var kinds: [PropKind] {
        switch self {
        case .back, .front: return [.barbell]
        case .goblet(let kettlebell): return [kettlebell ? .kettlebell : .dumbbell]
        case .sides, .overhead(.dumbbells): return [.dumbbell]
        case .overhead(.bar): return [.barbell]
        case .free, .overhead(.hands): return []
        }
    }

    /// Both hands closed for what they hold.
    func grips(_ body: Body3D) -> [String: HandGrip]? {
        let radius: Double, square: Double
        switch self {
        case .back, .front, .overhead(.bar): (radius, square) = (LegWeights.barRadius, 0.6)
        case .goblet(let kettlebell): (radius, square) = (kettlebell ? Self.hornRadius : Self.headRadius, 0)
        case .sides, .free, .overhead: (radius, square) = (LegWeights.dumbbellGrip, 0)
        }
        guard let r = body.grip("r", radius: radius, square: square), let l = body.grip("l", radius: radius, square: square)
        else { return nil }
        return ["r": r, "l": l]
    }

    /// Sets the shoulder blades for the weight; the arms themselves are fitted to it by `take`.
    /// Empty hands hang, or reach forward by `reach` (0...1) to balance hips that sit back.
    func ready(_ pose: inout JointPose, reach: Double? = nil) {
        switch self {
        case .back: break
        case .front: pose.scapula = Scapula(protraction: 1, elevation: 0.3, upRot: 12)
        case .goblet, .sides: pose.scapula = nil
        // Shoulder blades turned up under arms that reach overhead.
        case .overhead(.bar), .overhead(.dumbbells): pose.scapula = Scapula(protraction: 0, elevation: 0.5, upRot: 30)
        case .overhead(.hands):
            // Empty arms stay straight up as the trunk leans under them.
            pose.angles["shoulderFlex"] = 172 + 0.9 * (pose.angles["trunk"] ?? 0)
        case .free:
            guard let reach else { break }
            pose.scapula = nil
            pose.angles.merge(["shoulderFlex": 8 + 70 * reach + 0.9 * (pose.angles["trunk"] ?? 0), "shoulderAbd": 4,
                               "shoulderRot": 0, "elbowFlex": 10 - 4 * reach, "forearm": 0]) { $1 }
        }
    }

    /// Where the weight is from the pelvis, and how heavy next to the body, for a body whose
    /// heads `rel` were placed with the pelvis at the origin.
    func load(_ g: [String: M], _ rel: [String: V]) -> (at: V, mass: Double)? {
        let thorax = g["thorax"] ?? .identity
        let neck = rel["neck"] ?? V(0, 0, 0.6)
        switch self {
        case .back: return (neck + thorax * Self.onBack, 1.0)
        case .front: return (neck + thorax * Self.onFront, 0.8)
        case .goblet(let kettlebell): return (neck + thorax * (kettlebell ? Self.atChest : Self.headAtChest), 0.3)
        case .sides:
            let shoulders = ((rel["humerus.r"] ?? neck) + (rel["humerus.l"] ?? neck)) * 0.5
            return (shoulders + V(0, 0, -0.58), 0.5)
        case .overhead(let what):
            guard what != .hands else { return nil }
            let shoulders = ((rel["humerus.r"] ?? neck) + (rel["humerus.l"] ?? neck)) * 0.5
            return (shoulders + V(0, 0.02, 0.5), what == .bar ? 0.5 : 0.3)
        case .free: return nil
        }
    }

    /// Closes the hands on the weight, which is at `at` (the pelvis plus `load`'s point), and
    /// returns where its pieces are: the middle of the bar, the point between the hands of a
    /// goblet hold, or the right and left dumbbell.
    func take(_ body: Body3D, _ grips: [String: HandGrip], at: V?, _ g: inout [String: M], _ h: [String: V]) -> [V] {
        guard let at else { return [] }
        let thorax = g["thorax"] ?? .identity
        var held: [V] = []
        // A bar overhead is level, as high as the shorter reach of the two straight arms
        // leaves it, straight above the shoulders.
        var top = Double.infinity
        if case .overhead = self {
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let grip = grips[s], let shoulder = h["humerus.\(s)"] else { continue }
                let reach = body.reach(s, grip, bend: 4), out = self == .overhead(.bar) ? at.x - m * Self.overheadGrip - shoulder.x : -m * 0.04
                top = min(top, shoulder.z + max(0.04, reach * reach - out * out).squareRoot())
            }
        }
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            switch self {
            case .back:
                // Hands outside the shoulders, elbows under the bar and a little behind it.
                body.hold(s, grip, at: at + V(-m * Self.backGrip, 0, 0), across: V(-m, 0, 0),
                          pole: thorax * V(-m * 0.2, 0.35, -1), &g, h)
                held = [at]
            case .front:
                // The clean grip: the bar lies in the palm of a wrist bent back, elbows up in front.
                body.clasp(s, grip, at: at + V(-m * Self.frontGrip, 0, 0), across: V(-m, 0, 0),
                           fingers: thorax * V(0, 0.5, 0.866), pole: thorax * V(-m * 0.7, -1, -0.4), &g, h)
                held = [at]
            case .goblet(let kettlebell):
                // A hand on each side, thumbs up, elbows tucked under.
                let point = kettlebell ? at + V(-m * Self.halfHorns, 0, 0) : at
                body.clasp(s, grip, at: point, across: V(0, 0, -1), fingers: V(0, -1, 0), pole: V(-m * 0.45, 0.1, -1), &g, h)
                held = [at]
            case .sides:
                // Each dumbbell hangs under its shoulder, clear of the thigh.
                guard let shoulder = h["humerus.\(s)"], let hip = h["femur.\(s)"] else { continue }
                let mid = h["pelvis"]?.x ?? 0
                let x = mid - m * max(abs(shoulder.x - mid) + 0.12, abs(hip.x - mid) + 0.225)
                let reach = body.reach(s, grip, bend: 10)
                let dx = x - shoulder.x
                let point = V(x, shoulder.y, shoulder.z - max(0.04, reach * reach - dx * dx).squareRoot())
                body.hold(s, grip, at: point, across: V(0, 1, 0), pole: V(-m * 0.3, 1, 0), &g, h)
                held.append(point)
            case .overhead(.bar):
                body.hold(s, grip, at: V(at.x - m * Self.overheadGrip, at.y, top), across: V(-m, 0, 0), pole: V(-m, 0.5, -0.3), &g, h)
                held = [V(at.x, at.y, top)]
            case .overhead(.dumbbells):
                guard let shoulder = h["humerus.\(s)"] else { continue }
                let point = V(shoulder.x - m * 0.04, at.y, top)
                body.hold(s, grip, at: point, across: V(-m, 0, 0), pole: V(-m, 0.5, -0.3), &g, h)
                held.append(point)
            case .free, .overhead(.hands): break
            }
        }
        return held
    }

    /// The weight itself, where `take` said it is.
    func props(_ held: [V]) -> [PropPiece] {
        switch self {
        case .back, .front, .overhead(.bar): return held.first.map { LegWeights.barbell($0) } ?? []
        case .overhead(.dumbbells): return held.flatMap { LegWeights.dumbbell($0, along: V(1, 0, 0)) }
        case .goblet(let kettlebell):
            guard let at = held.first else { return [] }
            return kettlebell ? LegWeights.kettlebell(handle: at, halfHorns: Self.halfHorns, radius: Self.hornRadius)
                : LegWeights.dumbbell(at - V(0, 0, 0.1), along: V(0, 0, 1))
        case .sides: return held.flatMap { LegWeights.dumbbell($0, along: V(0, 1, 0)) }
        case .free, .overhead(.hands): return []
        }
    }

    /// The words of an exercise's name, for a staging that must know the meaning of every one
    /// before it claims the exercise.
    static func words(_ guide: HowToGuide) -> Set<String> {
        Set(guide.exerciseName.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

// MARK: - Squat and good morning

/// A squat with both feet flat where they stand, under whatever it is loaded with: a bar on the
/// upper back or on the front of the shoulders, one weight held at the chest, a dumbbell in each
/// hand, or nothing. The hips sit back and down as far as the keyframes bend the knees, keeping
/// the load over the middle of the feet. A good morning is the same lifter under the same bar,
/// with the knees nearly straight and the trunk bowing instead.
struct SquatStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The body under its load, without the equipment that stands on the floor.
    struct Lifter: Sendable {
        let body: Body3D
        let carry: LegLoad
        let depth: LegDepth
        let feet: [LegFootprint]
        let turnout: Double
        let grips: [String: HandGrip]
        /// How far behind the middle of the feet the hips may go.
        var sitBack = 0.35

        /// The body for one pose, and where its weights are (see `LegLoad.take`).
        func solve(_ pose: JointPose) -> (frame: BodyFrame, held: [V]) {
            var pose = pose
            carry.ready(&pose, reach: depth(pose))
            var g = body.rotations(pose)
            let carried = carry.load(g, body.place(g, root: V(0, 0, 0)))

            // Knees that cave in point inside the toes; heels that lift leave the floor.
            let turn = min(60, max(-25, turnout + depth.off("hipAbd", pose) + depth.off("hipRot", pose)))
            let heel = min(30, max(0, -depth.off("ankleDorsi", pose) - 3) * 1.5)
            var h = body.stand(&g, on: feet, knee: pose.angles["kneeFlex"] ?? 0, kneeTurn: turn, heel: heel,
                               load: carried, sitBack: sitBack)
            let root = h["pelvis"] ?? V(0, 0, 0)
            let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
            h = body.place(g, root: root)
            return (body.made(g, h, floor: 0), held)
        }
    }

    let lifter: Lifter
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let hinge = guide.familyID == "back-extension"
        guard let carry = hinge ? Self.hinge(for: guide) : Self.carry(for: guide), let grips = carry.grips(body),
              let hip = body.head["femur.l"] else { return nil }

        // The stance the keyframes spread the hips to: heels under the shoulders for a plain
        // squat, wider with the toes further out for a sumo squat. Dumbbells at the sides need
        // the knees inside them, and a good morning stands with the feet under the hips.
        let name = guide.exerciseName
        let top = guide.keyframes.first?.pose.angles ?? [:]
        var half = hip.x + 0.47 * sin((top["hipAbd"] ?? 15) * .pi / 180)
        var out = top["hipRot"] ?? 20
        if name.contains("sumo"), guide.subtypeID != "sumo" { (half, out) = (hip.x + 0.235, 40) }
        if carry == .sides { (half, out) = (hip.x + 0.05, 12) }
        if hinge { (half, out) = (hip.x + 0.07, 12) }
        if name.contains("narrow") { (half, out) = (hip.x + 0.03, 8) }
        let feet = [("r", -1.0), ("l", 1.0)].compactMap { body.footprint($0.0, x: $0.1 * half, y: 0, turnout: out) }
        guard feet.count == 2 else { return nil }
        lifter = Lifter(body: body, carry: carry, depth: LegDepth(guide.keyframes), feet: feet, turnout: out,
                        grips: grips, sitBack: hinge ? 0.24 : 0.35)

        var kinds = carry.kinds
        // A box squat goes down until the hips touch the box or bench behind.
        var pieces: [PropPiece] = []
        if guide.subtypeID == "box", let deepest = guide.keyframes.max(by: {
            ($0.pose.angles["kneeFlex"] ?? 0) < ($1.pose.angles["kneeFlex"] ?? 0)
        }), let seat = lifter.solve(deepest.pose).frame.heads["pelvis"] {
            let top = seat[2] - 0.105
            if name.contains("bench") {
                kinds.append(.bench)
                let front = seat[1] - 0.09, back = seat[1] + 1.0
                pieces.append(Plan.box(V(0, (front + back) / 2, top - 0.04), (0.3, back - front, 0.08), .pad))
                for y in [front + 0.12, back - 0.12] {
                    pieces.append(Plan.box(V(0, y, (top - 0.08) / 2), (0.24, 0.05, top - 0.08), .metal))
                }
            } else {
                kinds.append(.box)
                pieces.append(Plan.box(V(0, seat[1] + 0.15, top / 2), (0.5, 0.45, top), .wood))
            }
        }
        // A bar squatted with comes off a stand: behind the lifter, who has stepped out of it,
        // far enough back for the hips to sit down in front of its uprights' line and for
        // the bar and its plates to pass clear of the hooks. The hooks are a little under
        // the bar as it rides when the lifter stands tall.
        if !hinge, guide.subtypeID != "box", carry == .back || carry == .front,
           let first = guide.keyframes.first, let top = lifter.solve(first.pose).held.first {
            var back = top.y + 0.42
            for key in guide.keyframes {
                let (frame, held) = lifter.solve(key.pose)
                back = max(back, (held.first?.y ?? top.y) + 0.42, (frame.heads["pelvis"]?[1] ?? 0) + 0.2)
            }
            pieces += LegWeights.rack(y: back, height: top.z - 0.07)
        }
        self.kinds = kinds
        fixed = pieces
    }

    /// Which squat this is, or nil for one this staging does not show honestly. Every word of
    /// the name must be one this staging knows the meaning of.
    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        guard [nil, "sumo", "box", "front", "overhead"].contains(guide.subtypeID) else { return nil }
        if guide.subtypeID == "overhead" {
            // Arms locked overhead the whole way down and up, with or without a weight in the hands.
            switch guide.equipment {
            case "barbell": return words == ["barbell", "overhead", "squat"] ? .overhead(.bar) : nil
            case "dumbbell": return words == ["dumbbell", "overhead", "squat"] ? .overhead(.dumbbells) : nil
            case nil: return words.isSubset(of: ["bodyweight", "overhead", "squat", "arms"]) ? .overhead(.hands) : nil
            default: return nil
            }
        }
        // A box or bench is only drawn for the box squat's own, shallower movement.
        if guide.subtypeID != "box", !words.isDisjoint(with: ["box", "bench"]) { return nil }
        let front = guide.subtypeID == "front"
        let plain: Set<String> = ["squat", "squats", "full", "narrow", "stance", "wide", "sumo", "box", "bench", "quarter",
                                  "pulse", "pause", "v", "version", "2", "sec", "hold"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        switch guide.equipment {
        case "barbell":
            if front {
                return words.contains("front") && only("barbell", "front", "clean", "grip", "chest", "weighted") ? .front : nil
            }
            return only("barbell", "speed", "olympic", "high", "low", "bar", "with", "rack", "back", "side", "pov", "form",
                        "check", "knees", "hips", "end", "middle", "position") ? .back : nil
        case "dumbbell":
            if words.contains("goblet") { return only("dumbbell", "goblet") ? .goblet(kettlebell: false) : nil }
            return !front && guide.subtypeID != "sumo" && only("dumbbell", "dumbbells") ? .sides : nil
        case "kettlebell":
            return words.contains("goblet") && only("kettlebell", "goblet") ? .goblet(kettlebell: true) : nil
        case nil:
            return !front && only("air", "bodyweight", "deep", "knee", "bend") ? .free : nil
        default: return nil
        }
    }

    /// A standing good morning with the bar on the upper back.
    static func hinge(for guide: HowToGuide) -> LegLoad? {
        guard guide.subtypeID == "good-morning", guide.equipment == "barbell" else { return nil }
        return LegLoad.words(guide).isSubset(of: ["barbell", "good", "morning", "stiff", "leg"]) ? .back : nil
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = lifter.solve(pose)
        return (frame, lifter.carry.props(held))
    }
}

// MARK: - Standing calf raise

/// A standing calf raise: the balls of the feet on the edge of a low step (or on the floor),
/// the heels dropping below it and rising as far as the keyframes point the ankles. The body
/// stays long and goes straight up and down over the balls of the feet. On one leg it is the
/// right foot that stands, under the middle of the body, with the left held up behind.
struct CalfRaiseStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    static let stepHeight = 0.1

    let body: Body3D
    let carry: LegLoad
    let feet: [LegFootprint]
    let grips: [String: HandGrip]
    /// With no step under the toes the heels stop at the floor.
    let onFloor: Bool
    /// On the right leg alone.
    let single: Bool
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.subtypeID == nil, let carry = Self.carry(for: guide), let grips = carry.grips(body),
              let hip = body.head["femur.l"] else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        onFloor = guide.exerciseName.contains("floor")
        single = !LegLoad.words(guide).isDisjoint(with: ["single", "one"])
        let top = onFloor ? 0 : Self.stepHeight
        feet = single ? [body.footprint("r", x: -0.035, y: 0, turnout: 6, floor: top)].compactMap { $0 }
            : [("r", -1.0), ("l", 1.0)].compactMap { body.footprint($0.0, x: $0.1 * (hip.x + 0.015), y: 0, turnout: 8, floor: top) }
        guard feet.count == (single ? 1 : 2) else { return nil }
        var pieces: [PropPiece] = []
        if !onFloor {
            // The step's edge is just behind the balls of the feet, so the heels hang free.
            let edge = feet.map(\.ball.y).reduce(0, +) / Double(feet.count) + 0.035
            pieces.append(PropPlan.box(V(0, edge - 0.15, top / 2), (0.6, 0.3, top), .wood))
        }
        fixed = pieces
        kinds = carry.kinds + (onFloor ? [] : [.step])
    }

    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        var plain: Set<String> = ["standing", "calf", "calves", "raise", "raises", "v", "2", "pulse"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        // "single leg" or "one leg", off a step or on the floor.
        if words.isSuperset(of: ["single", "leg"]) || words.isSuperset(of: ["one", "leg"]) {
            guard guide.equipment != "barbell" else { return nil }
            plain.formUnion(["single", "one", "leg", "off", "step"])
        }
        switch guide.equipment {
        case nil: return only("bodyweight", "elevated", "on", "a", "staircase", "floor") ? .free : nil
        case "dumbbell": return only("dumbbell") ? .sides : nil
        case "barbell": return only("barbell", "leg", "floor") ? .back : nil
        default: return nil
        }
    }

    /// The body, and where its weights are.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        carry.ready(&pose)
        // The leg that does not stand is folded up behind.
        if single { pose.angles.merge(["kneeFlexL": 75, "hipFlexL": 0, "ankleDorsiL": -10]) { $1 } }
        var g = body.rotations(pose)
        let carried = carry.load(g, body.place(g, root: V(0, 0, 0)))
        // The keyframes' ankle angle tips the foot about its ball: heel under the step's level
        // at the stretch, high above it at the top.
        let point = -(pose.angles["ankleDorsi"] ?? 0)
        // The weight stays over the front of the feet, a little further forward as the ankles
        // come up over the toes, so the body rises straight instead of rocking.
        let over = feet.map(\.ball.y).reduce(0, +) / Double(feet.count) + 0.03 - 0.05 * min(1, max(0, (point + 15) / 55))
        var h = body.stand(&g, on: feet, knee: pose.angles["kneeFlex"] ?? 0, kneeTurn: 8,
                           heel: onFloor ? max(0, point) : point, load: carried, over: over)
        let root = h["pelvis"] ?? V(0, 0, 0)
        let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        return (frame, carry.props(held))
    }
}

// MARK: - Two feet at different places

extension Body3D {
    /// The higher of the two points that are `r1` from `a` and `r2` from `b`, all in the plane
    /// the body moves forward in (x is ignored). Two points too far apart for that give the
    /// point between them that keeps the two distances in proportion.
    static func apex(_ a: V, _ r1: Double, _ b: V, _ r2: Double) -> V {
        let d = V(0, b.y - a.y, b.z - a.z)
        let far = d.length
        guard far > 1e-6 else { return V(0, a.y, a.z + r1) }
        let along = d * (1 / far)
        guard far < r1 + r2 else { return V(0, a.y, a.z) + along * (far * r1 / (r1 + r2)) }
        let x = min(r1, max(-r1, (r1 * r1 - r2 * r2 + far * far) / (2 * far)))
        var up = V(0, -along.z, along.y)
        if up.z < 0 { up = up * -1 }
        return V(0, a.y, a.z) + along * x + up * max(0, r1 * r1 - x * x).squareRoot()
    }
}

// MARK: - Step-up

/// A step-up onto a box: the right foot flat on the box the whole time, the left on the floor
/// behind it at the start. The right leg lifts the body until it stands on the box, the left
/// leg hanging beside it, and lowers it until the left foot is back on the floor.
struct StepUpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    static let boxTop = 0.3, benchTop = 0.4
    /// The box's near face, behind the heel of the foot that stands on it.
    static let boxBack = 0.09

    let body: Body3D
    let carry: LegLoad
    let depth: LegDepth
    let front: LegFootprint, back: LegFootprint
    let grips: [String: HandGrip]
    /// The height of what is stepped onto.
    let top: Double
    /// How far behind the box foot's ankle the hips are with the floor foot down, and at the top.
    let startY: Double, topY = -0.03
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let bench = LegLoad.words(guide).contains("bench")
        let top = bench ? Self.benchTop : Self.boxTop
        guard guide.subtypeID == nil, let carry = Self.carry(for: guide), let grips = carry.grips(body),
              let hip = body.head["femur.l"], let knee = body.head["shin.l"], let ankle = body.head["foot.l"],
              let front = body.footprint("r", x: -(hip.x + 0.015), y: 0, turnout: 6, floor: top),
              let back = body.footprint("l", x: hip.x + 0.015, y: Self.boxBack + 0.25, turnout: 6),
              let deepest = guide.keyframes.max(by: { ($0.pose.angles["kneeFlex"] ?? 0) < ($1.pose.angles["kneeFlex"] ?? 0) })
        else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        self.front = front
        self.back = back
        self.top = top
        depth = LegDepth(guide.keyframes)
        kinds = carry.kinds + [bench ? .bench : .box]
        if bench {
            // A flat bench stepped onto from its side.
            var pieces = [PropPlan.box(V(0, Self.boxBack - 0.15, top - 0.04), (1.1, 0.3, 0.08), .pad)]
            for x in [-0.43, 0.43] {
                pieces.append(PropPlan.box(V(x, Self.boxBack - 0.15, (top - 0.08) / 2), (0.05, 0.24, top - 0.08), .metal))
            }
            fixed = pieces
        } else {
            fixed = [PropPlan.box(V(0, Self.boxBack - 0.225, top / 2), (0.5, 0.45, top), .wood)]
        }
        // At the start both feet are down: the hips are where the box knee has its deepest bend
        // and the floor leg is all but straight.
        let thigh = (knee - hip).length, shin = (ankle - knee).length
        let a = deepest.pose.angles
        let start = Body3D.apex(front.ankle, Body3D.span(thigh, shin, bend: a["kneeFlex"] ?? 90),
                                back.ankle, Body3D.span(thigh, shin, bend: max(4, a["kneeFlexL"] ?? 5)))
        startY = start.y
    }

    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        // "single leg" is the same climb, done on one leg at a time.
        let plain: Set<String> = ["step", "up", "on", "box", "stepbox", "bench", "single", "leg", "v", "2"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        switch guide.equipment {
        case nil: return only("bodyweight") ? .free : nil
        case "dumbbell": return only("dumbbell") ? .sides : nil
        case "barbell": return only("barbell") ? .back : nil
        default: return nil
        }
    }

    /// The body, and where its weights are.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        carry.ready(&pose)
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let carried = carry.load(g, rel)
        let u = depth(pose)
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let tip = body.tail["toes.r"], let hipF = rel["femur.r"] else { return (body.made(g, rel, floor: 0), []) }

        // The box foot stays flat unless its heel lifts by mistake. The hips are as far above it
        // as its knee's bend leaves them, coming forward over it as the knee straightens.
        let lead = body.lifted(front, heel: min(30, max(0, -depth.off("ankleDorsi", pose) - 3) * 1.5))
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: max(1, pose.angles["kneeFlex"] ?? 0))
        let y = topY + (startY - topY) * u
        let dx = hipF.x - lead.ankle.x, dy = y + hipF.y - lead.ankle.y
        var root = V(0, y, lead.ankle.z + max(0, leg * leg - dx * dx - dy * dy).squareRoot() - hipF.z)
        var h = body.place(g, root: root)

        // The other foot stands on the floor at the start, then hangs from the hip as the
        // keyframes swing it (less far back than a stride would), level, and never through the box.
        let off = min(1, (1 - u) / 0.35), swing = off * off * (3 - 2 * off)
        var hung = h["foot.l"] ?? back.ankle
        if let hip = h["femur.l"], hung.y > hip.y { hung.y = hip.y + (hung.y - hip.y) * 0.55 }
        var trail = mix(back.ankle, hung, swing)
        trail.z = max(trail.z, back.ankle.z)
        let over = min(1, max(0, (trail.z - back.ankle.z - top - 0.005) / 0.03))
        let toes = (rAnkle - tip).flat.length + 0.03
        trail.y = max(trail.y, (Self.boxBack + toes) * (1 - over) - over)
        // Onto something high the hips start no higher than the leg on the floor is long,
        // and the knee on top bends the more for it.
        if let hipB = rel["femur.l"] {
            let most = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: 3)
            for _ in 0..<4 {
                let hip = root + hipB, d = (hip - trail).length
                if d > most { root.z -= (d * d - most * most) / (2 * max(0.2, hip.z - trail.z)) }
            }
            h = body.place(g, root: root)
        }
        // Pushing off the floor foot by mistake points it.
        let pushed = min(40, max(0, -(pose.angles["ankleDorsiL"] ?? 0) - 12))
        let turn = (6 + depth.off("hipAbd", pose) + depth.off("hipRot", pose)) * .pi / 180
        body.plant("r", ankle: lead.ankle, foot: lead.foot, pole: V(-sin(turn), -cos(turn), 0), &g, h)
        body.plant("l", ankle: trail, foot: M.axis(V(0, 0, 1).cross(back.toe), pushed) * back.turn, pole: V(0, -1, 0), &g, h)
        g["toes.r"] = front.turn
        g["toes.l"] = back.turn
        h = body.place(g, root: root)
        let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        return (frame, carry.props(held))
    }
}

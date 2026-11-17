import Foundation

/// The balls of both feet on the edge of a foot bar, so the heels can drop below it and rise
/// above it: where each ball rests, the foot's rotation when it is level, and the ankle that
/// follows from how far the heel has come up.
struct MachineToeHold: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    let body: Body3D
    let balls: [String: V]
    let level: [String: M]

    /// Feet `half` either side of the middle with the balls at `y`, on a bar whose top is `top`.
    init?(_ body: Body3D, half: Double, y: Double, top: Double, turnout: Double = 8) {
        var balls: [String: V] = [:], level: [String: M] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let ankle = body.head["foot.\(s)"], let ball = body.head["toes.\(s)"], let tip = body.tail["toes.\(s)"]
            else { return nil }
            // The foot already points a little outward at rest.
            let heading = atan2(-m * (tip.x - ankle.x), -(tip.y - ankle.y)) * 180 / .pi
            let turn = M.z(-m * (turnout - heading))
            level[s] = turn
            let at = turn * (ball - ankle)
            balls[s] = V(-m * half + at.x, y, top + body.ankleHeight + at.z)
        }
        self.body = body
        self.balls = balls
        self.level = level
    }

    /// The foot of side `s` with its heel `heel` degrees above level (below, when negative):
    /// its rotation and where its ankle is.
    func foot(_ s: String, heel: Double) -> (turn: M, ankle: V) {
        guard let level = level[s], let at = balls[s], let ankle = body.head["foot.\(s)"],
              let ball = body.head["toes.\(s)"], let tip = body.tail["toes.\(s)"] else { return (.identity, V(0, 0, 0)) }
        let toe = level * (tip - ball)
        let turn = M.axis(V(0, 0, 1).cross(V(toe.x, toe.y, 0)), heel) * level
        return (turn, at + turn * (ankle - ball))
    }

    /// The bar itself: its edge just behind the balls of the feet, on a foot each side.
    func bar(top: Double) -> [PropPiece] {
        guard let r = balls["r"], let l = balls["l"] else { return [] }
        let y = (r.y + l.y) / 2 - 0.02
        var p = [PropPlan.box(V(0, y, top - 0.02), (0.56, 0.11, 0.04), .dark)]
        for x in [-0.24, 0.24] { p.append(PropPlan.box(V(x, y, (top - 0.04) / 2), (0.05, 0.09, top - 0.04), .metal)) }
        return p
    }
}

// MARK: - Seated calf raise

/// A seated calf raise: hips on a small seat, the balls of the feet on the foot bar, a pad
/// across the thighs just behind the knees. The heels drop and rise; the knees go up and down
/// with them and carry the pad, its lever and the weight on it. The hands rest on the pad's grips.
struct MachineSeatedCalfStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let barTop = 0.14, roller = 0.05, gripRadius = 0.015, armX = 0.3

    let body: Body3D
    let range: MachineRange
    let grips: [String: HandGrip]
    let toes: MachineToeHold
    let hip: V
    /// Where the pad's lever turns, in front of the knees.
    let pivot: V
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.familyID == "calf-raise", guide.subtypeID == "seated", words.contains("raise"),
              words.isSubset(of: ["lever", "seated", "calf", "raise", "plate", "loaded", "v", "2"]),
              let r = body.grip("r", radius: Self.gripRadius, square: 0.6), let l = body.grip("l", radius: Self.gripRadius, square: 0.6),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let rBall = body.head["toes.r"], let pelvis = body.head["pelvis"]
        else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, "ankleDorsi")
        // Thighs level and shins upright when the feet are level on the bar.
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
        let hip = V(0, 0, Self.barTop + body.ankleHeight + shin)
        self.hip = hip
        let half = pelvis.x - rHip.x + 0.01
        guard let toes = MachineToeHold(body, half: half, y: -thigh - (rAnkle.y - rBall.y), top: Self.barTop) else { return nil }
        self.toes = toes

        var p = toes.bar(top: Self.barTop)
        // The seat on its post, and the frame forward to the post the lever turns on.
        let seat = hip.z - MachineFit.seat
        p.append(Plan.box(V(0, 0.03, seat - 0.035), (0.38, 0.32, 0.07), .pad))
        p.append(Plan.box(V(0, 0.03, (seat - 0.07) / 2), (0.08, 0.08, seat - 0.07), .metal))
        p.append(Plan.box(V(0, 0.03, 0.02), (0.5, 0.07, 0.04), .metal))
        let pad = Self.pad(body, hip: hip, knees: ["r": V(-half, -thigh, hip.z), "l": V(half, -thigh, hip.z)])
        pivot = V(0, pad.y - 0.62, pad.z)
        p.append(Plan.box(V(0, (0.1 + pivot.y) / 2, 0.02), (0.08, 0.1 - pivot.y, 0.04), .metal))
        p.append(Plan.box(V(0, pivot.y, 0.02), (0.6, 0.07, 0.04), .metal))
        for x in [-Self.armX - 0.04, Self.armX + 0.04] {
            p.append(Plan.rod(V(x, pivot.y, 0.02), V(x, pivot.y, pivot.z), 0.025, .metal))
        }
        p.append(Plan.rod(pivot - V(Self.armX + 0.04, 0, 0), pivot + V(Self.armX + 0.04, 0, 0), 0.02, .metal))
        fixed = p
    }

    /// The middle of the thigh pad for knees at `knees`: across the thighs a hand behind the
    /// knees, lying on top of them.
    static func pad(_ body: Body3D, hip: V, knees: [String: V]) -> V {
        var sum = V(0, 0, 0), n = 0.0
        for s in ["r", "l"] {
            guard let knee = knees[s], let rHip = body.head["femur.\(s)"], let pelvis = body.head["pelvis"] else { continue }
            let along = (knee - (hip + V(rHip.x - pelvis.x, 0, 0))).unit
            let over = V(0, along.z, -along.y)
            sum = sum + knee - along * 0.1 + over * (MachineFit.thighTop - 0.008 + roller)
            n += 1
        }
        let mid = sum * (1 / max(1, n))
        return V(0, mid.y, mid.z)
    }

    /// The posed body, and the middle of the thigh pad.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, pad: V) {
        var g = body.rotations(pose)
        var h = body.place(g, root: hip)
        let heel = -(pose.angles["ankleDorsi"] ?? 0)
        for s in ["r", "l"] {
            let foot = toes.foot(s, heel: heel)
            body.plant(s, ankle: foot.ankle, foot: foot.turn, pole: V(0, -0.3, 1), &g, h)
            // The toes stay flat on the bar.
            if let level = toes.level[s] { g["toes.\(s)"] = level }
        }
        h = body.place(g, root: hip)
        let pad = Self.pad(body, hip: hip, knees: ["r": h["shin.r"] ?? hip, "l": h["shin.l"] ?? hip])
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: handle(pad, m), across: V(-m, 0, 0), pole: V(-m * 0.7, 0.5, -0.5), &g, h)
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), pad)
    }

    /// The grip on the pad's axle outside each thigh.
    func handle(_ pad: V, _ m: Double) -> V { pad + V(-m * 0.255, 0, 0.0) }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, pad) = solve(pose)
        var p = [Plan.disc(pad, axis: V(1, 0, 0), radius: Self.roller, thickness: 0.4, .pad),
                 Plan.rod(pad - V(Self.armX, 0, 0), pad + V(Self.armX, 0, 0), 0.012, .metal)]
        for m in [-1.0, 1.0] {
            let end = pad + V(m * Self.armX, 0, 0), hinge = pivot + V(m * Self.armX, 0, 0)
            p.append(Plan.rod(pad + V(m * 0.21, 0, 0), pad + V(m * 0.295, 0, 0), Self.gripRadius, .dark))
            p.append(Plan.rod(end, hinge, 0.018, .metal))
            p.append(Plan.ball(end, 0.018, .metal))
        }
        // The weight: plates on a peg between the lever's arms, out in front of the knees.
        let peg = mix(pad, pivot, 0.52)
        p.append(Plan.rod(peg - V(Self.armX, 0, 0), peg + V(Self.armX, 0, 0), 0.02, .metal))
        for x in [-0.045, 0.045] { p.append(Plan.disc(peg + V(x, 0, 0), axis: V(1, 0, 0), radius: 0.15, thickness: 0.06, .plate)) }
        return (frame, p)
    }
}

// MARK: - Standing calf raise

/// A standing calf raise in its machine: the balls of the feet on the foot bar, the shoulders
/// under two pads on a lever that turns on the column behind, hands on the grips in front of
/// the pads. The body stays long and goes straight up and down; the pads ride on the shoulders.
struct MachineStandingCalfStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let barTop = 0.14, gripRadius = 0.015, column = 0.62

    let body: Body3D
    let range: MachineRange
    let grips: [String: HandGrip]
    let toes: MachineToeHold
    /// The height of the lever's hinge on the column.
    let hinge: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.familyID == "calf-raise", guide.subtypeID == nil,
              words.isSubset(of: ["lever", "standing", "calf", "raise", "bench", "press", "machine"]),
              !words.isDisjoint(with: ["standing", "bench"]),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let rHip = body.head["femur.r"], let pelvis = body.head["pelvis"],
              let toes = MachineToeHold(body, half: pelvis.x - rHip.x + 0.015, y: 0, top: Self.barTop) else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, "ankleDorsi")
        self.toes = toes
        fixed = toes.bar(top: Self.barTop) + Self.tower()
        // The hinge is level with the pads halfway up, so they travel all but straight.
        var heights: [Double] = []
        for key in guide.keyframes {
            let pose = key.pose
            var g = body.rotations(pose)
            let h = Self.stand(body, toes, pose, &g)
            heights.append(Self.pads(body, g, h).r.z)
        }
        hinge = ((heights.min() ?? 1.5) + (heights.max() ?? 1.5)) / 2
    }

    /// Stands the posed body on the foot bar and returns the bone heads.
    static func stand(_ body: Body3D, _ toes: MachineToeHold, _ pose: JointPose, _ g: inout [String: M]) -> [String: V] {
        let rel = body.place(g, root: V(0, 0, 0))
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let hip = rel["femur.r"] else { return rel }
        let heel = -(pose.angles["ankleDorsi"] ?? 0)
        let right = toes.foot("r", heel: heel)
        // The hips stay over the balls of the feet, so the body rises straight.
        let ball = toes.balls["r"] ?? right.ankle
        let y = ball.y + 0.06
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: max(1, pose.angles["kneeFlex"] ?? 0))
        let dx = hip.x - right.ankle.x, dy = y + hip.y - right.ankle.y
        let root = V(0, y, right.ankle.z + max(0, leg * leg - dx * dx - dy * dy).squareRoot() - hip.z)
        let h = body.place(g, root: root)
        for s in ["r", "l"] {
            let foot = toes.foot(s, heel: heel)
            body.plant(s, ankle: foot.ankle, foot: foot.turn, pole: V(0, -1, 0), &g, h)
            if let level = toes.level[s] { g["toes.\(s)"] = level }
        }
        return body.place(g, root: root)
    }

    /// The middle of the underside of each shoulder pad: on the muscle between the neck and
    /// the point of the shoulder.
    static func pads(_ body: Body3D, _ g: [String: M], _ h: [String: V]) -> (r: V, l: V) {
        func one(_ s: String, _ m: Double) -> V {
            let tip = h["scapula.\(s)"] ?? h["neck"] ?? V(0, 0, 1.45)
            let neck = h["neck"] ?? tip
            return V(-m * 0.15, neck.y + 0.015, tip.z + 0.028)
        }
        return (one("r", 1), one("l", -1))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var pose = pose
        // Arms up to the grips: the shoulder blades follow.
        pose.scapula = nil
        var g = body.rotations(pose)
        var h = Self.stand(body, toes, pose, &g)
        let root = h["pelvis"] ?? V(0, 0, 1)
        let p = Self.yoke(body, grips, hinge: hinge, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), p)
    }

    /// The two shoulder pads on their arms from the column's hinge, each with a grip in front
    /// that its hand closes on.
    static func yoke(_ body: Body3D, _ grips: [String: HandGrip], hinge: Double, column: Double = MachineStandingCalfStaging.column,
                     _ g: inout [String: M], _ h: [String: V]) -> [PropPiece] {
        let pads = Self.pads(body, g, h)
        var p: [PropPiece] = []
        for (s, m, pad) in [("r", 1.0, pads.r), ("l", -1.0, pads.l)] {
            p.append(Plan.box(pad + V(0, 0, 0.035), (0.11, 0.17, 0.07), .pad))
            // Each pad on its own arm from the hinge, with a grip out in front.
            let top = pad + V(0, 0, 0.085)
            p.append(Plan.rod(top + V(0, -0.2, 0), V(pad.x, column, hinge + 0.085), 0.02, .metal))
            let grip = top + V(-m * 0.09, -0.2, -0.085)
            p.append(Plan.rod(top + V(0, -0.2, 0), grip + V(0, 0, 0.07), 0.012, .metal))
            p.append(Plan.rod(grip + V(0, 0, 0.07), grip - V(0, 0, 0.07), Self.gripRadius, .dark))
            if let hand = grips[s] {
                body.hold(s, hand, at: grip, across: V(0, 0, -1), pole: V(-m * 0.5, 0.2, -1), &g, h)
            }
        }
        p.append(Plan.rod(V(-0.2, column, hinge + 0.085), V(0.2, column, hinge + 0.085), 0.025, .metal))
        return p
    }

    /// The column behind the lifter, with the weight stack in it, on a foot that runs under them.
    static func tower(_ y: Double = MachineStandingCalfStaging.column) -> [PropPiece] {
        return [Plan.box(V(0, y, 0.95), (0.1, 0.1, 1.9), .metal),
                Plan.box(V(0, y + 0.12, 0.6), (0.26, 0.12, 1.1), .dark),
                Plan.box(V(0, y / 2 - 0.1, 0.02), (0.09, y + 0.3, 0.04), .metal),
                Plan.box(V(0, y, 0.02), (0.6, 0.08, 0.04), .metal)]
    }
}

// MARK: - Squat under the same yoke

/// A squat in a lever machine: standing on the floor with the shoulders under two pads on a
/// lever that turns on the column behind, hands on the grips in front of the pads. The squat
/// itself is the one done with no load; the pads ride the shoulders down and up.
struct MachineLeverSquatStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The column stands clear of hips that go back as the knees bend.
    static let column = 0.95

    let body: Body3D
    let inner: any BodyStaging
    let grips: [String: HandGrip]
    let hinge: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.equipment == "machine", guide.familyID == "squat", guide.subtypeID == nil, words.contains("squat"),
              words.isSubset(of: ["lever", "full", "squat", "plate", "loaded"]) else { return nil }
        var free = guide
        free.equipment = nil
        free.exerciseName = "bodyweight squat"
        guard let inner = Stagings.make(free, body),
              let r = body.grip("r", radius: MachineStandingCalfStaging.gripRadius),
              let l = body.grip("l", radius: MachineStandingCalfStaging.gripRadius) else { return nil }
        self.body = body
        self.inner = inner
        grips = ["r": r, "l": l]
        // The hinge is level with the pads halfway down, so the arms' reach changes least.
        var heights: [Double] = []
        for key in guide.keyframes {
            let made = inner.frame(key.pose).body
            let g = made.rotations.mapValues { M($0) }, h = made.heads.mapValues { V($0) }
            heights.append(MachineStandingCalfStaging.pads(body, g, h).r.z)
        }
        hinge = ((heights.min() ?? 1.2) + (heights.max() ?? 1.5)) / 2
        fixed = inner.fixed + MachineStandingCalfStaging.tower(Self.column)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let made = inner.frame(pose)
        var g = made.body.rotations.mapValues { M($0) }
        var h = made.body.heads.mapValues { V($0) }
        guard let root = h["pelvis"] else { return made }
        let p = MachineStandingCalfStaging.yoke(body, grips, hinge: hinge, column: Self.column, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: made.body.floor), made.props + p)
    }
}

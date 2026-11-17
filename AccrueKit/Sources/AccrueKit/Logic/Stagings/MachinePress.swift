import Foundation

/// A machine's seat at chair height with a back pad behind it, and the body that sits in it:
/// hips on the seat, back on the pad, both feet flat on the floor.
struct MachineChair: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    let body: Body3D
    let rest: MachineRest
    let ankles: [String: V]

    /// A chair whose back pad leans back by `lean` degrees.
    init?(_ body: Body3D, lean: Double) {
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        // Thighs level and shins upright: the hips sit as high as the knees.
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
        let hip = V(0, 0, body.ankleHeight + shin)
        rest = MachineRest(body, hip: hip, lean: lean)
        let out = pelvis.x - rHip.x + 0.04
        ankles = ["r": V(-out, -thigh + 0.01, body.ankleHeight), "l": V(out, -thigh + 0.01, body.ankleHeight)]
    }

    /// The pose's rotations, bone heads and the pelvis's place, sitting with the feet planted.
    func sit(_ pose: JointPose, forward: Double = 0) -> (g: [String: M], h: [String: V], root: V) {
        var (g, h) = rest.settle(pose, forward: forward)
        let root = h["pelvis"] ?? rest.hip
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
        }
        h = body.place(g, root: root)
        return (g, h, root)
    }

    /// The seat on its post and the back pad on its spine, up to `top` above the hip joints.
    /// A machine the lifter faces has no back pad.
    func pieces(top: Double = 0.64, headRest: Bool = false, back hasBack: Bool = true) -> [PropPiece] {
        let hip = rest.hip
        let seat = hip.z - MachineFit.seat
        let back = MachineFit.back + 0.02
        var p = [Plan.box(V(0, (back - 0.3) / 2, seat - 0.035), (0.42, back + 0.3, 0.07), .pad),
                 Plan.box(V(0, -0.05, (seat - 0.07) / 2), (0.09, 0.09, seat - 0.07), .metal)]
        guard hasBack else { return p }
        p.append(rest.backPad(from: 0.02, to: top))
        if headRest {
            p.append(rest.backPad(from: top + 0.02, to: top + 0.24, width: 0.26, thick: 0.07 + MachineFit.back - MachineFit.head,
                                  proud: MachineFit.back - MachineFit.head))
        }
        let low = rest.behind(0.0, 0.1), high = rest.behind(top + (headRest ? 0.2 : -0.04), 0.1)
        p.append(Plan.box((low + high) * 0.5, (0.08, (high - low).length, 0.06), z: rest.out, .metal))
        p.append(Plan.rod(V(0, -0.02, seat - 0.06), low, 0.03, .metal))
        return p
    }
}

/// A seated machine press: chest press (level, inclined or declined) or shoulder press. The
/// body sits against the back pad with its feet on the floor; each hand holds a handle on a
/// lever arm, and the arms swing about one axle as the elbows straighten, so the handles
/// travel on an arc that the machine fixes, not the hands. A weight stack behind rises with them.
struct MachinePressStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Which press this is.
    struct Setup: Sendable, Equatable {
        /// How far the back pad leans back, and how far the line of the press is tipped up
        /// from square to the chest, both in degrees.
        var lean = 10.0, pitch = 0.0
        /// Each hand's distance from the middle.
        var half = 0.3
        /// Handles that stand along the lever arms (palms facing in) instead of across them.
        var neutral = false
        var headRest = false
        /// The handles with the elbows bent, from the shoulder joints: out along the press
        /// and down across it.
        var near = 0.13, drop = 0.1
    }

    static let gripRadius = 0.016, stackHeight = 1.75
    /// The axle the arms turn on, from the shoulder joints: across the line of the press, and along it.
    static let axle = (across: 0.85, along: 0.1)

    let body: Body3D
    let setup: Setup
    let chair: MachineChair
    let progress: PullProgress
    let grips: [String: HandGrip]
    /// The line of the press and the direction square to it, toward the axle.
    let along: V, across: V
    /// The axle's middle, the arms' length, and their swing with the elbows bent and straight.
    let pivot: V
    let radius: Double
    let swing: (near: Double, far: Double)
    let column: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let setup = Self.setup(for: guide), let chair = MachineChair(body, lean: setup.lean),
              let r = body.grip("r", radius: Self.gripRadius, square: setup.neutral ? 0 : 0.5),
              let l = body.grip("l", radius: Self.gripRadius, square: setup.neutral ? 0 : 0.5),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.setup = setup
        self.chair = chair
        grips = ["r": r, "l": l]
        progress = PullProgress(guide.keyframes)
        let rest = chair.rest
        let p = setup.pitch * .pi / 180
        let along = rest.out * cos(p) + rest.up * sin(p), across = rest.up * cos(p) - rest.out * sin(p)
        self.along = along
        self.across = across

        // The machine is set to the shoulders: the axle, and where the handles start and end.
        let seated = chair.sit(first)
        let shoulders = ["r", "l"].compactMap { seated.h["humerus.\($0)"] }
        guard shoulders.count == 2 else { return nil }
        var mid = (shoulders[0] + shoulders[1]) * 0.5
        mid.x = 0
        let wide = abs(shoulders[0].x - shoulders[1].x) / 2
        let pivot = mid + across * Self.axle.across + along * Self.axle.along
        self.pivot = pivot
        let start = mid + along * setup.near - across * setup.drop
        radius = (start - pivot).length
        func angle(_ at: V) -> Double { atan2((at - pivot).dot(along), -(at - pivot).dot(across)) }
        let near = angle(start)
        // Arms long: as far round as the hands reach with the elbows all but straight.
        let reach = body.reach("r", r, bend: max(8, progress.low))
        let lateral = setup.half - wide
        var lo = near, hi = near + .pi / 2
        for _ in 0..<30 {
            let a = (lo + hi) / 2
            let at = pivot + (along * sin(a) - across * cos(a)) * radius
            if (at - mid).length * (at - mid).length + lateral * lateral < reach * reach { lo = a } else { hi = a }
        }
        swing = (near, lo)

        // The frame: two uprights behind the seat up to the axle, the stack behind them.
        var pieces = chair.pieces(top: setup.headRest ? 0.62 : 0.64, headRest: setup.headRest)
        let reachBack = rest.behind(0.3, 0.2).y
        let column = max(pivot.y, reachBack + 0.12)
        self.column = column
        let armX = Self.armX(setup)
        for x in [-armX - 0.05, armX + 0.05] {
            let top = V(x, column, max(pivot.z, 1.0) + 0.04)
            pieces.append(Plan.box(V(x, column, top.z / 2), (0.07, 0.07, top.z), .metal))
            pieces.append(Plan.box(V(x, column - 0.25, 0.02), (0.07, 1.0, 0.04), .metal))
            if pivot.y < column - 0.01 { pieces.append(Plan.rod(top - V(0, 0, 0.04), V(x, pivot.y, pivot.z), 0.03, .metal)) }
        }
        pieces.append(Plan.rod(pivot - V(armX + 0.05, 0, 0), pivot + V(armX + 0.05, 0, 0), 0.025, .metal))
        pieces.append(Plan.box(V(0, column, 0.02), (2 * armX + 0.17, 0.07, 0.04), .metal))
        pieces.append(Plan.box(V(0, (column + 0.38) / 2, 0.02), (0.08, column + 0.38 + 0.2, 0.04), .metal))
        pieces += stackFrame(y: column + 0.38, height: Self.stackHeight)
        fixed = pieces
    }

    /// The lever arms stand outside the hands when the handles lie across them.
    static func armX(_ setup: Setup) -> Double { setup.neutral ? setup.half : setup.half + 0.1 }

    /// Which press the name describes, or nil for one this machine does not show honestly.
    static func setup(for guide: HowToGuide) -> Setup? {
        let words = MachineStagings.words(guide)
        var setup = Setup()
        switch guide.familyID {
        case "bench-press":
            guard words.isSuperset(of: ["chest", "press"]),
                  words.isSubset(of: ["lever", "chest", "press", "v", "2", "4", "stack", "seated", "plate", "loaded",
                                      "incline", "decline", "parallel"]) else { return nil }
            switch guide.subtypeID {
            case "seated": break
            case "incline": (setup.lean, setup.pitch, setup.headRest) = (32, 6, true)
            case "decline": (setup.lean, setup.pitch, setup.drop) = (8, -22, 0.13)
            default: return nil
            }
            if words.contains("parallel") { (setup.neutral, setup.half) = (true, 0.25) }
        case "overhead-press":
            guard guide.subtypeID == "seated", words.contains("press"),
                  words.isSubset(of: ["lever", "military", "shoulder", "press", "v", "2", "3", "seated", "hammer", "grip"])
            else { return nil }
            // Pressing straight up the line of the back pad: the axle is behind the shoulders.
            (setup.lean, setup.pitch, setup.near, setup.drop) = (8, 84, 0.1, 0.12)
            if words.contains("hammer") { (setup.neutral, setup.half) = (true, 0.26) }
        default: return nil
        }
        return setup
    }

    /// Where each hand's handle is when the arms have swung to `angle`, and the way the grip runs.
    func handle(_ m: Double, _ angle: Double) -> (at: V, grip: V) {
        let arm = along * sin(angle) - across * cos(angle)
        let at = pivot + arm * radius + V(-m * setup.half, 0, 0)
        return (at, setup.neutral ? arm : V(-m, 0, 0))
    }

    /// The posed body, and how far the arms have swung.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, angle: Double) {
        var (g, h, root) = chair.sit(pose)
        let angle = swing.far + (swing.near - swing.far) * progress(pose)
        let thorax = g["thorax"] ?? .identity
        // Elbows out as far as the keyframes flare them: under the hands for an overhead
        // press, behind them for a chest press.
        let flare = min(85, max(15, (pose.angles["shoulderAbd"] ?? 40) + (setup.neutral ? -15 : 10))) * .pi / 180
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            let handle = handle(m, angle)
            let pole = setup.pitch > 45 ? thorax * V(-m * sin(flare), 0.1, -cos(flare)) : thorax * V(-m * sin(flare), 0.25, -cos(flare))
            body.hold(s, grip, at: handle.at, across: handle.grip, pole: pole, &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), angle)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, angle) = solve(pose)
        var p: [PropPiece] = []
        let armX = Self.armX(setup)
        for m in [-1.0, 1.0] {
            let handle = handle(m, angle)
            let hinge = pivot + V(-m * armX, 0, 0)
            if setup.neutral {
                // The arm ends in the grip itself.
                let arm = (handle.at - hinge).unit
                p.append(Plan.rod(hinge, handle.at - arm * 0.07, 0.02, .metal))
                p.append(Plan.rod(handle.at - arm * 0.07, handle.at + arm * 0.07, Self.gripRadius, .dark))
            } else {
                // The arm comes down outside the hand, and the grip stands in from its end.
                let end = handle.at + V(-m * 0.1, 0, 0)
                p.append(Plan.rod(hinge, end, 0.02, .metal))
                p.append(Plan.ball(end, 0.02, .metal))
                p.append(Plan.rod(end, handle.at + V(m * 0.07, 0, 0), Self.gripRadius, .dark))
            }
        }
        // The plates the arms lift.
        let travel = radius * abs(angle - swing.near) * 0.6
        p += liftedPlates(y: column + 0.38, height: Self.stackHeight, travel: travel)
        return (frame, p)
    }
}

import Foundation

// MARK: - One-leg squat and pistol

/// A squat on the right leg alone. Its foot stays flat on one spot, under the middle of the
/// body; the hips sit back and down as far as the keyframes bend the knee, keeping the weight
/// over that foot; the other leg is held out in front as the keyframes hold it, clear of the
/// floor all the way down.
struct SingleLegSquatStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far the free foot stays off the floor.
    static let clear = 0.08

    let body: Body3D
    let carry: LegLoad
    let depth: LegDepth
    let foot: LegFootprint
    let grips: [String: HandGrip]
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "single-leg-squat", let carry = Self.carry(for: guide), let grips = carry.grips(body),
              let foot = body.footprint("r", x: -0.035, y: 0, turnout: 6) else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        self.foot = foot
        depth = LegDepth(guide.keyframes)
        kinds = carry.kinds
    }

    /// What is carried, or nil for a one-leg squat this staging does not show honestly: one
    /// that holds on to something, sits to a box, or keeps the free leg behind.
    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        var plain: Set<String> = ["one", "single", "leg", "squat"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        switch guide.subtypeID {
        case nil: break
        case "pistol": plain.formUnion(["pistol", "male"])
        default: return nil
        }
        switch guide.equipment {
        case nil: return only("bodyweight") ? .free : nil
        case "dumbbell": return only("dumbbell") ? .sides : nil
        case "barbell": return only("barbell") ? .back : nil
        // A kettlebell at the chest would hang into the leg held out under it.
        default: return nil
        }
    }

    /// The body, and where its weights are.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        carry.ready(&pose)
        var g = body.rotations(pose)
        let carried = carry.load(g, body.place(g, root: V(0, 0, 0)))
        // A knee that caves in points inside its toes; a heel that lifts leaves the floor.
        let turn = min(40, max(-25, 6 + depth.off("hipAbd", pose) + depth.off("hipRot", pose)))
        let heel = min(30, max(0, -depth.off("ankleDorsi", pose) - 3) * 1.5)
        var h = body.stand(&g, on: [foot], knee: pose.angles["kneeFlex"] ?? 0, kneeTurn: turn, heel: heel, load: carried, sitBack: 0.3)
        let root = h["pelvis"] ?? V(0, 0, 0)

        // The free leg is held as the keyframes hold it, and lifted where that would put its
        // foot on the floor or through it.
        if let ankle = h["foot.l"], let turned = g["foot.l"], let rAnkle = body.head["foot.l"], let rTip = body.tail["toes.l"] {
            let tip = ankle + turned * (rTip - rAnkle)
            let low = min(ankle.z - body.ankleHeight, tip.z - 0.02)
            if low < Self.clear {
                body.plant("l", ankle: ankle + V(0, 0, Self.clear - low), foot: turned, pole: V(0, -1, 0.3), &g, h)
                h = body.place(g, root: root)
            }
        }
        let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        return (frame, carry.props(held))
    }
}

// MARK: - Jump squat

/// A jump squat: a dip with both feet flat, a drive up onto the balls of the feet and off the
/// floor, a flight straight up, and a landing on the same two spots, balls of the feet first,
/// that sinks back into the squat. The keyframes give the legs, trunk and arms; how high the
/// body is off the floor comes from how long the keyframes leave it in the air.
struct JumpSquatStaging: LoopStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    let body: Body3D
    let carry: LegLoad
    let depth: LegDepth
    let feet: [LegFootprint]
    let turnout: Double
    let grips: [String: HandGrip]
    /// When the feet leave the floor and when they come back, and how high the jump goes.
    let off: Double, land: Double, height: Double
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "jump-squat-tuck", guide.subtypeID == nil, let carry = Self.carry(for: guide),
              let grips = carry.grips(body), let hip = body.head["femur.l"],
              let jump = guide.keyframes.first(where: { $0.phase == "Jump" }),
              let air = guide.keyframes.first(where: { $0.phase == "Air" }),
              let landing = guide.keyframes.first(where: { $0.phase == "Land" }), jump.t < air.t, air.t < landing.t
        else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        depth = LegDepth(guide.keyframes)
        // Feet under the hips, or outside dumbbells that hang beside the knees.
        let half = hip.x + (carry == .sides ? 0.05 : 0.07)
        turnout = 12
        feet = [("r", -1.0), ("l", 1.0)].compactMap { body.footprint($0.0, x: $0.1 * half, y: 0, turnout: 12) }
        guard feet.count == 2 else { return nil }
        // The feet leave as the legs come straight, and touch down a little before the
        // landing is at its deepest. A body in the air that long rises this far.
        off = jump.t
        land = air.t + 0.3 * (landing.t - air.t)
        let flight = (land - off) * guide.seconds
        height = min(0.35, 9.81 * flight * flight / 8)
        kinds = carry.kinds
    }

    /// What is carried, or nil for a jump this staging does not show honestly.
    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        let plain: Set<String> = ["jump", "jumping", "squat", "semi", "male", "v", "2"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        guard !words.isDisjoint(with: ["jump", "jumping"]), words.contains("squat") else { return nil }
        switch guide.equipment {
        case nil: return only("bodyweight") ? .free : nil
        case "dumbbell": return only("dumbbell") ? .sides : nil
        case "barbell": return only("barbell") ? .back : nil
        case "kettlebell": return only("kettlebell", "goblet") && words.contains("goblet") ? .goblet(kettlebell: true) : nil
        default: return nil
        }
    }

    /// How far off the floor the body is at moment `t` of the loop.
    func lift(at t: Double) -> Double {
        guard t > off, t < land else { return 0 }
        let s = (t - off) / (land - off)
        return 4 * height * s * (1 - s)
    }

    /// With no moment of the loop to go by, the feet are on the floor.
    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) { frame(pose, at: 0) }

    func frame(_ pose: JointPose, at t: Double) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose, at: t)
        return (frame, carry.props(held))
    }

    /// The body at moment `t` of the loop, and where its weights are.
    func solve(_ pose: JointPose, at t: Double) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        carry.ready(&pose)
        var g = body.rotations(pose)
        // Empty arms swing as the keyframes swing them, in one piece through overhead.
        if carry == .free { CardioFooting.steadyArms(body, &g, pose) }
        let carried = carry.load(g, body.place(g, root: V(0, 0, 0)))
        // Ankles that point lift the heels: at the end of the drive, in the air, and as the
        // balls of the feet touch down.
        let heel = min(40, max(0, -(pose.angles["ankleDorsi"] ?? 0)))
        let turn = min(50, max(-25, turnout + (pose.angles["hipAbd"] ?? 0) + (pose.angles["hipRot"] ?? 0)))
        var h = body.stand(&g, on: feet, knee: pose.angles["kneeFlex"] ?? 0, kneeTurn: turn, heel: heel, load: carried)
        let up = lift(at: t)
        let root = (h["pelvis"] ?? V(0, 0, 0)) + V(0, 0, up)
        // In the air the toes point with the foot; on the floor they lie flat under a raised heel.
        let loose = min(1, up / 0.04)
        for print in feet {
            g["toes.\(print.side)"] = M.axis(V(0, 0, 1).cross(print.toe), heel * loose) * print.turn
        }
        h = body.place(g, root: root)
        let held = carry.take(body, grips, at: carried.map { root + $0.at }, &g, h)
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }
}

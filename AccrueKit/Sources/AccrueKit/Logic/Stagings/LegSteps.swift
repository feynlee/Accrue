import Foundation

// MARK: - Step-up from the side

/// A step-up onto a box that stands beside the lifter: the right foot flat on the box the whole
/// time, the left on the floor next to it at the start. The hips begin beside the box over the
/// floor foot, move across over the box foot as its leg straightens, and come back down the same
/// way. The left leg hangs beside the box at the top, never over it or in it.
struct SideStepUpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    static let boxTop = 0.25

    let body: Body3D
    let carry: LegLoad
    let depth: LegDepth
    /// The foot on the box, and where the other one stands on the floor.
    let front: LegFootprint, back: LegFootprint
    let grips: [String: HandGrip]
    /// The side of the box that faces the floor foot.
    let face: Double
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "step-up", guide.subtypeID == "lateral", let carry = Self.carry(for: guide),
              let grips = carry.grips(body),
              let front = body.footprint("r", x: -0.16, y: 0, turnout: 8, floor: Self.boxTop),
              let back = body.footprint("l", x: 0.11, y: 0, turnout: 6) else { return nil }
        self.body = body
        self.carry = carry
        self.grips = grips
        self.front = front
        self.back = back
        depth = LegDepth(guide.keyframes)
        face = front.ankle.x + 0.065
        fixed = [PropPlan.box(V(face - 0.225, -0.06, Self.boxTop / 2), (0.45, 0.5, Self.boxTop), .wood)]
        kinds = carry.kinds + [.box]
    }

    /// What is carried, or nil for a side step-up with more to it than the step.
    static func carry(for guide: HowToGuide) -> LegLoad? {
        let words = LegLoad.words(guide)
        let plain: Set<String> = ["lateral", "side", "step", "up"]
        switch guide.equipment {
        case nil: return words.isSubset(of: plain.union(["bodyweight"])) ? .free : nil
        case "dumbbell": return words.isSubset(of: plain.union(["dumbbell"])) ? .sides : nil
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
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let hipF = rel["femur.r"], let hipB = rel["femur.l"], let footB = rel["foot.l"]
        else { return (body.made(g, rel, floor: 0), []) }
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length

        // The box foot stays flat unless its heel lifts by mistake. The hips are as far from it
        // as its knee's bend leaves them.
        let lead = body.lifted(front, heel: min(30, max(0, -depth.off("ankleDorsi", pose) - 3) * 1.5))
        let leg = Body3D.span(thigh, shin, bend: max(1, pose.angles["kneeFlex"] ?? 0))
        let most = Body3D.span(thigh, shin, bend: 3)
        // They cross from over the floor foot to over the box foot in the first part of the
        // rise, so the floor foot has little left to carry when it leaves.
        let up = 1 - depth(pose)
        let across = min(1, up / 0.6), over = across * across * (3 - 2 * across)
        let beside = back.ankle.x - hipB.x - 0.01, onTop = lead.ankle.x + 0.04
        let x = beside + (onTop - beside) * over
        // The floor foot stands until the hips are well over the box, then hangs from the hip
        // as the keyframes hold it: level, beside the box.
        let off = min(1, up / 0.35), swing = off * off * (3 - 2 * off)

        /// The hips for a body whose hips are `y` forward or back, and the floor foot's ankle.
        func settle(_ y: Double) -> (root: V, trail: V) {
            let dx = x + hipF.x - lead.ankle.x, dy = y + hipF.y - lead.ankle.y
            var root = V(x, y, lead.ankle.z + max(0.05, leg * leg - dx * dx - dy * dy).squareRoot() - hipF.z)
            var trail = back.ankle
            // Beside something this high the hips start no higher than the leg on the floor
            // is long, and the knee on the box bends the more for it.
            for _ in 0..<4 {
                var hung = root + footB
                hung.x = max(hung.x, face + 0.07)
                hung.z = max(hung.z, back.ankle.z)
                trail = mix(back.ankle, hung, swing)
                let hip = root + hipB, d = (hip - trail).length
                if d > most { root.z -= (d * d - most * most) / (2 * max(0.2, hip.z - trail.z)) }
            }
            return (root, trail)
        }
        // A box knee that caves in points inside its toes.
        let turn = (8 + depth.off("hipAbd", pose) + depth.off("hipRot", pose)) * .pi / 180
        func legs(_ at: (root: V, trail: V), _ g: inout [String: M]) {
            let h = body.place(g, root: at.root)
            body.plant("r", ankle: lead.ankle, foot: lead.foot, pole: V(-sin(turn), -cos(turn), 0), &g, h)
            body.plant("l", ankle: at.trail, foot: back.turn, pole: back.toe, &g, h)
            g["toes.r"] = front.turn
            g["toes.l"] = back.turn
        }

        // Forward and back, the hips sit where the weight is over the feet.
        let middle = lead.ankle.y - 0.055
        var y = middle
        for _ in 0..<4 {
            let at = settle(y)
            var trial = g
            legs(at, &trial)
            var weight = body.balance(trial, body.place(trial, root: at.root))
            if let carried { weight = (weight + (at.root + carried.at) * carried.mass) * (1 / (1 + carried.mass)) }
            y = min(middle + 0.3, max(middle - 0.2, y - (weight.y - middle)))
        }
        let at = settle(y)
        legs(at, &g)
        var h = body.place(g, root: at.root)
        let held = carry.take(body, grips, at: carried.map { at.root + $0.at }, &g, h)
        h = body.place(g, root: at.root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        return (frame, carry.props(held))
    }
}

// MARK: - Seated calf raise

/// A calf raise sitting on a bench with the weight on the knees: the balls of the feet on a low
/// block, the heels dropping below it and rising as far as the keyframes point the ankles. The
/// hips stay on the bench; the knees ride up and down on the shins and carry the weight with
/// them. A dumbbell stands on each knee under its hand, or a bar lies across both thighs.
struct SeatedCalfRaiseStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    enum Weight: Sendable, Equatable { case dumbbells, bar }

    static let blockTop = 0.08
    /// How far the skin is under the hip joints of a sitting body, and above the line of the thigh bone.
    static let underHips = 0.095, overThigh = 0.095
    /// How far from the middle of the bar each hand is: outside the thighs.
    static let barGrip = 0.27

    let body: Body3D
    let weight: Weight
    let feet: [LegFootprint]
    let grips: [String: HandGrip]
    /// Midway between the hip joints.
    let hip: V
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "calf-raise", guide.subtypeID == "seated", let weight = Self.weight(for: guide),
              let rHip = body.head["femur.r"], let lHip = body.head["femur.l"], let rKnee = body.head["shin.r"],
              let rAnkle = body.head["foot.r"] else { return nil }
        let radius = weight == .bar ? LegWeights.barRadius : LegWeights.dumbbellGrip
        guard let r = body.grip("r", radius: radius, square: weight == .bar ? 0.6 : 0),
              let l = body.grip("l", radius: radius, square: weight == .bar ? 0.6 : 0) else { return nil }
        self.body = body
        self.weight = weight
        grips = ["r": r, "l": l]
        // Thighs level and shins upright when the feet are level on the block.
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
        hip = V(0, 0, Self.blockTop + body.ankleHeight + shin)
        let half = (lHip.x - rHip.x) / 2 + 0.02
        feet = [("r", -1.0), ("l", 1.0)].compactMap {
            body.footprint($0.0, x: $0.1 * half, y: -thigh, turnout: 4, floor: Self.blockTop)
        }
        guard feet.count == 2 else { return nil }
        let seat = hip.z - Self.underHips
        var pieces = [PropPlan.box(V(0, 0.05, seat - 0.04), (1.1, 0.3, 0.08), .pad)]
        for x in [-0.4, 0.4] {
            pieces.append(PropPlan.box(V(x, 0.05, (seat - 0.08) / 2), (0.05, 0.24, seat - 0.08), .metal))
        }
        // The block's edge is just behind the balls of the feet, so the heels hang free.
        let edge = feet.map(\.ball.y).reduce(0, +) / 2 + 0.035
        pieces.append(PropPlan.box(V(0, edge - 0.15, Self.blockTop / 2), (0.6, 0.3, Self.blockTop), .wood))
        fixed = pieces
        kinds = [weight == .bar ? .barbell : .dumbbell, .bench, .step]
    }

    /// What lies on the knees, or nil for a seated calf raise this staging does not show: one
    /// leg at a time, on a chair or a machine, or with something else for a weight.
    static func weight(for guide: HowToGuide) -> Weight? {
        let words = LegLoad.words(guide)
        let plain: Set<String> = ["seated", "calf", "raise"]
        switch guide.equipment {
        case "dumbbell": return words.isSubset(of: plain.union(["dumbbell"])) ? .dumbbells : nil
        case "barbell": return words.isSubset(of: plain.union(["barbell"])) ? .bar : nil
        default: return nil
        }
    }

    /// The body, and where its weights are: the middle of each dumbbell's handle, or of the bar.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, held: [V]) {
        var pose = pose
        pose.scapula = nil
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let root = hip - ((rel["femur.r"] ?? V(0, 0, 0)) + (rel["femur.l"] ?? V(0, 0, 0))) * 0.5
        var h = body.place(g, root: root)
        // The keyframes' ankle angle tips each foot about its ball, and the knee goes with it.
        let heel = -(pose.angles["ankleDorsi"] ?? 0)
        for print in feet {
            let foot = body.lifted(print, heel: heel)
            body.plant(print.side, ankle: foot.ankle, foot: foot.foot, pole: V(0, -0.3, 1), &g, h)
            g["toes.\(print.side)"] = print.turn
        }
        h = body.place(g, root: root)

        // Where something lying on a thigh touches it, `back` from the knee.
        func onThigh(_ s: String, back: Double) -> V? {
            guard let knee = h["shin.\(s)"], let top = h["femur.\(s)"] else { return nil }
            let along = (knee - top).unit
            return knee - along * back + V(0, along.z, -along.y) * Self.overThigh
        }
        var held: [V] = []
        switch weight {
        case .dumbbells:
            // Each dumbbell stands on end on its knee, the hand closed round its handle.
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let grip = grips[s], let base = onThigh(s, back: 0.09) else { continue }
                let mid = base + V(0, 0, 0.135)
                body.hold(s, grip, at: mid, across: V(0, 0, 1), pole: V(-m * 0.6, 0.6, -0.3), &g, h)
                held.append(mid)
            }
        case .bar:
            // The bar lies level across both thighs a hand behind the knees.
            guard let r = onThigh("r", back: 0.12), let l = onThigh("l", back: 0.12) else { break }
            let mid = V(0, (r.y + l.y) / 2, max(r.z, l.z) + LegWeights.barRadius)
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let grip = grips[s] else { continue }
                body.hold(s, grip, at: mid + V(-m * Self.barGrip, 0, 0), across: V(-m, 0, 0), pole: V(-m * 0.7, 0.5, -0.5), &g, h)
            }
            held = [mid]
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        switch weight {
        case .dumbbells: return (frame, held.flatMap { LegWeights.dumbbell($0, along: V(0, 0, 1)) })
        case .bar: return (frame, held.first.map { LegWeights.barbell($0) } ?? [])
        }
    }
}

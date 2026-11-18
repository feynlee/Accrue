import Foundation

/// A seated crunch machine: sitting against a low back pad with the feet on the floor, each
/// hand on a handle that comes over its shoulder on an arm from an axle beside the hips. The
/// trunk curls forward from the hips and the arms of the machine turn with it, so the handles
/// stay over the shoulders the whole way. A weight stack behind rises as the trunk comes down.
struct MachineCrunchStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015, armX = 0.36, halfHands = 0.25, stackHeight = 1.7
    /// The furthest the trunk comes forward, in degrees.
    static let deepest = 45.0

    let body: Body3D
    let chair: MachineChair
    let grips: [String: HandGrip]
    /// The trunk's angle in the keyframe that sits tallest.
    let upright: Double
    /// The axle through the hips, and from it to the middle of the handles when sitting tall.
    let axle: V, reach: V
    let stackY: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let range = MachineRange(guide.keyframes, "trunk")
        guard guide.equipment == "machine", guide.familyID == "crunch-sit-up", guide.subtypeID == "seated-machine",
              words.contains("crunch"),
              words.isSubset(of: ["lever", "seated", "crunch", "chest", "pad", "hands", "v", "2", "full", "total", "abdominal"]),
              range.high - range.low > 15,
              let chair = MachineChair(body, lean: 4),
              let r = body.grip("r", radius: Self.gripRadius, square: 0.5), let l = body.grip("l", radius: Self.gripRadius, square: 0.5),
              let tall = guide.keyframes.min(by: { ($0.pose.angles["trunk"] ?? 0) < ($1.pose.angles["trunk"] ?? 0) })?.pose
        else { return nil }
        self.body = body
        self.chair = chair
        grips = ["r": r, "l": l]
        upright = range.low
        let seated = chair.sit(tall)
        guard let rs = seated.h["humerus.r"], let ls = seated.h["humerus.l"] else { return nil }
        let hip = chair.rest.hip
        axle = V(0, hip.y, hip.z)
        // The handles are in front of the shoulders, their bar across the top of the chest.
        let shoulders = (rs + ls) * 0.5
        reach = V(0, shoulders.y - 0.15, shoulders.z + 0.02) - axle

        var p = chair.pieces(top: 0.34)
        stackY = chair.rest.behind(0.3, 0.2).y + 0.45
        for m in [-1.0, 1.0] {
            let x = m * (Self.armX + 0.05)
            p.append(Plan.box(V(x, axle.y, (axle.z + 0.05) / 2), (0.06, 0.06, axle.z + 0.05), .metal))
            p.append(Plan.disc(V(m * (Self.armX + 0.02), axle.y, axle.z), axis: V(1, 0, 0), radius: 0.055, thickness: 0.05, .dark))
            p.append(Plan.box(V(x, (axle.y + stackY) / 2, 0.02), (0.07, stackY - axle.y + 0.3, 0.04), .metal))
        }
        p += stackFrame(y: stackY, height: Self.stackHeight)
        fixed = p
    }

    /// How far the trunk has come forward from sitting tall, in degrees.
    func curl(_ pose: JointPose) -> Double { min(Self.deepest, max(0, (pose.angles["trunk"] ?? 0) - upright)) }

    /// Sitting with the trunk leant `forward` degrees from the pad. The hip joints stay on
    /// the seat: the trunk turns about them, however the back rounds.
    static func hinged(_ chair: MachineChair, _ pose: JointPose, forward: Double) -> (g: [String: M], h: [String: V], root: V) {
        let body = chair.body
        var (g, h) = chair.rest.settle(pose, forward: forward)
        let hip = chair.rest.hip
        let joints = ((h["femur.r"] ?? hip) + (h["femur.l"] ?? hip)) * 0.5
        let root = (h["pelvis"] ?? hip) + (hip - joints)
        h = body.place(g, root: root)
        for s in ["r", "l"] {
            guard let ankle = chair.ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
        }
        return (g, body.place(g, root: root), root)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let curl = curl(pose)
        var (g, h, root) = Self.hinged(chair, pose, forward: curl)
        let turn = M.x(curl)
        let mid = axle + turn * reach
        var p = [Plan.rod(mid - V(Self.armX, 0, 0), mid + V(Self.armX, 0, 0), 0.014, .metal)]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            let at = mid + V(-m * Self.halfHands, 0, 0)
            body.hold(s, grip, at: at, across: V(-m, 0, 0), pole: V(-m * 0.5, -0.4, -1), &g, h)
            p.append(Plan.rod(at - V(0.065, 0, 0), at + V(0.065, 0, 0), Self.gripRadius, .dark))
            // The arm of the machine: up from the axle behind the shoulder, then over it.
            let hinge = axle + V(-m * Self.armX, 0, 0)
            let top = hinge + turn * V(0, 0.1, reach.z + 0.1)
            let end = mid + V(-m * Self.armX, 0, 0)
            p.append(Plan.rod(hinge, top, 0.022, .metal))
            p.append(Plan.rod(top, end, 0.022, .metal))
            p.append(Plan.ball(top, 0.022, .metal))
            p.append(Plan.ball(end, 0.022, .metal))
        }
        h = body.place(g, root: root)
        p += liftedPlates(y: stackY, height: Self.stackHeight, travel: curl * 0.007)
        return (body.made(g, h, floor: 0), p)
    }
}

// MARK: - Seated back extension

/// A seated back extension machine: sitting with the feet on the floor and a roller pad
/// across the shoulder blades, on two arms from an axle beside the hips. The trunk goes from
/// leaning forward to leaning back about the hips and pushes the roller round with it; the
/// arms stay folded on the chest. A weight stack stands well behind, clear of the roller.
struct MachineBackExtensionStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let roller = 0.065, armX = 0.3, stackHeight = 1.7
    /// How far the trunk leans forward at the start, and back at the end, in degrees.
    static let forward = 36.0, back = 18.0
    /// How far up the back from the hip joints the roller lies.
    static let high = 0.42

    let body: Body3D
    let chair: MachineChair
    let range: MachineRange
    let axle: V
    let stackY: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let range = MachineRange(guide.keyframes, "trunk")
        guard guide.equipment == "machine", guide.familyID == "back-extension", guide.subtypeID == nil,
              words.isSubset(of: ["lever", "back", "extension", "v", "2"]), range.high - range.low > 30,
              let chair = MachineChair(body, lean: 0) else { return nil }
        self.body = body
        self.chair = chair
        self.range = range
        let hip = chair.rest.hip
        axle = V(0, hip.y, hip.z)
        stackY = hip.y + 1.05
        var p = chair.pieces(back: false)
        for m in [-1.0, 1.0] {
            let x = m * (Self.armX + 0.05)
            p.append(Plan.box(V(x, axle.y, (axle.z + 0.05) / 2), (0.06, 0.06, axle.z + 0.05), .metal))
            p.append(Plan.disc(V(m * (Self.armX + 0.02), axle.y, axle.z), axis: V(1, 0, 0), radius: 0.055, thickness: 0.05, .dark))
            p.append(Plan.box(V(x, (axle.y + stackY) / 2, 0.02), (0.07, stackY - axle.y + 0.3, 0.04), .metal))
        }
        p += stackFrame(y: stackY, height: Self.stackHeight)
        fixed = p
    }

    /// How far forward of upright the trunk leans: the keyframes' most bent is furthest forward.
    func lean(_ pose: JointPose) -> Double { -Self.back + (Self.forward + Self.back) * range(pose) }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let lean = lean(pose)
        let (g, h, _) = MachineCrunchStaging.hinged(chair, pose, forward: lean)
        let pad = axle + M.x(lean) * V(0, MachineFit.back + Self.roller - 0.01, Self.high)
        var p = [Plan.disc(pad, axis: V(1, 0, 0), radius: Self.roller, thickness: 0.46, .pad),
                 Plan.rod(pad - V(Self.armX, 0, 0), pad + V(Self.armX, 0, 0), 0.014, .metal)]
        for m in [-1.0, 1.0] {
            p.append(Plan.rod(axle + V(m * Self.armX, 0, 0), pad + V(m * Self.armX, 0, 0), 0.022, .metal))
            p.append(Plan.ball(pad + V(m * Self.armX, 0, 0), 0.022, .metal))
        }
        p += liftedPlates(y: stackY, height: Self.stackHeight, travel: (Self.forward - lean) * 0.006)
        return (body.made(g, h, floor: 0), p)
    }
}

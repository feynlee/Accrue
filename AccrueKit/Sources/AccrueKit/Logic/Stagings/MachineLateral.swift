import Foundation

/// A lateral raise machine: sitting against the back pad, each arm hanging beside the body
/// under a pad that lies on the outside of the elbow, the hand on a handle below it. Each arm
/// lifts out to the side about its shoulder, and the machine's arm turns with it about an axle
/// straight behind that shoulder. A weight stack behind rises as the arms do.
struct MachineLateralRaiseStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015, stackHeight = 1.7
    /// How far behind the shoulders the machine's arms turn, and how far forward of straight
    /// out to the side the lifter's arms point.
    static let behind = 0.24, forward = 0.1

    let body: Body3D
    let chair: MachineChair
    let grips: [String: HandGrip]
    let shoulders: [String: V]
    /// From the shoulder to the middle of the grip, and to the elbow.
    let reach, upper: Double
    let lowest: Double
    let stackY: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let range = MachineRange(guide.keyframes, "shoulderAbd")
        guard guide.equipment == "machine", guide.familyID == "lateral-raise", guide.subtypeID == "machine",
              words.isSubset(of: ["lever", "lateral", "raise", "plate", "loaded", "v", "2"]),
              range.high - range.low > 30,
              let chair = MachineChair(body, lean: 5),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let first = guide.keyframes.first?.pose,
              let rShoulder = body.head["humerus.r"], let rElbow = body.head["ulna.r"] else { return nil }
        self.body = body
        self.chair = chair
        grips = ["r": r, "l": l]
        reach = body.reach("r", r, bend: 15)
        upper = (rElbow - rShoulder).length
        lowest = Self.turn(range.low)
        let seated = chair.sit(first)
        guard let rs = seated.h["humerus.r"], let ls = seated.h["humerus.l"] else { return nil }
        shoulders = ["r": rs, "l": ls]

        var p = chair.pieces(top: 0.6)
        let axle = rs.y + Self.behind
        stackY = axle + 0.4
        for at in [rs, ls] {
            // A post behind each shoulder carries that side's axle.
            p.append(Plan.box(V(at.x, axle + 0.06, (at.z + 0.06) / 2), (0.06, 0.06, at.z + 0.06), .metal))
            p.append(Plan.disc(V(at.x, axle + 0.02, at.z), axis: V(0, 1, 0), radius: 0.05, thickness: 0.06, .dark))
        }
        p.append(Plan.box(V(0, axle + 0.06, 0.02), (abs(rs.x - ls.x) + 0.3, 0.07, 0.04), .metal))
        p.append(Plan.box(V(0, axle + 0.06, rs.z + 0.03), (abs(rs.x - ls.x) + 0.06, 0.06, 0.06), .metal))
        p.append(Plan.box(V(0, (axle + stackY) / 2, 0.02), (0.08, stackY - axle + 0.1, 0.04), .metal))
        p += stackFrame(y: stackY, height: Self.stackHeight)
        fixed = p
    }

    /// How far each arm is lifted from hanging straight down, in degrees.
    static func turn(_ abd: Double) -> Double { min(88, max(12, abd)) }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h, root) = chair.sit(pose)
        let degrees = Self.turn(pose.angles["shoulderAbd"] ?? 0)
        let a = degrees * .pi / 180
        var p: [PropPiece] = []
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let shoulder = shoulders[s] else { continue }
            // The arm's line, a little forward of straight out to the side; the machine's arm
            // keeps to the plane behind it.
            let level = V(-m * sin(a), 0, -cos(a)), over = V(-m * cos(a), 0, sin(a))
            let along = (level - V(0, Self.forward, 0)).unit
            let hand = shoulder + along * reach
            body.hold(s, grip, at: hand, across: V(0, 1, 0), pole: V(-m * 0.1, 1, 0.1), &g, h)

            let pivot = shoulder + V(0, Self.behind, 0)
            let end = pivot + level * (reach * 0.96)
            p.append(Plan.rod(pivot, end, 0.022, .metal))
            // The pad on the outside of the elbow, and the handle in the hand.
            let elbow = shoulder + along * (upper * 1.02)
            let pad = elbow + over * (0.05 + 0.028)
            p.append(Plan.box(pad, (0.17, 0.13, 0.05), x: along, z: over, .pad))
            let carry = pivot + level * (upper * 1.02) + over * 0.085
            p.append(Plan.rod(pivot + level * (upper * 1.02), carry, 0.016, .metal))
            p.append(Plan.rod(carry, V(pad.x, pad.y + 0.05, pad.z) + over * 0.007, 0.016, .metal))
            p.append(Plan.rod(hand - V(0, 0.065, 0), hand + V(0, 0.065, 0), Self.gripRadius, .dark))
            p.append(Plan.rod(hand + V(0, 0.065, 0), end, 0.014, .metal))
        }
        h = body.place(g, root: root)
        p += liftedPlates(y: stackY, height: Self.stackHeight, travel: (degrees - lowest) * 0.005)
        return (body.made(g, h, floor: 0), p)
    }
}

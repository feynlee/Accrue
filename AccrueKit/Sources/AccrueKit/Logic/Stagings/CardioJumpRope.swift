import Foundation

/// Skipping with a rope. The body hops on the spot on the balls of its feet, the hands hold
/// the handles beside the hips, and the rope turns about the line between them: it passes
/// under the feet while they are off the floor and over the head half a turn later.
struct CardioJumpRopeStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let sides: [(String, Double)] = [("r", 1.0), ("l", -1.0)]
    /// The rope's thickness, as the plain plan draws it.
    static let rope = 0.006
    /// Where a hand holds its handle, from the pelvis: out to its side, a little forward and up.
    static let hand = V(0.30, -0.13, 0.12)
    /// How far the handle sticks out of the fist toward the rope.
    static let handle = 0.09

    let body: Body3D
    let loop: CardioLoop
    /// When the feet leave the floor, and how high the hop is at its top.
    let off: Double, height: Double
    /// The moments the rope goes under the feet: once a hop, or twice.
    let passes: [Double]
    /// Where the balls of the feet stay.
    let spot: V
    let grips: [String: HandGrip]
    /// The lowest the pelvis is as the rope goes under, with nothing going wrong.
    private(set) var low = 0.0
    let kinds: [PropKind] = [.jumpRope]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "jump-rope" else { return nil }
        let words = CardioStagings.words(guide)
        guard let off = guide.keyframes.first(where: { $0.phase == "Push" })?.t, off > 0, off < 0.9,
              let r = body.grip("r", radius: 0.013), let l = body.grip("l", radius: 0.013),
              let ball = body.head["toes.r"], let pelvis = body.head["pelvis"] else { return nil }
        let mid = (off + 1) / 2
        switch guide.subtypeID {
        case "basic":
            // The two-foot bounce, small or high. Hopping from side to side is another move.
            if words == ["jump", "rope"] { height = 0.035 } else if words == ["high", "jump", "rope"] { height = 0.12 } else { return nil }
            passes = [mid]
        case "double-under":
            guard words.contains("double"), words.isSubset(of: ["double", "under", "jump", "rope"]) else { return nil }
            height = 0.17
            // Two turns to a hop, evenly spaced: both fall within the flight.
            passes = [mid - 0.25, mid + 0.25]
        default:
            // Alternate feet: the loop there is the same going out and coming back, so the
            // pose alone cannot say which way the rope has got to.
            return nil
        }
        self.body = body
        self.off = off
        loop = CardioLoop(guide, steps: 384)
        spot = V(0, ball.y - pelvis.y, 0)
        grips = ["r": r, "l": l]
        low = lowest(nil)
    }

    /// The loop's pose at `t` with a mistake on it.
    func pose(at t: Double, fault: JointPose?) -> JointPose {
        let clean = Figure.smooth(loop.closed, at: t)
        return fault.map { CardioStagings.applying($0, to: clean) } ?? clean
    }

    /// How far a pose's `key` is from the clean loop's at `t`, as a share of `full` degrees.
    func extra(_ key: String, _ pose: JointPose, at t: Double, full: Double) -> Double {
        let clean = Figure.smooth(loop.closed, at: t)
        return min(1, max(0, (CardioStagings.angle(pose, key) - CardioStagings.angle(clean, key)) / full))
    }

    /// The body at moment `t`: on the balls of its feet on the floor, or as high above it as
    /// the hop has got. Knees tucked up by a mistake go with a higher hop.
    func placed(at t: Double, fault: JointPose?) -> (g: [String: M], root: V, pose: JointPose) {
        let pose = pose(at: t, fault: fault)
        let u = (t - off) / (1 - off)
        var hop = 0.0, air = 0.0
        if u > 0 {
            hop = 4 * (height + 0.08 * extra("hipFlex", pose, at: t, full: 30)) * u * (1 - u)
            air = CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.2)
        }
        let g = CardioFooting.settle(body.rotations(pose), air: ["r": air, "l": air])
        return (g, CardioFooting.root(body, g, ball: spot, floor: hop), pose)
    }

    /// The lowest the pelvis is at the moments the rope goes under the feet.
    func lowest(_ fault: JointPose?) -> Double {
        passes.map { placed(at: $0, fault: fault).root.z }.min() ?? 0.9
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        let placed = placed(at: found.t, fault: found.fault)
        var g = placed.g
        let root = placed.root
        var h = body.place(g, root: root)
        // "Arms swing wide": the hands go out and up from the hips.
        let wide = extra("shoulderAbd", placed.pose, at: found.t, full: 40)
        var props: [PropPiece] = []
        var ends: [V] = []
        for (s, m) in Self.sides {
            guard let grip = grips[s] else { continue }
            let out = V(-m, 0, 0)
            let point = root + V(-m * (Self.hand.x + 0.2 * wide), Self.hand.y - 0.08 * wide, Self.hand.z + 0.14 * wide)
            // Palm up, thumb to the outside, the elbow back by the ribs.
            body.hold(s, grip, at: point, across: out * -1, pole: V(-m * (0.4 + wide), 1, -0.2), &g, h)
            props.append(Plan.rod(point - out * 0.05, point + out * Self.handle, 0.013, .dark))
            ends.append(point + out * Self.handle)
        }
        h = body.place(g, root: root)
        guard ends.count == 2 else { return (body.made(g, h, floor: 0), props) }

        // The rope is as long as it takes to brush the floor as it goes under the feet. It
        // turns forward over the head and back under the feet.
        let centre = (ends[0] + ends[1]) * 0.5
        let rise = centre.z - root.z
        let reach = (found.fault == nil ? low : lowest(found.fault)) + rise - Self.rope - 0.002
        let turn = 2 * Double.pi * Double(passes.count) * (found.t - passes[0])
        let way = V(0, sin(turn), -cos(turn))
        // Where it would go into the floor it lies along it instead.
        let far = cos(turn) > 0 ? min(reach, (centre.z - Self.rope) / cos(turn)) : reach
        let across = ends[1] - ends[0]
        let count = 16
        let points = (0...count).map { i -> V in
            let a = Double.pi * Double(i) / Double(count)
            return centre - across * (0.5 * cos(a)) + way * (far * sin(a))
        }
        for i in 0..<count { props.append(Plan.rod(points[i], points[i + 1], Self.rope, .dark)) }
        return (body.made(g, h, floor: 0), props)
    }
}

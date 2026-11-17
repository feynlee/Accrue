import Foundation

/// A jump onto a box. The box stands where the jump lands; the body dips and takes off from
/// the floor in front of it (or beside it), flies in an arc that carries the tucked feet over
/// the edge, and lands with both feet flat on the top, where it stands up.
struct CardioBoxJumpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The height of the box's top, and its size along the jump and across it.
    static let top = 0.5, deep = 0.5, wide = 0.6
    /// The clear floor between the toes and the box before the jump.
    static let gap = 0.25

    let body: Body3D
    let loop: CardioLoop
    /// When the feet leave the floor and when they meet the box.
    let off: Double, land: Double
    /// Where the balls of the feet are before the jump and after it.
    let from: V, to: V
    /// The middle of the box, the way the jump goes and the way across it.
    let centre: V, way: V, across: V
    /// How far the feet's flight rises above a plain climb from the floor to the top.
    private(set) var rise = 0.0
    let kinds: [PropKind] = [.box]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "box-jump" else { return nil }
        let words = CardioStagings.words(guide)
        let way: V
        switch guide.subtypeID {
        case nil:
            // A plain jump onto a box, facing it.
            guard words.isSuperset(of: ["jump", "box"]), words.isSubset(of: ["jump", "box", "on", "fit", "v", "2"]) else { return nil }
            way = V(0, -1, 0)
        case "lateral":
            // Side-on to the box, which is on the body's left.
            guard words == ["lateral", "box", "jump"] else { return nil }
            way = V(1, 0, 0)
        default: return nil
        }
        guard let off = guide.keyframes.first(where: { $0.phase == "Jump" })?.t,
              let land = guide.keyframes.first(where: { $0.phase == "Land" })?.t, off < land,
              let ball = body.head["toes.r"], let tip = body.tail["toes.r"], let ankle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        self.off = off
        self.land = land
        self.way = way
        across = way.cross(V(0, 0, 1))
        // Sampled finely: the moment of take-off has to be found to a few thousandths.
        loop = CardioLoop(guide, steps: 480)
        // How far the two feet reach from the middle of their balls, toward the box and away
        // from it: the toes and the heels, or half the stance and half a foot's width.
        let ahead = way.y < 0 ? ball.y - tip.y : abs(ball.x) + 0.06
        let behind = way.y < 0 ? ankle.y + 0.045 - ball.y : abs(ball.x) + 0.06
        // The jump starts with the hips over the origin and lands in the middle of the top.
        from = V(0, ball.y - pelvis.y, 0)
        let face = ahead + Self.gap
        to = from + way * (face + Self.deep / 2 + (behind - ahead) / 2)
        centre = from + way * (face + Self.deep / 2) + V(0, 0, Self.top / 2)
        fixed = [Plan.box(centre, (way.y < 0 ? Self.wide : Self.deep, way.y < 0 ? Self.deep : Self.wide, Self.top), .wood)]
        // The lowest arc that carries the feet over the edge, with every mistake too.
        let faults: [JointPose?] = [nil] + loop.faults.map { Optional($0) }
        var rise = 0.2
        while rise < 0.8, !faults.allSatisfy({ clears($0, rise) }) { rise += 0.025 }
        self.rise = rise
    }

    /// The feet stay out of the box through the whole flight, and of a little room round its edges.
    func clears(_ fault: JointPose?, _ rise: Double) -> Bool {
        for i in 1..<32 {
            let (g, root) = solve(at: off + (land - off) * Double(i) / 32, fault: fault, rise: rise)
            let h = body.place(g, root: root)
            for (p, skin) in body.contactPoints("feet", g, h) + body.contactPoints("toes", g, h) {
                let d = p - centre
                let along = d.dot(way), aside = d.dot(across)
                guard abs(aside) < Self.wide / 2 + 0.03, along > -Self.deep / 2 - 0.04, along < Self.deep / 2 + 0.03 else { continue }
                if p.z - skin < Self.top - 0.001 { return false }
            }
        }
        return true
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        let (g, root) = solve(at: found.t, fault: found.fault, rise: rise)
        return (body.made(g, body.place(g, root: root), floor: 0), [])
    }

    /// The loop's pose at `t` with a mistake on it. The mistakes are all ways of landing
    /// badly, so one comes on as the body flies, is whole as the feet meet the box, and goes
    /// again as the body stands up: the dip and the take-off stay as they should be.
    func pose(at t: Double, fault: JointPose?) -> JointPose {
        var pose = Figure.smooth(loop.closed, at: t)
        guard var fault, t > off else { return pose }
        let share = t < land ? CardioStagings.ease((t - off) / (land - off), from: 0.2, to: 0.9)
            : 1 - CardioStagings.ease(t, from: land + 0.05, to: 1)
        fault.angles = fault.angles.mapValues { $0 * share }
        fault.scapula = nil
        pose = CardioStagings.applying(fault, to: pose)
        // A knee stops at straight.
        for key in ["kneeFlex", "kneeFlexL"] { if let v = pose.angles[key] { pose.angles[key] = max(0, v) } }
        return pose
    }

    /// The posed body with its feet on a surface at height `floor`, the balls of the feet over
    /// `ball`: `air` 0 standing on it, 1 flying above it.
    func placed(at t: Double, fault: JointPose?, ball: V, floor: Double, air: Double) -> (g: [String: M], root: V) {
        let pose = pose(at: t, fault: fault)
        var g = body.rotations(pose)
        CardioFooting.steadyArms(body, &g, pose)
        g = CardioFooting.settle(g, air: ["r": air, "l": air])
        return (g, CardioFooting.root(body, g, ball: ball, floor: floor))
    }

    func solve(at t: Double, fault: JointPose?, rise: Double) -> (g: [String: M], root: V) {
        if t <= off { return placed(at: t, fault: fault, ball: from, floor: 0, air: 0) }
        if t >= land { return placed(at: t, fault: fault, ball: to, floor: Self.top, air: 0) }
        // In flight the feet lead: they go up first and across later, as if the floor under
        // them rose to the top of the box and a little over it, and the legs are the
        // keyframes' own, so the hips are wherever the tuck leaves them above the feet.
        let u = (t - off) / (land - off)
        let air = CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.25)
        let floor = Self.top * (1 - (1 - u) * (1 - u)) + 4 * rise * u * (1 - u)
        return placed(at: t, fault: fault, ball: mix(from, to, u * u), floor: floor, air: air)
    }
}

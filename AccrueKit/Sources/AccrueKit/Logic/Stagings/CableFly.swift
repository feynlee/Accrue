import Foundation

// MARK: - Standing cable fly

/// A standing cable fly, or crossover: between two stacks with a pulley high on each, one foot
/// ahead of the other, a stirrup handle in each hand. The arms open wide toward the pulleys and
/// hug together in front of the body; each cable runs straight from its wheel to its handle and
/// each stack rises as far as its cable is drawn out. The keyframes place the arms, so elbows
/// that bend into a press and arms that open too deep show as written.
struct CableFlyStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The station's height, how far to each side its stacks stand, and how far behind the
    /// front foot's line the pulleys are.
    static let top = 2.2, spread = 1.3, behind = 0.12
    /// Half the distance between the fists when they meet, the handle's thickness, and how far
    /// from the grip the stirrup's ring is.
    static let together = 0.06, gripRadius = 0.015, ring = 0.13

    let body: Body3D
    let grips: [String: HandGrip]
    let stance: CableKit.SplitStance
    /// Set when the fly is done on the knees: the legs are then the posture's, not the stance's.
    let posture: PostureStaging?
    /// The shoulder's swing out to the side with the arms open and with them together (degrees).
    let open, closed: Double
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []
    /// The middle of each side's wheel, and how to turn and place that side's stack.
    let wheels: [String: V]
    let turns: [String: M]
    let bases: [String: V]
    /// Each cable's length out of its wheel with the arms open, where the stacks rest.
    private(set) var slack: [String: Double] = [:]

    init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support? = nil) {
        guard let first = guide.keyframes.first?.pose,
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius) else { return nil }
        // The keyframes step one leg forward: that foot is the front one.
        let lead = (first.angles["hipFlex"] ?? 0) >= (first.angles["hipFlexL"] ?? first.angles["hipFlex"] ?? 0) ? "r" : "l"
        guard let stance = CableKit.SplitStance(body, front: lead) else { return nil }
        self.body = body
        self.stance = stance
        if let support {
            guard let posture = PostureStaging(guide, body, support) else { return nil }
            self.posture = posture
        } else {
            posture = nil
        }
        kinds = [.cable] + (posture?.kinds.filter { $0 != .cable } ?? [])
        grips = ["r": r, "l": l]
        let swings = guide.keyframes.map { $0.pose.angles["shoulderAbd"] ?? 0 }
        open = swings.max() ?? 85
        closed = min(swings.min() ?? 15, open - 1)

        // A stack on each side, turned to face the body, with its own wheel as the pulley.
        let y = (posture?.hip.y ?? stance.hips.y) + Self.behind
        var wheels: [String: V] = [:], turns: [String: M] = [:], bases: [String: V] = [:]
        var pieces: [PropPiece] = []
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            let turn = M.z(-m * 90), base = V(-m * Self.spread, y, 0)
            turns[s] = turn
            bases[s] = base
            wheels[s] = turn * V(0, CableKit.wheel, Self.top - 0.13) + base
            pieces += CableKit.moved(stackFrame(y: 0, height: Self.top), turn: turn, by: base)
        }
        // The beam overhead that ties the two stacks into one frame.
        pieces.append(Plan.box(V(0, y, Self.top + 0.03), (2 * Self.spread + 0.5, 0.08, 0.06), .metal))
        self.wheels = wheels
        self.turns = turns
        self.bases = bases
        fixed = pieces + (posture?.fixed ?? [])
        let start = layout(first)
        for s in ["r", "l"] {
            guard let ring = start.rings[s], let wheel = wheels[s] else { continue }
            slack[s] = (ring - wheel).length
        }
    }

    struct Layout {
        var frame: BodyFrame
        /// The grip's middle line under each palm, its direction from thumb to little finger,
        /// the stirrup's ring, and where that side's cable leaves its wheel.
        var hands: [String: V]
        var across: [String: V]
        var rings: [String: V]
        var rims: [String: V]
    }

    func layout(_ pose: JointPose) -> Layout {
        var g: [String: M], h: [String: V], root: V
        if let posture {
            (g, h, root) = posture.settle(pose)
        } else {
            g = body.rotations(pose)
            (root, h) = stance.stand(body, &g)
        }
        let thorax = g["thorax"] ?? .identity
        let swing = pose.angles["shoulderAbd"] ?? open
        let u = min(1, max(0, (open - swing) / (open - closed))), ease = u * u * (3 - 2 * u)
        var hands: [String: V] = [:], across: [String: V] = [:], rings: [String: V] = [:], rims: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let wheel = wheels[s], let shoulder = h["humerus.\(s)"],
                  let elbow = h["ulna.\(s)"], let wrist = h["hand.\(s)"] else { continue }
            // Where the keyframes' arm would hold, a palm's depth past the wrist. They leave the
            // hands apart at the end: the hug brings the fists together in front.
            let fore = (wrist - elbow).unit
            let c0 = grip.centre
            var at = wrist + fore * (c0 - grip.across * c0.dot(grip.across)).length
            at.x = -m * (abs(at.x) + (Self.together - abs(at.x)) * ease)
            at = CableKit.within(body, s, grip, shoulder: shoulder, at, bend: 12)
            // The stirrup hangs in line with its cable, and turns about it to lie square
            // across the forearm, thumb up and forward.
            let rim = CableKit.rim(wheel, axis: V(0, 1, 0), from: at, side: V(m, 0, 0))
            let c = (rim - at).unit
            let down = thorax * V(0, 0.4, -1)
            var line = c.cross(fore)
            if line.dot(down) < 0 { line = line * -1 }
            line = line + (down - c * down.dot(c)) * 0.25
            line = (line - c * line.dot(c)).unit
            let pole = (elbow - shoulder).unit + thorax * V(-m * 0.3, 0.6, -0.4) * 0.5
            body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            hands[s] = at
            across[s] = line
            rings[s] = at + c * Self.ring
            rims[s] = rim
        }
        return Layout(frame: body.made(g, body.place(g, root: root), floor: 0), hands: hands, across: across, rings: rings, rims: rims)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        var p: [PropPiece] = []
        for s in ["r", "l"] {
            guard let hand = at.hands[s], let line = at.across[s], let ring = at.rings[s], let rim = at.rims[s],
                  let wheel = wheels[s], let turn = turns[s], let base = bases[s] else { continue }
            // The stirrup: a grip, and a strap from each of its ends to the ring.
            let a = hand - line * 0.065, b = hand + line * 0.065
            p.append(Plan.rod(a, b, Self.gripRadius, .dark))
            for end in [a, b] {
                p.append(Plan.rod(end, ring, 0.006, .metal))
                p.append(Plan.ball(end, 0.008, .metal))
            }
            p.append(Plan.ball(ring, 0.014, .metal))
            p.append(Plan.rod(ring, rim, CableKit.cable, .cable))
            let travel = max(0, (ring - wheel).length - (slack[s] ?? 0))
            p += CableKit.moved(liftedPlates(y: 0, height: Self.top, travel: travel), turn: turn, by: base)
        }
        return (at.frame, p)
    }
}

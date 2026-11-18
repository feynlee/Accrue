import Foundation

// MARK: - A handle in each hand, between two pulleys

/// A press, a fly or a raise done sitting, kneeling or lying between the two stacks of a cable
/// station, with a stirrup handle in each hand. The body rests on its bench or its knees; the
/// keyframes carry the arms, and each hand closes on its grip where they put it, turned to lie
/// square across its cable. Each cable runs straight from its wheel to its handle, and each
/// stack rises as far as its cable is drawn out. An exercise whose cables would have to pass
/// through the body is not staged at all.
struct CableHandlesStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Where the wheels are set on their masts: near the floor in line with the hands, or level
    /// with the shoulders and a little behind them.
    enum Pulleys: Sendable { case low, chest }

    /// The station's height, the least distance from the middle to each wheel, and how far
    /// outside the widest reach of the hands the wheels stand.
    static let top = 2.2, spread = 0.9, margin = 0.3
    /// A low wheel's height, and how far behind the shoulders a wheel at chest height is.
    static let low = 0.22, behind = 0.32
    /// The handle's thickness, how far from the grip the stirrup's ring is, and how near the
    /// body a cable may pass.
    static let gripRadius = 0.015, ring = 0.13, clear = 0.012
    /// Half the distance between the fists when they meet in the middle.
    static let together = 0.055

    let body: Body3D
    let grips: [String: HandGrip]
    let posture: PostureStaging
    let pulleys: Pulleys
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []
    /// The middle of each side's wheel, how that side's station is turned and placed, and
    /// where its stack stands along its own line.
    private(set) var wheels: [String: V] = [:]
    private(set) var turns: [String: M] = [:]
    private(set) var bases: [String: V] = [:]
    private(set) var column = 0.0
    /// Each cable's shortest length out of its wheel through the loop, where its stack rests.
    private(set) var slack: [String: Double] = [:]

    init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support, pulleys: Pulleys) {
        guard let posture = PostureStaging(guide, body, support),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius) else { return nil }
        self.body = body
        self.posture = posture
        self.pulleys = pulleys
        grips = ["r": r, "l": l]
        var kinds: [PropKind] = [.cable]
        for kind in posture.kinds where !kinds.contains(kind) { kinds.append(kind) }
        self.kinds = kinds

        // Where the hands go through the loop, and where the shoulders are.
        let loop = (0...24).map { Figure.smooth(guide.keyframes, at: Double($0) / 24) }
        var wide = 0.0, depth = 0.0, n = 0.0, shoulder = V(0, 0, 0), m = 0.0
        for pose in loop {
            let (g, h, _) = posture.settle(pose)
            for s in ["r", "l"] {
                guard let at = Self.palm(s, g, h, grips) else { continue }
                wide = max(wide, abs(at.x))
                depth += at.y
                n += 1
                if let joint = h["humerus.\(s)"] {
                    shoulder = shoulder + joint
                    m += 1
                }
            }
        }
        guard n > 0, m > 0 else { return nil }
        shoulder = shoulder * (1 / m)
        let out = max(Self.spread, wide + Self.margin)
        let wheel = pulleys == .low ? V(0, depth / n, Self.low) : V(0, shoulder.y + Self.behind, shoulder.z)

        // A mast and its stack on each side, turned to face the body.
        var pieces = posture.fixed
        for (s, side) in [("r", 1.0), ("l", -1.0)] {
            let turn = M.z(-side * 90), base = V(-side * out, wheel.y, 0)
            let station = CableKit.mastStation(pulley: V(0, 0, wheel.z), top: Self.top)
            column = station.column
            turns[s] = turn
            bases[s] = base
            wheels[s] = base + V(0, 0, wheel.z)
            pieces += CableKit.moved(station.pieces, turn: turn, by: base)
        }
        // The beam overhead that ties the two sides into one frame.
        pieces.append(Plan.box(V(0, wheel.y, Self.top + 0.03), (2 * (out - column) + 0.2, 0.08, 0.06), .metal))
        fixed = pieces

        // The stacks rest where the cables are shortest, and no cable may run through the body.
        var poses = loop
        let fault = Figure.smooth(guide.keyframes, at: guide.faultT)
        poses += guide.steps.flatMap(\.mistakes).compactMap { step in step.pose.map { Figure.applying($0, to: fault) } }
        for (i, pose) in poses.enumerated() {
            let at = layout(pose)
            for s in ["r", "l"] {
                guard let ring = at.rings[s], let rim = at.rims[s], let wheel = wheels[s] else { return nil }
                if i < loop.count { slack[s] = min(slack[s] ?? .infinity, (ring - wheel).length) }
                let run = rim - ring
                guard run.length > 0.05 else { return nil }
                if Body3D.wayOut((ring + rim) * 0.5, axis: run.unit, half: run.length / 2, radius: Self.clear,
                                 of: at.bulk, front: Body3D.forward) != nil { return nil }
            }
        }
    }

    /// The middle of the grip in a hand as the keyframes pose it.
    static func palm(_ s: String, _ g: [String: M], _ h: [String: V], _ grips: [String: HandGrip]) -> V? {
        guard let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"], let grip = grips[s] else { return nil }
        return wrist + hand * grip.centre
    }

    struct Layout {
        var frame: BodyFrame
        /// The grip's middle line under each palm, its direction from thumb to little finger,
        /// the stirrup's ring, and where that side's cable leaves its wheel.
        var hands: [String: V]
        var across: [String: V]
        var rings: [String: V]
        var rims: [String: V]
        /// The trunk, head and legs, which the cables stay out of.
        var bulk: [BulkRod]
    }

    func layout(_ pose: JointPose) -> Layout {
        var (g, h, root) = posture.settle(pose)
        var hands: [String: V] = [:], across: [String: V] = [:], rings: [String: V] = [:], rims: [String: V] = [:]
        for s in ["r", "l"] {
            guard let grip = grips[s], let wheel = wheels[s], var at = Self.palm(s, g, h, grips), let hand = g["hand.\(s)"],
                  let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"], let wrist = h["hand.\(s)"] else { continue }
            // Each fist stays on its own side: hands the keyframes cross meet in the middle.
            let own: Double = wheel.x > 0 ? 1 : -1
            if at.x * own < Self.together { at.x = own * Self.together }
            // The cable comes down the far side of the mast and round under the wheel, so it
            // leaves from the wheel's lower, inner side.
            let rim = CableKit.rim(wheel, axis: V(0, 1, 0), from: at, side: V(wheel.x > 0 ? -1 : 1, 0, -1))
            let c = (rim - at).unit
            // The stirrup hangs in line with its cable. The hand keeps as much of its own turn
            // as that allows; a grip that would lie along the cable lies across the forearm.
            var line = hand * grip.across
            line = line - c * line.dot(c)
            if line.length < 0.4 {
                let fore = (wrist - elbow).unit
                var other = c.cross(fore)
                if other.dot(hand * grip.across) < 0 { other = other * -1 }
                line = line + (other - c * other.dot(c))
            }
            guard line.length > 1e-6 else { continue }
            line = line.unit
            // The elbow stays on the side of the arm's line the keyframes have it.
            let hinge = (g["humerus.\(s)"] ?? .identity) * body.hingeAxis(s)
            let pole = (elbow - (shoulder + at) * 0.5) + (at - shoulder).cross(hinge).unit * 0.05
            body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            hands[s] = at
            across[s] = line
            rings[s] = at + c * Self.ring
            rims[s] = CableKit.rim(wheel, axis: V(0, 1, 0), from: at + c * Self.ring, side: rim - wheel)
        }
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: across, rings: rings, rims: rims,
                      bulk: body.bulk(g, h, walls: false))
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
            p += CableKit.moved(liftedPlates(y: column, height: Self.top, travel: travel), turn: turn, by: base)
        }
        return (at.frame, p)
    }
}

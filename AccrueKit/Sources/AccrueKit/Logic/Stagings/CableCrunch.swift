import Foundation

// MARK: - Cable crunch

/// A cable crunch on the knees: under a high pulley, the ends of the rope held beside the head,
/// the hips still over the knees while the trunk curls down and draws the cable out. The
/// keyframes curl the trunk and carry the arms; the fists only keep clear of the head, and the
/// rope runs from them up over it to the swivel.
struct CableCrunchStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The station's height, how far in front of the high wheel the stack stands, and how far
    /// in front of the hands the wheel hangs.
    static let top = 2.2, boom = 0.55, ahead = 0.22
    /// Where the right fist rests against the side of the head, as a point of the standing
    /// model: above the ear, so the rope's halves pass over the skull to the swivel.
    static let temple = V(-0.132, -0.015, 1.615)
    /// How far from there the keyframes' own hand may be before it is taken as it is (a
    /// mistake that pulls with the arms), from not at all to wholly.
    static let strays = (from: 0.22, to: 0.42)

    let body: Body3D
    let grips: [String: HandGrip]
    let footing: CableKit.Footing
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []
    private(set) var pulley = V(0, -0.5, CableCrunchStaging.top - 0.13)
    private(set) var column = -1.05
    /// The cable's shortest length out of the wheel through the loop, where the stack rests.
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support) {
        guard let footing = CableKit.Footing(guide, body, on: support),
              let r = body.grip("r", radius: CableKit.rope), let l = body.grip("l", radius: CableKit.rope) else { return nil }
        self.body = body
        self.footing = footing
        grips = ["r": r, "l": l]
        kinds = footing.kinds
        // The wheel hangs in front of the hands' furthest reach, so the cable always leans
        // forward from the head.
        let loop = (0...24).map { Figure.smooth(guide.keyframes, at: Double($0) / 24) }
        let fronts = loop.flatMap { reach($0).hands.values.map(\.y) }
        guard let front = fronts.min() else { return nil }
        pulley = V(0, front - Self.ahead, Self.top - 0.13)
        column = pulley.y - Self.boom
        fixed = CableKit.highStation(pulley: pulley, column: column, top: Self.top) + footing.pieces
        slack = loop.map { (layout($0).eye - pulley).length }.min() ?? 0
    }

    /// The body on its knees, where each fist holds the rope, and where its elbow goes.
    func reach(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V, hands: [String: V], poles: [String: V]) {
        let (g, h, root) = footing.settle(body, pose)
        let thorax = g["thorax"] ?? .identity
        var hands: [String: V] = [:], poles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"], let grip = grips[s],
                  let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"] else { continue }
            // The fists rest against the sides of the head and go where it goes. Hands the
            // keyframes take well away from the head are pulling with the arms, and are shown
            // where they are.
            var at = wrist + hand * grip.centre
            if let skull = h["head"], let rest = body.head["head"] {
                let temple = V(m * Self.temple.x, Self.temple.y, Self.temple.z)
                let held = skull + (g["head"] ?? .identity) * (temple - rest)
                let stray = min(1, max(0, ((at - held).length - Self.strays.from) / (Self.strays.to - Self.strays.from)))
                at = mix(held, at, stray * stray * (3 - 2 * stray))
            }
            hands[s] = CableKit.within(body, s, grip, shoulder: shoulder, at)
            // The elbows point forward and down, in front of the chest.
            poles[s] = (elbow - shoulder).unit + thorax * V(-m * 0.2, -1, -0.3) * 0.4
        }
        return (g, h, root, hands, poles)
    }

    struct Layout {
        var frame: BodyFrame
        /// The rope's middle line in each hand, and its direction from thumb to little finger.
        var hands: [String: V]
        var across: [String: V]
        /// The way the rope runs through each fist toward its end.
        var run: [String: V]
        /// The rope's swivel, and where the cable leaves the wheel.
        var eye, rim: V
    }

    func layout(_ pose: JointPose) -> Layout {
        var (g, h, root, hands, poles) = reach(pose)
        // Thumbs up toward the swivel, the rope's knobs under the little fingers.
        let held = CableKit.holdRope(body, grips, hands: hands, poles: poles, pulley: pulley, side: V(0, 1, 0), &g, h, root: root)
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: held.across, run: held.run, eye: held.eye, rim: held.rim)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        var p = CableKit.ropePieces(eye: at.eye, hands: at.hands, run: at.run)
        p.append(Plan.rod(at.eye, at.rim, CableKit.cable, .cable))
        p += liftedPlates(y: column, height: Self.top, travel: max(0, (at.eye - pulley).length - slack))
        return (at.frame, p)
    }
}

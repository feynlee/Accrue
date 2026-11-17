import Foundation

// MARK: - Triceps pushdown and standing cable curl

/// Standing at a cable stack and bending only the elbows, with both hands closed on one handle:
/// the triceps pushdown under a high pulley (the handle goes from chest height down to
/// straight arms) and the biceps curl over a low one (from the thighs up to the shoulders).
/// The feet stay flat, the cable runs straight from the wheel to the handle, and the stack's
/// plates rise as far as it is drawn out. The keyframes place the trunk and the upper arms,
/// so elbows that drift and a body that leans or swings show as they are written.
struct StandingCableStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    enum Move: Sendable { case pushdown, curl }
    /// A short straight bar, the V-shaped bar, the cambered bar, or the rope.
    enum Handle: Sendable { case bar, vBar, ezBar, rope }

    static let barRadius = 0.014
    /// The station's height, and how far in front of the high wheel the stack stands.
    static let top = 2.2, boom = 0.55
    /// The low wheel's height, and how far in front of the hanging hands it is.
    static let low = 0.2, step = 0.5
    /// The V-bar: how steeply each handle drops away from the swivel (degrees), how long it is,
    /// and how far along it the hand closes.
    static let vSlope = 30.0, vLength = 0.2, vHand = 0.11
    /// The cambered bar's right half, as (out from the middle, away from the pulley): level in
    /// the middle, away and out, back and out again, and level ends.
    static let camber: [(Double, Double)] = [(0, 0), (0.03, 0), (0.14, 0.045), (0.25, 0), (0.31, 0)]
    /// How near the body the handle's middle line may come, and how far in front of the joint
    /// at the base of the neck the cable passes the face.
    static let clear = 0.055, swing = 20.0, face = 0.21

    let body: Body3D
    let move: Move
    let handle: Handle
    /// Palms up on a bar: the usual way to curl, the reverse way to push down.
    let underhand: Bool
    /// Half the distance between the hands with the elbows straight and with them bent. Only
    /// the rope's ends move apart.
    let halves: (straight: Double, bent: Double)
    let progress: PullProgress
    let grips: [String: HandGrip]
    let stance: CableKit.Stance
    let kinds: [PropKind] = [.cable]
    private(set) var fixed: [PropPiece] = []
    /// The middle of the wheel the cable runs to, and where the stack stands.
    private(set) var pulley = V(0, -0.6, StandingCableStaging.top - 0.13)
    private(set) var column = -1.15
    /// The cable's length out of the wheel at the start of the loop, where the stack rests.
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, move: Move, handle: Handle, underhand: Bool = false, close: Bool = false) {
        let radius = handle == .rope ? CableKit.rope : handle == .vBar ? 0.015 : Self.barRadius
        let square = handle == .bar ? (underhand ? 0.3 : 0.4) : 0.0
        guard let first = guide.keyframes.first?.pose,
              let r = body.grip("r", radius: radius, square: square),
              let l = body.grip("l", radius: radius, square: square) else { return nil }
        self.body = body
        self.move = move
        self.handle = handle
        self.underhand = underhand
        switch handle {
        case .bar:
            let half = close ? 0.08 : move == .curl ? 0.17 : underhand ? 0.16 : 0.13
            halves = (half, half)
        case .vBar:
            let half = Self.vHand * cos(Self.vSlope * .pi / 180)
            halves = (half, half)
        case .ezBar:
            let (a, b) = Self.slope(move, underhand: underhand)
            halves = ((a.0 + b.0) / 2, (a.0 + b.0) / 2)
        case .rope:
            // Pushed down, the rope's ends come apart beside the thighs; curled, the fists stay
            // a little apart all the way.
            halves = move == .pushdown ? (0.17, 0.055) : (0.11, 0.13)
        }
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        stance = CableKit.Stance(body, first: first)
        let start = reach(first).centre
        switch move {
        case .pushdown:
            // The wheel hangs in front of where the hands start, so the cable leans toward the
            // body as the handle drops. It is far enough out that the cable passes in front of
            // the face all loop long, and still does when the body leans over the handle.
            pulley = V(0, start.y - CableKit.wheel - 0.04, Self.top - 0.13)
            var poses = (0...12).map { Figure.smooth(guide.keyframes, at: Double($0) / 12) }
            let fault = Figure.smooth(guide.keyframes, at: guide.faultT)
            poses += guide.steps.flatMap(\.mistakes).compactMap { m in m.pose.map { Figure.applying($0, to: fault) } }
            for pose in poses {
                let at = reach(pose)
                guard let neck = at.h["neck"] else { continue }
                let share = (neck.z + 0.1 - at.centre.z) / (pulley.z - at.centre.z)
                guard share > 0.05 else { continue }
                let leaves = at.centre.y + (neck.y - Self.face - at.centre.y) / share
                pulley.y = min(pulley.y, leaves - CableKit.wheel)
            }
            column = pulley.y - Self.boom
            fixed = CableKit.highStation(pulley: pulley, column: column, top: Self.top)
        case .curl:
            // The wheel sits near the floor a step in front of the hanging hands.
            pulley = V(0, start.y - Self.step, Self.low)
            let station = CableKit.mastStation(pulley: pulley, top: Self.top)
            fixed = station.pieces
            column = station.column
        }
        slack = (layout(first).eye - pulley).length
    }

    /// Which of the cambered bar's sloping parts the hands hold, as its inner and outer ends.
    /// The thumb's end of each fist sits a little further from the pulley when the palms face
    /// it and a little nearer when they face away, so the wrists stay straight.
    static func slope(_ move: Move, underhand: Bool) -> ((Double, Double), (Double, Double)) {
        (move == .pushdown) != underhand ? (camber[1], camber[2]) : (camber[2], camber[3])
    }

    /// The side of the wheel the cable leaves from: the body's side of the high wheel, and
    /// under the low one.
    var leaves: V { move == .pushdown ? V(0, 1, 0) : V(0, 1, -1) }

    /// The body standing on its feet, and the point midway between the hands: at the end of
    /// the forearms the keyframes give, brought in to the handle's width.
    func reach(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V, centre: V, half: Double) {
        var g = body.rotations(pose)
        let (root, h) = stance.stand(body, &g)
        let bent = progress(pose), ease = bent * bent * (3 - 2 * bent)
        let half = halves.straight + (halves.bent - halves.straight) * ease
        var elbow = V(0, 0, 0), dir = V(0, 0, 0), wide = 0.0, length = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let e = h["ulna.\(s)"], let w = h["hand.\(s)"], let grip = grips[s],
                  let rElbow = body.head["ulna.\(s)"], let rWrist = body.head["hand.\(s)"] else { continue }
            elbow = elbow + e
            dir = dir + (w - e).unit
            wide += abs(e.x)
            // The forearm ends a palm's depth short of the handle's middle line.
            let c = grip.centre
            length += (rWrist - rElbow).length + (c - grip.across * c.dot(grip.across)).length
            n += 1
        }
        guard n > 0 else { return (g, h, root, V(0, -0.4, 1.1), half) }
        elbow = elbow * (1 / n)
        elbow.x = 0
        dir.x = 0
        length /= n
        let side = wide / n - half
        let far = max(0.01, length * length - side * side).squareRoot()
        var centre = elbow + dir.unit * far
        // A handle that would sink into the thighs, the belly or the chest stops short of
        // them. The arms first swing forward from the shoulders, bent as they were, as far as
        // looks natural; what is still missing the elbows give by opening a little.
        let joints = ["r", "l"].compactMap { h["humerus.\($0)"] }
        func excess(_ p: V) -> Double { p.y - (CableKit.front(h, at: p.z) - Self.clear) }
        if joints.count == 2, excess(centre) > 0 {
            var pivot = (joints[0] + joints[1]) * 0.5
            pivot.x = 0
            let arm = centre - pivot
            // Forward is toward level with the shoulders, from below or from above.
            let way: Double = arm.z < 0 ? -1 : 1
            func swung(_ degrees: Double) -> V { pivot + M.x(way * degrees) * arm }
            var best = 0.0, least = excess(centre), found = false
            let steps = 80
            for i in 1...steps {
                let a = Self.swing * Double(i) / Double(steps), e = excess(swung(a))
                if e <= 0 {
                    // Between the last step and this one, the angle that just clears.
                    var lo = Self.swing * Double(i - 1) / Double(steps), hi = a
                    for _ in 0..<20 {
                        let mid = (lo + hi) / 2
                        if excess(swung(mid)) > 0 { lo = mid } else { hi = mid }
                    }
                    best = hi
                    found = true
                    break
                }
                if e < least { (best, least) = (a, e) }
            }
            centre = swung(best)
            if !found { centre.y -= max(0, excess(centre)) }
        }
        return (g, h, root, centre, half)
    }

    /// Everything about one pose: the body with its hands on the handle, where each hand
    /// holds and along which line, and the cable's ends.
    struct Layout {
        var frame: BodyFrame
        /// The handle's middle line under each palm, its direction from thumb to little
        /// finger, and (for the rope) the way it runs through the fist toward its end.
        var hands: [String: V]
        var across: [String: V]
        var run: [String: V]
        /// Midway between the hands, the direction from there along the cable, the swivel the
        /// cable ends at, and where the cable leaves the wheel.
        var centre, toPulley, eye, rim: V
    }

    func layout(_ pose: JointPose) -> Layout {
        var (g, h, root, centre, half) = reach(pose)
        let thorax = g["thorax"] ?? .identity
        var rim = CableKit.rim(pulley, from: centre, side: leaves)
        var c = (rim - centre).unit
        var hands: [String: V] = [:], across: [String: V] = [:], run: [String: V] = [:], poles: [String: V] = [:]
        var eye = centre + c * 0.075
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            hands[s] = centre + V(-m * half, 0, 0)
            switch handle {
            case .bar:
                across[s] = V(underhand ? m : -m, 0, 0)
            case .vBar:
                let a = Self.vSlope * .pi / 180
                across[s] = V(-m * cos(a), 0, 0) - c * sin(a)
                eye = centre + c * (Self.vHand * sin(a) + 0.06)
            case .ezBar:
                let (a, b) = Self.slope(move, underhand: underhand)
                let outward = (V(-m * (b.0 - a.0), 0, 0) - c * (b.1 - a.1)).unit
                across[s] = underhand ? outward * -1 : outward
                eye = centre + c * ((a.1 + b.1) / 2 + 0.06)
            case .rope:
                break
            }
            guard let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"] else { continue }
            // The elbow stays where the keyframes carry it, behind the hands' line.
            poles[s] = (elbow - shoulder).unit + thorax * V(-m * 0.2, 1, 0) * 0.6
        }
        if handle == .rope {
            // Pushing down, the thumbs are toward the pulley and the rope's knobs under the
            // little fingers. Curling, the knobs are on top of the fists, thumbs forward, and
            // the rope leaves each fist on the side the forearm folds away from.
            var lean = V(0, 0, 0)
            if move == .curl, let shoulder = h["humerus.r"], let elbow = h["ulna.r"], let wrist = h["hand.r"] {
                let fore = (wrist - elbow).unit
                var fold = (shoulder - elbow).unit + thorax * Body3D.forward * 0.3
                fold.x = 0
                fold = fold - fore * fold.dot(fore)
                lean = fold.unit * -1.5
            }
            let held = CableKit.holdRope(body, grips, hands: hands, poles: poles, pulley: pulley, side: leaves,
                                         thumbsIn: move == .pushdown, lean: lean, &g, h, root: root)
            (across, run, eye, rim) = (held.across, held.run, held.eye, held.rim)
            c = (rim - eye).unit
        } else {
            for s in ["r", "l"] {
                guard let grip = grips[s], let at = hands[s], let line = across[s], let pole = poles[s] else { continue }
                body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            }
        }
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: across, run: run, centre: centre,
                      toPulley: c, eye: eye, rim: CableKit.rim(pulley, from: eye, side: leaves))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        let c = at.toPulley, left = V(1, 0, 0)
        var p: [PropPiece] = []
        switch handle {
        case .bar:
            let end = max(0.25, halves.straight + 0.1)
            p.append(Plan.rod(at.centre - left * end, at.centre + left * end, Self.barRadius, .metal))
            for m in [-1.0, 1.0] { p.append(Plan.ball(at.centre + left * (m * end), Self.barRadius, .metal)) }
            p += CableKit.swivel(from: at.centre, eye: at.eye)
        case .vBar:
            let a = Self.vSlope * .pi / 180
            let apex = at.centre + c * (Self.vHand * sin(a))
            for m in [-1.0, 1.0] {
                let along = left * (m * cos(a)) - c * sin(a)
                let tip = apex + along * Self.vLength
                p.append(Plan.rod(apex, tip, 0.012, .metal))
                p.append(Plan.rod(apex + along * 0.045, tip, 0.015, .dark))
                p.append(Plan.ball(tip, 0.015, .dark))
            }
            p.append(Plan.ball(apex, 0.012, .metal))
            p += CableKit.swivel(from: apex, eye: at.eye)
        case .ezBar:
            let (a, b) = Self.slope(move, underhand: underhand)
            let line = at.centre + c * ((a.1 + b.1) / 2)
            for m in [-1.0, 1.0] {
                let points = Self.camber.map { line + left * (m * $0.0) - c * $0.1 }
                for (from, to) in zip(points, points.dropFirst()) {
                    p.append(Plan.rod(from, to, Self.barRadius, .metal))
                    p.append(Plan.ball(to, Self.barRadius, .metal))
                }
            }
            p += CableKit.swivel(from: line, eye: at.eye)
        case .rope:
            p += CableKit.ropePieces(eye: at.eye, hands: at.hands, run: at.run)
        }
        p.append(Plan.rod(at.eye, at.rim, CableKit.cable, .cable))
        p += liftedPlates(y: column, height: Self.top, travel: max(0, (at.eye - pulley).length - slack))
        return (at.frame, p)
    }
}

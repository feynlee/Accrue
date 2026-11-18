import Foundation

// MARK: - Lat pulldown, the other grips

/// The cable pulldown of `PulldownStaging`, on the same machine, for the other ways to hold
/// it: palms away on the lat bar with the hands wide or close, palms toward the face, and
/// palms facing each other on a bar with two handles or on the close V handle. The handle
/// hangs under the pulley at arm's length and comes down in front of the face to the top of
/// the chest; the stack rises as far as the cable is drawn out.
struct PulldownGripStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Palms away from the face, toward it, or facing each other.
    enum Grip: Sendable { case over, under, neutral }
    /// The long lat bar with bent ends, a bar with a handle hanging at each end for the
    /// palms to face each other, or the close handle with two grips side by side.
    enum Handle: Sendable { case latBar, parallelBar, vHandle }

    static let barRadius = PulldownStaging.barRadius
    /// Half the distance between the two grips of the close handle, and how far above the
    /// grips its swivel is.
    static let vHalf = 0.07, vEye = 0.16
    /// How far under their bar the handles of the parallel bar hang.
    static let drop = 0.07

    let body: Body3D
    let progress: PullProgress
    let grip: Grip
    let handle: Handle
    let halfGrip: Double
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.pulldown]
    let fixed: [PropPiece]
    let hip: V
    let pulley: V
    let column: V
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, grip: Grip, handle: Handle, halfGrip: Double) {
        // The machine itself is the starter pulldown's, seat, pads, stack and all.
        guard let machine = PulldownStaging(guide, body) else { return nil }
        let radius = handle == .latBar ? Self.barRadius : 0.015
        // A wide hand lies squarer across a straight bar than a narrow one.
        let square = handle != .latBar ? 0.0 : grip == .under ? 0.3 : halfGrip > 0.2 ? 0.6 : 0.3
        guard let r = body.grip("r", radius: radius, square: square),
              let l = body.grip("l", radius: radius, square: square) else { return nil }
        self.body = body
        self.grip = grip
        self.handle = handle
        self.halfGrip = handle == .vHandle ? Self.vHalf : halfGrip
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        fixed = machine.fixed
        hip = machine.hip
        pulley = machine.pulley
        column = machine.column
        if let first = guide.keyframes.first?.pose { slack = (pulley - solve(first).bar).length }
    }

    /// Which way the handle runs under the hand of side `m` (1 right, -1 left) from thumb to
    /// little finger, and where that elbow goes.
    func line(_ m: Double, thorax: M) -> (across: V, pole: V) {
        switch grip {
        case .over:
            let wide = halfGrip > 0.2
            return (V(-m, 0, 0), thorax * (wide ? V(-m * 0.4, 0.3, -1) : V(-m * 0.3, -0.2, -1)))
        case .under:
            return (V(m, 0, 0), thorax * V(-m * 0.15, -0.4, -1))
        case .neutral:
            // The close handle's grips lean, their tops toward the pulley, as a relaxed fist holds them.
            let tilt = handle == .vHandle ? SeatedRowStaging.tilt * .pi / 180 : 0
            return (V(0, -cos(tilt), -sin(tilt)), thorax * V(-m * (halfGrip > 0.2 ? 0.4 : 0.25), -0.25, -1))
        }
    }

    /// The posed body, and the middle of the line between the two hands.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V) {
        var g = body.rotations(pose)
        var h = body.place(g, root: hip)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let rHip = body.head["femur.\(s)"], let rKnee = body.head["shin.\(s)"] else { continue }
            let ankle = V(-m * 0.1, -(rKnee - rHip).length + 0.01, body.ankleHeight)
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
        }
        h = body.place(g, root: hip)
        let thorax = g["thorax"] ?? .identity
        let u = progress(pose)

        // Arms long: the handle hangs straight under the pulley as high as the hands can follow.
        var sum = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let shoulder = h["humerus.\(s)"], let grip = grips[s] else { continue }
            let reach = body.reach(s, grip, bend: 8)
            let dx = (s == "r" ? -halfGrip : halfGrip) - shoulder.x, dy = pulley.y - shoulder.y
            sum += shoulder.z + max(0, reach * reach - dx * dx - dy * dy).squareRoot()
            n += 1
        }
        let high = V(0, pulley.y, n > 0 ? sum / n : 1.5)
        // The squeeze: the handle at the top of the chest, or behind the neck for that mistake.
        let neck = h["neck"] ?? high
        let behind = (pose.angles["shoulderRot"] ?? 0) > 15
        let low = neck + thorax * (behind ? V(0, 0.1, 0.0) : V(0, -0.16, -0.105))
        // Down in front of the face first, then in to the chest.
        var bar = V(0, high.y + (low.y - high.y) * pow(u, 1.6), high.z + (low.z - high.z) * u)
        // It never cuts through the face, however the head is held. The close handle's frame
        // and the parallel bar's own bar ride above the hands, and must clear the face too.
        if !behind {
            let headTurn = g["head"] ?? thorax
            let clear = (handle == .latBar ? Self.barRadius : 0.03) + 0.025
            let above = handle == .vHandle ? Self.vEye : handle == .parallelBar ? Self.drop : 0
            for (forward, up) in PullUpStaging.face {
                let p = neck + headTurn * V(0, -forward, up)
                let dz = max(0, abs(bar.z + above / 2 - p.z) - above / 2)
                guard dz < clear else { continue }
                bar.y = min(bar.y, p.y - (clear * clear - dz * dz).squareRoot())
            }
        }

        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            let (across, pole) = line(m, thorax: thorax)
            body.hold(s, grip, at: bar + V(-m * halfGrip, 0, 0), across: across, pole: pole, &g, h)
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose)
        var p: [PropPiece] = []
        var eye = bar + V(0, 0, 0.075)
        switch handle {
        case .latBar:
            // The lat bar: straight in the middle, its ends bent down, with rubber grips on the ends.
            let bend = 0.46, tip = V(0.19 * cos(0.38), 0, -0.19 * sin(0.38))
            p.append(Plan.rod(bar - V(bend, 0, 0), bar + V(bend, 0, 0), Self.barRadius, .metal))
            for m in [-1.0, 1.0] {
                let a = bar + V(m * bend, 0, 0), b = a + V(m * tip.x, 0, tip.z)
                p.append(Plan.rod(a, b, Self.barRadius, .metal))
                p.append(Plan.ball(a, Self.barRadius, .metal))
                p.append(Plan.rod(a + (b - a) * 0.25, b, Self.barRadius + 0.004, .dark))
            }
            p.append(Plan.rod(bar, eye, 0.007, .metal))
        case .parallelBar:
            // A straight bar with a stirrup hanging at each end: the grip runs front to back.
            let top = bar + V(0, 0, Self.drop)
            eye = top + V(0, 0, 0.075)
            p.append(Plan.rod(top - V(halfGrip + 0.03, 0, 0), top + V(halfGrip + 0.03, 0, 0), Self.barRadius, .metal))
            for m in [-1.0, 1.0] {
                let centre = bar + V(m * halfGrip, 0, 0)
                let a = centre + V(0, -0.07, 0), b = centre + V(0, 0.07, 0)
                p.append(Plan.rod(a, b, 0.015, .dark))
                for end in [a, b] {
                    p.append(Plan.rod(end, V(end.x, top.y, top.z), 0.006, .metal))
                    p.append(Plan.ball(end, 0.008, .metal))
                }
                p.append(Plan.ball(top + V(m * (halfGrip + 0.03), 0, 0), Self.barRadius, .metal))
            }
            p.append(Plan.rod(top, eye, 0.007, .metal))
        case .vHandle:
            // The close handle: two grips, each on a loop that runs up to the swivel.
            let across = line(1, thorax: .identity).across
            eye = bar + V(0, 0, Self.vEye)
            for m in [-1.0, 1.0] {
                let centre = bar + V(m * halfGrip, 0, 0)
                let a = centre - across * 0.065, b = centre + across * 0.065
                p.append(Plan.rod(a, b, 0.015, .dark))
                for end in [a, b] {
                    p.append(Plan.rod(end, eye, 0.006, .metal))
                    p.append(Plan.ball(end, 0.008, .metal))
                }
            }
        }
        p.append(Plan.ball(eye, 0.014, .metal))
        p.append(Plan.rod(eye, V(0, pulley.y, pulley.z + 0.02), 0.004, .cable))
        // The plates the cable lifts.
        p += liftedPlates(y: column.y, height: pulley.z + 0.2, travel: max(0, (pulley - bar).length - slack))
        return (frame, p)
    }
}

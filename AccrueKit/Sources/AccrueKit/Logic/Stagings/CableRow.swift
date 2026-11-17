import Foundation

// MARK: - Seated cable row, the other handles

/// The seated cable row of `SeatedRowStaging`, on the same bench, foot plates and stack, with
/// the other handles: a straight bar held wide with the palms down or at shoulder width with
/// the palms up, and the rope. The handle travels along the cable's line from long arms to the
/// belly, and the stack rises as far as the cable is drawn out.
struct SeatedRowGripStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// A straight bar with the palms down or up, or the rope.
    enum Handle: Sendable { case barOver, barUnder, rope }

    static let barRadius = 0.014
    /// Half the distance between the hands on the rope with the arms long, and at the belly.
    static let ropeFar = 0.06, ropeNear = 0.19

    let body: Body3D
    let progress: PullProgress
    let handle: Handle
    let halfGrip: Double
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.cable, .bench]
    let fixed: [PropPiece]
    let hip: V
    let pulley: V
    /// The middle of the low wheel the cable runs over.
    let wheel: V
    let ankles: [String: V]
    let foot: M
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, handle: Handle, halfGrip: Double = 0) {
        // The bench, the foot plates and the stack are the starter row's.
        guard let machine = SeatedRowStaging(guide, body) else { return nil }
        let radius = handle == .rope ? CableKit.rope : Self.barRadius
        let square = handle == .barOver ? 0.5 : handle == .barUnder ? 0.3 : 0.0
        guard let r = body.grip("r", radius: radius, square: square),
              let l = body.grip("l", radius: radius, square: square) else { return nil }
        self.body = body
        self.handle = handle
        self.halfGrip = halfGrip
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        fixed = machine.fixed
        hip = machine.hip
        pulley = machine.pulley
        wheel = V(0, machine.pulley.y - CableKit.wheel, machine.pulley.z)
        ankles = machine.ankles
        foot = machine.foot
        if let first = guide.keyframes.first?.pose { slack = (layout(first).eye - wheel).length }
    }

    struct Layout {
        var frame: BodyFrame
        /// The handle's middle line under each palm, and its direction from thumb to little finger.
        var hands: [String: V]
        var across: [String: V]
        /// The way the rope runs through each fist toward its end.
        var run: [String: V]
        /// Midway between the hands, the swivel, and where the cable meets the wheel.
        var centre, eye, rim: V
    }

    func layout(_ pose: JointPose) -> Layout {
        var g = body.rotations(pose)
        var h = body.place(g, root: hip)
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: foot, pole: V(0, -0.2, 1), &g, h)
        }
        h = body.place(g, root: hip)
        let thorax = g["thorax"] ?? .identity
        let u = progress(pose)
        let half = handle == .rope ? Self.ropeFar + (Self.ropeNear - Self.ropeFar) * u * u * (3 - 2 * u) : halfGrip

        // The squeeze: a bar against the belly, or the rope's ends drawn past the ribs.
        let waist = h["thorax"] ?? hip
        let lumbar = g["lumbar"] ?? .identity
        let near: V
        switch handle {
        case .barOver: near = waist + lumbar * V(0, -0.195, -0.03)
        case .barUnder: near = waist + lumbar * V(0, -0.185, -0.06)
        case .rope: near = waist + lumbar * V(0, -0.12, -0.02)
        }
        // Arms long: the handle on the line from the shoulders to the pulley.
        let shoulders = ["r", "l"].compactMap { h["humerus.\($0)"] }
        var mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
        let wide = shoulders.first.map { abs($0.x - mid.x) } ?? 0.17
        mid.x = 0
        let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: 8) } }.reduce(0, +) / 2
        let lateral = wide - half
        let far = mid + (wheel + V(0, 0, CableKit.wheel) - mid).unit * max(0, reach * reach - lateral * lateral).squareRoot()
        let centre = mix(far, near, u)

        let top = V(0, 0, 1)
        var rim = CableKit.rim(wheel, from: centre, side: top)
        var eye = centre + (rim - centre).unit * 0.075
        var hands: [String: V] = [:], across: [String: V] = [:], run: [String: V] = [:], poles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            hands[s] = centre + V(-m * half, 0, 0)
            switch handle {
            case .barOver:
                // Wide hands, palms down: the elbows travel out to the sides.
                across[s] = V(-m, 0, 0)
                poles[s] = thorax * V(-m * 1, 0.7, -0.35)
            case .barUnder:
                across[s] = V(m, 0, 0)
                poles[s] = thorax * V(-m * 0.15, 1, -0.7)
            case .rope:
                poles[s] = thorax * V(-m * 0.3, 1, -0.5)
            }
        }
        if handle == .rope {
            let held = CableKit.holdRope(body, grips, hands: hands, poles: poles, pulley: wheel, side: top, lean: V(0, 0, -1), &g, h, root: hip)
            (across, run, eye, rim) = (held.across, held.run, held.eye, held.rim)
        } else {
            for s in ["r", "l"] {
                guard let grip = grips[s], let at = hands[s], let line = across[s], let pole = poles[s] else { continue }
                body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            }
        }
        h = body.place(g, root: hip)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: across, run: run, centre: centre, eye: eye, rim: rim)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        var p: [PropPiece] = []
        if handle == .rope {
            p += CableKit.ropePieces(eye: at.eye, hands: at.hands, run: at.run)
        } else {
            // A straight bar a little longer than the grip, with a cap on each end.
            let end = V(max(0.25, halfGrip + 0.12), 0, 0)
            p.append(Plan.rod(at.centre - end, at.centre + end, Self.barRadius, .metal))
            for m in [-1.0, 1.0] { p.append(Plan.ball(at.centre + end * m, Self.barRadius, .metal)) }
            p += CableKit.swivel(from: at.centre, eye: at.eye)
        }
        p.append(Plan.rod(at.eye, at.rim, CableKit.cable, .cable))
        // The plates the cable lifts.
        p += liftedPlates(y: pulley.y - 0.3, height: SeatedRowStaging.stackHeight, travel: max(0, (at.eye - wheel).length - slack))
        return (at.frame, p)
    }
}

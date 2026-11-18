import Foundation

// MARK: - Seated cable row, the other handles

/// The seated cable row of `SeatedRowStaging` with the other handles, seats and pulleys: a
/// straight bar held wide with the palms down or at shoulder width with the palms up, the rope
/// or the close handle; on the row bench, on the floor with the legs out, or on the knees; from
/// the low wheel to the belly or from a high one down to the chest. The handle travels along
/// the cable's line from long arms to the body, and the stack rises as the cable is drawn out.
struct SeatedRowGripStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// A straight bar with the palms down or up, the rope, the close handle with two grips, or
    /// a stirrup for the right hand alone while the left arm hangs.
    enum Handle: Sendable { case barOver, barUnder, rope, close, single }
    /// The row bench with its foot plates, the floor with the feet against plates, or the knees.
    enum Seat: Sendable { case bench, floor, knees }
    /// The wheel the cable comes from: low in front, high on a mast, or nearly overhead (a
    /// pulldown with one arm, done on the knees).
    enum Pulley: Sendable { case low, high, overhead }

    static let barRadius = 0.014
    /// Half the distance between the hands on the rope with the arms long, and at the belly.
    static let ropeFar = 0.06, ropeNear = 0.19
    /// Half the distance between the close handle's two grips, and how far ahead of them its swivel is.
    static let closeHalf = 0.07, closeEye = 0.16
    /// A stirrup's ring ahead of its grip, and how far to the side one hand finishes.
    static let ring = 0.13, beside = 0.2
    /// How far in front of the hips a wheel overhead hangs.
    static let overheadAhead = 0.55
    /// A high wheel's height above the hip joints, the mast's height, and the floor row's
    /// wheel: its height and how far beyond the feet it stands.
    static let highAbove = 1.3, mastTop = 2.2, floorWheel = 0.36, beyondFeet = 0.42

    let body: Body3D
    let progress: PullProgress
    let handle: Handle
    let halfGrip: Double
    let grips: [String: HandGrip]
    let seat: Seat
    let from: Pulley
    /// The ends of the bar are bent back toward the body, beyond the hands.
    let bent: Bool
    /// The legs' fit when the row is done on the knees.
    let posture: PostureStaging?
    let kinds: [PropKind]
    let fixed: [PropPiece]
    let hip: V
    let pulley: V
    /// The middle of the wheel the cable runs over, and the side of it the cable leaves from.
    let wheel: V
    let leaves: V
    let ankles: [String: V]
    let foot: M
    /// Where the stack stands, and how tall its frame is.
    let column, stackTop: Double
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, handle: Handle, halfGrip: Double = 0, seat: Seat = .bench,
          from: Pulley = .low, bent: Bool = false) {
        // The bench, the foot plates and the stack are the starter row's.
        guard let machine = SeatedRowStaging(guide, body) else { return nil }
        let radius = handle == .rope ? CableKit.rope : handle == .close || handle == .single ? SeatedRowStaging.gripRadius : Self.barRadius
        let square = handle == .barOver ? 0.5 : handle == .barUnder ? 0.3 : 0.0
        guard let r = body.grip("r", radius: radius, square: square),
              let l = body.grip("l", radius: radius, square: square),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let rToe = body.tail["toes.r"] else { return nil }
        self.body = body
        self.handle = handle
        self.halfGrip = handle == .close ? Self.closeHalf : halfGrip
        self.seat = seat
        self.from = from
        self.bent = bent
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        pulley = machine.pulley

        var pieces: [PropPiece] = []
        var posture: PostureStaging?
        switch seat {
        case .bench:
            hip = machine.hip
            ankles = machine.ankles
            foot = machine.foot
            // The machine's pieces start with its bench and foot plates: the pad, two legs with
            // their feet, the beam along the floor, and a plate and its brace under each sole.
            pieces = from == .low ? machine.fixed : Array(machine.fixed.prefix(10))
        case .floor:
            // Sitting on the floor with the legs out and a little bent, the soles on plates.
            let ankle = body.ankleHeight + 0.01
            hip = V(0, 0, MachineFit.seat + 0.005)
            let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: 22)
            let out = 0.045, drop = hip.z - ankle
            let forward = max(0, leg * leg - drop * drop - out * out).squareRoot()
            ankles = ["r": V(-(abs(rHip.x) + out), -forward, ankle), "l": V(abs(rHip.x) + out, -forward, ankle)]
            foot = M.x(-74)
            let sole = V(0, -0.045, -(rAnkle.z - (rToe.z - 0.01)))
            for s in ["r", "l"] {
                guard let at = ankles[s] else { continue }
                let centre = at + foot * sole, normal = foot * V(0, 0, 1), along = foot * V(0, -1, 0)
                pieces.append(Plan.box(centre - normal * 0.012 + along * 0.02, (0.15, 0.3, 0.024), x: V(1, 0, 0), z: normal, .dark))
                pieces.append(Plan.rod(centre - normal * 0.024, V(centre.x * 0.4, centre.y - 0.16, 0.05), 0.02, .metal))
            }
        case .knees:
            guard let knelt = PostureStaging(guide, body, .kneel(half: false)) else { return nil }
            posture = knelt
            hip = knelt.hip
            ankles = [:]
            foot = .identity
        }
        self.posture = posture

        if seat == .bench, from == .low {
            wheel = V(0, machine.pulley.y - CableKit.wheel, machine.pulley.z)
            leaves = V(0, 0, 1)
            column = machine.pulley.y - 0.3
            stackTop = SeatedRowStaging.stackHeight
        } else {
            // A wheel on a mast: high above the hips, or low just beyond the feet. Its cable
            // comes down the far side of the mast and leaves from under the wheel.
            let feet = ankles.values.map(\.y).min() ?? -0.75
            switch from {
            case .high: wheel = V(0, machine.pulley.y, hip.z + Self.highAbove)
            case .overhead: wheel = V(0, -Self.overheadAhead, Self.mastTop - 0.2)
            case .low: wheel = V(0, feet - Self.beyondFeet, Self.floorWheel)
            }
            leaves = V(0, 1, -1)
            let station = CableKit.mastStation(pulley: wheel, top: Self.mastTop)
            pieces += station.pieces
            column = station.column
            stackTop = Self.mastTop
        }
        fixed = pieces
        kinds = seat == .bench ? [.cable, .bench] : [.cable]
        slack = (0...24).map { (layout(Figure.smooth(guide.keyframes, at: Double($0) / 24)).eye - wheel).length }.min() ?? 0
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
        let pose = handle == .single ? CableKit.oneArmed(pose) : pose
        var g: [String: M], h: [String: V], root = hip
        if let posture {
            (g, h, root) = posture.settle(pose)
        } else {
            g = body.rotations(pose)
            h = body.place(g, root: hip)
            for s in ["r", "l"] {
                guard let ankle = ankles[s] else { continue }
                body.plant(s, ankle: ankle, foot: foot, pole: V(0, -0.2, 1), &g, h)
            }
            h = body.place(g, root: hip)
        }
        let thorax = g["thorax"] ?? .identity
        let u = progress(pose)
        let half = handle == .rope ? Self.ropeFar + (Self.ropeNear - Self.ropeFar) * u * u * (3 - 2 * u) : halfGrip

        // The squeeze: a bar against the belly, or the rope's ends drawn past the ribs. From a
        // high wheel the handle comes to the top of the chest instead.
        let waist = h["thorax"] ?? hip
        let lumbar = g["lumbar"] ?? .identity
        let near: V
        switch (handle, from) {
        case (.barOver, .low): near = waist + lumbar * V(0, -0.195, -0.03)
        case (.barUnder, .low): near = waist + lumbar * V(0, -0.185, -0.06)
        case (.rope, .low): near = waist + lumbar * V(0, -0.12, -0.02)
        case (.close, .low): near = waist + lumbar * V(0, -0.235, -0.03)
        case (.barOver, .high), (.barUnder, .high): near = waist + thorax * V(0, -0.205, 0.15)
        case (.rope, .high): near = waist + thorax * V(0, -0.14, 0.14)
        case (.close, .high): near = waist + thorax * V(0, -0.25, 0.13)
        // One hand comes back beside the ribs, or down beside the chest.
        case (.single, .low): near = waist + lumbar * V(-Self.beside, -0.07, -0.04)
        case (.single, .high): near = waist + thorax * V(-Self.beside, -0.1, 0.12)
        // Pulled down from overhead, the hand finishes beside the shoulder.
        case (_, .overhead): near = waist + thorax * V(handle == .single ? -Self.beside - 0.03 : 0, -0.12, 0.2)
        }
        // Arms long: the handle on the line from the shoulders to the pulley.
        let shoulders = ["r", "l"].compactMap { h["humerus.\($0)"] }
        var mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
        let wide = shoulders.first.map { abs($0.x - mid.x) } ?? 0.17
        mid.x = 0
        let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: 8) } }.reduce(0, +) / 2
        let lateral = wide - half
        let aim = from == .low && seat == .bench ? wheel + V(0, 0, CableKit.wheel) : wheel
        var far = mid + (aim - mid).unit * max(0, reach * reach - lateral * lateral).squareRoot()
        if handle == .single, let shoulder = h["humerus.r"], let grip = grips["r"] {
            // The one arm reaches from its own shoulder straight at the wheel.
            far = shoulder + (aim - shoulder).unit * body.reach("r", grip, bend: 8)
        }
        let centre = mix(far, near, u)

        let top = leaves
        var rim = CableKit.rim(wheel, from: centre, side: top)
        let c = (rim - centre).unit
        var eye = centre + c * (handle == .close ? Self.closeEye : handle == .single ? Self.ring : 0.075)
        // Pulling down from a high wheel the elbows travel down as well as back.
        let down = from == .high ? -0.5 : from == .overhead ? -1.2 : 0.0
        var hands: [String: V] = [:], across: [String: V] = [:], run: [String: V] = [:], poles: [String: V] = [:]
        for (s, m) in handle == .single ? [("r", 1.0)] : [("r", 1.0), ("l", -1.0)] {
            hands[s] = centre + V(-m * half, 0, 0)
            switch handle {
            case .single:
                // The grip stands square across the cable, thumb up, the elbow close to the side.
                across[s] = SeatedRowStaging.axes(centre, pulley: rim).grip * -1
                poles[s] = thorax * V(-m * 0.15, 1, -0.6 + down)
            case .barOver:
                // Wide hands, palms down: the elbows travel out to the sides.
                across[s] = V(-m, 0, 0)
                poles[s] = thorax * V(-m * 1, 0.7, -0.35 + down)
            case .barUnder:
                across[s] = V(m, 0, 0)
                poles[s] = thorax * V(-m * 0.15, 1, -0.7 + down)
            case .rope:
                poles[s] = thorax * V(-m * 0.3, 1, -0.5 + down)
            case .close:
                // Each grip stands square across the cable, its top leaning toward the wheel.
                across[s] = SeatedRowStaging.axes(centre, pulley: rim).grip * -1
                poles[s] = thorax * V(-m * 0.25, 1, -0.5 + down)
            }
        }
        if handle == .rope {
            let held = CableKit.holdRope(body, grips, hands: hands, poles: poles, pulley: wheel, side: top, lean: V(0, 0, -1), &g, h, root: root)
            (across, run, eye, rim) = (held.across, held.run, held.eye, held.rim)
        } else {
            for s in ["r", "l"] {
                guard let grip = grips[s], let at = hands[s], let line = across[s], let pole = poles[s] else { continue }
                body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            }
        }
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: across, run: run, centre: centre, eye: eye, rim: rim)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        var p: [PropPiece] = []
        switch handle {
        case .rope:
            p += CableKit.ropePieces(eye: at.eye, hands: at.hands, run: at.run)
        case .close:
            // The double-D handle of the starter row: two grips, each on a loop to the swivel.
            for s in ["r", "l"] {
                guard let hand = at.hands[s], let line = at.across[s] else { continue }
                let a = hand - line * 0.065, b = hand + line * 0.065
                p.append(Plan.rod(a, b, SeatedRowStaging.gripRadius, .dark))
                for end in [a, b] {
                    p.append(Plan.rod(end, at.eye, 0.006, .metal))
                    p.append(Plan.ball(end, 0.008, .metal))
                }
            }
            p.append(Plan.ball(at.eye, 0.014, .metal))
        case .single:
            // A stirrup: a grip, and a strap from each of its ends to the ring.
            if let hand = at.hands["r"], let line = at.across["r"] {
                let a = hand - line * 0.065, b = hand + line * 0.065
                p.append(Plan.rod(a, b, SeatedRowStaging.gripRadius, .dark))
                for end in [a, b] {
                    p.append(Plan.rod(end, at.eye, 0.006, .metal))
                    p.append(Plan.ball(end, 0.008, .metal))
                }
            }
            p.append(Plan.ball(at.eye, 0.014, .metal))
        case .barOver, .barUnder:
            // A straight bar a little longer than the grip, with a cap on each end; or one
            // whose ends are bent back toward the body beyond the hands.
            let end = V(max(0.25, halfGrip + (bent ? 0.07 : 0.12)), 0, 0)
            p.append(Plan.rod(at.centre - end, at.centre + end, Self.barRadius, .metal))
            let back = (at.centre - at.eye).unit
            for m in [-1.0, 1.0] {
                let corner = at.centre + end * m
                p.append(Plan.ball(corner, Self.barRadius, .metal))
                guard bent else { continue }
                let tip = corner + (V(m, 0, 0) * 0.75 + back * 0.66).unit * 0.13
                p.append(Plan.rod(corner, tip, Self.barRadius, .metal))
                p.append(Plan.rod(corner + (tip - corner) * 0.25, tip, Self.barRadius + 0.004, .dark))
                p.append(Plan.ball(tip, Self.barRadius + 0.004, .dark))
            }
            p += CableKit.swivel(from: at.centre, eye: at.eye)
        }
        p.append(Plan.rod(at.eye, at.rim, CableKit.cable, .cable))
        // The plates the cable lifts.
        p += liftedPlates(y: column, height: stackTop, travel: max(0, (at.eye - wheel).length - slack))
        return (at.frame, p)
    }
}

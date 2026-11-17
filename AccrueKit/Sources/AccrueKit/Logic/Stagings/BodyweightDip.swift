import Foundation

// MARK: - Dip on parallel bars

/// A dip between two parallel bars. The hands never move: each is closed on its bar with the
/// wrist over it, and the body is carried between the bars with its weight over the hands, so
/// it leans forward as it sinks. How deep it sinks is the elbow bend the keyframes give, which
/// keeps the "too deep" and "shrug" mistakes showing.
struct DipStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let barHeight = 1.2, halfWidth = 0.27, barRadius = 0.019
    /// The shoulders never sink closer to the bars than this, however deep the elbows are asked to bend.
    static let lowest = 0.17

    let body: Body3D
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.dipBars]
    let fixed: [PropPiece]
    /// A plate hung from a belt, for the weighted dips.
    let loaded: Bool
    /// Half the distance between the bars: wider than the standard for a wide-grip dip.
    let half: Double

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let r = body.grip("r", radius: Self.barRadius), let l = body.grip("l", radius: Self.barRadius) else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        loaded = guide.equipment == "weighted" || guide.exerciseName.contains("weighted")
        let half = guide.exerciseName.contains("wide") ? Self.halfWidth + 0.07 : Self.halfWidth
        self.half = half
        let z = Self.barHeight
        var p: [PropPiece] = []
        // Each bar on two uprights, on a runner along the floor; a brace joins the two at the back.
        let front = -0.42, back = 0.4
        for x in [-half, half] {
            p.append(Plan.rod(V(x, front, z), V(x, back, z), Self.barRadius, .metal))
            for y in [front, back] { p.append(Plan.ball(V(x, y, z), Self.barRadius, .metal)) }
            for y in [front + 0.07, back - 0.07] {
                p.append(Plan.box(V(x, y, (z - Self.barRadius * 0.5) / 2), (0.05, 0.05, z - Self.barRadius * 0.5), .metal))
            }
            p.append(Plan.box(V(x, (front + back) / 2, 0.02), (0.07, back - front + 0.1, 0.04), .metal))
        }
        p.append(Plan.box(V(0, back - 0.07, 0.02), (2 * half, 0.07, 0.04), .metal))
        fixed = p
    }

    func hold(_ s: String) -> V { V(s == "r" ? -half : half, 0, Self.barHeight) }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let shoulders = ["r", "l"].compactMap { rel["humerus.\($0)"] }
        let mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))

        // The body's weight rests over the hands (the arms are a tenth of it, halfway up).
        let weight = body.balance(g, rel)
        let y = -(0.9 * weight.y + 0.05 * mid.y) / 0.95

        // The shoulders are as far above the bars as the bent arms hold them.
        let bend = min(140, max(4, pose.angles["elbowFlex"] ?? 0))
        var sum = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let shoulder = rel["humerus.\(s)"], let grip = grips[s] else { continue }
            let reach = body.reach(s, grip, bend: bend)
            let dx = hold(s).x - shoulder.x, dy = shoulder.y + y
            sum += Self.barHeight + max(Self.lowest, max(0, reach * reach - dx * dx - dy * dy).squareRoot()) - shoulder.z
            n += 1
        }
        let root = V(0, y, n > 0 ? sum / n : Self.barHeight)
        var h = body.place(g, root: root)

        // Elbows point back, and out as far as the upper arms are held from the sides.
        let flare = tan(min(60, max(0, pose.angles["shoulderAbd"] ?? 20)) * .pi / 180) * 0.8
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: hold(s), across: V(0, 1, 0), pole: V(-m * flare, 1, 0.15), &g, h)
        }
        h = body.place(g, root: root)

        let props = loaded ? BodyweightStagings.beltPlate(g, h) : []
        return (body.made(g, h, floor: 0), props)
    }
}

// MARK: - Bench dip

/// A dip off the edge of a bench: the hands on the edge behind the hips with the fingers over
/// it, the heels on the floor (or on a second bench), and the hips sliding down and up just in
/// front of the bench as the elbows bend back.
struct BenchDipStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Where the feet rest.
    enum Feet: Sendable { case heels, flat, raised }

    static let top = 0.44, depth = 0.3, halfHands = 0.21
    /// How far the hips stay in front of the bench's edge, and how near the floor they may come.
    static let hipsOut = 0.16, hipsLowest = 0.2

    let body: Body3D
    let hands: [String: HandPress]
    let kinds: [PropKind]
    let fixed: [PropPiece]
    let feet: Feet
    let ankles: [String: V]
    let foot: M
    /// What lies on the lap, if anything.
    let load: PropKind?

    init?(_ guide: HowToGuide, _ body: Body3D, feet: Feet) {
        guard let r = body.flatHand("r", curl: [72, 25, 10]), let l = body.flatHand("l", curl: [72, 25, 10]),
              let rHip = body.head["femur.r"] else { return nil }
        self.body = body
        self.feet = feet
        hands = ["r": r, "l": l]
        load = guide.equipment == "dumbbell" ? .dumbbell : guide.equipment == "weighted" ? .plate : nil
        kinds = [.bench] + (load.map { [$0] } ?? [])

        var p = Self.bench(front: 0)
        // The hips' height at the top and at the deepest the loop (or a mistake) takes them.
        let bends = guide.keyframes.map { $0.pose.angles["elbowFlex"] ?? 0 }
        let first = guide.keyframes.first?.pose ?? JointPose(angles: [:])
        let high = Self.root(first, bend: bends.min() ?? 5, body: body, hands: hands).z
        let low = Self.root(first, bend: min(125, (bends.max() ?? 95) + 20), body: body, hands: hands).z
        // The feet go as far out as the legs reach all the way down and up without sliding.
        let toesUp: Double, ankleZ: Double, knee: Double
        switch feet {
        case .heels: (toesUp, ankleZ, knee) = (50, Self.heelLift(body, toesUp: 50), 12)
        case .raised: (toesUp, ankleZ, knee) = (50, Self.top + Self.heelLift(body, toesUp: 50), 12)
        case .flat: (toesUp, ankleZ, knee) = (0, body.ankleHeight, 75)
        }
        let leg = body.legSpan(bend: knee)
        let far = [high, low].map { max(0.01, leg * leg - ($0 - ankleZ) * ($0 - ankleZ)).squareRoot() }.min() ?? 0.5
        let y = -Self.hipsOut - far
        ankles = ["r": V(rHip.x - 0.015, y, ankleZ), "l": V(-rHip.x + 0.015, y, ankleZ)]
        foot = M.x(-toesUp)
        if feet == .raised { p += Self.bench(front: y - Self.depth + 0.1) }
        fixed = p
    }

    /// A flat bench lying across behind the body, its front edge at `front`.
    static func bench(front: Double) -> [PropPiece] {
        var p = [Plan.box(V(0, front + depth / 2, top - 0.04), (1.1, depth, 0.08), .pad)]
        for x in [-0.43, 0.43] {
            p.append(Plan.box(V(x, front + depth / 2, (top - 0.08) / 2), (0.05, 0.24, top - 0.08), .metal))
        }
        return p
    }

    /// How high the ankle is when the foot rests on the back of its heel with the toes up.
    static func heelLift(_ body: Body3D, toesUp: Double) -> Double {
        let heel = M.x(-toesUp) * V(0, 0.03, -(body.ankleHeight - 0.036))
        return 0.036 - heel.z
    }

    /// Where the middle knuckle of each hand rests: on the edge, so the fingers hang over it.
    static func knuckle(_ s: String) -> V { V(s == "r" ? -halfHands : halfHands, -0.012, top) }

    /// The pelvis for one pose with the elbows bent by `bend`: just in front of the bench, as
    /// high as the arms hold the shoulders over the hands.
    static func root(_ pose: JointPose, bend: Double, body: Body3D, hands: [String: HandPress]) -> V {
        let g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let y = -hipsOut
        var sum = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let shoulder = rel["humerus.\(s)"], let hand = hands[s] else { continue }
            let wrist = body.pressWrist(hand, at: knuckle(s), fingers: Body3D.forward, normal: Body3D.up)
            let reach = body.armSpan(s, bend: bend)
            let dx = wrist.x - shoulder.x, dy = wrist.y - (shoulder.y + y)
            sum += wrist.z + max(0, reach * reach - dx * dx - dy * dy).squareRoot() - shoulder.z
            n += 1
        }
        return V(0, y, max(hipsLowest, n > 0 ? sum / n : 0.5))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let bend = min(125, max(4, pose.angles["elbowFlex"] ?? 0))
        let root = Self.root(pose, bend: bend, body: body, hands: hands)
        var h = body.place(g, root: root)
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: foot, pole: V(0, -0.2, 1), &g, h)
        }
        // Elbows point straight back, and out only as far as the upper arms are held from the sides.
        let flare = tan(min(60, max(0, (pose.angles["shoulderAbd"] ?? 15) - 15)) * .pi / 180)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = hands[s] else { continue }
            body.press(s, hand, at: Self.knuckle(s), fingers: Body3D.forward, pole: V(-m * flare, 1, 0.1), &g, h)
        }
        h = body.place(g, root: root)

        var props: [PropPiece] = []
        // A weight rests across the thighs, close to the hips.
        if let load, let hip = h["femur.r"], let knee = h["shin.r"] {
            let line = (knee - hip).unit
            let up = V(1, 0, 0).cross(line).unit * (line.y < 0 ? -1 : 1)
            // The more the thighs tip up, the further from the belly it has to lie.
            let tip = max(0, line.z), radius = load == .plate ? 0.15 : 0.06
            let lap = V(0, hip.y, hip.z) + line * min(0.31, radius + (0.11 + 0.1 * tip) / max(0.5, -line.y))
            if load == .plate {
                props.append(Plan.disc(lap + up * 0.105, axis: up, radius: radius, thickness: 0.035, .plate))
            } else {
                let c = lap + up * 0.15
                props.append(Plan.rod(c - V(0.13, 0, 0), c + V(0.13, 0, 0), 0.016, .metal))
                for side in [-1.0, 1.0] {
                    props.append(Plan.disc(c + V(side * 0.1, 0, 0), axis: V(1, 0, 0), radius: 0.06, thickness: 0.07, .dark))
                }
            }
        }
        return (body.made(g, h, floor: 0), props)
    }
}

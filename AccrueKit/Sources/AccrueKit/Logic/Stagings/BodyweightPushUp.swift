import Foundation

/// A body held face down in a line over the floor, resting on its toes (or its knees) and
/// turning about them as the shoulders go down and up. The feet never slide: the balls of the
/// feet are the hinge, and the toes lie flat on the floor in front of them.
struct ProneLine: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    let body: Body3D
    /// Resting on the knees, lower legs lifted, instead of on the toes.
    let onKnees: Bool
    /// Where the hinge rests: midway between the balls of the feet (or the knees).
    let pivot: V
    /// How high the surface under the body is at a point (a bench under the hands or the feet).
    let surface: @Sendable (V) -> Double

    /// How far the middle of the knee sits above the floor it kneels on.
    static let kneePad = 0.055
    /// The toes rest on their tips, their roots a little off the floor, and the ankle is let
    /// out so the toes are not folded square under the foot (degrees).
    static let toesTip = 12.0, ankleOut = 18.0

    init(body: Body3D, onKnees: Bool, feetHeight: Double = 0, surface: @escaping @Sendable (V) -> Double = { _ in 0 }) {
        self.body = body
        self.onKnees = onKnees
        self.surface = surface
        var ball = 0.03
        if let root = body.head["toes.r"], let tip = body.tail["toes.r"] {
            // The height of the toe's root that leaves its tip resting on the floor.
            ball = 0.011 - (M.x(Self.toesTip) * (tip - root)).z
        }
        pivot = V(0, 0, feetHeight + (onKnees ? Self.kneePad : ball))
    }

    /// The body for `pose`, turned about its feet until the shoulders are `height` above the floor.
    func place(_ pose: JointPose, shoulders height: Double) -> (g: [String: M], h: [String: V]) {
        var pose = pose
        if onKnees {
            // Lower legs up behind, feet relaxed.
            pose.angles["kneeFlex"] = 65
            pose.angles["kneeFlexL"] = 65
            pose.angles["ankleDorsi"] = -25
            pose.angles["ankleDorsiL"] = -25
        } else {
            pose.angles["ankleDorsi"] = -Self.ankleOut
            pose.angles["ankleDorsiL"] = -Self.ankleOut
        }
        var g = body.rotations(pose)
        var h = body.heads(g)
        let hinge = onKnees ? "shin" : "toes"
        func mid(_ bone: String, _ h: [String: V]) -> V {
            let ps = ["r", "l"].compactMap { h["\(bone).\($0)"] }
            return ps.reduce(V(0, 0, 0), +) * (1 / Double(max(1, ps.count)))
        }
        // Turning by φ about the side-to-side line lifts the shoulders to d.y sin φ + d.z cos φ.
        let d = mid("humerus", h) - mid(hinge, h)
        let r = max(1e-6, hypot(d.y, d.z)), offset = atan2(d.z, d.y)
        let a = asin(min(1, max(-1, (height - pivot.z) / r)))
        func wrapped(_ x: Double) -> Double {
            var x = x
            while x > .pi { x -= 2 * .pi }
            while x < -.pi { x += 2 * .pi }
            return x
        }
        let first = wrapped(a - offset), second = wrapped(.pi - a - offset)
        let turn = M.x((abs(first) < abs(second) ? first : second) * 180 / .pi)
        for (bone, rotation) in g { g[bone] = turn * rotation }
        if !onKnees {
            // The toes stay where they are on the floor while the foot turns over them.
            for s in ["r", "l"] { g["toes.\(s)"] = M.x(Self.toesTip) }
        }
        h = settle(g)
        return (g, h)
    }

    /// Bone heads with the hinge back on its spot, after the arms have been posed.
    func settle(_ g: [String: M]) -> [String: V] {
        var h = body.heads(g)
        let ps = ["r", "l"].compactMap { h["\(onKnees ? "shin" : "toes").\($0)"] }
        guard !ps.isEmpty else { return h }
        let shift = pivot - ps.reduce(V(0, 0, 0), +) * (1 / Double(ps.count))
        for (k, p) in h { h[k] = p + shift }
        return h
    }

    /// How much room the front of the body has left over whatever is under it: the chest and
    /// the face may come to `gap` above it, the belly, hips and legs to a finger's width. Below
    /// zero, something is too low.
    func clearance(_ g: [String: M], _ h: [String: V], gap: Double) -> Double {
        var room = 1.0
        func add(_ bone: String, turnedBy: String? = nil, _ offset: V, _ margin: Double) {
            guard let p = h[bone] else { return }
            let q = p + (g[turnedBy ?? bone] ?? .identity) * offset
            room = min(room, q.z - surface(q) - margin)
        }
        for x in [-0.08, 0.08] { add("thorax", V(x, -0.15, 0.2), gap) }
        add("neck", turnedBy: "head", V(0, -0.146, 0.105), gap)
        add("thorax", V(0, -0.14, 0.05), 0.012)
        add("lumbar", V(0, -0.125, 0.03), 0.012)
        add("pelvis", V(0, -0.11, -0.02), 0.012)
        // A kneeling body's thighs come down to the floor at the knees whatever the chest does.
        if !onKnees {
            for s in ["r", "l"] {
                add("femur.\(s)", V(0, -0.095, -0.2), 0.012)
                add("shin.\(s)", V(0, -0.06, 0), 0.012)
            }
        }
        return room
    }
}

// MARK: - Push-up

/// A push-up: palms flat under the shoulders with the fingers forward, toes (or knees) on the
/// floor, the body in a line that turns about the feet until the chest is just above the floor.
/// The hands may be on a bench (an incline push-up) or the feet may be (a decline one).
struct PushUpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// What the body rests on, and how the hands are set.
    struct Setup: Sendable {
        var onKnees = false
        /// Half the distance between the hands.
        var halfHands = 0.25
        /// How far the fingers turn in toward each other, degrees (a diamond push-up).
        var turnedIn = 0.0
        /// How much of the keyframes' elbow flare is kept: close hands keep the elbows in.
        var flare = 1.0
        /// A bench under the hands or under the feet; the one under the hands may be a wooden box.
        var handsOnBench = false, feetOnBench = false, handsOnBox = false
        /// A plate carried on the upper back.
        var plate = false
    }

    static let benchTop = 0.44, benchDepth = 0.3
    /// How far the chest stops above the floor (or the bench) at the bottom.
    static let chestGap = 0.035
    /// The least the wrists are in front of the shoulders at the top.
    static let ahead = 0.03

    let body: Body3D
    let setup: Setup
    let line: ProneLine
    let progress: PullProgress
    let hands: [String: HandPress]
    /// Where the middle knuckle of each hand rests, and which way its fingers point.
    let knuckles: [String: V]
    let fingers: [String: V]
    let top, bottom: Double
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D, _ setup: Setup = Setup()) {
        guard let r = body.flatHand("r", spread: 1.6), let l = body.flatHand("l", spread: 1.6),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.setup = setup
        let hands = ["r": r, "l": l]
        self.hands = hands
        progress = PullProgress(guide.keyframes)
        let handsUp = setup.handsOnBench ? Self.benchTop : 0.0
        let turned = setup.turnedIn * .pi / 180
        var fingers: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] { fingers[s] = V(m * sin(turned), -cos(turned), 0) }
        self.fingers = fingers

        let straight = guide.keyframes.min { ($0.pose.angles["elbowFlex"] ?? 0) < ($1.pose.angles["elbowFlex"] ?? 0) }?.pose ?? first
        let bent = guide.keyframes.max { ($0.pose.angles["elbowFlex"] ?? 0) < ($1.pose.angles["elbowFlex"] ?? 0) }?.pose ?? first
        let feetUp = setup.feetOnBench ? Self.benchTop : 0.0
        let open = ProneLine(body: body, onKnees: setup.onKnees, feetHeight: feetUp)
        guard let shoulder = body.heads(body.rotations(straight))["humerus.r"] else { return nil }
        let wristRest = body.pressWrist(r, at: V(0, 0, 0), fingers: fingers["r"] ?? Body3D.forward, normal: Body3D.up)
        let reach = body.armSpan("r", bend: 7)
        let dx = setup.halfHands - abs(shoulder.x)
        let handsOnBench = setup.handsOnBench, feetOnBench = setup.feetOnBench
        let feetEdge = open.pivot.y - 0.1
        func shouldersY(_ h: [String: V]) -> Double { ((h["humerus.r"]?.y ?? -1.2) + (h["humerus.l"]?.y ?? -1.2)) / 2 }

        // The body turns about its feet, so the shoulders travel forward as they come down. The
        // hands go midway: a little in front of the shoulders at the top (arms all but
        // straight), a little behind them at the bottom (chest just above the floor).
        var ahead = Self.ahead
        // Hands set together lie under the chest, which then stops on the backs of them.
        let gap = Self.chestGap + (setup.halfHands < 0.1 ? 0.035 : 0)
        var top = 0.0, bottom = 0.0, handsY = 0.0, near = 0.0
        var line = open
        for round in 0..<4 {
            top = handsUp + wristRest.z + max(0.01, reach * reach - dx * dx - ahead * ahead).squareRoot()
            let high = shouldersY(open.place(straight, shoulders: top).h)
            handsY = high - ahead
            // What is under each part of the body: the floor, or a bench under the hands or the feet.
            let edge = handsY + Self.benchDepth / 2 + 0.02
            near = edge
            line = ProneLine(body: body, onKnees: setup.onKnees, feetHeight: feetUp) { point in
                if handsOnBench && point.y < edge { return Self.benchTop }
                if feetOnBench && point.y > feetEdge { return Self.benchTop }
                return 0
            }
            var low = handsUp + 0.05, up = top
            for _ in 0..<24 {
                let mid = (low + up) / 2
                let placed = line.place(bent, shoulders: mid)
                if line.clearance(placed.g, placed.h, gap: gap) < 0 { low = mid } else { up = mid }
            }
            bottom = up
            if round < 3 { ahead = max(Self.ahead, (high - shouldersY(line.place(bent, shoulders: bottom).h)) / 2) }
        }
        self.top = top
        self.bottom = bottom
        self.line = line
        var knuckles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = hands[s], let f = fingers[s] else { continue }
            let wrist = body.pressWrist(hand, at: V(0, 0, 0), fingers: f, normal: Body3D.up)
            knuckles[s] = V(-m * setup.halfHands - wrist.x, handsY - wrist.y, handsUp)
        }
        self.knuckles = knuckles

        var p: [PropPiece] = []
        var kinds: [PropKind] = []
        if setup.handsOnBox {
            p.append(Plan.box(V(0, near - 0.2, Self.benchTop / 2), (0.75, 0.4, Self.benchTop), .wood))
            kinds.append(.box)
        } else if setup.handsOnBench {
            p += BenchDipStaging.bench(front: near - Self.benchDepth)
            kinds.append(.bench)
        }
        if setup.feetOnBench {
            p += BenchDipStaging.bench(front: feetEdge)
            kinds.append(.bench)
        }
        if setup.plate { kinds.append(.plate) }
        self.kinds = kinds
        fixed = p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let u = progress(pose)
        var height = top + (bottom - top) * u
        var (g, h) = line.place(pose, shoulders: height)
        // A mistake that drops the hips or the head must not push them through the floor.
        var tries = 0
        while line.clearance(g, h, gap: 0.012) < 0, tries < 30 {
            height += 0.01
            (g, h) = line.place(pose, shoulders: height)
            tries += 1
        }
        // Elbows point back toward the feet, and out as far as the upper arms are held from the sides.
        let out = tan(min(75, max(0, (pose.angles["shoulderAbd"] ?? 45) * setup.flare)) * .pi / 180)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = hands[s], let point = knuckles[s], let f = fingers[s] else { continue }
            body.press(s, hand, at: point, fingers: f, pole: V(-m * out, 1, 0.35), &g, h)
        }
        h = line.settle(g)

        var props: [PropPiece] = []
        if setup.plate, let chest = h["thorax"], let turn = g["thorax"] {
            // The plate lies on the upper back, between the shoulder blades.
            props.append(Plan.disc(chest + turn * V(0, 0.112, 0.13), axis: turn * V(0, 1, 0), radius: 0.19, thickness: 0.035, .plate))
        }
        return (body.made(g, h, floor: 0), props)
    }
}

// MARK: - Plank

/// A front plank: forearms flat on the floor with the elbows under the shoulders, palms down,
/// toes (or knees) on the floor, the body held in a line.
struct PlankStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How far the middle of the elbow sits above the floor it rests on.
    static let elbowPad = 0.045

    let body: Body3D
    let line: ProneLine
    let hands: [String: HandPress]
    let height: Double
    /// From the shoulder to the wrist when the forearm lies on the floor.
    let reach: V
    let plate: Bool
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D, onKnees: Bool = false, plate: Bool = false) {
        guard let r = body.flatHand("r", spread: 1.3), let l = body.flatHand("l", spread: 1.3),
              let shoulder = body.head["humerus.r"], let elbow = body.head["ulna.r"], let wrist = body.head["hand.r"] else { return nil }
        self.body = body
        self.plate = plate
        kinds = plate ? [.plate] : []
        hands = ["r": r, "l": l]
        line = ProneLine(body: body, onKnees: onKnees)
        // The forearm lies along the floor and the upper arm stands on it at a right angle.
        let upper = (elbow - shoulder).length, fore = (wrist - elbow).length
        let dip = asin(min(1, max(-1, (Self.elbowPad - r.wristLift) / fore)))
        height = Self.elbowPad + upper * cos(dip)
        reach = V(0, upper * sin(dip) - fore * cos(dip), -upper * cos(dip) - fore * sin(dip))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h) = line.place(pose, shoulders: height)
        for s in ["r", "l"] {
            guard let hand = hands[s], let shoulder = h["humerus.\(s)"] else { continue }
            let wrist = V(shoulder.x, shoulder.y, height) + reach
            let rest = body.pressWrist(hand, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
            body.press(s, hand, at: V(wrist.x - rest.x, wrist.y - rest.y, 0), fingers: Body3D.forward, pole: V(0, 1, -1), &g, h)
        }
        h = line.settle(g)
        var props: [PropPiece] = []
        if plate, let chest = h["thorax"], let turn = g["thorax"] {
            props.append(Plan.disc(chest + turn * V(0, 0.112, 0.13), axis: turn * V(0, 1, 0), radius: 0.19, thickness: 0.035, .plate))
        }
        return (body.made(g, h, floor: 0), props)
    }
}

import Foundation

/// An exercise acted out on its real equipment. The equipment is built first, to the body's
/// size, and the body is fitted to it: hands closed on the bar, feet planted, hips on the seat.
/// The family's keyframes still drive the timing, the trunk, the shoulder blades and how far
/// the pull has gone, so the how-to's phases and mistakes play as before.
protocol BodyStaging: Sendable {
    var kinds: [PropKind] { get }
    /// Equipment that never moves.
    var fixed: [PropPiece] { get }
    /// The body for one pose, and the equipment that moves with it.
    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece])
}

enum Stagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        switch guide.exerciseID {
        case StarterIDs.pullUp: return PullUpStaging(guide, body)
        case StarterIDs.pulldown: return PulldownStaging(guide, body)
        case StarterIDs.seatedRow: return SeatedRowStaging(guide, body)
        default: return nil
        }
    }
}

/// How far a pull has gone, read from the elbow bend the keyframes give: 0 with the arms long,
/// 1 at the squeeze. A "half reps" mistake changes the elbow angle, so it shows here too.
struct PullProgress: Sendable {
    let low, high: Double

    init(_ keys: [Keyframe]) {
        let bends = keys.map { $0.pose.angles["elbowFlex"] ?? 0 }
        low = bends.min() ?? 0
        high = max((bends.max() ?? 100), low + 1)
    }

    func callAsFunction(_ pose: JointPose) -> Double {
        min(1, max(0, ((pose.angles["elbowFlex"] ?? 0) - low) / (high - low)))
    }
}

private func mix(_ a: Body3D.V, _ b: Body3D.V, _ t: Double) -> Body3D.V { a + (b - a) * t }

/// A weight stack between two uprights with a pulley over it, at `y` in front of the body.
private func stackFrame(y: Double, height: Double) -> [PropPiece] {
    typealias V = Body3D.V
    var p: [PropPiece] = []
    for x in [-0.22, 0.22] {
        p.append(PropPlan.box(V(x, y, height / 2), (0.06, 0.08, height), .metal))
        p.append(PropPlan.box(V(x, y, 0.025), (0.08, 0.6, 0.05), .metal))
    }
    p.append(PropPlan.box(V(0, y, height - 0.03), (0.5, 0.08, 0.06), .metal))
    for x in [-0.09, 0.09] {
        p.append(PropPlan.rod(V(x, y, 0.05), V(x, y, height - 0.06), 0.01, .metal))
    }
    p.append(PropPlan.box(V(0, y, 0.05 + 0.16), (0.26, 0.1, 0.32), .plate))
    p.append(PropPlan.disc(V(0, y + 0.055, height - 0.13), axis: V(1, 0, 0), radius: 0.055, thickness: 0.025, .dark))
    return p
}

/// The plates the cable has lifted by `travel`, and the cable down to them.
private func liftedPlates(y: Double, height: Double, travel: Double) -> [PropPiece] {
    typealias V = Body3D.V
    let bottom = 0.37 + min(travel, height - 0.8)
    return [PropPlan.box(V(0, y, bottom + 0.09), (0.26, 0.1, 0.18), .plate),
            PropPlan.rod(V(0, y, bottom + 0.18), V(0, y, height - 0.13), 0.004, .cable)]
}

// MARK: - Pull-up

/// A strict pull-up on a fixed bar. The hands never move; the body hangs from them with its
/// weight under the bar, and rises until the chin is over it.
struct PullUpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let barHeight = 2.3, halfGrip = 0.3, barRadius = 0.016
    /// The deepest elbow bend the pull may reach, in degrees.
    static let deepest = 150.0

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.pullUpBar]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let r = body.grip("r", radius: Self.barRadius, square: 0.6),
              let l = body.grip("l", radius: Self.barRadius, square: 0.6) else { return nil }
        self.body = body
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        let z = Self.barHeight
        var pieces = [Plan.rod(V(-0.66, 0, z), V(0.66, 0, z), Self.barRadius, .metal)]
        for x in [-0.62, 0.62] {
            pieces.append(Plan.rod(V(x, 0, 0), V(x, 0, z + 0.04), 0.03, .metal))
            pieces.append(Plan.box(V(x, 0, 0.02), (0.09, 1.0, 0.04), .metal))
        }
        fixed = pieces
    }

    /// The face from the chin to the brow, as (forward, up) from the joint at the base of the
    /// neck, in the head's own axes. The bar must pass in front of it.
    static let face: [(Double, Double)] = [(0.085, 0.0), (0.114, 0.03), (0.127, 0.045), (0.137, 0.075),
                                           (0.146, 0.105), (0.132, 0.135), (0.128, 0.165), (0.125, 0.195)]

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let u = progress(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let thorax = g["thorax"] ?? .identity
        let z0 = Self.barHeight
        func hold(_ s: String) -> V { V(s == "r" ? -Self.halfGrip : Self.halfGrip, 0, z0) }
        let shoulders = ["r", "l"].compactMap { rel["humerus.\($0)"] }
        let mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
        let neck = rel["neck"] ?? mid

        // The body's weight hangs under the bar (the arms are a tenth of it, halfway up).
        let weight = body.balance(g, rel)
        var y = -(0.9 * weight.y + 0.05 * mid.y) / 0.95

        /// The height of the hips that leaves each elbow bent by `bend`.
        func hips(bend: Double, y: Double) -> Double {
            var sum = 0.0, n = 0.0
            for s in ["r", "l"] {
                guard let shoulder = rel["humerus.\(s)"], let grip = grips[s] else { continue }
                let reach = body.reach(s, grip, bend: bend)
                let dx = hold(s).x - shoulder.x, dy = -(shoulder.y + y)
                sum += z0 - max(0, reach * reach - dx * dx - dy * dy).squareRoot() - shoulder.z
                n += 1
            }
            return n > 0 ? sum / n : 0
        }
        // At the top the chin is over the bar, as far as the arms can fold.
        let headTurn = g["head"] ?? thorax
        let chin = neck + headTurn * V(0, -0.114, 0.03)
        let want = z0 + Self.barRadius + 0.014 - chin.z
        let hang = hips(bend: 6, y: y)
        var z = hang + (min(want, hips(bend: Self.deepest, y: y)) - hang) * u

        // The face passes behind the bar on the way up.
        let clear = Self.barRadius + 0.012
        for (forward, up) in Self.face {
            let p = neck + headTurn * V(0, -forward, up)
            let dz = p.z + z - z0
            guard abs(dz) < clear else { continue }
            y = max(y, -p.y + (clear * clear - dz * dz).squareRoot())
        }
        // Arms that cannot fold far enough let the body lean back a touch instead.
        var lean = 0.0
        while lean < 0.05, hips(bend: Self.deepest, y: y + lean) < want { lean += 0.005 }
        y += lean * u * u
        z = hang + (min(want, hips(bend: Self.deepest, y: y)) - hang) * u

        let root = V(0, y, z)
        var h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: hold(s), across: V(-m, 0, 0), pole: thorax * V(-m * 0.5, -0.15, -1), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), [])
    }
}

// MARK: - Lat pulldown

/// A cable pulldown: hips on the seat, thighs under the pads, feet flat. The bar hangs from the
/// pulley and comes down in front of the face to the upper chest; the weight stack rises as
/// far as the cable is drawn out.
struct PulldownStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let barRadius = 0.014, halfGrip = 0.33

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.pulldown]
    let fixed: [PropPiece]
    let hip: V
    let pulley: V
    let column: V
    let slack: Double

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let r = body.grip("r", radius: Self.barRadius, square: 0.6),
              let l = body.grip("l", radius: Self.barRadius, square: 0.6),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"] else { return nil }
        self.body = body
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        // Thighs level and shins upright: the hips sit as high as the knees.
        let shin = (rAnkle - rKnee).length, thigh = (rKnee - rHip).length
        hip = V(0, 0, body.ankleHeight + shin)
        pulley = V(0, -0.2, 2.02)
        column = V(0, -1.0, 0)

        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        // Seat on its post.
        let seatTop = hip.z - 0.1
        p.append(Plan.box(V(0, 0.02, seatTop - 0.035), (0.38, 0.34, 0.07), .pad))
        p.append(Plan.box(V(0, 0.02, (seatTop - 0.07) / 2), (0.07, 0.07, seatTop - 0.07), .metal))
        // Thigh pads over the thighs, just behind the knees, on a post between the legs.
        let padY = -thigh * 0.62, padZ = hip.z + 0.078 + 0.05
        for x in [-0.13, 0.13] {
            p.append(Plan.disc(V(x, padY, padZ), axis: side, radius: 0.05, thickness: 0.17, .pad))
        }
        p.append(Plan.rod(V(-0.2, padY, padZ), V(0.2, padY, padZ), 0.014, .metal))
        p.append(Plan.box(V(0, padY, padZ / 2), (0.05, 0.05, padZ), .metal))
        // Frame: a foot under everything, the weight stack in front, the boom overhead to the pulley.
        let top = pulley.z + 0.2
        p.append(Plan.box(V(0, (column.y + 0.2) / 2, 0.025), (0.09, 0.2 - column.y, 0.05), .metal))
        p.append(Plan.box(V(0, 0.2, 0.025), (0.5, 0.09, 0.05), .metal))
        p += stackFrame(y: column.y, height: top)
        p.append(Plan.box(V(0, (column.y + pulley.y + 0.1) / 2, top - 0.03), (0.07, pulley.y + 0.1 - column.y, 0.06), .metal))
        p.append(Plan.disc(V(0, pulley.y + 0.055, pulley.z + 0.02), axis: side, radius: 0.055, thickness: 0.025, .dark))
        p.append(Plan.rod(V(0, pulley.y + 0.055, pulley.z + 0.075), V(0, column.y + 0.055, top - 0.075), 0.004, .cable))
        fixed = p

        // The cable's length out of the pulley with the arms long, where the stack rests.
        var rest = 0.0
        if let first = guide.keyframes.first?.pose {
            let (_, bar) = Self.solve(first, body: body, grips: grips, hip: hip, pulley: pulley, progress: progress)
            rest = (pulley - bar).length
        }
        slack = rest
    }

    /// The posed body's rotations and heads, and where the bar's centre is.
    static func solve(_ pose: JointPose, body: Body3D, grips: [String: HandGrip], hip: V, pulley: V,
                      progress: PullProgress) -> (frame: BodyFrame, bar: V) {
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

        // Arms long: the bar hangs straight under the pulley as high as the hands can follow.
        var sum = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let shoulder = h["humerus.\(s)"], let grip = grips[s] else { continue }
            let reach = body.reach(s, grip, bend: 8)
            let dx = (s == "r" ? -halfGrip : halfGrip) - shoulder.x, dy = pulley.y - shoulder.y
            sum += shoulder.z + max(0, reach * reach - dx * dx - dy * dy).squareRoot()
            n += 1
        }
        let high = V(0, pulley.y, n > 0 ? sum / n : 1.5)
        // The squeeze: the bar at the top of the chest, or behind the neck for that mistake.
        let neck = h["neck"] ?? high
        let behind = (pose.angles["shoulderRot"] ?? 0) > 15
        let low = neck + thorax * (behind ? V(0, 0.1, 0.0) : V(0, -0.16, -0.105))
        // Down in front of the face first, then in to the chest.
        var bar = V(0, high.y + (low.y - high.y) * pow(u, 1.6), high.z + (low.z - high.z) * u)
        // It never cuts through the face, however the head is held.
        if !behind {
            let headTurn = g["head"] ?? thorax
            let clear = barRadius + 0.025
            for (forward, up) in PullUpStaging.face {
                let p = neck + headTurn * V(0, -forward, up)
                let dz = bar.z - p.z
                guard abs(dz) < clear else { continue }
                bar.y = min(bar.y, p.y - (clear * clear - dz * dz).squareRoot())
            }
        }

        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: bar + V(-m * halfGrip, 0, 0), across: V(-m, 0, 0),
                      pole: thorax * V(-m * 0.4, 0.3, -1), &g, h)
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = Self.solve(pose, body: body, grips: grips, hip: hip, pulley: pulley, progress: progress)
        var p: [PropPiece] = []
        // The lat bar: straight in the middle, its ends bent down, with rubber grips on the ends.
        let bend = 0.46, tip = V(0.19 * cos(0.38), 0, -0.19 * sin(0.38))
        p.append(Plan.rod(bar - V(bend, 0, 0), bar + V(bend, 0, 0), Self.barRadius, .metal))
        for m in [-1.0, 1.0] {
            let a = bar + V(m * bend, 0, 0), b = a + V(m * tip.x, 0, tip.z)
            p.append(Plan.rod(a, b, Self.barRadius, .metal))
            p.append(Plan.ball(a, Self.barRadius, .metal))
            p.append(Plan.rod(a + (b - a) * 0.25, b, Self.barRadius + 0.004, .dark))
        }
        // Its swivel, and the cable up to the pulley.
        let eye = bar + V(0, 0, 0.075)
        p.append(Plan.rod(bar, eye, 0.007, .metal))
        p.append(Plan.ball(eye, 0.014, .metal))
        p.append(Plan.rod(eye, V(0, pulley.y, pulley.z + 0.02), 0.004, .cable))
        // The plates the cable lifts.
        p += liftedPlates(y: column.y, height: pulley.z + 0.2, travel: max(0, (pulley - bar).length - slack))
        return (frame, p)
    }
}

// MARK: - Seated cable row

/// A seated cable row with the close neutral handle: hips on the bench, feet on the foot
/// plates, knees soft. The handle travels along the cable's line from long arms to the belly.
struct SeatedRowStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015, halfHandle = 0.07, tilt = 15.0, stackHeight = 1.6

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.cable, .bench]
    let fixed: [PropPiece]
    let hip: V
    let pulley: V
    let ankles: [String: V]
    let foot: M
    let slack: Double

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let rToe = body.tail["toes.r"] else { return nil }
        self.body = body
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        let seatTop = 0.42
        hip = V(0, 0, seatTop + 0.1)
        pulley = V(0, -1.3, 0.62)
        // Feet on the plates with the knees a little bent.
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: 25)
        let drop = 0.15, out = 0.045
        let forward = max(0, leg * leg - drop * drop - out * out).squareRoot()
        ankles = ["r": V(-(abs(rHip.x) + out), -forward, hip.z - drop), "l": V(abs(rHip.x) + out, -forward, hip.z - drop)]
        foot = M.x(-62)

        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        // The bench.
        p.append(Plan.box(V(0, -0.1, seatTop - 0.035), (0.32, 0.75, 0.07), .pad))
        for y in [0.2, -0.4] {
            p.append(Plan.box(V(0, y, (seatTop - 0.07) / 2), (0.07, 0.07, seatTop - 0.07), .metal))
            p.append(Plan.box(V(0, y, 0.02), (0.5, 0.07, 0.04), .metal))
        }
        p.append(Plan.box(V(0, (0.2 + pulley.y - 0.3) / 2, 0.025), (0.07, 0.2 - (pulley.y - 0.3), 0.05), .metal))
        // A foot plate under each sole, on a brace from the frame.
        let sole = V(0, -0.045, -(rAnkle.z - (rToe.z - 0.01)))
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            let centre = ankle + foot * sole, normal = foot * V(0, 0, 1), along = foot * V(0, -1, 0)
            p.append(Plan.box(centre - normal * 0.012 + along * 0.02, (0.15, 0.3, 0.024), x: side, z: normal, .dark))
            p.append(Plan.rod(centre - normal * 0.024, V(centre.x * 0.4, centre.y - 0.16, 0.05), 0.02, .metal))
        }
        // The low pulley, and the weight stack behind it.
        p.append(Plan.disc(V(0, pulley.y - 0.055, pulley.z), axis: side, radius: 0.055, thickness: 0.025, .dark))
        p.append(Plan.box(V(0, pulley.y - 0.07, pulley.z / 2), (0.05, 0.05, pulley.z), .metal))
        p += stackFrame(y: pulley.y - 0.3, height: Self.stackHeight)
        p.append(Plan.rod(V(0, pulley.y - 0.11, pulley.z), V(0, pulley.y - 0.3 + 0.055, Self.stackHeight - 0.075), 0.004, .cable))
        fixed = p

        var rest = 0.0
        if let first = guide.keyframes.first?.pose {
            let (_, handle) = Self.solve(first, body: body, grips: grips, hip: hip, pulley: pulley, ankles: ankles,
                                         foot: foot, progress: progress)
            rest = (pulley - handle).length
        }
        slack = rest
    }

    /// The handle's own directions: toward the pulley, and up along its grips (their tops lean
    /// toward the pulley, as a relaxed fist holds them).
    static func axes(_ handle: V, pulley: V) -> (toPulley: V, grip: V) {
        let c = (pulley - handle).unit
        let up = c.cross(V(1, 0, 0)).unit
        let t = tilt * .pi / 180
        return (c, (up * cos(t) + c * sin(t)).unit)
    }

    static func solve(_ pose: JointPose, body: Body3D, grips: [String: HandGrip], hip: V, pulley: V,
                      ankles: [String: V], foot: M, progress: PullProgress) -> (frame: BodyFrame, handle: V) {
        var g = body.rotations(pose)
        var h = body.place(g, root: hip)
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: foot, pole: V(0, -0.2, 1), &g, h)
        }
        h = body.place(g, root: hip)
        let thorax = g["thorax"] ?? .identity
        let u = progress(pose)

        // The squeeze: the handle in front of the belly, the fists almost touching it.
        let waist = h["thorax"] ?? hip
        let near = waist + (g["lumbar"] ?? .identity) * V(0, -0.235, -0.03)
        // Arms long: the handle on the line from the shoulders to the pulley.
        let shoulders = ["r", "l"].compactMap { h["humerus.\($0)"] }
        var mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
        let wide = shoulders.first.map { abs($0.x - mid.x) } ?? 0.17
        mid.x = 0
        let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: 8) } }.reduce(0, +) / 2
        let lateral = wide - halfHandle
        let far = mid + (pulley - mid).unit * max(0, reach * reach - lateral * lateral).squareRoot()
        let handle = mix(far, near, u)

        let (_, gripAxis) = axes(handle, pulley: pulley)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: handle + V(-m * halfHandle, 0, 0), across: gripAxis * -1,
                      pole: thorax * V(-m * 0.25, 1, -0.5), &g, h)
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), handle)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, handle) = Self.solve(pose, body: body, grips: grips, hip: hip, pulley: pulley, ankles: ankles,
                                         foot: foot, progress: progress)
        let (c, gripAxis) = Self.axes(handle, pulley: pulley)
        var p: [PropPiece] = []
        // The double-D handle: two grips, each on a loop that runs forward to the swivel.
        let eye = handle + c * 0.16
        for m in [-1.0, 1.0] {
            let centre = handle + V(m * Self.halfHandle, 0, 0)
            let a = centre - gripAxis * 0.065, b = centre + gripAxis * 0.065
            p.append(Plan.rod(a, b, Self.gripRadius, .dark))
            for end in [a, b] {
                p.append(Plan.rod(end, eye, 0.006, .metal))
                p.append(Plan.ball(end, 0.008, .metal))
            }
        }
        p.append(Plan.ball(eye, 0.014, .metal))
        p.append(Plan.rod(eye, V(0, pulley.y, pulley.z + 0.05), 0.004, .cable))
        // The plates the cable lifts.
        p += liftedPlates(y: pulley.y - 0.3, height: Self.stackHeight, travel: max(0, (pulley - handle).length - slack))
        return (frame, p)
    }
}

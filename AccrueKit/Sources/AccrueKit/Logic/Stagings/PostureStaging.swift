import Foundation

/// A standing family's movement done on a support: sitting on a bench or a ball, lying back on
/// a bench, or lying face down on one. The family's keyframes stand, so the trunk is first put
/// on its support and the legs are planted; the arms then do what the keyframes say, carried
/// with the trunk, and the hands close on the same equipment the plain picture draws.
struct PostureStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    enum Support: Sendable, Equatable {
        /// Sitting on the end of a flat bench, or in an upright bench with a back pad.
        case seat(back: Bool)
        /// Sitting on top of a stability ball.
        case ball
        /// Lying back on a bench whose pad slopes up from the hips by `tilt` degrees.
        case supine(tilt: Double)
        /// Lying face down on a pad, the trunk leaning `lean` degrees forward from upright
        /// (90 is a flat bench, high enough for the arms to hang).
        case prone(lean: Double)
    }

    /// The most a sitting trunk leans forward before the chest meets the thighs.
    static let seatedLean = 52.0
    /// How far the lower back rounds when someone sitting bends over.
    static let seatedRound = 28.0
    /// How far out the arms are held so dumbbells pass outside the thighs of someone sitting.
    static let clearAbd = 15.0
    static let ballRadius = 0.3, ballSink = 0.03
    static let padWidth = 0.28, padThick = 0.07
    /// The hip joints' height on an incline bench lain on face down, and the top of the tall
    /// flat bench: both leave the hanging arms clear of the floor.
    static let proneHip = 0.68, proneTop = 0.92
    /// How far the heels are off the floor for someone lying face down on an incline.
    static let proneHeel = 55.0

    let body: Body3D
    /// The plain picture of the same exercise: how its hands hold, and what they hold.
    let plan: PropPlan
    let support: Support
    let kinds: [PropKind]
    let fixed: [PropPiece]
    /// The trunk's lean in the keyframes, which a pose is measured against.
    let baseLean: Double
    /// Where the middle of the hip joints rests.
    let hip: V
    private(set) var ankles: [String: V] = [:]
    private(set) var feet: [String: M] = [:]
    /// The toes' own turn where they stay flat on the floor under a lifted heel.
    private(set) var toes: [String: M] = [:]
    let chair: MachineChair?
    let recline: BenchStagings.Recline?
    /// The pad and posts a bar has to stay out of.
    let blocks: [BulkRod]
    /// Where a bar goes to stay out of the body through the loop: at each of the loop's
    /// moments, the middle of the hands' own line and how far the bar is moved off it.
    private(set) var trail: [(mid: V, off: V)] = []
    /// Where a bar hangs clear of the bench at the start of the loop.
    private(set) var hang: V?

    init?(_ guide: HowToGuide, _ body: Body3D, _ support: Support) {
        guard let first = guide.keyframes.first?.pose, let rHip = body.head["femur.r"], let lHip = body.head["femur.l"],
              let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"], let rShoulder = body.head["humerus.r"] else { return nil }
        let plan = PropPlan(guide: guide, body: body, plain: true)
        // A bar with a place of its own (across the hips, on the floor) is another picture.
        guard plan.hands?.bar?.rest == nil else { return nil }
        self.body = body
        self.plan = plan
        self.support = support
        baseLean = first.angles["trunk"] ?? 0
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
        let knee = body.ankleHeight + shin
        let apart = abs(lHip.x - rHip.x) / 2
        let side = V(1, 0, 0)
        var pieces: [PropPiece] = []
        var blocks: [BulkRod] = []
        var chair: MachineChair?
        var recline: BenchStagings.Recline?
        var seat: PropKind = .bench

        switch support {
        case .seat(let back):
            // Thighs level and shins upright: the hips sit as high as the knees.
            hip = V(0, 0, knee)
            let out = apart + 0.04
            ankles = ["r": V(-out, -thigh + 0.01, body.ankleHeight), "l": V(out, -thigh + 0.01, body.ankleHeight)]
            let top = hip.z - MachineFit.seat
            if back, let upright = MachineChair(body, lean: 8) {
                chair = upright
                pieces = upright.pieces(top: 0.6)
                // The chair's own post stands on a foot, and its back on a leg.
                pieces.append(Plan.box(V(0, -0.05, 0.015), (0.46, 0.5, 0.03), .metal))
                let low = upright.rest.behind(0.0, 0.1)
                pieces.append(Plan.rod(low, V(0, low.y + 0.12, 0.03), 0.03, .metal))
                pieces.append(Plan.box(V(0, low.y + 0.12, 0.015), (0.46, 0.06, 0.03), .metal))
            } else {
                // A flat bench, sat on at its end.
                let near = -(thigh - 0.14), far = 0.85
                pieces += Self.flatBench(from: near, to: far, top: top, posts: [near + 0.14, far - 0.14])
            }
        case .ball:
            // Hips a little higher than the knees, the feet out in front.
            let r = Self.ballRadius
            hip = V(0, 0, 2 * r - Self.ballSink + MachineFit.seat)
            let drop = hip.z - knee
            let forward = max(0.05, thigh * thigh - drop * drop).squareRoot()
            let out = apart + 0.07
            ankles = ["r": V(-out, -forward + 0.01, body.ankleHeight), "l": V(out, -forward + 0.01, body.ankleHeight)]
            let height = 2 * r - Self.ballSink
            pieces.append(Plan.ball(V(0, 0.03, height / 2), r, .accent, squash: height / (2 * r)))
            seat = .stabilityBall
        case .supine(let tilt):
            let pad = BenchStagings.Recline(body, lying: first, onFloor: false, lean: tilt)
            recline = pad
            hip = pad.hinge
            pieces = pad.bench()
        case .prone(let lean):
            let flat = lean > 80
            let joint = V(0, 0, flat ? Self.proneTop + MachineFit.front : Self.proneHip)
            hip = joint
            let t = lean * .pi / 180
            // Up the trunk toward the head, and out of the chest toward the pad.
            let along = V(0, -sin(t), cos(t)), front = V(0, -cos(t), -sin(t))
            let chest = (rShoulder.z - rHip.z) - 0.13
            let from = flat ? -(thigh + shin * 0.55) : 0.0
            func under(_ s: Double, _ depth: Double) -> V { joint + along * s + front * (MachineFit.front + depth) }
            let thick = Self.padThick
            pieces.append(Plan.box(under((from + chest) / 2, thick / 2), (Self.padWidth, chest - from, thick), x: side, z: front * -1, .pad))
            pieces.append(Plan.box(under((from + chest) / 2, thick + 0.02), (0.07, chest - from - 0.06, 0.04), x: side, z: front * -1, .metal))
            blocks.append(BulkRod(a: under(from + 0.05, 0.05), b: under(chest - 0.05, 0.05), ra: 0.075, rb: 0.075))
            // Posts under the belly and the hips (or the shins), clear of where the arms hang.
            let posts = flat ? [under(chest - 0.3, thick + 0.04), under(from + 0.15, thick + 0.04)]
                : [under(0.16, thick + 0.04), under(0.02, thick + 0.04)]
            for post in posts {
                pieces.append(Plan.box(V(0, post.y, post.z / 2), (0.06, 0.06, post.z), .metal))
                blocks.append(BulkRod(a: V(0, post.y, 0), b: post, ra: 0.04, rb: 0.04))
            }
            let ends = flat ? posts.map(\.y) : [posts[0].y - 0.3, posts[1].y + 0.42]
            let near = ends.min() ?? 0, far = ends.max() ?? 0
            pieces.append(Plan.box(V(0, (near + far) / 2, 0.025), (0.06, far - near, 0.05), .metal))
            for y in [near, far] { pieces.append(Plan.box(V(0, y, 0.02), (0.45, 0.06, 0.04), .metal)) }
        }
        self.chair = chair
        self.recline = recline
        self.blocks = blocks
        fixed = pieces
        kinds = plan.kinds.filter { ![.bench, .stabilityBall, .box, .step].contains($0) } + [seat]

        if case .prone(let lean) = support, lean <= 80 {
            // The legs run back to the floor, on the balls of the feet.
            let (_, h, _) = settle(first)
            let reach = Body3D.span(thigh, shin, bend: 18)
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let joint = h["femur.\(s)"], let print = body.footprint(s, x: -m * (apart + 0.05), y: 0, turnout: 6) else { continue }
                let up = body.lifted(print, heel: Self.proneHeel)
                let dz = joint.z - up.ankle.z, dx = joint.x - up.ankle.x
                let back = max(0.05, reach * reach - dz * dz - dx * dx).squareRoot()
                ankles[s] = V(up.ankle.x, joint.y + back, up.ankle.z)
                feet[s] = up.foot
                toes[s] = print.turn
            }
        }
        // A bar is carried round the loop once, as the plain picture carries it, so it comes
        // down onto the thighs of someone sitting and stays on top of them.
        if let hands = plan.hands, let bar = hands.bar, bar.clear {
            let loop = (0...24).map { i -> (g: [String: M], h: [String: V], floor: Double?) in
                let (g, h, _) = settle(Figure.interpolate(guide.keyframes, at: Double(i) / 24))
                return (g, h, 0)
            }
            let mids = loop.compactMap { hands.follow($0.g, $0.h, bar)?.mid }
            let offs = hands.track(loop, bar, loops: guide.keyframes.first?.pose == guide.keyframes.last?.pose)
            if mids.count == offs.count { trail = Array(zip(mids, offs)).map { (mid: $0.0, off: $0.1) } }
            if !blocks.isEmpty, let first = trail.first { hang = first.mid + first.off }
        }
    }

    /// How far off the hands' line the bar is carried when that line's middle is at `mid`:
    /// what the loop's nearest moments have, so it changes smoothly with the pose.
    func carried(_ mid: V) -> V {
        // Measured from the nearest moment, so a pose far from the whole loop still finds one.
        guard let least = trail.map({ ($0.mid - mid).length }).min() else { return V(0, 0, 0) }
        var sum = V(0, 0, 0), weight = 0.0
        for step in trail {
            let d = ((step.mid - mid).length - least) / 0.04
            let w = exp(-d * d)
            sum = sum + step.off * w
            weight += w
        }
        return sum * (1 / weight)
    }

    /// A flat bench along the body's line from `near` to `far`, its top at `top`.
    static func flatBench(from near: Double, to far: Double, top: Double, posts: [Double]) -> [PropPiece] {
        let mid = (near + far) / 2, thick = padThick
        var p = [Plan.box(V(0, mid, top - thick / 2), (0.3, far - near, thick), .pad),
                 Plan.box(V(0, mid, top - thick - 0.02), (0.07, far - near - 0.1, 0.04), .metal)]
        for y in posts {
            p.append(Plan.box(V(0, y, (top - thick - 0.04) / 2), (0.06, 0.06, top - thick - 0.04), .metal))
            p.append(Plan.box(V(0, y, 0.02), (0.38, 0.06, 0.04), .metal))
        }
        if let a = posts.min(), let b = posts.max(), b > a {
            p.append(Plan.box(V(0, (a + b) / 2, 0.025), (0.06, b - a, 0.05), .metal))
        }
        return p
    }

    /// Adds `degrees` to the shoulders' swing forward, so arms that hung straight down from a
    /// trunk leaning one way still hang straight down when it leans another.
    static func swing(_ pose: inout JointPose, by degrees: Double) {
        pose.angles["shoulderFlex"] = (pose.angles["shoulderFlex"] ?? 0) + degrees
        if let left = pose.angles["shoulderFlexL"] { pose.angles["shoulderFlexL"] = left + degrees }
    }

    /// The posed body on its support with the legs planted, and where its pelvis is.
    func settle(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V) {
        var pose = pose
        var g: [String: M], h: [String: V]
        func seated(_ pose: JointPose) -> ([String: M], [String: V]) {
            let g = body.rotations(pose)
            let rel = body.place(g, root: V(0, 0, 0))
            let joints = ["r", "l"].compactMap { rel["femur.\($0)"] }
            let mid = joints.reduce(V(0, 0, 0), +) * (1 / Double(max(1, joints.count)))
            return (g, body.place(g, root: hip - mid))
        }
        switch support {
        case .seat, .ball:
            if plan.hands?.each == true {
                for key in ["shoulderAbd", "shoulderAbdL"] {
                    if let abd = pose.angles[key], abd < Self.clearAbd { pose.angles[key] = Self.clearAbd }
                }
                if pose.angles["shoulderAbd"] == nil { pose.angles["shoulderAbd"] = Self.clearAbd }
            }
            if let chair {
                let sat = chair.sit(pose)
                return (sat.g, sat.h, sat.root)
            }
            if baseLean > 30 {
                // A trunk bent further over than sitting allows comes up, and the arms with it.
                // The hips stay sat: the lower back rounds to take half of the lean.
                let less = min(0, Self.seatedLean - baseLean)
                pose.angles["trunk"] = (pose.angles["trunk"] ?? 0) + less - Self.seatedRound / 2
                pose.angles["lumbar"] = (pose.angles["lumbar"] ?? 0) + Self.seatedRound
                Self.swing(&pose, by: less)
            }
            (g, h) = seated(pose)
            for s in ["r", "l"] {
                guard let ankle = ankles[s] else { continue }
                body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
            }
        case .supine:
            guard let recline else { return (body.rotations(pose), [:], hip) }
            (g, h) = recline.settle(pose)
            recline.plant(&g, h)
        case .prone(let lean):
            // The chest stays on the pad; a mistake that lifts it shows as the trunk coming up.
            let rise = min(0, (pose.angles["trunk"] ?? baseLean) - baseLean)
            pose.angles["trunk"] = lean + rise
            Self.swing(&pose, by: lean - baseLean)
            if lean > 80 {
                // Legs long on the bench, the feet hanging off its end.
                for key in ["hipFlex", "kneeFlex", "ankleDorsi", "hipAbd"] {
                    pose.angles[key + "L"] = nil
                }
                pose.angles["hipFlex"] = -rise
                pose.angles["kneeFlex"] = 3
                pose.angles["ankleDorsi"] = -30
                pose.angles["hipAbd"] = 3
            }
            (g, h) = seated(pose)
            for s in ["r", "l"] {
                guard let ankle = ankles[s], let foot = feet[s] else { continue }
                body.plant(s, ankle: ankle, foot: foot, pole: (g["pelvis"] ?? .identity) * V(0, -1, 0), &g, h)
                if let flat = toes[s] { g["toes.\(s)"] = flat }
            }
        }
        let root = h["pelvis"] ?? hip
        return (g, body.place(g, root: root), root)
    }

    /// Closes the hands on what they hold, as the plain picture does: a bar in both hands is
    /// kept out of the body and its support, and both arms are fitted to it.
    func fit(_ g: inout [String: M], _ h: inout [String: V], root: V) -> Held {
        var held = Held()
        guard let hands = plan.hands else { return held }
        if let bar = hands.bar, let line = hands.follow(g, h, bar) {
            var goal = line.mid + carried(line.mid)
            if let hang {
                // Under a bench the bar comes up from where it hung until it meets the pad or a
                // post, and waits there: it never jumps round to their other side.
                func clear(_ p: V) -> Bool {
                    Body3D.wayOut(p, axis: line.axis, half: bar.length, radius: bar.radius + 0.006, of: blocks, front: line.front) == nil
                }
                let steps = max(1, Int(((goal - hang).length / 0.01).rounded(.up)))
                var reached = hang
                for i in 1...steps {
                    let p = mix(hang, goal, Double(i) / Double(steps))
                    guard clear(p) else { break }
                    reached = p
                }
                goal = reached
            }
            var mid = hands.settle(goal, axis: line.axis, front: line.front, rods: body.bulk(g, h, behind: bar.behind), h, bar, floor: 0)
            for (s, m) in Handhold.sides {
                guard let grip = hands.grips[s], let shoulder = h["humerus.\(s)"] else { continue }
                let point = hands.target(s, m, mid: mid, axis: line.axis, bar)
                let across: V
                switch bar.handles {
                case .along: across = line.axis * (bar.turn[s] ?? -m)
                case .forward: across = line.axis.cross(V(0, 0, 1)).unit * -1
                case .upright: across = line.axis.cross(line.front)
                }
                let hinge = (g["humerus.\(s)"] ?? .identity) * body.hingeAxis(s)
                body.hold(s, grip, at: point, across: across, pole: (point - shoulder).cross(hinge), &g, h)
            }
            h = body.place(g, root: root)
            var miss = V(0, 0, 0)
            for (s, m) in Handhold.sides {
                guard let c = hands.centre(s, g, h) else { continue }
                miss = miss + (c - hands.target(s, m, mid: mid, axis: line.axis, bar)) * 0.5
            }
            mid = mid + miss
            held.bar = (mid, line.axis)
        } else if hands.each {
            for (s, _) in Handhold.sides {
                guard let grip = hands.grips[s], let hand = g["hand.\(s)"] else { continue }
                for (bone, turn) in grip.turns { g[bone] = hand * turn }
            }
            h = body.place(g, root: root)
        }
        for (s, _) in Handhold.sides {
            if let grip = hands.grips[s], let c = hands.centre(s, g, h), let hand = g["hand.\(s)"] {
                held.grips[s] = PropPlan.Grip(point: c, across: hand * grip.across, palm: hand * grip.palm, fingers: hand * grip.along)
            } else if let open = PropPlan.grip(g, h, s) {
                held.grips[s] = open
            }
        }
        return held
    }

    /// The body for one pose, and what its hands hold.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, held: Held) {
        var (g, h, root) = settle(pose)
        let held = fit(&g, &h, root: root)
        return (body.made(g, h, floor: 0), held)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, held) = solve(pose)
        return (frame, plan.moving(frame, held))
    }
}

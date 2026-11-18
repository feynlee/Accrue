import Foundation

/// Lying or sitting on a bench with a bar or dumbbells: bench press, fly, pullover, lying triceps extension, hip thrust.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum BenchStagings {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        switch guide.familyID {
        case "bench-press": return BenchPressStaging(guide, body)
        case "chest-fly", "pullover", "triceps-extension": return BenchLyingStaging(guide, body)
        case "hip-thrust-bridge": return BenchThrustStaging(guide, body)
        default: return nil
        }
    }

    // MARK: The body's surface

    /// Where the skin is, measured on the model at rest, down the middle of the body. A lying
    /// body rests on these and a bar stops at them. `hips`, `seat`, `back` and `skull` are
    /// (how far behind the body's middle line, height above the floor); `chest` is (height, how
    /// far in front).
    enum Skin {
        static let hips: [(Double, Double)] = [(0.148, 0.78), (0.154, 0.82), (0.153, 0.86), (0.144, 0.90)]
        static let seat: [(Double, Double)] = [(0.125, 0.74), (0.148, 0.78), (0.154, 0.82)]
        static let back: [(Double, Double)] = [(0.133, 1.18), (0.136, 1.22), (0.140, 1.26), (0.140, 1.30),
                                               (0.137, 1.34), (0.129, 1.38)]
        static let skull: [(Double, Double)] = [(0.095, 1.54), (0.107, 1.58), (0.107, 1.62), (0.098, 1.66)]
        static let chest: [(Double, Double)] = [(1.10, 0.134), (1.14, 0.135), (1.18, 0.134), (1.22, 0.138), (1.26, 0.139),
                                                (1.30, 0.132), (1.34, 0.113), (1.38, 0.089), (1.42, 0.060)]
        static let crown = 1.71

        /// How far the chest stands in front of the middle line at `height`.
        static func front(_ height: Double) -> Double {
            guard let first = chest.first, let last = chest.last else { return 0.13 }
            if height <= first.0 { return first.1 }
            for (a, b) in zip(chest, chest.dropFirst()) where height <= b.0 {
                return a.1 + (b.1 - a.1) * (height - a.0) / (b.0 - a.0)
            }
            return last.1
        }
    }

    // MARK: Progress

    /// How far a movement has gone, read from one angle of the pose: 0 where the loop starts,
    /// 1 at its far end. A mistake that changes that angle shows here too.
    struct Travel: Sendable {
        let key: String
        let from, to: Double

        init(_ key: String, _ keys: [Keyframe]) {
            self.key = key
            let values = keys.map { $0.pose.angles[key] ?? 0 }
            let start = values.first ?? 0
            from = start
            let far = values.max { abs($0 - start) < abs($1 - start) } ?? start
            to = abs(far - start) < 1 ? start + 1 : far
        }

        func callAsFunction(_ pose: JointPose) -> Double {
            min(1, max(0, ((pose.angles[key] ?? from) - from) / (to - from)))
        }
    }

    /// An angle of the pose as the keyframes have it at each end of the movement, to tell how
    /// far a mistake has pushed it from where it should be.
    struct Expected: Sendable {
        let key: String
        let start, end: Double

        init(_ key: String, _ keys: [Keyframe], along travel: Travel) {
            self.key = key
            let first = keys.first?.pose
            let far = keys.max { travel($0.pose) < travel($1.pose) }?.pose
            start = first?.angles[key] ?? 0
            end = far?.angles[key] ?? start
        }

        /// How many degrees the pose is past the keyframes' own value at travel `u`.
        func excess(_ pose: JointPose, at u: Double) -> Double {
            (pose.angles[key] ?? 0) - (start + (end - start) * u)
        }
    }

    // MARK: Lying down

    /// The pad a body lies back on, and how the body is laid on it: the hips and the upper back
    /// both resting on the pad, and the head laid back onto it. The pad slopes up from the hips
    /// by `tilt` degrees (0 flat, 30 an incline, -15 a decline); with no bench it is the floor.
    struct Recline: Sendable {
        enum Kind: Sendable { case floor, flat, incline, decline }

        let body: Body3D
        let kind: Kind
        let tilt: Double
        /// A point on the pad's top at its hips' end: where an incline's back meets its seat.
        let hinge: V
        /// How far up the pad from there the hip joints lie.
        private(set) var hips = 0.0
        /// How far the hips' soft parts press into the pad.
        let sink: Double
        /// Where the pad ends, past the top of the head.
        private(set) var headEnd = 1.2
        private(set) var ankles: [String: V] = [:]
        private(set) var knees: [String: V] = [:]
        /// Legs held straight out in the air instead of planted (a Larsen press).
        let legsOut: Bool

        static let padWidth = 0.3, padThick = 0.07

        /// `lean` is the pad's slope when the pose does not say (families whose keyframes all lie flat).
        init(_ body: Body3D, lying pose: JointPose, onFloor: Bool, knees bend: Double = 85, legsOut: Bool = false,
             lean slope: Double? = nil) {
            self.body = body
            self.legsOut = legsOut
            let lean = slope ?? 90 + (pose.angles["trunk"] ?? -90)
            if onFloor {
                kind = .floor
                tilt = 0
                hinge = V(0, 0, 0)
                sink = 0.005
            } else if lean > 8 {
                kind = .incline
                tilt = min(60, lean)
                hinge = V(0, 0, 0.4)
                sink = 0.015
            } else if lean < -8 {
                kind = .decline
                tilt = max(-25, lean)
                hinge = V(0, 0, 0.66)
                sink = 0.015
            } else {
                kind = .flat
                tilt = 0
                hinge = V(0, 0, 0.43)
                sink = 0.015
            }
            hips = kind == .floor ? 0 : 0.11
            if kind == .incline {
                // The hips slide down the back pad until they sit on the seat.
                let (g, h) = settle(pose)
                let low = Skin.seat.compactMap { body.benchSkin("pelvis", back: $0.0, up: $0.1, g, h)?.z }.min() ?? hinge.z
                hips += (hinge.z - sink - low) / sin(tilt * .pi / 180)
            }
            let (g, h) = settle(pose)
            if let crown = body.benchSkin("head", back: 0.02, up: Skin.crown, g, h) {
                headEnd = (crown - hinge).dot(along) + 0.05
            }
            (ankles, knees) = legs(h, bend: bend)
        }

        /// Up the pad from the hips to the head, and straight out of its top.
        var along: V { V(0, cos(tilt * .pi / 180), sin(tilt * .pi / 180)) }
        var normal: V { V(0, -sin(tilt * .pi / 180), cos(tilt * .pi / 180)) }

        /// How far `p` is above the pad's top.
        func height(_ p: V) -> Double { (p - hinge).dot(normal) }

        /// The point `s` up the pad from the hinge and `under` below its top.
        func point(_ s: Double, under: Double = 0) -> V { hinge + along * s - normal * under }

        /// The posed body laid on the pad. `lift` (degrees) tips it up about the upper back so
        /// the hips leave the pad, for the mistakes that do that.
        func settle(_ pose: JointPose, lift: Double = 0) -> (g: [String: M], h: [String: V]) {
            var g = body.rotations(pose)
            var h = body.place(g, root: V(0, 0, 0))
            let n = normal
            func lowest(_ bone: String, _ skin: [(Double, Double)], _ turn: M) -> V {
                var best = V(0, 0, 0), low = Double.infinity
                for (back, up) in skin {
                    guard let p = body.benchSkin(bone, back: back, up: up, g, h) else { continue }
                    let z = (turn * p).dot(n)
                    if z < low { low = z; best = p }
                }
                return best
            }
            // Turn the whole body until the hips and the upper back lie along the pad.
            var angle = 0.0
            for _ in 0..<4 {
                let r = M.x(angle)
                let d = lowest("thorax", Skin.back, r) - lowest("pelvis", Skin.hips, r)
                angle = tilt - atan2(d.z, d.y) * 180 / .pi
            }
            let r = M.x(angle)
            for (k, m) in g { g[k] = r * m }
            h = body.place(g, root: V(0, 0, 0))
            let seat = lowest("pelvis", Skin.hips, .identity)
            var root = hinge + along * hips - n * (sink + seat.dot(n))
            h = body.place(g, root: root)
            if lift > 0 {
                let pivot = lowest("thorax", Skin.back, .identity)
                let up = M.x(-lift)
                for (k, m) in g { g[k] = up * m }
                root = pivot + up * (root - pivot)
                h = body.place(g, root: root)
            }
            restHead(&g, &h)
            return (g, h)
        }

        /// Lays the head back until the skull rests on the pad, as far as the neck allows.
        /// `most` is how far the chin may come toward the chest to keep it there.
        func restHead(_ g: inout [String: M], _ h: inout [String: V], most: Double = 20) {
            guard let thorax = g["thorax"], let neck = h["neck"], let rNeck = body.head["neck"],
                  let rHead = body.head["head"] else { return }
            func gap(_ nod: Double) -> Double {
                let base = neck + thorax * M.x(nod / 2) * (rHead - rNeck)
                let turn = thorax * M.x(nod)
                return Skin.skull.map { height(base + turn * (V(0, $0.0, $0.1) - rHead)) }.min() ?? 0
            }
            var back = -30.0, forward = most
            if gap(back) > 0 {
                forward = back
            } else if gap(forward) < 0 {
                back = forward
            } else {
                for _ in 0..<18 {
                    let mid = (back + forward) / 2
                    if gap(mid) > 0 { forward = mid } else { back = mid }
                }
            }
            let nod = (back + forward) / 2
            g["neck"] = thorax * M.x(nod / 2)
            g["head"] = thorax * M.x(nod)
            h["head"] = neck + thorax * M.x(nod / 2) * (rHead - rNeck)
        }

        /// Where the legs go, found once from the body as it first lies: feet flat on the floor
        /// either side of the bench with the knees bent by `bend` (or on the floor the body lies
        /// on), and on a decline the knees hooked over one roller with the shins behind another.
        func legs(_ h: [String: V], bend: Double) -> (ankles: [String: V], knees: [String: V]) {
            var ankles: [String: V] = [:], knees: [String: V] = [:]
            let wide = kind == .floor ? 0.12 : 0.25
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let hip = h["femur.\(s)"], let rHip = body.head["femur.\(s)"], let rKnee = body.head["shin.\(s)"],
                      let rAnkle = body.head["foot.\(s)"] else { continue }
                let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
                if legsOut {
                    ankles[s] = V(hip.x, hip.y - (thigh + shin) * 0.995, hip.z - 0.03)
                } else if kind == .decline {
                    // Thighs a little above the pad's own line, shins hanging from the knees.
                    let rise = (10 - tilt) * .pi / 180, hang = rise - Self.hookedKnee * .pi / 180
                    let knee = V(hip.x * 1.25, hip.y - thigh * cos(rise), hip.z + thigh * sin(rise))
                    knees[s] = knee
                    ankles[s] = knee + V(0, -cos(hang), sin(hang)) * shin
                } else {
                    let leg = Body3D.span(thigh, shin, bend: bend)
                    let drop = hip.z - body.ankleHeight, aside = wide - abs(hip.x)
                    let forward = max(0.04, leg * leg - drop * drop - aside * aside).squareRoot()
                    ankles[s] = V(-m * wide, hip.y - forward, body.ankleHeight)
                }
            }
            return (ankles, knees)
        }

        /// How far the knees bend over a decline bench's roller.
        static let hookedKnee = 100.0

        /// Puts the legs where `legs` found them.
        func plant(_ g: inout [String: M], _ h: [String: V]) {
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let ankle = ankles[s] else { continue }
                if kind == .decline || legsOut {
                    body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
                    // The feet hang square to the shins, toes pulled up a little.
                    if let shin = g["shin.\(s)"] {
                        g["foot.\(s)"] = shin * M.x(-8)
                        g["toes.\(s)"] = shin * M.x(-8)
                    }
                } else {
                    body.plant(s, ankle: ankle, foot: .identity, pole: V(-m * 0.25, -1, 0.5), &g, h)
                }
            }
        }

        // MARK: The bench itself

        /// How far up the pad the post at the head's end stands.
        var headFoot: Double { headEnd - 0.22 }

        /// The bench: its pads on a frame with a foot at each end.
        func bench() -> [PropPiece] {
            guard kind != .floor else { return [] }
            var p: [PropPiece] = []
            let side = V(1, 0, 0), n = normal
            let thick = Self.padThick
            let start = kind == .incline ? 0.05 : 0.0
            // The pad the back lies on comes first: it is the one a test looks for.
            p.append(Plan.box(point((start + headEnd) / 2, under: thick / 2), (Self.padWidth, headEnd - start, thick),
                              x: side, z: n, .pad))
            p.append(Plan.box(point((start + headEnd) / 2, under: thick + 0.02), (0.07, headEnd - start - 0.1, 0.04),
                              x: side, z: n, .metal))
            var posts = [point(headFoot, under: thick + 0.03)]
            var feet = [(posts[0].y, 0.5)]
            if kind == .incline {
                // A level seat in front of the back pad.
                let seat = V(0, hinge.y - 0.19, hinge.z)
                p.append(Plan.box(seat - V(0, 0, thick / 2), (Self.padWidth - 0.02, 0.32, thick), .pad))
                posts.append(seat - V(0, 0.02, thick))
                posts.append(point(0.3, under: thick + 0.03))
                feet.append((seat.y - 0.12, 0.4))
            } else {
                posts.append(point(0.14, under: thick + 0.03))
                feet.append((posts[1].y, 0.36))
            }
            for post in posts {
                p.append(Plan.box(V(0, post.y, post.z / 2), (0.06, 0.06, post.z), .metal))
            }
            if kind == .decline, !legsOut, let knee = knees["l"], let ankle = ankles["l"] {
                // A roller under the knees and one in front of the shins, on a post between the legs.
                let shin = (ankle - knee).unit
                let pit = (V(0, cos((10 - tilt) * .pi / 180), -sin((10 - tilt) * .pi / 180)) + shin).unit
                let under = V(0, knee.y, knee.z) + pit * 0.12
                let front = V(0, ankle.y, ankle.z) - shin * 0.07 + V(0, shin.z, -shin.y) * 0.1
                for (c, radius) in [(under, 0.06), (front, 0.05)] {
                    for x in [-0.135, 0.135] {
                        p.append(Plan.disc(c + V(x, 0, 0), axis: side, radius: radius, thickness: 0.17, .pad))
                    }
                    p.append(Plan.rod(c - V(0.21, 0, 0), c + V(0.21, 0, 0), 0.014, .metal))
                }
                let foot = V(0, under.y - 0.02, 0)
                p.append(Plan.rod(foot, under, 0.025, .metal))
                p.append(Plan.rod(under, front, 0.02, .metal))
                p.append(Plan.box(V(0, foot.y, 0.02), (0.4, 0.06, 0.04), .metal))
                feet.append((foot.y, 0))
            }
            // One rail along the floor, and a foot across it at each end.
            let ends = feet.map(\.0)
            let near = ends.min() ?? 0, far = ends.max() ?? 0
            p.append(Plan.box(V(0, (near + far) / 2, 0.025), (0.06, far - near, 0.05), .metal))
            for (y, width) in feet where width > 0 {
                p.append(Plan.box(V(0, y, 0.02), (width, 0.06, 0.04), .metal))
            }
            return p
        }
    }

    // MARK: What the hands hold

    /// A loaded bar centred on `mid`, as the plain equipment draws it.
    static func barbell(_ mid: V, axis: V = V(1, 0, 0), length: Double = 2.0, plate: Double = 0.225) -> [PropPiece] {
        let half = length / 2, a = axis.unit
        var p = [Plan.rod(mid - a * half, mid + a * half, 0.014, .metal)]
        for side in [-1.0, 1.0] {
            p.append(Plan.disc(mid + a * (side * (half - 0.2)), axis: a, radius: plate, thickness: 0.07, .plate))
            p.append(Plan.disc(mid + a * (side * (half - 0.27)), axis: a, radius: 0.03, thickness: 0.03, .metal))
        }
        return p
    }

    static let dumbbellHandle = 0.016, dumbbellHead = 0.06

    /// A dumbbell with its handle centred on `mid`.
    static func dumbbell(_ mid: V, axis: V) -> [PropPiece] {
        let a = axis.unit
        var p = [Plan.rod(mid - a * 0.13, mid + a * 0.13, dumbbellHandle, .metal)]
        for side in [-1.0, 1.0] {
            p.append(Plan.disc(mid + a * (side * 0.1), axis: a, radius: dumbbellHead, thickness: 0.07, .dark))
        }
        return p
    }

    /// The roundness of a hand that rests or presses flat: as if it lay over a wide tube.
    static let openHand = 0.07

    /// Lays the left hand flat on the belly, out of the way of the arm that works. `idle` is
    /// the left hand's grip at `openHand`.
    static func rest(_ body: Body3D, _ idle: HandGrip, _ g: inout [String: M], _ h: [String: V]) {
        guard let waist = h["lumbar"], let rWaist = body.head["lumbar"], let turn = g["lumbar"] else { return }
        // A little left of the navel, where the belly's skin faces up and slightly aside.
        let out = (turn * V(0.25, -1, 0)).unit
        let reach = turn * V(-0.9, 0, -0.45)
        let fingers = (reach - out * reach.dot(out)).unit
        let touch = waist + turn * (V(0.08, -0.118, 1.04) - rWaist)
        let hand = Body3D.frameMap(idle.along, idle.palm, to: fingers, out * -1)
        body.benchLay("l", wrist: touch + out * 0.022 - fingers * 0.06, hand: hand, turns: idle.turns,
                      pole: turn * V(1, 0.6, 0.3), &g, h)
    }

    /// Two uprights with hooks for the bar, standing behind the head at `y`, the hooks at `height`.
    static func rack(y: Double, height: Double, from bench: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        for x in [-0.56, 0.56] {
            p.append(Plan.box(V(x, y, (height + 0.1) / 2), (0.05, 0.05, height + 0.1), .metal))
            p.append(Plan.box(V(x, y - 0.1, 0.02), (0.07, 0.6, 0.04), .metal))
            // The hook: a ledge the bar sits on, with a lip in front.
            p.append(Plan.box(V(x, y - 0.06, height - 0.012), (0.05, 0.07, 0.016), .metal))
            p.append(Plan.box(V(x, y - 0.09, height + 0.008), (0.05, 0.012, 0.04), .metal))
        }
        p.append(Plan.box(V(0, y, 0.025), (1.12, 0.05, 0.05), .metal))
        if abs(bench - y) > 0.03 {
            p.append(Plan.box(V(0, (bench + y) / 2, 0.025), (0.06, abs(bench - y), 0.05), .metal))
        }
        return p
    }
}

extension Body3D {
    /// A point of the skin that rides on `bone`, given where it is at rest on the body's middle
    /// line: `back` behind it and `up` above the floor.
    func benchSkin(_ bone: String, back: Double, up: Double, _ g: [String: M], _ h: [String: V]) -> V? {
        guard let at = h[bone], let rest = head[bone] else { return nil }
        return at + (g[bone] ?? .identity) * (V(0, back, up) - rest)
    }

    /// Poses the arm of side `s` so its wrist is at `wrist` with the hand turned as `hand`, the
    /// elbow toward `pole`: for a hand that rests on something or presses flat against it
    /// rather than closing round a bar. `turns` are the finger bones' turns from the hand.
    func benchLay(_ s: String, wrist: V, hand: M, turns: [String: M], pole: V, _ g: inout [String: M], _ h: [String: V]) {
        let m = s == "r" ? 1.0 : -1.0
        guard let shoulder = h["humerus.\(s)"], let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"],
              let rRadius = head["radius.\(s)"], let rWrist = head["hand.\(s)"] else { return }
        let upper = rElbow - rShoulder
        let hinge = hingeAxis(s), axis = pronationAxis(s)
        let toRadius = rRadius - rElbow, toWrist = rWrist - rRadius
        var pronation = 90.0
        var ulna = M.identity, elbow = shoulder
        var k = hinge
        for _ in 0..<6 {
            let v = toRadius + M.axis(axis, -m * pronation) * toWrist
            let solved = Self.bend(root: shoulder, target: wrist, upper: upper.length, lower: v.length, pole: pole)
            elbow = solved.joint
            let n = pole.cross(solved.end - shoulder)
            if n.length > 1e-9 { k = n.unit }
            ulna = Self.frameMap(v, hinge, to: solved.end - elbow, k)
            // The forearm turns as far as the hand's own turn about the forearm's line asks.
            let q = (ulna.t * hand).quat
            var p = -m * 2 * atan2(q.x * axis.x + q.y * axis.y + q.z * axis.z, q.w) * 180 / .pi
            if p < -90 { p += 360 }
            pronation = min(175, max(0, p))
        }
        g["humerus.\(s)"] = Self.frameMap(upper, hinge, to: elbow - shoulder, k)
        g["ulna.\(s)"] = ulna
        turnForearm(s, ulna: ulna, pronation: pronation, into: &g)
        g["hand.\(s)"] = hand
        for (bone, turn) in turns { g[bone] = hand * turn }
    }
}

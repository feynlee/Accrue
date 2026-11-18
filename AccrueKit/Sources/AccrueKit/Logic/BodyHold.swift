import Foundation

/// A hand closed around a bar or handle of one thickness, worked out once from the rig: where
/// the bar lies in the palm and how every finger bone turns to wrap it. All in the hand's rest
/// axes, so a posed hand is `hand rotation × turn`.
struct HandGrip: Sendable {
    /// The bar's centre line under the palm, from the wrist.
    var centre: Body3D.V
    /// Along the bar from the thumb side to the little finger, along the hand, and out of the palm.
    var across, along, palm: Body3D.V
    /// How far the wrist bends back (degrees) so the forearm's pull runs through the bar.
    var wristBack: Double
    /// Each finger and thumb bone's turn from rest.
    var turns: [String: Body3D.M]
}

extension Body3D {
    // MARK: Small tools

    /// The rotation taking direction `a0` exactly onto `a1`, with `b0` turned as near to `b1` as
    /// that leaves room for.
    static func frameMap(_ a0: V, _ b0: V, to a1: V, _ b1: V) -> M {
        func basis(_ a: V, _ b: V) -> M {
            let a = a.unit
            var c = a.cross(b)
            if c.length < 1e-9 { c = a.cross(abs(a.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0)) }
            c = c.unit
            let d = c.cross(a)
            return M(r0: V(a.x, d.x, c.x), r1: V(a.y, d.y, c.y), r2: V(a.z, d.z, c.z))
        }
        return basis(a1, b1) * basis(a0, b0).t
    }

    /// The middle joint of a two-bone limb reaching from `root` to `target`, bent toward `pole`.
    /// A target out of reach is pulled in along the same line, and returned as `end`.
    static func bend(root: V, target: V, upper: Double, lower: Double, pole: V) -> (joint: V, end: V) {
        let d = target - root
        let dir = d.length > 1e-9 ? d.unit : V(0, 0, -1)
        let reach = min(max(d.length, abs(upper - lower) + 1e-4), upper + lower - 1e-4)
        let a = (upper * upper - lower * lower + reach * reach) / (2 * reach)
        let h = max(0, upper * upper - a * a).squareRoot()
        var p = pole - dir * pole.dot(dir)
        if p.length < 1e-6 { p = dir.cross(abs(dir.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0)) }
        return (root + dir * a + p.unit * h, root + dir * reach)
    }

    /// The straight-line distance from shoulder to wrist (or hip to ankle) at a joint bend in degrees.
    static func span(_ upper: Double, _ lower: Double, bend degrees: Double) -> Double {
        (upper * upper + lower * lower + 2 * upper * lower * cos(degrees * .pi / 180)).squareRoot()
    }

    /// Bone heads with the pelvis at `root`.
    func place(_ g: [String: M], root: V) -> [String: V] {
        var h = heads(g)
        guard let p = h["pelvis"] else { return h }
        let d = root - p
        for (k, v) in h { h[k] = v + d }
        return h
    }

    /// The body's centre of mass without the arms (Winter's segment masses), which a hanging
    /// body keeps under the bar.
    func balance(_ g: [String: M], _ h: [String: V]) -> V {
        var sum = V(0, 0, 0), mass = 0.0
        func add(_ a: String, _ b: String?, _ share: Double, _ m: Double) {
            guard let p = h[a] else { return }
            let q = b.flatMap { h[$0] } ?? tip(a, g, h) ?? p
            sum = sum + (p + (q - p) * share) * m
            mass += m
        }
        add("pelvis", "lumbar", 0.2, 0.142)
        add("lumbar", "thorax", 0.5, 0.139)
        add("thorax", "neck", 0.45, 0.216)
        add("head", nil, 0.6, 0.081)
        for s in ["r", "l"] {
            add("femur.\(s)", "shin.\(s)", 0.433, 0.1)
            add("shin.\(s)", "foot.\(s)", 0.433, 0.0465)
            add("foot.\(s)", "toes.\(s)", 0.5, 0.0145)
        }
        return mass > 0 ? sum * (1 / mass) : V(0, 0, 0)
    }

    // MARK: The closed hand

    /// The hand of side `s` closed around a bar of `radius`. `square` turns the bar from lying
    /// along the knuckles (0) to lying square across the hand (1); a wide grip on a straight bar
    /// sits in between.
    func grip(_ s: String, radius: Double, square: Double = 0) -> HandGrip? {
        guard let wrist = head["hand.\(s)"], let k2 = head["f2a.\(s)"], let k3 = head["f3a.\(s)"],
              let k4 = head["f4a.\(s)"], let k5 = head["f5a.\(s)"] else { return nil }
        let reach = (k3 - wrist).unit
        let knuckles = (k5 - k2).unit
        let squared = (knuckles - reach * knuckles.dot(reach)).unit
        let across = (knuckles * (1 - square) + squared * square).unit
        let along = (reach - across * reach.dot(across)).unit
        var palm = across.cross(along).unit
        if palm.dot(Self.forward) < 0 { palm = palm * -1 }

        // The bar presses into the palm just behind the knuckles.
        let palmPad = 0.020, setBack = 0.018
        let mid = (k2 + k3 + k4 + k5) * 0.25
        let centre = mid + palm * (radius + palmPad) - along * setBack
        func flat(_ p: V) -> (Double, Double) { ((p - centre).dot(along), (p - centre).dot(palm)) }
        func dir(_ a: Double) -> V { along * cos(a) + palm * sin(a) }
        func turn(_ a: Double) -> Double {
            var a = a
            while a > .pi { a -= 2 * .pi }
            while a < -.pi { a += 2 * .pi }
            return a
        }
        let deg = Double.pi / 180
        var turns: [String: M] = [:]

        // Fingers: each bone lies against the bar, so the finger goes round it as a chain of
        // tangents. `pads` is how far each bone's middle line sits from the skin of its pad.
        let pads = [0.013, 0.010, 0.007]
        let limits = [(-10.0, 95.0), (0.0, 110.0), (12.0, 75.0)]
        for f in 2...5 {
            let names = ["a", "b", "c"].map { "f\(f)\($0).\(s)" }
            guard let p0 = head[names[0]], let p1 = head[names[1]], let p2 = head[names[2]],
                  let p3 = tail[names[2]] else { continue }
            let pts = [p0, p1, p2, p3]
            var (x, y) = flat(p0)
            var before = 0.0
            for i in 0..<3 {
                let rest = pts[i + 1] - pts[i]
                let r = radius + pads[i]
                let d = hypot(x, y), toCentre = atan2(-y, -x)
                let tangent = d > r ? toCentre - asin(r / d) : toCentre - .pi / 2
                let flex = min(max(turn(tangent - before), limits[i].0 * deg), limits[i].1 * deg)
                let a = before + flex
                turns[names[i]] = Self.frameMap(rest, palm, to: dir(a), dir(a + .pi / 2))
                x += rest.length * cos(a)
                y += rest.length * sin(a)
                before = a
            }
        }

        // Thumb: round the other way, beside the first finger.
        let thumb = ["a", "b", "c"].map { "f1\($0).\(s)" }
        if let c0 = head[thumb[0]], let c1 = head[thumb[1]], let c2 = head[thumb[2]], let c3 = tail[thumb[2]] {
            let pts = [c0, c1, c2, c3]
            let splay = 14 * deg
            let r = radius + 0.010
            let pad = (across * 0.8 + palm * 0.6).unit
            let limits = [(0.0, 0.0), (0.0, 55.0), (0.0, 75.0)]
            var (x, y) = flat(c0)
            var before = 0.0
            for i in 0..<3 {
                let rest = pts[i + 1] - pts[i]
                let d = hypot(x, y), toCentre = atan2(-y, -x)
                let tangent = d > r ? toCentre + asin(r / d) : toCentre + .pi / 2
                var a = tangent
                if i == 0 {
                    a = min(max(turn(a), 15 * deg), 80 * deg)
                } else {
                    let flex = min(max(turn(before - tangent), limits[i].0 * deg), limits[i].1 * deg)
                    a = before - flex
                }
                let to = dir(a) * cos(splay) - across * sin(splay)
                turns[thumb[i]] = Self.frameMap(rest, pad, to: to, dir(a - .pi / 2))
                x += rest.length * cos(splay) * cos(a)
                y += rest.length * cos(splay) * sin(a)
                before = a
            }
        }

        let (wx, wy) = flat(wrist)
        let back = atan2(-wy, -wx) / deg
        return HandGrip(centre: centre - wrist, across: across, along: along, palm: palm,
                        wristBack: back * 0.8, turns: turns)
    }

    /// The hand's rotation when it holds a bar that runs along `across` (thumb side to little
    /// finger) with the forearm arriving along `forearm` (elbow to wrist).
    func handTurn(_ grip: HandGrip, across: V, forearm: V) -> M {
        let a = across.unit
        var f = forearm - a * forearm.dot(a)
        if f.length < 1e-6 { f = a.cross(abs(a.z) < 0.9 ? V(0, 0, 1) : V(0, 1, 0)) }
        let flat = Self.frameMap(grip.across, grip.along, to: a, f)
        // Turning about the bar by +angle takes the fingers toward across × along.
        let sign = grip.across.cross(grip.along).dot(grip.palm) > 0 ? -1.0 : 1.0
        return M.axis(a, sign * grip.wristBack) * flat
    }

    // MARK: Limbs that reach a target

    /// Poses the arm of side `s` so its hand holds a bar at `point` (the bar's centre under the
    /// palm) running along `across`, with the elbow toward `pole`. The shoulder stays where the
    /// shoulder blade put it; the forearm turns as far as the grip needs.
    /// Returns the elbow bend in degrees.
    @discardableResult
    func hold(_ s: String, _ grip: HandGrip, at point: V, across: V, pole: V,
              _ g: inout [String: M], _ h: [String: V]) -> Double {
        let m = s == "r" ? 1.0 : -1.0
        guard let shoulder = h["humerus.\(s)"], let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"],
              let rRadius = head["radius.\(s)"], let rWrist = head["hand.\(s)"] else { return 0 }
        let upper = rElbow - rShoulder
        let hinge = hingeAxis(s), axis = pronationAxis(s)
        let toRadius = rRadius - rElbow, toWrist = rWrist - rRadius
        func forearm(_ pronation: Double) -> V { toRadius + M.axis(axis, -m * pronation) * toWrist }

        var pronation = 120.0
        var along = (point - shoulder).unit
        var elbow = shoulder, wrist = point
        var ulna = M.identity, hand = M.identity
        var k = pole.cross(point - shoulder).unit
        for _ in 0..<6 {
            hand = handTurn(grip, across: across, forearm: along)
            wrist = point - hand * grip.centre
            let v = forearm(pronation)
            let solved = Self.bend(root: shoulder, target: wrist, upper: upper.length, lower: v.length, pole: pole)
            elbow = solved.joint
            wrist = solved.end
            along = (wrist - elbow).unit
            let n = pole.cross(wrist - shoulder)
            if n.length > 1e-9 { k = n.unit }
            ulna = Self.frameMap(v, hinge, to: wrist - elbow, k)
            // The forearm's turn is the part of the hand's rotation about the forearm's own line.
            let q = (ulna.t * hand).quat
            var p = -m * 2 * atan2(q.x * axis.x + q.y * axis.y + q.z * axis.z, q.w) * 180 / .pi
            if p < -90 { p += 360 }
            pronation = min(175, max(0, p))
        }
        g["humerus.\(s)"] = Self.frameMap(upper, hinge, to: elbow - shoulder, k)
        g["ulna.\(s)"] = ulna
        turnForearm(s, ulna: ulna, pronation: pronation, into: &g)
        g["hand.\(s)"] = hand
        for (bone, turn) in grip.turns { g[bone] = hand * turn }
        let a = (elbow - shoulder).unit, b = (wrist - elbow).unit
        return acos(min(1, max(-1, a.dot(b)))) * 180 / .pi
    }

    /// The straight-line distance from the shoulder to the bar when the elbow is bent `degrees`,
    /// for an arm that hangs from or pulls on the bar.
    func reach(_ s: String, _ grip: HandGrip, bend degrees: Double) -> Double {
        guard let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"], let rWrist = head["hand.\(s)"] else { return 0.6 }
        let arm = Self.span((rElbow - rShoulder).length, (rWrist - rElbow).length, bend: degrees)
        // The wrist sits in line between the shoulder and the bar, a palm's depth short of it.
        let c = grip.centre
        let depth = (c - grip.across * c.dot(grip.across)).length
        return arm + depth
    }

    /// Poses the leg of side `s` so its ankle is at `ankle` with the knee toward `pole`, and the
    /// foot turned by `foot`.
    func plant(_ s: String, ankle: V, foot: M, pole: V, _ g: inout [String: M], _ h: [String: V]) {
        guard let hip = h["femur.\(s)"], let rHip = head["femur.\(s)"], let rKnee = head["shin.\(s)"],
              let rAnkle = head["foot.\(s)"] else { return }
        let thigh = rKnee - rHip, shin = rAnkle - rKnee
        let hinge = V(1, 0, 0)
        let solved = Self.bend(root: hip, target: ankle, upper: thigh.length, lower: shin.length, pole: pole)
        let n = pole.cross(solved.end - hip)
        let k = n.length > 1e-9 ? n.unit : hinge
        g["femur.\(s)"] = Self.frameMap(thigh, hinge, to: solved.joint - hip, k)
        g["shin.\(s)"] = Self.frameMap(shin, hinge, to: solved.end - solved.joint, k)
        g["foot.\(s)"] = foot
        g["toes.\(s)"] = foot
    }

    /// How high the ankle joint is above the floor when the foot stands flat.
    var ankleHeight: Double {
        guard let ankle = head["foot.r"], let toe = tail["toes.r"] else { return 0.075 }
        return ankle.z - (toe.z - 0.01)
    }
}

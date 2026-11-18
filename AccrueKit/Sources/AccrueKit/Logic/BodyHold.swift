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

// MARK: - Holding equipment that has no staging

/// A round-ended rod of the body's bulk, as thick as `ra` at `a` and `rb` at `b`.
struct BulkRod: Sendable {
    var a, b: Body3D.V
    var ra, rb: Double
}

extension Body3D {
    /// The legs, hips, trunk and head as a handful of rods, for keeping a bar out of them. The
    /// sizes are measured on the model's skin at rest; each rod is carried by its bone.
    /// A bar held in front of the body cannot get round behind it, so the trunk and head also
    /// reach a long way back (or forward, for a bar held `behind`): the bar can then only leave
    /// them to its own side, or over the top. `walls` false leaves that out, for something that
    /// hangs from one hand and may be anywhere round the body.
    func bulk(_ g: [String: M], _ h: [String: V], behind: Bool = false, walls: Bool = true) -> [BulkRod] {
        var rods: [BulkRod] = []
        func at(_ bone: String, _ rest: V) -> V? {
            guard let p = h[bone], let r = head[bone] else { return nil }
            return p + (g[bone] ?? .identity) * (rest - r)
        }
        let away = behind ? -0.5 : 0.5
        func shadow(_ bone: String, _ rest: V, _ radius: Double) {
            guard walls, let a = at(bone, rest), let b = at(bone, rest + V(0, away, 0)) else { return }
            rods.append(BulkRod(a: a, b: b, ra: radius, rb: radius))
        }
        /// A rod lying across the body at depth `y` and height `z`.
        func across(_ bone: String, y: Double, z: Double, half: Double, _ radius: Double) {
            guard let a = at(bone, V(-half, y, z)), let b = at(bone, V(half, y, z)) else { return }
            rods.append(BulkRod(a: a, b: b, ra: radius, rb: radius))
            shadow(bone, V(0, y, z), radius)
        }
        across("pelvis", y: 0.027, z: 0.885, half: 0.09, 0.128)   // hips and buttocks
        across("pelvis", y: -0.012, z: 0.955, half: 0.08, 0.108)  // lower belly
        across("lumbar", y: -0.008, z: 1.04, half: 0.08, 0.118)   // waist
        across("thorax", y: 0.0, z: 1.16, half: 0.09, 0.134)      // ribs
        across("thorax", y: 0.002, z: 1.27, half: 0.1, 0.138)     // chest
        if let r = h["humerus.r"], let l = h["humerus.l"] { rods.append(BulkRod(a: r, b: l, ra: 0.07, rb: 0.07)) }
        shadow("thorax", V(0, 0.027, 1.381), 0.07)
        if let a = at("neck", V(0, 0.03, 1.445)), let b = at("neck", V(0, 0.012, 1.53)) {
            rods.append(BulkRod(a: a, b: b, ra: 0.062, rb: 0.062))
        }
        shadow("neck", V(0, 0.02, 1.49), 0.062)
        shadow("head", V(0, -0.03, 1.5), 0.078)   // jaw
        shadow("head", V(0, -0.005, 1.59), 0.117) // skull
        if !walls {
            // The head is all wall above; without walls it is still there.
            for (rest, radius) in [(V(0, -0.03, 1.5), 0.078), (V(0, -0.005, 1.59), 0.117)] {
                if let p = at("head", rest) { rods.append(BulkRod(a: p, b: p, ra: radius, rb: radius)) }
            }
        }
        for s in ["r", "l"] {
            guard let hip = head["femur.\(s)"], let knee = head["shin.\(s)"], let ankle = head["foot.\(s)"] else { continue }
            // The thigh's bulk lies in front of the bone.
            let lead = V(0, -0.012, 0)
            if let a = at("femur.\(s)", hip + lead), let b = at("femur.\(s)", knee + lead) {
                rods.append(BulkRod(a: a, b: b, ra: 0.097, rb: 0.088))
            }
            if let a = at("shin.\(s)", knee), let b = at("shin.\(s)", ankle) {
                rods.append(BulkRod(a: a, b: b, ra: 0.07, rb: 0.042))
            }
            // Nor does a bar get round behind the legs, or under the thighs of someone sitting.
            for share in [0.0, 0.5, 1.0] { shadow("femur.\(s)", mix(hip, knee, share) + lead, 0.097 - 0.009 * share) }
            for share in [0.0, 0.5] { shadow("shin.\(s)", mix(knee, ankle, share), 0.07 - 0.028 * share) }
        }
        return rods
    }

    /// How far along each of two segments their closest points are (0 at `p`, 1 at `q`).
    static func nearest(_ p1: V, _ q1: V, _ p2: V, _ q2: V) -> (Double, Double) {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r)
        if a < 1e-12 && e < 1e-12 { return (0, 0) }
        if a < 1e-12 { return (0, clamp(f / e)) }
        let c = d1.dot(r)
        if e < 1e-12 { return (clamp(-c / a), 0) }
        let b = d1.dot(d2), denom = a * e - b * b
        var s = denom > 1e-12 ? clamp((b * f - c * e) / denom) : 0.5
        var t = (b * s + f) / e
        if t < 0 {
            t = 0
            s = clamp(-c / a)
        } else if t > 1 {
            t = 1
            s = clamp((b - c) / a)
        }
        return (s, t)
    }

    /// A move, square to the bar, that takes a bar centred at `centre` along `axis` out of the
    /// rods it is in by the nearest way, or nil when it is clear of them all. Where it is in
    /// several, the deepest counts most, and each counts for less as the bar leaves it, so the
    /// move never changes suddenly. A bar that runs right through the middle of a rod has no
    /// nearest way out, so it leaves toward `front`.
    static func wayOut(_ centre: V, axis: V, half: Double, radius: Double, of rods: [BulkRod], front: V) -> V? {
        var sum = V(0, 0, 0), weight = 0.0
        let p = centre - axis * half, q = centre + axis * half
        for rod in rods {
            let (s, t) = nearest(p, q, rod.a, rod.b)
            let gap = (p + (q - p) * s) - (rod.a + (rod.b - rod.a) * t)
            let room = rod.ra + (rod.rb - rod.ra) * t + radius
            guard gap.length < room else { continue }
            let along = gap.dot(axis)
            let square = gap - axis * along
            let need = max(0, room * room - along * along).squareRoot() - square.length
            guard need > 1e-5 else { continue }
            sum = sum + (square.length > 0.004 ? square.unit : front) * (need * need)
            weight += need
        }
        return weight > 0 ? sum * (1 / weight) : nil
    }
}

/// What the hands hold in one frame: the grip line in each hand, and the bar they share.
struct Held {
    var grips: [String: PropPlan.Grip] = [:]
    var bar: (mid: Body3D.V, axis: Body3D.V)?
}

/// How the hands hold an exercise's equipment when nothing stages it. A bar in both hands is
/// worked out from where the keyframes put the hands, kept out of the body and off the floor,
/// and both arms are then fitted to it; a thing in each hand has the fingers closed round it
/// where the keyframes put the hand.
struct Handhold: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    enum Rest: Sendable { case hips, floor }

    /// Which way the handles of a two-handed thing run.
    enum Handles: Sendable {
        /// Along the bar itself.
        case along
        /// Front to back at each end (a trap bar).
        case forward
        /// Up and down at each side (the rim of a plate).
        case upright
    }

    struct Bar: Sendable {
        /// What the fingers close round.
        var radius: Double
        /// Half of the length that has to stay out of the body.
        var length: Double
        /// How near the floor its centre may come: the plates' radius.
        var lowest: Double = 0
        /// A loaded bar stays level across the body; a stick may tilt with the hands.
        var level = true
        var handles = Handles.along
        /// The least and most the hands can be apart on it, as half distances.
        var narrow = 0.07
        var wide: Double
        /// Kept out of the body. A frame the body stands inside is not.
        var clear = true
        /// A bar with a place of its own, which the hands go to: across the hips, or rolling on
        /// the floor.
        var rest: Rest?
        /// Passed behind the body rather than in front when it has to give way.
        var behind = false
        /// Half the hands' distance apart, and which way round each hand is, for the whole loop.
        var half = 0.2
        var turn: [String: Double] = [:]
        /// How far the bar is moved off the hands' own line at each moment of the loop.
        var track: [V] = []
    }

    let body: Body3D
    let guide: HowToGuide
    let lift: Double
    /// The leg a cable is strapped to, for cable work that leaves the hands empty.
    var ankle: String?
    var bar: Bar?
    /// Every hand closes on a handle of its own.
    var each = false
    var grips: [String: HandGrip] = [:]
    var reach: [String: Double] = [:]

    static let sides: [(String, Double)] = [("r", 1.0), ("l", -1.0)]

    init(kinds: [PropKind], guide: HowToGuide, body: Body3D, lift: Double) {
        self.body = body
        self.guide = guide
        self.lift = lift
        var radius = 0.016, square = 0.0
        let poses = (0...24).map { Figure.interpolate(guide.keyframes, at: Double($0) / 24) }
        let loop = poses.map { placed($0) }
        // How far apart the keyframes ever put the hands.
        let apart = loop.compactMap { p -> Double? in
            guard let r = PropPlan.grip(p.g, p.h, "r"), let l = PropPlan.grip(p.g, p.h, "l") else { return nil }
            return (r.point - l.point).length
        }
        let widest = apart.max() ?? 0

        if kinds.contains(.cable), Builder.ankleCable(guide) {
            ankle = Builder.strapped { s in loop.compactMap { $0.h["foot.\(s)"] } }
        }
        var bar: Bar?
        for kind in kinds where bar == nil && !each {
            switch kind {
            case .barbell: bar = Bar(radius: 0.014, length: 1.0, lowest: 0.225, wide: 0.6)
            case .ezBar: bar = Bar(radius: 0.014, length: 0.65, lowest: 0.15, wide: 0.28)
            case .smith: bar = Bar(radius: 0.015, length: 0.85, lowest: 0.2, wide: 0.55)
            case .dowel: bar = Bar(radius: 0.012, length: 0.7, level: false, wide: 0.6)
            case .trapBar: bar = Bar(radius: 0.015, length: 0, lowest: 0.225, handles: .forward, narrow: 0.33, wide: 0.33, clear: false)
            case .pulldown: bar = Bar(radius: 0.014, length: 0.6, wide: 0.52)
            case .rower: bar = Bar(radius: 0.016, length: 0.28, wide: 0.2)
            case .abWheel: bar = Bar(radius: 0.012, length: 0.13, narrow: 0.085, wide: 0.1, clear: false, rest: .floor)
            case .cable where ankle != nil: break
            case .cable:
                if Builder.twoCables(guide) || Builder.rope(guide) { each = true } else { bar = Bar(radius: 0.014, length: 0.25, level: false, wide: 0.2) }
            case .plate:
                // One plate held by its rim, unless the hands part: then a plate in each.
                if widest < 0.7 {
                    bar = Bar(radius: 0.02, length: 0, handles: .upright, narrow: 0.21, wide: 0.21, clear: false)
                } else {
                    each = true
                    radius = 0.02
                }
            case .kettlebell:
                // Hands that stay together share one bell.
                if widest < 0.32 && widest > 0 {
                    bar = Bar(radius: 0.012, length: 0.11, narrow: 0.055, wide: 0.06)
                } else {
                    each = true
                    radius = 0.012
                }
            case .dumbbell, .suspension, .rings, .skiErg: each = true
            case .battleRope:
                each = true
                radius = 0.018
            case .band, .jumpRope:
                each = true
                radius = 0.012
            default: break
            }
        }
        if let b = bar {
            radius = b.radius
            square = b.handles == .along && b.wide > 0.3 ? 0.5 : 0
        }
        guard bar != nil || each else { return }
        for (s, _) in Self.sides {
            guard let grip = body.grip(s, radius: radius, square: square) else { continue }
            grips[s] = grip
            reach[s] = body.reach(s, grip, bend: 5)
        }
        guard var bar, grips.count == 2 else { return }
        bar.behind = guide.exerciseName.contains("behind") || carriedBehind(loop, bar)
        if guide.familyID == "hip-thrust-bridge", bar.lowest > 0 {
            bar.rest = .hips
            bar.clear = false
        }

        // The hands keep one distance apart and one way round on the bar through the whole loop.
        let lines = loop.compactMap { follow($0.g, $0.h, bar) }
        var halves: [Double] = [], turned = ["r": 0.0, "l": 0.0]
        for (p, line) in zip(loop, lines) {
            guard let r = centre("r", p.g, p.h), let l = centre("l", p.g, p.h) else { continue }
            halves.append((l - r).dot(line.axis) / 2)
            for (s, _) in Self.sides {
                guard let grip = grips[s], let hand = p.g["hand.\(s)"] else { continue }
                turned[s, default: 0] += (hand * grip.across).dot(line.axis) / Double(loop.count)
            }
        }
        halves.sort()
        bar.half = min(bar.wide, max(bar.narrow, halves.isEmpty ? 0.2 : halves[halves.count / 2]))
        for (s, m) in Self.sides {
            // Overhand unless the keyframes clearly turn the palm up.
            let t = turned[s] ?? 0
            bar.turn[s] = abs(t) > 0.25 ? (t > 0 ? 1 : -1) : -m
        }
        if bar.clear {
            let loops = guide.keyframes.first?.pose == guide.keyframes.last?.pose
            bar.track = track(loop, bar, loops: loops)
            // A bar the keyframes cannot hold behind the body is held in front after all.
            if bar.behind {
                var front = bar
                front.behind = false
                front.track = track(loop, front, loops: loops)
                func strain(_ b: Bar) -> Double {
                    let leaps = zip(b.track, b.track.dropFirst()).map { ($1 - $0).length }.max() ?? 0
                    return leaps + (b.track.map(\.length).max() ?? 0)
                }
                if strain(bar) > 0.4, strain(front) < strain(bar) { bar = front }
            }
        }
        self.bar = bar
    }

    /// The body for one pose, raised onto its equipment.
    func placed(_ pose: JointPose) -> (g: [String: M], h: [String: V], floor: Double?) {
        var p = body.posed(pose, contacts: guide.contacts)
        if lift != 0 { p.h = p.h.mapValues { $0 + V(0, 0, lift) } }
        return p
    }

    /// The middle of the handle a hand would close on, as the hand is posed.
    func centre(_ s: String, _ g: [String: M], _ h: [String: V]) -> V? {
        guard let grip = grips[s], let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"] else { return nil }
        return wrist + hand * grip.centre
    }

    /// The bar as it would lie if it simply followed the hands: its middle, its direction (to
    /// the body's left) and the way the chest faces, square to it.
    func follow(_ g: [String: M], _ h: [String: V], _ bar: Bar) -> (mid: V, axis: V, front: V)? {
        guard let r = centre("r", g, h), let l = centre("l", g, h) else { return nil }
        var mid = (r + l) * 0.5
        let between = l - r
        var axis = between.length > 0.08 ? between.unit : (g["thorax"] ?? .identity) * V(1, 0, 0)
        if bar.level {
            let flat = ["thorax", "pelvis"].map { ((g[$0] ?? .identity) * V(1, 0, 0)).flat }.first { $0.length > 0.3 }
            if let flat { axis = flat.unit } else if between.flat.length > 0.08 { axis = between.flat.unit }
        }
        switch bar.rest {
        case .hips: if let pelvis = h["pelvis"] { mid = pelvis + V(0, 0, 0.16) }
        case .floor: mid.z = 0.09
        case nil: break
        }
        var front = (g["thorax"] ?? .identity) * Body3D.forward * (bar.behind ? -1 : 1)
        front = front - axis * front.dot(axis)
        front = front.length > 1e-6 ? front.unit : axis.cross(V(0, 0, 1)).unit
        return (mid, axis, front)
    }

    /// The keyframes hold the bar behind the shoulders (a squat's bar on the back) whenever the
    /// hands are up at the shoulders or the head.
    func carriedBehind(_ loop: [(g: [String: M], h: [String: V], floor: Double?)], _ bar: Bar) -> Bool {
        var depths: [Double] = []
        for p in loop {
            guard let line = follow(p.g, p.h, bar), let r = p.h["humerus.r"], let l = p.h["humerus.l"] else { continue }
            let thorax = p.g["thorax"] ?? .identity
            let from = line.mid - (r + l) * 0.5
            if abs(from.dot(thorax * Body3D.up)) < 0.3 { depths.append(from.dot(thorax * Body3D.forward)) }
        }
        depths.sort()
        return !depths.isEmpty && depths[depths.count / 2] < -0.02
    }

    /// Where each hand closes on a bar centred at `mid`.
    func target(_ s: String, _ m: Double, mid: V, axis: V, _ bar: Bar) -> V { mid - axis * (m * bar.half) }

    /// `mid` moved out of the body and off the floor, and then back within both arms' reach.
    func settle(_ mid: V, axis: V, front: V, rods: [BulkRod], _ h: [String: V], _ bar: Bar, floor: Double?) -> V {
        var c = mid
        for _ in 0..<4 {
            let before = c
            if bar.clear {
                for _ in 0..<12 {
                    guard let move = Body3D.wayOut(c, axis: axis, half: bar.length, radius: bar.radius + 0.006, of: rods, front: front) else { break }
                    c = c + move
                }
            }
            if let floor, bar.lowest > 0 { c.z = max(c.z, floor + bar.lowest) }
            for _ in 0..<4 {
                var moved = false
                for (s, m) in Self.sides {
                    guard let shoulder = h["humerus.\(s)"], let length = reach[s] else { continue }
                    let d = target(s, m, mid: c, axis: axis, bar) - shoulder
                    if d.length > length {
                        c = c - d.unit * (d.length - length)
                        moved = true
                    }
                }
                if !moved { break }
            }
            if (c - before).length < 1e-5 { break }
        }
        return c
    }

    /// How far the bar has to move off the hands' line at each moment of the loop to stay out of
    /// the body. Worked out for the whole loop at once, so the bar keeps to one side of whatever
    /// it meets (it comes down onto the thighs and stays on top of them) and eases out and back
    /// instead of jumping.
    func track(_ loop: [(g: [String: M], h: [String: V], floor: Double?)], _ bar: Bar, loops: Bool) -> [V] {
        let n = loop.count
        let lines = loop.map { follow($0.g, $0.h, bar) }
        let rods = loop.map { body.bulk($0.g, $0.h, behind: bar.behind) }
        guard n > 1, lines.allSatisfy({ $0 != nil }) else { return [] }
        func settled(_ i: Int, _ d: V) -> V {
            let line = lines[i]!
            return settle(line.mid + d, axis: line.axis, front: line.front, rods: rods[i], loop[i].h, bar, floor: loop[i].floor) - line.mid
        }
        var d = [V](repeating: V(0, 0, 0), count: n)
        /// An offset eased a little toward `to`, never by so much that it could cross a limb.
        func eased(_ from: V, toward to: V, _ share: Double) -> V {
            let step = (to - from) * share
            return from + (step.length > 0.03 ? step.unit * 0.03 : step)
        }
        // Start where the bar is clear and furthest out on its own side, if it ever is clear,
        // and carry it on from there: it then meets the body from the side it was really on.
        func out(_ i: Int) -> Double {
            guard let hips = loop[i].h["pelvis"] else { return 0 }
            return (lines[i]!.mid - hips).dot(lines[i]!.front)
        }
        let clear = (0..<n).filter { i in
            Body3D.wayOut(lines[i]!.mid, axis: lines[i]!.axis, half: bar.length, radius: bar.radius + 0.006, of: rods[i],
                          front: lines[i]!.front) == nil
        }.max { out($0) < out($1) }
        let start = clear ?? 0
        if clear == nil {
            // Never clear: it starts on its own side of whatever it is in.
            let line = lines[start]!
            let far = (0...30).first {
                Body3D.wayOut(line.mid + line.front * (0.02 * Double($0)), axis: line.axis, half: bar.length, radius: bar.radius + 0.006,
                              of: rods[start], front: line.front) == nil
            }
            d[start] = line.front * (0.02 * Double(far ?? 2))
        }
        d[start] = settled(start, d[start])
        /// The bar carried from where it was at moment `j` to moment `i`, in steps short enough
        /// that hands moving fast drag it along the body and not through it.
        func carried(_ i: Int, from j: Int) -> V {
            let line = lines[i]!
            var c = lines[j]!.mid + d[j]
            let goal = line.mid + eased(d[j], toward: V(0, 0, 0), 0.15)
            let steps = max(1, Int(((goal - c).length / 0.03).rounded(.up)))
            let stride = (goal - c) * (1 / Double(steps))
            for _ in 0..<steps {
                c = settle(c + stride, axis: line.axis, front: line.front, rods: rods[i], loop[i].h, bar, floor: loop[i].floor)
            }
            return c - line.mid
        }
        if loops {
            // Round the loop once; its last moment is its first.
            let m = n - 1
            let first = start % m
            d[first] = d[start]
            for k in 1..<m {
                let i = (first + k) % m
                d[i] = carried(i, from: (i + m - 1) % m)
            }
            d[m] = d[0]
        } else {
            for i in stride(from: start + 1, to: n, by: 1) { d[i] = carried(i, from: i - 1) }
            for i in stride(from: start - 1, through: 0, by: -1) { d[i] = carried(i, from: i + 1) }
        }
        // Then let it spring back toward the hands wherever it can, evenly through the loop. It
        // goes a little at a time, so it slides along whatever it rests on and never through it.
        let stiff = 1.5
        for _ in 0..<60 {
            for i in 0..<n {
                var before = i > 0 ? d[i - 1] : nil, after = i < n - 1 ? d[i + 1] : nil
                if loops {
                    if i == 0 { before = d[n - 2] }
                    if i == n - 1 { after = d[1] }
                }
                let around = [before, after].compactMap { $0 }
                let pull = around.reduce(V(0, 0, 0), +) * (stiff / (1 + stiff * Double(around.count)))
                d[i] = settled(i, eased(d[i], toward: pull, 0.35))
            }
            if loops { d[n - 1] = d[0] }
        }
        return d
    }

    /// The body at one pose with its hands closed on what they hold. `t` is the moment of the
    /// loop the pose belongs to.
    func frame(_ pose: JointPose, at t: Double) -> (frame: BodyFrame, held: Held) {
        var (g, h, floor) = placed(pose)
        var held = Held()
        guard let root = h["pelvis"] else { return (body.made(g, h, floor: floor), held) }

        if let bar, let line = follow(g, h, bar) {
            var mid = line.mid
            if bar.rest == nil {
                var d = V(0, 0, 0)
                if bar.track.count > 1 {
                    let x = min(1, max(0, t)) * Double(bar.track.count - 1)
                    let i = min(bar.track.count - 2, Int(x))
                    d = mix(bar.track[i], bar.track[i + 1], x - Double(i))
                }
                mid = settle(mid + d, axis: line.axis, front: line.front, rods: body.bulk(g, h, behind: bar.behind), h, bar, floor: floor)
            }
            let up = V(0, 0, 1)
            let forward = line.axis.cross(up).unit
            var miss = V(0, 0, 0)
            for (s, m) in Self.sides {
                guard let grip = grips[s], let shoulder = h["humerus.\(s)"] else { continue }
                let point = target(s, m, mid: mid, axis: line.axis, bar)
                let across: V
                switch bar.handles {
                case .along: across = line.axis * (bar.turn[s] ?? -m)
                case .forward: across = forward * -1
                case .upright: across = line.axis.cross(line.front)
                }
                // The elbow keeps bending the way the keyframes turned it.
                let hinge = (g["humerus.\(s)"] ?? .identity) * body.hingeAxis(s)
                body.hold(s, grip, at: point, across: across, pole: (point - shoulder).cross(hinge), &g, h)
            }
            h = body.place(g, root: root)
            for (s, m) in Self.sides {
                guard let c = centre(s, g, h) else { continue }
                miss = miss + (c - target(s, m, mid: mid, axis: line.axis, bar)) * 0.5
            }
            // Arms that could not reach still have the bar in their hands.
            if bar.rest == nil { mid = mid + miss }
            held.bar = (mid, line.axis)
        } else if each {
            for (s, _) in Self.sides {
                guard let grip = grips[s], let hand = g["hand.\(s)"] else { continue }
                for (bone, turn) in grip.turns { g[bone] = hand * turn }
            }
            h = body.place(g, root: root)
        }
        for (s, _) in Self.sides {
            if let grip = grips[s], let c = centre(s, g, h), let hand = g["hand.\(s)"] {
                held.grips[s] = PropPlan.Grip(point: c, across: hand * grip.across, palm: hand * grip.palm, fingers: hand * grip.along)
            } else if let open = PropPlan.grip(g, h, s) {
                held.grips[s] = open
            }
        }
        return (body.made(g, h, floor: floor), held)
    }
}

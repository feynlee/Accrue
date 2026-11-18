import Foundation

/// A hand opened flat to press on the floor, a bench or a wall, worked out once from the rig:
/// the palm's own directions and how every finger bone turns to lie on the surface. All in the
/// hand's rest axes, so a posed hand is `hand rotation × turn`.
struct HandPress: Sendable {
    /// Along the hand from the wrist to the knuckles, across it from the thumb side to the
    /// little finger, and out of the palm.
    var along, across, palm: Body3D.V
    /// From the wrist to the middle knuckle.
    var knuckle: Body3D.V
    /// How far the wrist and the knuckles sit above the surface the palm lies on.
    var wristLift, knuckleLift: Double
    /// Each finger and thumb bone's turn from rest.
    var turns: [String: Body3D.M]
}

extension Body3D {
    /// The hand of side `s` laid flat, palm down, fingers straight and a little spread. `curl`
    /// bends the three bones of each finger further (degrees), for fingers that hang over the
    /// edge of a bench; `spread` opens the fingers wider than they rest.
    func flatHand(_ s: String, curl: [Double] = [0, 0, 0], spread: Double = 1) -> HandPress? {
        guard let wrist = head["hand.\(s)"], let k2 = head["f2a.\(s)"], let k3 = head["f3a.\(s)"],
              let k5 = head["f5a.\(s)"] else { return nil }
        let along = (k3 - wrist).unit
        let knuckles = (k5 - k2).unit
        let across = (knuckles - along * knuckles.dot(along)).unit
        var palm = across.cross(along).unit
        if palm.dot(Self.forward) < 0 { palm = palm * -1 }
        // The heel of the hand is thicker than the pad under the knuckles.
        let wristLift = 0.027, knuckleLift = 0.019
        let tilt = asin((wristLift - knuckleLift) / (k3 - wrist).length)
        /// How far `p` is above the surface when the palm lies on it.
        func height(_ p: V) -> Double {
            let d = p - wrist
            return wristLift - d.dot(palm) * cos(tilt) - d.dot(along) * sin(tilt)
        }
        // The surface's own directions, seen from the hand: along it and down into it.
        let level = (along * cos(tilt) - palm * sin(tilt)).unit
        let down = (palm * cos(tilt) + along * sin(tilt)).unit
        let deg = Double.pi / 180
        var turns: [String: M] = [:]

        /// Lays one finger out: each bone keeps its own heading across the surface and sinks
        /// until its pad touches. `pads` is how far each joint's middle sits from the skin.
        func lay(_ names: [String], pads: [Double], curl: [Double], spread: Double) {
            guard let p0 = head[names[0]], let p1 = head[names[1]], let p2 = head[names[2]],
                  let p3 = tail[names[2]] else { return }
            let pts = [p0, p1, p2, p3]
            var high = height(p0)
            var bent = 0.0
            for i in 0..<3 {
                let rest = pts[i + 1] - pts[i]
                var heading = rest - down * rest.dot(down)
                // Spread: the part of the heading across the hand, made larger.
                heading = heading + across * (heading.dot(across) * (spread - 1))
                heading = heading.length > 1e-6 ? heading.unit : level
                bent += curl[i] * deg
                let sink = max(-0.3, min(0.5, (high - pads[i]) / rest.length))
                let a = bent > 0.01 ? bent : asin(sink)
                let to = heading * cos(a) + down * sin(a)
                turns[names[i]] = Self.frameMap(rest, palm, to: to, down * cos(a) - heading * sin(a))
                high -= rest.length * sin(a)
            }
        }
        for f in 2...5 {
            lay(["a", "b", "c"].map { "f\(f)\($0).\(s)" }, pads: [0.012, 0.010, 0.008], curl: curl, spread: spread)
        }
        // The thumb lies on the surface beside the palm whatever the fingers do.
        lay(["a", "b", "c"].map { "f1\($0).\(s)" }, pads: [0.016, 0.013, 0.010], curl: [0, 0, 0], spread: 1)
        return HandPress(along: along, across: across, palm: palm, knuckle: k3 - wrist,
                         wristLift: wristLift, knuckleLift: knuckleLift, turns: turns)
    }

    /// The hand's rotation when it lies on a surface that faces `normal`, fingers toward `fingers`.
    func pressTurn(_ press: HandPress, fingers: V, normal: V) -> M {
        let n = normal.unit
        var f = fingers - n * fingers.dot(n)
        if f.length < 1e-6 { f = n.cross(abs(n.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0)) }
        f = f.unit
        // The knuckles sit lower than the wrist, so the hand's own line dips toward the surface.
        let tilt = asin((press.wristLift - press.knuckleLift) / press.knuckle.length)
        let line = f * cos(tilt) - n * sin(tilt)
        return Self.frameMap(press.along, press.palm, to: line, n * -1)
    }

    /// Where the wrist is when the middle knuckle rests over `point` of that surface.
    func pressWrist(_ press: HandPress, at point: V, fingers: V, normal: V) -> V {
        point + normal.unit * press.knuckleLift - pressTurn(press, fingers: fingers, normal: normal) * press.knuckle
    }

    /// Poses the arm of side `s` so its hand lies flat on a surface facing `normal`, the middle
    /// knuckle over `point` and the fingers toward `fingers`, with the elbow toward `pole`. The
    /// shoulder stays where the shoulder blade put it; the forearm turns as far as the hand needs.
    /// Returns the elbow bend in degrees.
    @discardableResult
    func press(_ s: String, _ press: HandPress, at point: V, fingers: V, normal: V = V(0, 0, 1), pole: V,
               _ g: inout [String: M], _ h: [String: V]) -> Double {
        let hand = pressTurn(press, fingers: fingers, normal: normal)
        let wrist = pressWrist(press, at: point, fingers: fingers, normal: normal)
        let bend = arm(s, wrist: wrist, hand: hand, pole: pole, &g, h)
        for (bone, turn) in press.turns { g[bone] = hand * turn }
        return bend
    }

    /// Poses the arm of side `s` so the wrist is at `wrist` and the hand is turned by `hand`,
    /// with the elbow toward `pole`. Returns the elbow bend in degrees.
    @discardableResult
    func arm(_ s: String, wrist target: V, hand: M, pole: V, _ g: inout [String: M], _ h: [String: V]) -> Double {
        let m = s == "r" ? 1.0 : -1.0
        guard let shoulder = h["humerus.\(s)"], let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"],
              let rRadius = head["radius.\(s)"], let rWrist = head["hand.\(s)"] else { return 0 }
        let upper = rElbow - rShoulder
        let hinge = hingeAxis(s), axis = pronationAxis(s)
        let toRadius = rRadius - rElbow, toWrist = rWrist - rRadius
        func forearm(_ pronation: Double) -> V { toRadius + M.axis(axis, -m * pronation) * toWrist }

        var pronation = 90.0
        var elbow = shoulder, wrist = target
        var ulna = M.identity
        var k = pole.cross(target - shoulder).unit
        for _ in 0..<6 {
            let v = forearm(pronation)
            let solved = Self.bend(root: shoulder, target: target, upper: upper.length, lower: v.length, pole: pole)
            elbow = solved.joint
            wrist = solved.end
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
        let a = (elbow - shoulder).unit, b = (wrist - elbow).unit
        return acos(min(1, max(-1, a.dot(b)))) * 180 / .pi
    }

    /// The straight-line distance from the shoulder to the wrist when the elbow is bent `degrees`.
    func armSpan(_ s: String, bend degrees: Double) -> Double {
        guard let rShoulder = head["humerus.\(s)"], let rElbow = head["ulna.\(s)"], let rWrist = head["hand.\(s)"] else { return 0.5 }
        return Self.span((rElbow - rShoulder).length, (rWrist - rElbow).length, bend: degrees)
    }

    /// The leg's length from hip to ankle when the knee is bent `degrees`.
    func legSpan(bend degrees: Double) -> Double {
        guard let hip = head["femur.r"], let knee = head["shin.r"], let ankle = head["foot.r"] else { return 0.75 }
        return Self.span((knee - hip).length, (ankle - knee).length, bend: degrees)
    }
}

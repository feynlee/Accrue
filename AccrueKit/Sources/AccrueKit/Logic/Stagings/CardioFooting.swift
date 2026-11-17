import Foundation

/// Feet that meet a surface. The keyframes are drawn for a figure whose feet go wherever its
/// joint angles put them, so a squat leaves the heels in the air and a landing comes down on
/// the toes. A foot that stands on something is laid flat on it here, or on its ball with the
/// toes flat when the keyframes point it well down, and a foot in flight is left as it is.
enum CardioFooting {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The most an ankle bends up, in degrees.
    static let dorsi = 32.0

    /// How far a foot turned by `foot` points its toes down, in degrees.
    static func pitch(_ foot: M) -> Double {
        let f = foot * V(0, -1, 0)
        return atan2(-f.z, V(f.x, f.y, 0).length) * 180 / .pi
    }

    /// The heel lift a standing foot keeps of the keyframes' `pitch`: pointed well down it is
    /// up on its ball, toes pulled well up stay up (a heel landing), and anything less is flat.
    static func planted(_ pitch: Double) -> Double {
        pitch < 0 ? pitch * CardioStagings.ease(-pitch, from: 8, to: 20) : pitch * CardioStagings.ease(pitch, from: 18, to: 34)
    }

    /// `g` with its feet made to stand. `air` is 0 for a foot on a surface and 1 for a foot in
    /// flight, by side. Where a flat foot would bend the ankle further than an ankle goes, the
    /// whole body rocks back about the feet to make up the rest.
    ///
    /// `bearing`, where given, is how much of the body's weight each foot has. Only a foot with
    /// weight on it rocks the body back; one that is only passing near the floor is levelled
    /// as far as its own ankle bends and no further.
    static func settle(_ g: [String: M], air: [String: Double], bearing: [String: Double]? = nil) -> [String: M] {
        var g = g
        var tilt = 0.0
        for s in ["r", "l"] {
            guard let shin = g["shin.\(s)"], let foot = g["foot.\(s)"] else { continue }
            let down = shin * V(0, 0, -1)
            let lean = atan2(down.y, -down.z) * 180 / .pi
            tilt = max(tilt, (bearing?[s] ?? 1 - (air[s] ?? 0)) * (lean - planted(pitch(foot)) - dorsi))
        }
        if tilt > 0 {
            let back = M.x(-tilt)
            g = g.mapValues { back * $0 }
        }
        for s in ["r", "l"] {
            guard let foot = g["foot.\(s)"] else { continue }
            let a = air[s] ?? 0
            let given = pitch(foot)
            let stood = planted(given)
            var p = stood + (given - stood) * a
            if let weight = bearing?[s], let shin = g["shin.\(s)"] {
                let down = shin * V(0, 0, -1)
                let least = min(given, atan2(down.y, -down.z) * 180 / .pi - dorsi)
                p += (1 - weight) * (max(p, least) - p)
            }
            let f = foot * V(0, -1, 0)
            let flat = V(f.x, f.y, 0).length > 1e-6 ? V(f.x, f.y, 0).unit : V(0, -1, 0)
            // The sole lies level on a surface; in flight it rolls with the leg.
            let up = mix(V(0, 0, 1), foot * V(0, 0, 1), a)
            func turned(_ pitch: Double) -> M {
                let r = pitch * .pi / 180
                return Body3D.frameMap(V(0, -1, 0), V(0, 0, 1), to: flat * cos(r) + V(0, 0, -1) * sin(r), up)
            }
            g["foot.\(s)"] = turned(p)
            // Under a raised heel the toes stay flat on the surface.
            g["toes.\(s)"] = turned(p > 0 ? p * a : p)
        }
        return g
    }

    /// Body3D bends the elbow toward the front of the chest, so as an arm swings up through
    /// level its elbow turns right over, and the forearm and hand jump. This turns the arm
    /// back once it is above level, which keeps the swing in one piece: overhead, the elbow
    /// then bends the way it was bending on the way up.
    static func steadyArms(_ body: Body3D, _ g: inout [String: M], _ pose: JointPose) {
        let legs = ["femur", "shin", "foot", "toes", "clavicle", "scapula"]
        for (s, side) in [("r", ""), ("l", "L")] {
            guard CardioStagings.angle(pose, "shoulderFlex" + side) > 90, abs(CardioStagings.angle(pose, "shoulderAbd" + side)) < 1,
                  let humerus = g["humerus.\(s)"], let top = body.head["humerus.\(s)"], let end = body.tail["humerus.\(s)"]
            else { continue }
            let over = M.axis(humerus * (end - top).unit, 180)
            for bone in g.keys where bone.hasSuffix("." + s) && !legs.contains(where: { bone.hasPrefix($0) }) {
                g[bone] = over * (g[bone] ?? .identity)
            }
        }
    }

    /// Where the pelvis is for a body that stands on a surface at height `floor` with the
    /// balls of its feet, taken together, over `ball`.
    static func root(_ body: Body3D, _ g: [String: M], ball: V, floor: Double) -> V {
        let rel = body.place(g, root: V(0, 0, 0))
        let mid = ((rel["toes.r"] ?? V(0, 0, 0)) + (rel["toes.l"] ?? V(0, 0, 0))) * 0.5
        return V(ball.x - mid.x, ball.y - mid.y, body.cardioStand(g, floor: floor))
    }
}

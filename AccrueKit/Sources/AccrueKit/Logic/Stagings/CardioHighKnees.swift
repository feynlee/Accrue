import Foundation

/// High knees and butt kicks, run on the spot. Whichever foot is lower stands flat on the
/// floor and stays where it is, and the hips ride over it; the other leg is the keyframes' own.
struct CardioHighKneesStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far a foot is off the floor before it is wholly the keyframes' again.
    static let clear = 0.08
    /// How nearly alike the knees are bent, in degrees, while the hips pass from one foot to
    /// the other.
    static let change = 4.0
    /// The most the body leans in from the ankle to keep the hips over the foot, degrees.
    static let lean = 12.0

    let body: Body3D
    let loop: CardioLoop
    /// Where the ball of the standing foot stays, front to back.
    let spot: Double
    /// The least and the most the knees bend in the loop.
    let knees: (low: Double, high: Double)
    /// How much more one knee is bent than the other at the top of its lift.
    let span: Double
    /// For a loop that has no landing of its own: each leg angle with the foot down, and at
    /// the top of the lift.
    let legs: [String: (down: Double, up: Double)]
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "high-knees-butt-kicks", guide.equipment == nil || guide.equipment == "none",
              let ball = body.head["toes.r"], let pelvis = body.head["pelvis"] else { return nil }
        // Only the plain runs: twists, taps, skips, squats and wall drills are other movements.
        let words = CardioStagings.words(guide)
        switch guide.subtypeID {
        case "high-knees": guard [["high", "knee", "run"], ["high", "knee", "sprints"]].contains(words) else { return nil }
        case "butt-kicks": guard words == ["butt", "kicks"] else { return nil }
        default: return nil
        }
        let loop = CardioLoop(guide)
        // The keyframes at which the right leg, and the left, is at the top of its lift.
        let frames = loop.closed
        let bends = frames.flatMap { [Self.knee($0.pose, ""), Self.knee($0.pose, "L")] }
        guard let low = bends.min(), let high = bends.max(),
              let right = frames.max(by: { Self.ahead($0.pose) < Self.ahead($1.pose) }),
              let left = frames.min(by: { Self.ahead($0.pose) < Self.ahead($1.pose) }),
              Self.ahead(right.pose) > 30, Self.ahead(left.pose) < -30 else { return nil }
        self.body = body
        self.loop = loop
        spot = ball.y - pelvis.y
        knees = (low, high)
        span = min(Self.ahead(right.pose), -Self.ahead(left.pose))
        // Two keyframes, one leg up in each, and nothing between: halfway from one to the
        // other both knees would be half bent and the body would drop into a squat. Each leg
        // instead stands as it does in the other leg's keyframe until its own turn to lift.
        var legs: [String: (down: Double, up: Double)] = [:]
        if !frames.contains(where: { abs(Self.ahead($0.pose)) < 10 }) {
            for name in ["hipFlex", "kneeFlex", "ankleDorsi"] {
                legs[name] = (CardioStagings.angle(left.pose, name), CardioStagings.angle(right.pose, name))
                legs[name + "L"] = (CardioStagings.angle(right.pose, name + "L"), CardioStagings.angle(left.pose, name + "L"))
            }
        }
        self.legs = legs
    }

    static func knee(_ pose: JointPose, _ side: String) -> Double { CardioStagings.angle(pose, "kneeFlex" + side) }

    /// How much more the right knee is bent than the left.
    static func ahead(_ pose: JointPose) -> Double { knee(pose, "") - knee(pose, "L") }

    /// The pose of the loop that `pose` belongs to, with each leg's lift kept to its own half
    /// of the loop where the keyframes have no landing, and the pose's mistake on it. With it,
    /// how much of the body's weight each foot has: the leg whose knee is less bent stands.
    func legwork(_ pose: JointPose) -> (pose: JointPose, stands: [String: Double]) {
        let found = loop.find(pose)
        var good = Figure.smooth(loop.closed, at: found.t)
        let left = CardioStagings.ease(Self.ahead(good), from: -Self.change, to: Self.change)
        let stands = ["r": 1 - left, "l": left]
        // How far through its lift each leg is.
        var lift: [String: Double] = [:]
        if legs.isEmpty {
            for side in ["", "L"] { lift[side] = CardioStagings.ease(Self.knee(good, side), from: knees.low, to: knees.high) }
        } else {
            let share = Self.ahead(good) / span
            lift = ["": CardioStagings.ease(share, from: 0, to: 1), "L": CardioStagings.ease(-share, from: 0, to: 1)]
            for (key, leg) in legs {
                good.angles[key] = leg.down + (lift[key.hasSuffix("L") ? "L" : ""] ?? 0) * (leg.up - leg.down)
            }
        }
        guard var fault = found.fault else { return (good, stands) }
        // A mistake of the hips or knees is one of the lifted leg: the leg that stands keeps
        // standing under the hips.
        for (key, value) in fault.angles where key.hasPrefix("hip") || key.hasPrefix("knee") {
            fault.angles[key] = value * (lift[key.hasSuffix("L") ? "L" : ""] ?? 0)
        }
        return (CardioStagings.applying(fault, to: good), stands)
    }

    /// The body standing on the foot that has its weight, with the whole of it leant `tilt`
    /// degrees forward from the ankle, and where the hips then are.
    func stand(_ pose: JointPose, on stands: [String: Double], tilt: Double) -> (g: [String: M], root: V) {
        var g = body.rotations(pose)
        if tilt != 0 { g = g.mapValues { M.x(tilt) * $0 } }
        /// Each foot's lowest point, with the hips at the origin.
        func lows(_ g: [String: M]) -> [String: Double] {
            let rel = body.place(g, root: V(0, 0, 0))
            var low: [String: Double] = [:]
            for (s, word) in [("r", "right"), ("l", "left")] {
                let points = body.contactPoints(word + " feet", g, rel) + body.contactPoints(word + " toes", g, rel)
                low[s] = points.map { $0.0.z - $0.1 }.min() ?? 0
            }
            return low
        }
        func standing(_ low: [String: Double]) -> Double { low.reduce(0.0) { $0 + (stands[$1.key] ?? 0) * $1.value } }
        // The foot that stands is flat; the other comes level as it nears the floor.
        var low = lows(g)
        var floor = standing(low)
        var air: [String: Double] = [:]
        for (s, z) in low { air[s] = (1 - (stands[s] ?? 0)) * CardioStagings.ease(z - floor, from: 0, to: Self.clear) }
        g = CardioFooting.settle(g, air: air, bearing: stands)
        low = lows(g)
        floor = standing(low)
        // The hips go over the standing foot, so it does not slide. The feet change over as
        // they pass each other at the floor, where both are in the same place under the hips.
        let rel = body.place(g, root: V(0, 0, 0))
        var y = 0.0
        for s in ["r", "l"] {
            guard let ball = rel["toes.\(s)"] else { continue }
            y += (stands[s] ?? 0) * (spot - ball.y)
        }
        // The standing foot is on the floor, and the other is never under it.
        return (g, V(0, y, -min(floor, low.values.min() ?? floor)))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (pose, stands) = legwork(pose)
        var out = stand(pose, on: stands, tilt: 0)
        if out.root.y > 0 {
            // Landing with the hips and knees bent would sit the hips back behind the heel.
            // The knees go forward over the toes instead, as far as brings the hips back over
            // the foot.
            var from = 0.0, to = Self.lean
            for _ in 0..<12 {
                let mid = (from + to) / 2
                if stand(pose, on: stands, tilt: mid).root.y > 0 { from = mid } else { to = mid }
            }
            out = stand(pose, on: stands, tilt: (from + to) / 2)
        }
        return (body.made(out.g, body.place(out.g, root: out.root), floor: 0), [])
    }
}

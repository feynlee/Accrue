import Foundation

/// Standing with a bar, dumbbells or kettlebells: deadlift, row, curl, raise, overhead press, clean, snatch, carry.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum FreeWeightStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        switch guide.familyID {
        case "deadlift":
            if let floor = FreeWeightDeadliftStaging(guide, body) { return floor }
            return FreeWeightHingeStaging(guide, body)
        case "row": return FreeWeightRowStaging(guide, body)
        case "overhead-press": return FreeWeightPressStaging(guide, body)
        case "kettlebell-swing": return FreeWeightSwingStaging(guide, body)
        default: return nil
        }
    }
}

// MARK: - What is lifted

/// The weight a standing lifter holds in both hands in front of the body: one bar, or a
/// dumbbell in each hand with its handle across the body like a bar's.
enum FreeWeightTool: Sendable, Equatable {
    case barbell, dumbbells

    typealias V = Body3D.V

    var kinds: [PropKind] { self == .barbell ? [.barbell] : [.dumbbell] }
    /// What the fingers close round.
    var gripRadius: Double { self == .barbell ? LegWeights.barRadius : LegWeights.dumbbellGrip }
    /// How thick the part is that passes the legs and the trunk: the bar itself, or a dumbbell's heads.
    var bulk: Double { self == .barbell ? LegWeights.barRadius : 0.06 }
    /// How near the floor its middle line can come: the radius of a plate, or of a dumbbell's head.
    var lowest: Double { self == .barbell ? LegWeights.plateRadius : 0.06 }

    /// Half of the length that has to stay out of the body, for hands `half` from the middle.
    func extent(_ half: Double) -> Double { self == .barbell ? 1.0 : half + 0.135 }

    /// The pieces, the bar first, for a middle at `mid` and hands `half` either side of it.
    func props(_ mid: V, half: Double) -> [PropPiece] {
        switch self {
        case .barbell: return LegWeights.barbell(mid)
        case .dumbbells: return [-1.0, 1.0].flatMap { LegWeights.dumbbell(mid + V($0 * half, 0, 0), along: V(1, 0, 0)) }
        }
    }
}

// MARK: - The clean movement, to tell a mistake from it

/// How far one joint angle of the keyframes has gone between its least and its most.
struct FreeWeightRange: Sendable {
    let key: String
    let low, high: Double

    init(_ keys: [Keyframe], _ key: String) {
        let values = keys.map { $0.pose.angles[key] ?? 0 }
        self.key = key
        low = values.min() ?? 0
        high = max(values.max() ?? 1, low + 1)
    }

    func callAsFunction(_ pose: JointPose) -> Double {
        min(1, max(0, ((pose.angles[key] ?? 0) - low) / (high - low)))
    }
}

/// The loop as the keyframes play it when nothing goes wrong. A staging works the arms out
/// itself, so a mistake that swings them ("the bar drifts forward") has to be read off the
/// pose: it is how far an angle is from where the clean loop has it at the same moment, and
/// the moment is found from the angles the mistake leaves alone.
struct FreeWeightCourse: Sendable {
    let samples: [JointPose]
    let drivers: [String]

    init(_ keys: [Keyframe], drivers: [String]) {
        samples = (0...48).map { Figure.smooth(keys, at: Double($0) / 48) }
        self.drivers = drivers
    }

    /// How many degrees `key` is off the clean loop, beyond a `slack` that the spacing of the
    /// samples could account for.
    func off(_ key: String, _ pose: JointPose, slack: Double = 3) -> Double {
        var best = Double.infinity, clean = pose.angles[key] ?? 0
        for sample in samples {
            let d = drivers.reduce(0.0) { sum, k in
                let x = (pose.angles[k] ?? 0) - (sample.angles[k] ?? 0)
                return sum + x * x
            }
            if d < best {
                best = d
                clean = sample.angles[key] ?? 0
            }
        }
        let off = (pose.angles[key] ?? 0) - clean
        return off > slack ? off - slack : off < -slack ? off + slack : 0
    }
}

// MARK: - The body above the hips

/// The posed body above the hip joints with its pelvis at the origin, as little as fitting it
/// to a bar needs: the hip joints, the point between the shoulders, the arms' reach in the
/// plane the body bends in, and the bulk of the hips, trunk and head. Leaning the trunk
/// further turns all of it about the pelvis, so one posed body serves for every lean tried.
struct FreeWeightTrunk: Sendable {
    typealias V = Body3D.V

    var hips: [String: V]
    var mid: V
    var reach: Double
    var rods: [BulkRod]

    func leaning(_ degrees: Double) -> FreeWeightTrunk {
        guard degrees != 0 else { return self }
        let turn = Body3D.M.x(degrees)
        return FreeWeightTrunk(hips: hips.mapValues { turn * $0 }, mid: turn * mid, reach: reach,
                               rods: rods.map { BulkRod(a: turn * $0.a, b: turn * $0.b, ra: $0.ra, rb: $0.rb) })
    }
}

// MARK: - The lifter

/// A lifter on two planted feet with both hands on one weight: the feet, the closed hands and
/// the handful of measurements every standing lift needs.
struct FreeWeightLifter: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    static let sides: [(String, Double)] = [("r", 1.0), ("l", -1.0)]
    /// The weight counts as touching the body when its skin is this near.
    static let touch = 0.004

    let body: Body3D
    let tool: FreeWeightTool
    let feet: [LegFootprint]
    /// How far outward the knees point, in degrees: the feet's own turn.
    let kneeTurn: Double
    let grips: [String: HandGrip]
    /// Half the hands' distance apart.
    let half: Double
    /// From the shoulder to the middle of the handle with the arm long.
    let arm: Double
    /// The lengths of the thigh and the shin.
    let thigh: Double, shin: Double
    /// The bulk of a leg as Body3D.bulk has it at rest: the thigh's rod and the shin's.
    let thighBulk: BulkRod, shinBulk: BulkRod

    /// Feet `stance` either side of the middle with the toes turned out by `turnout` degrees,
    /// hands `grip` either side of the middle of the weight.
    init?(_ body: Body3D, _ tool: FreeWeightTool, stance: Double, turnout: Double, grip: Double) {
        let square = tool == .barbell ? 0.5 : 0
        guard let r = body.grip("r", radius: tool.gripRadius, square: square),
              let l = body.grip("l", radius: tool.gripRadius, square: square),
              let right = body.footprint("r", x: -stance, y: 0, turnout: turnout),
              let left = body.footprint("l", x: stance, y: 0, turnout: turnout),
              let hip = body.head["femur.r"], let knee = body.head["shin.r"], let ankle = body.head["foot.r"] else { return nil }
        // The right leg's two rods are the ones that start nearest its hip and its knee.
        let atRest = body.bulk([:], body.head, walls: false).filter { ($0.a - $0.b).length > 0.3 && $0.a.x < -0.03 && $0.b.x < -0.03 }
        guard let upper = atRest.min(by: { ($0.a - hip).length < ($1.a - hip).length }),
              let lower = atRest.min(by: { ($0.a - knee).length < ($1.a - knee).length }) else { return nil }
        thigh = (knee - hip).length
        shin = (ankle - knee).length
        thighBulk = BulkRod(a: upper.a - hip, b: upper.b - knee, ra: upper.ra, rb: upper.rb)
        shinBulk = BulkRod(a: lower.a - knee, b: lower.b - ankle, ra: lower.ra, rb: lower.rb)
        self.body = body
        self.tool = tool
        feet = [right, left]
        kneeTurn = turnout
        grips = ["r": r, "l": l]
        half = grip
        arm = (body.reach("r", r, bend: 5) + body.reach("l", l, bend: 5)) / 2
    }

    /// The middle of the feet, where a standing body keeps its weight: a little in front of the ankles.
    var middle: Double { feet.map { $0.ankle.y - 0.055 * abs($0.toe.y) }.reduce(0, +) / Double(feet.count) }

    /// The point between the shoulders, and how far the weight is from it with the arms long,
    /// measured in the plane the body bends in (the hands are wider or narrower than the shoulders).
    func shoulders(_ h: [String: V]) -> (mid: V, reach: Double) {
        guard let r = h["humerus.r"], let l = h["humerus.l"] else { return (V(0, 0, 1.4), arm) }
        let aside = half - (l - r).length / 2
        return ((r + l) * 0.5, max(0.04, arm * arm - aside * aside).squareRoot())
    }

    /// Both legs fitted between the hips, with the pelvis at `root`, and the planted feet.
    func legs(_ g: inout [String: M], root: V) -> [String: V] {
        let h = body.place(g, root: root)
        let a = kneeTurn * .pi / 180
        for f in feet {
            let m = f.side == "r" ? 1.0 : -1.0
            body.plant(f.side, ankle: f.ankle, foot: f.turn, pole: V(-m * sin(a), -cos(a), 0), &g, h)
        }
        return body.place(g, root: root)
    }

    /// The body above the hips as `g` poses it.
    func trunk(_ g: [String: M]) -> FreeWeightTrunk {
        let rel = body.place(g, root: V(0, 0, 0))
        let (mid, reach) = shoulders(rel)
        // Body3D.bulk's rods without the legs, which start at the hip joints and the knees.
        let starts = Self.sides.flatMap { s, _ in [rel["femur.\(s)"], rel["shin.\(s)"]].compactMap { $0 } }
        let rods = body.bulk(g, rel, walls: false).filter { rod in !starts.contains { ($0 - rod.a).length < 0.02 } }
        var hips: [String: V] = [:]
        for (s, _) in Self.sides { hips[s] = rel["femur.\(s)"] }
        return FreeWeightTrunk(hips: hips, mid: mid, reach: reach, rods: rods)
    }

    /// The highest the pelvis can be at depth `y` with both feet still flat.
    func ceiling(_ trunk: FreeWeightTrunk, y: Double) -> Double {
        let leg = Body3D.span(thigh, shin, bend: 3)
        var most = Double.infinity
        for f in feet {
            guard let hip = trunk.hips[f.side] else { continue }
            let dx = hip.x - f.ankle.x, dy = y + hip.y - f.ankle.y
            most = min(most, f.ankle.z + max(0, leg * leg - dx * dx - dy * dy).squareRoot() - hip.z)
        }
        return most
    }

    /// The knee of each leg that reaches from the planted foot to a pelvis at `root`.
    func knees(_ trunk: FreeWeightTrunk, root: V) -> [(hip: V, knee: V, ankle: V, front: V)] {
        let a = kneeTurn * .pi / 180
        return feet.compactMap { f in
            guard let rel = trunk.hips[f.side] else { return nil }
            let m = f.side == "r" ? 1.0 : -1.0
            let hip = root + rel, pole = V(-m * sin(a), -cos(a), 0)
            let solved = Body3D.bend(root: hip, target: f.ankle, upper: thigh, lower: shin, pole: pole)
            let along = (solved.joint - hip).unit
            return (hip, solved.joint, solved.end, (pole - along * pole.dot(along)).unit)
        }
    }

    /// How far the knees are bent, in degrees, with the pelvis at `root`.
    func knee(_ trunk: FreeWeightTrunk, root: V) -> Double {
        var most = 0.0
        for f in feet {
            guard let rel = trunk.hips[f.side] else { continue }
            let far = (f.ankle - root - rel).length
            let c = (far * far - thigh * thigh - shin * shin) / (2 * thigh * shin)
            most = max(most, acos(min(1, max(-1, c))) * 180 / .pi)
        }
        return most
    }

    /// The room between the weight at `mid` and a body whose pelvis is at `root`: its trunk as
    /// given, its legs reaching to the planted feet.
    func room(_ mid: V, _ trunk: FreeWeightTrunk, root: V) -> Double {
        var rods = trunk.rods.map { BulkRod(a: $0.a + root, b: $0.b + root, ra: $0.ra, rb: $0.rb) }
        // The thigh's bulk lies a little in front of the bone.
        let lead = thighBulk.a.length
        for leg in knees(trunk, root: root) {
            rods.append(BulkRod(a: leg.hip + leg.front * lead, b: leg.knee + leg.front * lead, ra: thighBulk.ra, rb: thighBulk.rb))
            rods.append(BulkRod(a: leg.knee, b: leg.ankle, ra: shinBulk.ra, rb: shinBulk.rb))
        }
        return room(mid, rods)
    }

    /// The legs, hips, trunk and head of the posed body, as the rods a weight must stay out of.
    func rods(_ g: [String: M], _ h: [String: V]) -> [BulkRod] { body.bulk(g, h, walls: false) }

    /// How much room there is between the weight, its middle at `mid`, and the nearest of
    /// `rods`: less than nothing when it is inside one.
    func room(_ mid: V, _ rods: [BulkRod]) -> Double {
        let reach = tool.extent(half)
        let p = mid - V(reach, 0, 0), q = mid + V(reach, 0, 0)
        var least = Double.infinity
        for rod in rods {
            let (s, t) = Body3D.nearest(p, q, rod.a, rod.b)
            let apart = (mix(p, q, s) - mix(rod.a, rod.b, t)).length
            least = min(least, apart - (rod.ra + (rod.rb - rod.ra) * t) - tool.bulk)
        }
        return least
    }

    /// Where the weight hangs from long arms: straight down from the shoulders, or drawn in
    /// against the legs when they are within `back` degrees behind that, and never inside the
    /// body. `swing` degrees further forward is for a mistake that lets it drift.
    func hang(_ g: [String: M], _ h: [String: V], back: Double, swing: Double = 0) -> V {
        let (mid, reach) = shoulders(h)
        let rods = rods(g, h)
        func at(_ angle: Double) -> V {
            let a = angle * .pi / 180
            return V(0, mid.y + reach * sin(a), mid.z - reach * cos(a))
        }
        func free(_ angle: Double) -> Bool { room(at(angle), rods) > Self.touch }
        // Carried round from well out in front until it meets the body.
        var angle = -70.0
        while angle < back, free(angle + 2) { angle += 2 }
        if angle < back {
            var clear = angle, met = min(back, angle + 2)
            if free(met) { clear = met } else {
                for _ in 0..<10 {
                    let between = (clear + met) / 2
                    if free(between) { clear = between } else { met = between }
                }
            }
            angle = clear
        }
        return at(min(angle, back) - swing)
    }

    /// Closes both hands on the weight, its middle at `mid`: overhand, or with the palms turned
    /// up. `pole` is the way the elbows point, for the right arm's side `m` = 1 and the left's -1.
    func close(_ g: inout [String: M], _ h: [String: V], on mid: V, palmsUp: Bool = false, pole: (Double) -> V) {
        for (s, m) in Self.sides {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: mid + V(-m * half, 0, 0), across: V(palmsUp ? m : -m, 0, 0), pole: pole(m), &g, h)
        }
    }
}

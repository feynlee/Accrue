import Foundation

/// Carrying a load at a walk: farmers walk, suitcase carry, overhead carries and a goblet carry.
/// The load is placed first: a weight at the side hangs straight down from its shoulder, moved
/// out just far enough to clear the leg that swings past it, and a weight overhead stands over
/// its shoulder on a long arm. The arms are then fitted to it with the hands closed, and the
/// legs walk on the spot with the lower foot on the floor.
struct CarryStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// What one hand carries. `bar` is a loaded bar held at its middle, lying front to back.
    enum Tool: Sendable, Equatable { case dumbbell, kettlebell, bar }
    /// Where one arm is: long at the side with a weight, locked out overhead with one, or empty.
    enum Arm: Sendable, Equatable { case side, overhead, free }
    enum Load: Sendable, Equatable {
        /// A weight for each hand that has one. Only the left hand is ever empty: the catalog
        /// puts a single weight in the right. `bottomsUp` stands a kettlebell on its handle.
        case hands(Tool, r: Arm, l: Arm, bottomsUp: Bool)
        /// One frame the body stands inside, a handle at each side.
        case trapBar
        /// One bar across both hands overhead.
        case barbellOverhead
        /// One kettlebell held by its horns at the chest.
        case goblet
    }

    static let sides: [(String, Double)] = [("r", 1.0), ("l", -1.0)]
    /// The clear air kept between a hanging weight and the leg it passes.
    static let air = 0.015
    /// Half the distance between a trap bar's handles, and between the hands on a bar overhead.
    static let trapHalf = 0.33, barHalf = 0.33
    /// From a kettlebell's handle to the middle of its ball, and the ball's radius.
    static let toBall = 0.145, ball = 0.1

    let body: Body3D
    let loop: CardioLoop
    let load: Load
    let grips: [String: HandGrip]
    /// From each shoulder to the handle with the arm long.
    let reach: [String: Double]
    /// How far outside its shoulder a weight at the side hangs, so that it clears the thigh
    /// through the whole stride without moving in and out with it.
    let out: Double
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    /// The carry an exercise is, when every word of its name is one this staging can show.
    static func load(_ guide: HowToGuide) -> Load? {
        let words = CardioStagings.words(guide)
        let tool: Tool?
        switch guide.equipment {
        case "dumbbell": tool = .dumbbell
        case "kettlebell": tool = .kettlebell
        case "barbell": tool = .bar
        default: tool = nil
        }
        let walk: Set<String> = ["farmers", "farmer", "walk", "carry"]
        func only(_ known: Set<String>) -> Bool { words.isSubset(of: known.union(walk)) }
        switch guide.subtypeID {
        case nil:
            if guide.equipment == "trap-bar" { return words.contains("trap") && only(["trap", "bar"]) ? .trapBar : nil }
            guard let tool, !words.isDisjoint(with: ["farmers", "farmer"]),
                  only(["dumbbell", "kettlebell", "barbell", "strongman"]) else { return nil }
            return .hands(tool, r: .side, l: .side, bottomsUp: false)
        case "suitcase":
            guard let tool, only(["dumbbell", "kettlebell", "barbell", "suitcase", "unilateral"]) else { return nil }
            return .hands(tool, r: .side, l: .free, bottomsUp: false)
        case "overhead":
            guard let tool, only(["dumbbell", "kettlebell", "barbell", "overhead", "high", "low", "single", "arm", "bottoms", "up"])
            else { return nil }
            if tool == .bar { return words == ["barbell", "overhead", "carry"] ? .barbellOverhead : nil }
            // One weight overhead and the other at the side.
            if words.contains("high") { return words.contains("low") ? .hands(tool, r: .overhead, l: .side, bottomsUp: false) : nil }
            guard words.contains("overhead") else { return nil }
            let up = words.contains("bottoms")
            guard !up || tool == .kettlebell else { return nil }
            return .hands(tool, r: .overhead, l: words.contains("single") ? .free : .overhead, bottomsUp: up)
        case "front":
            return guide.equipment == "kettlebell" && words == ["kettlebell", "goblet", "carry"] ? .goblet : nil
        default:
            return nil
        }
    }

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "loaded-carry", let load = Self.load(guide) else { return nil }
        self.body = body
        self.load = load
        loop = CardioLoop(guide)

        let radius: Double, square: Double
        switch load {
        case .hands(.dumbbell, _, _, _): (radius, square, kinds) = (LegWeights.dumbbellGrip, 0, [.dumbbell])
        case .hands(.kettlebell, _, _, _): (radius, square, kinds) = (0.012, 0, [.kettlebell])
        case .hands(.bar, _, _, _): (radius, square, kinds) = (LegWeights.barRadius, 0, [.barbell])
        case .trapBar: (radius, square, kinds) = (0.015, 0, [.trapBar])
        case .barbellOverhead: (radius, square, kinds) = (LegWeights.barRadius, 0.5, [.barbell])
        case .goblet: (radius, square, kinds) = (LegLoad.hornRadius, 0, [.kettlebell])
        }
        if load == .goblet {
            guard let grips = LegLoad.goblet(kettlebell: true).grips(body) else { return nil }
            self.grips = grips
        } else {
            guard let r = body.grip("r", radius: radius, square: square), let l = body.grip("l", radius: radius, square: square)
            else { return nil }
            grips = ["r": r, "l": l]
        }
        var reach: [String: Double] = [:]
        for (s, _) in Self.sides { reach[s] = grips[s].map { body.reach(s, $0, bend: 4) } ?? 0.6 }
        self.reach = reach

        // The widest any moment of the stride needs, for both sides alike.
        var out = 0.0
        if case .hands(let tool, let r, let l, _) = load, r == .side || l == .side {
            for i in 0..<24 {
                let pose = Figure.smooth(loop.closed, at: Double(i) / 24)
                let g = body.rotations(pose)
                let h = body.place(g, root: V(0, 0, body.cardioStand(g)))
                let rods = body.bulk(g, h, walls: false)
                // Two loaded bars side by side: their plates must not meet in the middle.
                if tool == .bar, r == l, let right = h["humerus.r"], let left = h["humerus.l"] {
                    out = max(out, LegWeights.plateRadius + 0.02 - (left - right).length / 2)
                }
                for (s, m) in Self.sides where (s == "r" ? r : l) == .side {
                    out = max(out, Self.clearance(tool, shoulder: h["humerus.\(s)"], m, reach: reach[s] ?? 0.6, swing: 0, rods))
                }
            }
        }
        self.out = out
    }

    // MARK: A weight at the side

    /// The handle of a weight hanging from `shoulder` on a long arm, `off` outside it and
    /// swung `swing` degrees forward.
    static func hanging(_ shoulder: V, _ m: Double, off: Double, reach: Double, swing: Double) -> V {
        let drop = max(0.04, reach * reach - off * off).squareRoot()
        let a = swing * .pi / 180
        return shoulder + V(-m * off, -sin(a) * drop, -cos(a) * drop)
    }

    /// The room between the body's `rods` and a weight whose handle is at `p`, lying front to
    /// back: less than nothing when it is inside one. The closed fist counts with the handle.
    static func room(_ tool: Tool, at p: V, _ rods: [BulkRod]) -> Double {
        let along = V(0, 1, 0)
        let parts: [(a: V, b: V, radius: Double)]
        switch tool {
        case .dumbbell: parts = [(p - along * 0.135, p + along * 0.135, 0.06)]
        case .kettlebell: parts = [(p - along * 0.06, p + along * 0.06, 0.045), (p - V(0, 0, toBall), p - V(0, 0, toBall), ball)]
        case .bar: parts = [(p - along * 0.7, p + along * 0.7, 0.045)]
        }
        var least = Double.infinity
        for part in parts {
            for rod in rods {
                let (s, t) = Body3D.nearest(part.a, part.b, rod.a, rod.b)
                let apart = (mix(part.a, part.b, s) - mix(rod.a, rod.b, t)).length
                least = min(least, apart - (rod.ra + (rod.rb - rod.ra) * t) - part.radius)
            }
        }
        return least
    }

    /// How far outside its shoulder a weight at the side has to hang to be clear of the body.
    static func clearance(_ tool: Tool, shoulder: V?, _ m: Double, reach: Double, swing: Double, _ rods: [BulkRod]) -> Double {
        guard let shoulder else { return 0 }
        var off = 0.0
        while off < 0.3, room(tool, at: hanging(shoulder, m, off: off, reach: reach, swing: swing), rods) < air { off += 0.005 }
        return off
    }

    // MARK: The pieces

    /// The frame of a trap bar, its middle at `mid`: the size and finish of the plain plan's.
    static func trapBar(_ mid: V) -> [PropPiece] {
        let side = V(1, 0, 0), fwd = V(0, -1, 0)
        var p: [PropPiece] = []
        for s in [-1.0, 1.0] {
            let c = mid + side * (s * trapHalf)
            p.append(Plan.rod(c - fwd * 0.3, c + fwd * 0.3, 0.015, .metal))
            p.append(Plan.rod(c, c + side * (s * 0.45), 0.015, .metal))
            p.append(Plan.disc(c + side * (s * 0.4), axis: side, radius: 0.225, thickness: 0.07, .plate))
        }
        for s in [-1.0, 1.0] {
            p.append(Plan.rod(mid + fwd * (s * 0.3) - side * trapHalf, mid + fwd * (s * 0.3) + side * trapHalf, 0.015, .metal))
        }
        return p
    }

    /// One hand's weight with its handle at `p`, lying along `across`, its bell toward `toward`.
    static func weight(_ tool: Tool, at p: V, across: V, toward: V) -> [PropPiece] {
        switch tool {
        case .dumbbell: return LegWeights.dumbbell(p, along: across)
        case .kettlebell: return Plan.kettlebell(handle: p, across: across, half: 0.06, toward: toward)
        case .bar: return LegWeights.barbell(p, along: across)
        }
    }

    // MARK: The frame

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        var pose = Figure.smooth(loop.closed, at: found.t)
        if let fault = found.fault { pose = CardioStagings.applying(fault, to: pose) }
        func angle(_ key: String) -> Double { CardioStagings.angle(pose, key) }

        // The catalog shows leaning as both legs swung to one side under an upright trunk.
        // Legs that walk on a floor stay under the hips, so the trunk is bent over them instead.
        let lean = (angle("hipAbd") - angle("hipAbdL")) / 2
        if abs(lean) > 0.01 {
            pose.angles["hipAbd"] = angle("hipAbd") - lean
            pose.angles["hipAbdL"] = angle("hipAbdL") + lean
            pose.angles["trunkSide"] = (pose.angles["trunkSide"] ?? 0) - lean
        }
        var arms: (r: Arm, l: Arm) = (.side, .side)
        if case .hands(_, let r, let l, _) = load { arms = (r, l) }
        if arms.l == .free {
            // The empty arm hangs and swings a little with the opposite leg, as in walking.
            pose.angles.merge(["shoulderFlexL": 0.3 * angle("hipFlex") - 3, "shoulderAbdL": 6, "elbowFlexL": 12]) { $1 }
        }
        if load == .goblet { LegLoad.goblet(kettlebell: true).ready(&pose) }
        // What a mistake does to the arms: they drift this far forward of where they belong.
        let drift = (r: angle("shoulderFlex") - CardioStagings.angle(loop.closed[0].pose, "shoulderFlex"),
                     l: angle("shoulderFlexL") - CardioStagings.angle(loop.closed[0].pose, "shoulderFlexL"))

        var g = body.rotations(pose)
        let root = V(0, 0, body.cardioStand(g))
        var h = body.place(g, root: root)
        var props: [PropPiece] = []

        switch load {
        case .hands(let tool, _, _, let bottomsUp):
            let rods = found.fault == nil ? [] : body.bulk(g, h, walls: false)
            for (s, m) in Self.sides {
                let arm = s == "r" ? arms.r : arms.l
                guard arm != .free, let grip = grips[s], let shoulder = h["humerus.\(s)"], let reach = reach[s] else { continue }
                let swing = max(-30, min(30, s == "r" ? drift.r : drift.l))
                if arm == .side {
                    // A mistake can move the body into the weight: then it gives way further.
                    var off = out
                    if found.fault != nil { off = max(off, Self.clearance(tool, shoulder: shoulder, m, reach: reach, swing: swing, rods)) }
                    let point = Self.hanging(shoulder, m, off: off, reach: reach, swing: swing)
                    body.hold(s, grip, at: point, across: V(0, 1, 0), pole: V(-m * 0.3, 1, 0), &g, h)
                    props += Self.weight(tool, at: point, across: V(0, 1, 0), toward: V(0, 0, -1))
                } else {
                    // Straight up from the shoulder, palm forward, the elbow locked.
                    let a = swing * .pi / 180
                    let up = V(0, -sin(a), cos(a))
                    let point = shoulder + up * reach
                    body.hold(s, grip, at: point, across: V(-m, 0, 0), pole: V(-m, -0.3, 0), &g, h)
                    // A kettlebell lies over the back of the wrist; bottoms up it stands on its handle.
                    let toward = bottomsUp ? up : V(0, 0.8, -0.6)
                    props += Self.weight(tool, at: point, across: V(1, 0, 0), toward: toward)
                }
            }
        case .trapBar, .barbellOverhead:
            guard let r = h["humerus.r"], let l = h["humerus.l"] else { break }
            let overhead = load == .barbellOverhead
            let half = overhead ? Self.barHalf : Self.trapHalf
            let aside = half - (l - r).length / 2
            let arm = ((reach["r"] ?? 0.6) + (reach["l"] ?? 0.6)) / 2
            let far = max(0.04, arm * arm - aside * aside).squareRoot()
            // The frame of a trap bar has the legs inside it, so it swings very little.
            let swing = max(-5, min(overhead ? 30 : 5, (drift.r + drift.l) / 2)) * .pi / 180
            let way = overhead ? V(0, -sin(swing), cos(swing)) : V(0, -sin(swing), -cos(swing))
            let mid = (r + l) * 0.5 + way * far
            for (s, m) in Self.sides {
                guard let grip = grips[s] else { continue }
                let point = V(mid.x - m * half, mid.y, mid.z)
                if overhead {
                    body.hold(s, grip, at: point, across: V(-m, 0, 0), pole: V(-m, -0.3, 0), &g, h)
                } else {
                    body.hold(s, grip, at: point, across: V(0, 1, 0), pole: V(-m * 0.3, 1, 0), &g, h)
                }
            }
            props = overhead ? LegWeights.barbell(mid) : Self.trapBar(mid)
        case .goblet:
            let hold = LegLoad.goblet(kettlebell: true)
            let at = hold.load(g, body.place(g, root: V(0, 0, 0))).map { root + $0.at }
            props = hold.props(hold.take(body, grips, at: at, &g, h))
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), props)
    }
}

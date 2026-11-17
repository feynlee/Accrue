import Foundation

/// A bench press with a barbell or dumbbells: lying on a flat, inclined or declined bench (or
/// on the floor) with the feet planted, the weight travelling from straight arms over the
/// shoulders down to the chest.
struct BenchPressStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan
    typealias Skin = BenchStagings.Skin

    enum Load: Sendable, Equatable { case barbell, ezBar, dumbbells }

    static let barRadius = 0.014
    /// How close the elbow joint may come to the floor: the thickness of the arm behind it.
    static let elbowRoom = 0.045
    /// A plate's radius, which keeps the bar that far off the floor.
    static let plate = 0.225

    let body: Body3D
    let travel: BenchStagings.Travel
    let flare: BenchStagings.Expected
    let hipFlex: Double
    let grips: [String: HandGrip]
    /// A loosely curled hand, for the arm that rests while the other presses.
    let idle: HandGrip?
    let recline: BenchStagings.Recline
    let load: Load
    let halfGrip: Double
    /// Palms turned toward the face; palms turned toward each other; turning from one to the
    /// other on the way up; the dumbbells pressed together all the way.
    let reverse, neutral, twist, squeeze: Bool
    /// Only the right arm presses.
    let oneArm: Bool
    /// The height on the chest (standing, at rest) where the bar comes down.
    let touch: Double
    /// The share of the way down to the chest the weight may go before the elbows meet the floor.
    private(set) var depth = 1.0
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard guide.familyID == "bench-press", let first = guide.keyframes.first?.pose else { return nil }
        switch guide.subtypeID {
        case nil, "close", "incline", "decline", "floor": break
        default: return nil
        }
        // Presses that are not this picture: on a ball or a chair, one arm after the other, in
        // a machine, or stopped short on boards or pins.
        guard !has("ball", "chair", "bridge", "side lying", "sprinter", "catch", "alternat", "jm", "pin", "board",
                   "knees at 90", "smith") else { return nil }
        switch guide.equipment {
        case "barbell": load = .barbell
        case "ez-bar": load = .ezBar
        case "dumbbell": load = .dumbbells
        default: return nil
        }
        oneArm = has("one arm", "single arm")
        if oneArm && load != .dumbbells { return nil }
        let onFloor = guide.subtypeID == "floor"
        let radius = load == .dumbbells ? BenchStagings.dumbbellHandle : Self.barRadius
        guard let r = body.grip("r", radius: radius, square: load == .dumbbells ? 0 : 0.5),
              let l = body.grip("l", radius: radius, square: load == .dumbbells ? 0 : 0.5),
              let shoulder = body.head["humerus.l"] else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        idle = body.grip("l", radius: BenchStagings.openHand)
        travel = BenchStagings.Travel("elbowFlex", guide.keyframes)
        flare = BenchStagings.Expected("shoulderAbd", guide.keyframes, along: travel)
        hipFlex = first.angles["hipFlex"] ?? 0
        recline = BenchStagings.Recline(body, lying: first, onFloor: onFloor, knees: onFloor ? 95 : 85,
                                        legsOut: has("larsen"))
        reverse = has("reverse")
        squeeze = has("squeeze") || load == .dumbbells && has("close")
        twist = has("twist", "rotational")
        neutral = squeeze || has("hammer", "neutral", "palm-in", "palms in", "palm in")
        halfGrip = shoulder.x * (has("wide") ? 2.2 : has("close") ? 1.1 : 1.75)
        touch = has("guillotine") ? 1.38 : recline.kind == .incline ? 1.33 : recline.kind == .decline ? 1.21 : 1.25
        var kinds: [PropKind] = [load == .barbell ? .barbell : load == .ezBar ? .ezBar : .dumbbell]
        if !onFloor { kinds.append(.bench) }
        self.kinds = kinds

        if onFloor, let deep = guide.keyframes.max(by: { travel($0.pose) < travel($1.pose) })?.pose {
            depth = reachable(deep, within: 1)
        }
        var pieces = recline.bench()
        if load == .barbell, !onFloor, let hand = solve(first, depth: depth).holds.first?.at {
            // The rack stands behind the bar's highest place, its hooks just under the bar there.
            pieces += BenchStagings.rack(y: hand.y + 0.15, height: hand.z - 0.05,
                                         from: recline.point(recline.headFoot).y)
        }
        fixed = pieces
    }

    /// The body for one pose, where each hand holds its weight (right then left) and along
    /// which line, and how low the lower elbow is.
    func solve(_ pose: JointPose, depth: Double) -> (frame: BodyFrame, holds: [(at: V, across: V)], elbow: Double) {
        let u = travel(pose)
        // Hips pushed straighter than the keyframes have them lift off the pad.
        let rise = max(0, min(1, (hipFlex - (pose.angles["hipFlex"] ?? hipFlex)) / 25))
        var (g, h) = recline.settle(pose, lift: 11 * rise)
        let root = h["pelvis"] ?? V(0, 0, 0)
        recline.plant(&g, h)
        let thorax = g["thorax"] ?? .identity
        // Elbows further out than the keyframes have them bring the weight toward the neck.
        let wide = max(0, min(1, (flare.excess(pose, at: u) - 8) / 22))
        let feetward = thorax * V(0, 0, -1), outOfChest = thorax * V(0, -1, 0)
        var holds: [(at: V, across: V)] = []
        if let rs = h["humerus.r"], let ls = h["humerus.l"], let chest = h["thorax"], let rChest = body.head["thorax"] {
            /// The point `clear` off the chest at the height where the weight comes down, or `low` below it.
            func onChest(_ clear: Double, low: Double = 0) -> V {
                let up = touch - low + (1.37 - touch) * wide
                return chest + thorax * (V(0, -(Skin.front(up) + clear), up) - rChest)
            }
            switch load {
            case .barbell, .ezBar:
                // Arms straight: the bar over the shoulders.
                let mid = (rs + ls) * 0.5
                let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: 8) } }.reduce(0, +) / 2
                let aside = halfGrip - abs(rs.x - ls.x) / 2
                let top = V(0, mid.y, mid.z + max(0.01, reach * reach - aside * aside).squareRoot())
                // The bottom: the bar just on the chest, its plates clear of the floor.
                var low = onChest(Self.barRadius + 0.006)
                low = V(0, low.y, max(low.z, Self.plate + 0.01))
                let bar = mix(top, mix(top, low, depth), u)
                for m in [1.0, -1.0] {
                    holds.append((bar + V(-m * halfGrip, 0, 0), V(reverse ? m : -m, 0, 0)))
                }
            case .dumbbells:
                for (s, m, shoulder) in [("r", 1.0, rs), ("l", -1.0, ls)] {
                    let reach = grips[s].map { body.reach(s, $0, bend: 8) } ?? 0.6
                    // Arms straight: the dumbbells side by side over the shoulders.
                    let near = squeeze ? BenchStagings.dumbbellHead + 0.002 : neutral ? 0.075 : 0.155
                    let aside = abs(shoulder.x) - near
                    let top = V(-m * near, shoulder.y, shoulder.z + max(0.01, reach * reach - aside * aside).squareRoot())
                    // The bottom: beside the chest, the elbows under the wrists.
                    let far = abs(shoulder.x) + (neutral || twist ? 0.09 : 0.16) + 0.06 * wide
                    var low = V(-m * far, shoulder.y, shoulder.z) + outOfChest * 0.15
                        + feetward * ((neutral || twist ? 0.17 : 0.15) * (1 - wide))
                    if squeeze {
                        let centre = onChest(BenchStagings.dumbbellHead + 0.01, low: 0.06)
                        low = V(-m * near, centre.y, centre.z)
                    }
                    let level = V(reverse ? m : -m, 0, 0)
                    let across = neutral ? feetward : twist ? (level * (1 - u) + feetward * u).unit : level
                    holds.append((mix(top, mix(top, low, depth), u), across))
                }
            }
        }
        for (i, (s, m)) in [("r", 1.0), ("l", -1.0)].enumerated() where i < holds.count {
            guard let grip = grips[s] else { continue }
            if oneArm, s == "l" {
                if let idle { BenchStagings.rest(body, idle, &g, h) }
                continue
            }
            body.hold(s, grip, at: holds[i].at, across: holds[i].across,
                      pole: thorax * V(-m * (0.6 + 0.8 * wide), 1, -0.5 * (1 - wide)), &g, h)
        }
        if oneArm { holds.removeLast(max(0, holds.count - 1)) }
        h = body.place(g, root: root)
        let elbow = ["r", "l"].compactMap { h["ulna.\($0)"]?.z }.min() ?? 1
        return (body.made(g, h, floor: 0), holds, elbow)
    }

    /// The share of the way down the weight can go in this pose with the elbows off the floor.
    func reachable(_ pose: JointPose, within depth: Double) -> Double {
        guard solve(pose, depth: depth).elbow < Self.elbowRoom else { return depth }
        var short = 0.0, long = depth
        for _ in 0..<12 {
            let mid = (short + long) / 2
            if solve(pose, depth: mid).elbow < Self.elbowRoom { long = mid } else { short = mid }
        }
        return short
    }

    /// The pose as it is shown: on the floor, a mistake that drops the elbows stops higher.
    func shown(_ pose: JointPose) -> (frame: BodyFrame, holds: [(at: V, across: V)], elbow: Double) {
        let whole = solve(pose, depth: depth)
        guard recline.kind == .floor, whole.elbow < Self.elbowRoom - 0.002 else { return whole }
        return solve(pose, depth: reachable(pose, within: depth))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, holds, _) = shown(pose)
        var p: [PropPiece] = []
        switch load {
        case .barbell:
            if holds.count == 2 { p += BenchStagings.barbell((holds[0].at + holds[1].at) * 0.5) }
        case .ezBar:
            if holds.count == 2 { p += BenchStagings.barbell((holds[0].at + holds[1].at) * 0.5, length: 1.3, plate: 0.15) }
        case .dumbbells:
            for hold in holds { p += BenchStagings.dumbbell(hold.at, axis: hold.across) }
        }
        return (frame, p)
    }
}

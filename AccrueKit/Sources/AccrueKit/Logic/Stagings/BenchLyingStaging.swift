import Foundation

/// Lying on a bench (or the floor) with the feet planted while the arms do the work: the
/// dumbbell fly, the pullover and the lying triceps extension. The shoulders stay where the
/// keyframes' shoulder blades put them; the weight travels on an arc about them, or about the
/// elbows for the extension.
struct BenchLyingStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan
    typealias Skin = BenchStagings.Skin

    enum Move: Sendable { case fly, pullover, triceps }
    /// `single` is one dumbbell held by both hands, as a pullover has it.
    enum Load: Sendable, Equatable { case barbell, ezBar, dumbbells, single }
    typealias Hold = (at: V, across: V, pole: V)

    static let barRadius = 0.014
    static let elbowRoom = 0.045
    /// The room a hand closed on a bar needs between the bar and the head.
    static let handRoom = 0.1

    let body: Body3D
    let move: Move
    let load: Load
    let travel: BenchStagings.Travel
    /// The shoulder angle the keyframes mean, to see a mistake that swings the arms too far.
    let swing: BenchStagings.Expected
    let grips: [String: HandGrip]
    /// Open hands, for the arm that rests and for the hands that clasp one dumbbell.
    let open: [String: HandGrip]
    let recline: BenchStagings.Recline
    let halfGrip: Double
    let reverse: Bool
    /// Only the right arm works.
    let oneArm: Bool
    /// The elbow bend the arms keep when the keyframes do not say (a bent-arm pullover).
    let bend: Double?
    /// The share of the way a fly may open before the elbows meet the floor.
    private(set) var depth = 1.0
    /// How far an extension may fold the elbows before the bar meets the head.
    private(set) var fold = 150.0
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard let first = guide.keyframes.first?.pose else { return nil }
        // Not this picture: on a ball, one arm after the other, or two movements joined.
        guard !has("ball", "alternate", "knees at 90", "one leg", "band", "chair") else { return nil }
        let key: String
        switch (guide.familyID, guide.subtypeID) {
        case ("chest-fly", nil), ("chest-fly", "floor"):
            guard guide.equipment == "dumbbell",
                  !has("around the world", "maltese", "low fly", "hyght", "twist", "chain") else { return nil }
            move = .fly
            load = .dumbbells
            key = "shoulderAbd"
        case ("pullover", nil):
            guard !has("to press", "front raise", "around", "one arm") else { return nil }
            switch guide.equipment {
            case "barbell": load = .barbell
            case "ez-bar": load = .ezBar
            case "dumbbell": load = .single
            default: return nil
            }
            move = .pullover
            key = "shoulderFlex"
        case ("triceps-extension", "lying"):
            guard !has("across face", "pullover", "california", "to skull", "face press", "single", "one arm") else { return nil }
            switch guide.equipment {
            case "barbell": load = .barbell
            case "ez-bar": load = .ezBar
            case "dumbbell": load = .dumbbells
            default: return nil
            }
            move = .triceps
            key = "elbowFlex"
        default: return nil
        }
        oneArm = has("one arm", "single arm")
        let radius = load == .dumbbells ? BenchStagings.dumbbellHandle : Self.barRadius
        guard let r = body.grip("r", radius: radius, square: load == .dumbbells ? 0 : 0.5),
              let l = body.grip("l", radius: radius, square: load == .dumbbells ? 0 : 0.5),
              let openR = body.grip("r", radius: BenchStagings.openHand),
              let openL = body.grip("l", radius: BenchStagings.openHand),
              let shoulder = body.head["humerus.l"] else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        open = ["r": openR, "l": openL]
        travel = BenchStagings.Travel(key, guide.keyframes)
        swing = BenchStagings.Expected("shoulderFlex", guide.keyframes, along: travel)
        let onFloor = has("floor")
        recline = BenchStagings.Recline(body, lying: first, onFloor: onFloor, knees: onFloor ? 95 : 85,
                                        lean: has("incline") ? 30 : has("decline") ? -15 : 0)
        reverse = has("reverse", "supinated")
        bend = move == .pullover && has("bent") ? 55 : nil
        // A pullover and an extension take the bar about shoulder width; an EZ bar a little closer.
        halfGrip = shoulder.x * (has("wide") ? 1.7 : has("close") || load == .ezBar ? 0.7 : 1.0)
        var kinds: [PropKind] = [load == .barbell ? .barbell : load == .ezBar ? .ezBar : .dumbbell]
        if !onFloor { kinds.append(.bench) }
        self.kinds = kinds
        fixed = recline.bench()

        let far = guide.keyframes.max(by: { travel($0.pose) < travel($1.pose) })?.pose ?? first
        if move == .fly, onFloor { depth = reachable(far, within: 1) }
        if move == .triceps {
            // Fold the elbows only as far as leaves the bar clear of the head, or the dumbbells
            // clear of the pad beside it.
            var loose = 30.0, tight = 150.0
            for _ in 0..<12 {
                let mid = (loose + tight) / 2
                var deep = far
                deep.angles["elbowFlex"] = mid
                fold = mid
                if solve(deep, depth: 1).clear < 0 { tight = mid } else { loose = mid }
            }
            fold = loose
        }
    }

    /// The body for one pose; where the weight is held (right hand then left, or the top of
    /// the one dumbbell both hands clasp) and along which line; how low the lower elbow is; and
    /// the room left between a bar and the head, or between dumbbells and the pad.
    /// `limit` folds an extension's elbows less than `fold` allows, for a pose that needs it.
    func solve(_ pose: JointPose, depth: Double, fold limit: Double? = nil)
        -> (frame: BodyFrame, holds: [Hold], elbow: Double, clear: Double) {
        var (g, h) = recline.settle(pose)
        let root = h["pelvis"] ?? V(0, 0, 0)
        recline.plant(&g, h)
        let thorax = g["thorax"] ?? .identity
        // Along the body and out of the chest, as the pad lies.
        let feetward = recline.along * -1, outOfChest = recline.normal, headward = recline.along
        let u = travel(pose) * depth
        let elbowFlex = bend ?? pose.angles["elbowFlex"] ?? 20
        var holds: [Hold] = []
        guard let rs = h["humerus.r"], let ls = h["humerus.l"] else { return (body.made(g, h, floor: 0), [], 1, 1) }
        let mid = (rs + ls) * 0.5, wide = abs(rs.x - ls.x) / 2

        switch move {
        case .fly:
            // The arms swing out from straight up to level with the shoulders, the elbows a
            // little bent. A mistake that drops the arms further carries on down.
            let deeper = max(0, min(1, -swing.excess(pose, at: travel(pose)) / 25))
            for (s, m, shoulder) in [("r", 1.0, rs), ("l", -1.0, ls)] {
                guard let grip = grips[s] else { continue }
                let reach = body.reach(s, grip, bend: elbowFlex)
                let near = BenchStagings.dumbbellHead + 0.006
                let start = asin(max(-1, min(1, (near - abs(shoulder.x)) / reach)))
                let end = (84 + 16 * deeper) * .pi / 180
                let angle = start + (end - start) * u
                var at = shoulder + (V(-m, 0, 0) * sin(angle) + V(0, 0, 1) * cos(angle)) * reach + feetward * (0.04 * sin(angle))
                at.z = max(at.z, BenchStagings.dumbbellHead + 0.01)
                holds.append((at, feetward, thorax * V(-m * 0.7, 1, -0.2)))
            }
        case .pullover:
            // The arms swing from over the chest back past the head, about the shoulders.
            let angle = max(-15, min(105, (pose.angles["shoulderFlex"] ?? 85) - 90)) * .pi / 180
            let toward = outOfChest * cos(angle) + headward * sin(angle)
            if load == .single {
                // Both palms clasp the rim of the dumbbell's upper head; the rest hangs below.
                let arm = ["r", "l"].compactMap { body.benchArm($0, bend: elbowFlex) }.reduce(0, +) / 2 + 0.06
                let aside = wide - (BenchStagings.dumbbellHead + 0.012)
                var top = mid + toward * max(0.05, arm * arm - aside * aside).squareRoot()
                top = V(0, top.y, max(top.z, 0.2 + 0.035 + 0.01))
                holds.append((top, V(0, 0, 1), toward))
            } else {
                let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: elbowFlex) } }.reduce(0, +) / 2
                let aside = halfGrip - wide
                var bar = mid + toward * max(0.05, reach * reach - aside * aside).squareRoot()
                bar = V(0, bar.y, max(bar.z, (load == .barbell ? 0.225 : 0.15) + 0.01))
                for m in [1.0, -1.0] {
                    holds.append((bar + V(-m * halfGrip, 0, 0), V(reverse ? m : -m, 0, 0), thorax * V(-m, -0.3, -0.3)))
                }
            }
        case .triceps:
            // The upper arms stay put, leaning a little toward the head; only the elbows fold.
            let lean = max(0, min(50, (pose.angles["shoulderFlex"] ?? 105) - 90)) * .pi / 180
            let flex = min(limit ?? fold, max(0, pose.angles["elbowFlex"] ?? 0)) * .pi / 180
            let upperWay = outOfChest * cos(lean) + headward * sin(lean)
            let foreWay = outOfChest * cos(lean + flex) + headward * sin(lean + flex)
            var points: [V] = []
            for (s, m, shoulder) in [("r", 1.0, rs), ("l", -1.0, ls)] {
                guard let grip = grips[s], let upper = body.benchUpperArm(s) else { continue }
                let elbow = shoulder + upperWay * upper
                let fore = body.reach(s, grip, bend: 0) - upper
                if load == .dumbbells {
                    // Palms facing each other: the handle turns with the forearm.
                    let across = feetward * cos(flex) + outOfChest * sin(flex)
                    var at = elbow + foreWay * fore
                    at.z = max(at.z, BenchStagings.dumbbellHead + 0.01)
                    holds.append((at, across, elbow - shoulder))
                } else {
                    let aside = abs(shoulder.x) - halfGrip
                    points.append(elbow + foreWay * max(0.05, fore * fore - aside * aside).squareRoot())
                    holds.append((V(-m * halfGrip, 0, 0), V(reverse ? m : -m, 0, 0), elbow - shoulder))
                }
            }
            if load != .dumbbells, points.count == 2 {
                var bar = (points[0] + points[1]) * 0.5
                bar = V(0, bar.y, max(bar.z, (load == .barbell ? 0.225 : 0.15) + 0.01))
                for i in 0..<2 { holds[i].at = bar + holds[i].at }
            }
        }

        if load == .single, let top = holds.first {
            clasp(top.at, fingers: top.pole, &g, h)
        } else {
            // An extension's elbows must stay where they were put, so the hands are moved until
            // the arms that reach them bend at those elbows.
            var shift = V(0, 0, 0)
            for round in 0..<(move == .triceps ? 4 : 1) {
                var miss = V(0, 0, 0)
                for (i, s) in ["r", "l"].enumerated() where i < holds.count {
                    guard let grip = grips[s] else { continue }
                    if oneArm, s == "l" {
                        if round == 0, let idle = open["l"] { BenchStagings.rest(body, idle, &g, h) }
                        continue
                    }
                    body.hold(s, grip, at: holds[i].at + shift, across: holds[i].across, pole: holds[i].pole, &g, h)
                    if move == .triceps, let shoulder = h["humerus.\(s)"], let turn = g["humerus.\(s)"],
                       let rShoulder = body.head["humerus.\(s)"], let rElbow = body.head["ulna.\(s)"] {
                        miss = miss + (shoulder + holds[i].pole) - (shoulder + turn * (rElbow - rShoulder))
                    }
                }
                shift = shift + V(0, miss.y, miss.z) * (oneArm ? 1 : 0.5)
            }
            for i in holds.indices { holds[i].at = holds[i].at + shift }
            if oneArm { holds.removeLast(max(0, holds.count - 1)) }
        }
        h = body.place(g, root: root)
        let elbow = ["r", "l"].compactMap { h["ulna.\($0)"]?.z }.min() ?? 1
        var clear = 1.0
        if load == .dumbbells {
            // The lowest point of a dumbbell's heads over the pad.
            for hold in holds {
                let tip = abs(hold.across.unit.dot(recline.normal))
                let low = recline.height(hold.at) - 0.135 * tip - BenchStagings.dumbbellHead * (1 - tip * tip).squareRoot()
                clear = min(clear, low - 0.02)
            }
        } else if holds.count == 2, let neck = h["neck"], let base = h["head"], let rest = body.head["head"], let turn = g["head"] {
            let bar = (holds[0].at + holds[1].at) * 0.5
            let head = PullUpStaging.face.map { neck + turn * V(0, -$0.0, $0.1) }
                + (Skin.skull + [(0.02, Skin.crown)]).map { base + turn * (V(0, $0.0, $0.1) - rest) }
            // How near the bar's line passes to the face and the skull, less the room the hands need.
            clear = (head.map { p in ((p.y - bar.y) * (p.y - bar.y) + (p.z - bar.z) * (p.z - bar.z)).squareRoot() }.min() ?? 1)
                - Self.barRadius - Self.handRoom
        }
        return (body.made(g, h, floor: 0), holds, elbow, clear)
    }

    /// Both open hands pressed to the rim of a dumbbell's head centred on `top`, one each
    /// side, the fingers lying along `fingers` (the way the arms point).
    func clasp(_ top: V, fingers: V, _ g: inout [String: M], _ h: [String: V]) {
        let thorax = g["thorax"] ?? .identity
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = open[s] else { continue }
            let out = V(-m, 0, 0)
            let palm = top + out * (BenchStagings.dumbbellHead + 0.014)
            let hand = Body3D.frameMap(grip.along, grip.palm, to: fingers, out * -1)
            body.benchLay(s, wrist: palm + out * 0.012 - fingers.unit * 0.065, hand: hand, turns: grip.turns,
                          pole: thorax * V(-m, -0.3, -0.3), &g, h)
        }
    }

    /// The share of the way a fly can open in this pose with the elbows off the floor.
    func reachable(_ pose: JointPose, within depth: Double) -> Double {
        guard solve(pose, depth: depth).elbow < Self.elbowRoom else { return depth }
        var short = 0.0, long = depth
        for _ in 0..<12 {
            let mid = (short + long) / 2
            if solve(pose, depth: mid).elbow < Self.elbowRoom { long = mid } else { short = mid }
        }
        return short
    }

    /// The pose as it is shown: on the floor, a mistake that drops the elbows stops higher, and
    /// an extension whose elbows have drifted folds no further than the head or the pad allows.
    func shown(_ pose: JointPose) -> (frame: BodyFrame, holds: [Hold], elbow: Double, clear: Double) {
        let whole = solve(pose, depth: depth)
        if move == .triceps, whole.clear < -0.002 {
            var loose = 0.0, tight = fold
            for _ in 0..<10 {
                let mid = (loose + tight) / 2
                if solve(pose, depth: depth, fold: mid).clear < 0 { tight = mid } else { loose = mid }
            }
            return solve(pose, depth: depth, fold: loose)
        }
        guard move == .fly, recline.kind == .floor, whole.elbow < Self.elbowRoom - 0.002 else { return whole }
        return solve(pose, depth: reachable(pose, within: depth))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, holds, _, _) = shown(pose)
        var p: [PropPiece] = []
        switch load {
        case .barbell:
            if holds.count == 2 { p += BenchStagings.barbell((holds[0].at + holds[1].at) * 0.5) }
        case .ezBar:
            if holds.count == 2 { p += BenchStagings.barbell((holds[0].at + holds[1].at) * 0.5, length: 1.3, plate: 0.15) }
        case .dumbbells:
            for hold in holds { p += BenchStagings.dumbbell(hold.at, axis: hold.across) }
        case .single:
            // It hangs straight down from the head the hands clasp.
            if let top = holds.first { p += BenchStagings.dumbbell(top.at - V(0, 0, 0.1), axis: V(0, 0, 1)) }
        }
        return (frame, p)
    }
}

extension Body3D {
    /// The length of the upper arm of side `s`.
    func benchUpperArm(_ s: String) -> Double? {
        guard let shoulder = head["humerus.\(s)"], let elbow = head["ulna.\(s)"] else { return nil }
        return (elbow - shoulder).length
    }

    /// The straight-line distance from shoulder to wrist with the elbow bent by `degrees`.
    func benchArm(_ s: String, bend degrees: Double) -> Double? {
        guard let upper = benchUpperArm(s), let elbow = head["ulna.\(s)"], let wrist = head["hand.\(s)"] else { return nil }
        return Self.span(upper, (wrist - elbow).length, bend: degrees)
    }
}

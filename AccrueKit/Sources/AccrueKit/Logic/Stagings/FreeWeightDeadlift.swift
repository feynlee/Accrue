import Foundation

// MARK: - Deadlift from the floor

/// A deadlift from the floor, conventional or sumo. The bar is built first: it stands on its
/// plates over the feet, just in front of the shins, and goes straight up that line to where
/// long arms hold it when the lifter stands tall. The body is fitted to the bar: both feet
/// flat where they stand, the arms long, the trunk leaning as the keyframes lean it (and as
/// much further as this body's arms need to reach a bar on the floor), and the hips wherever
/// that leaves the shins and then the thighs just touching the bar on its way up.
struct FreeWeightDeadliftStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far in front of the ankles the bar's line is: over the laces, where upright thighs
    /// and shins that lean a little can both touch it.
    static let ahead = 0.105
    /// How far the shoulders are in front of the bar until it is past the knees, as an angle
    /// of the arms in degrees; how far behind it they may be at the top; and the most they are
    /// ever in front of it.
    static let over = 9.0, behind = 33.0, most = 16.0
    /// How many degrees further than the keyframes the knees may bend to keep the trunk as
    /// upright as the keyframes have it.
    static let squat = 22.0

    /// The body fitted to the bar for one pose.
    struct Pull: Sendable {
        let lifter: FreeWeightLifter
        let course: FreeWeightCourse
        let hips: FreeWeightRange, knees: FreeWeightRange
        /// The bar's line, and its height on the floor and at the top.
        let line: Double, low: Double
        var top: Double

        /// How far the bar has come up: 0 on the floor, 1 standing tall.
        func rise(_ pose: JointPose) -> Double { 1 - (hips(pose) + knees(pose)) / 2 }

        /// The hips that put the shoulders `angle` degrees behind a bar at `want` on long arms.
        /// Legs that cannot let the hips up that high keep them lower, and the bar comes down
        /// with the hands.
        func seat(_ trunk: FreeWeightTrunk, _ angle: Double, _ want: V) -> (root: V, bar: V) {
            let a = angle * .pi / 180
            var root = V(0, want.y + trunk.reach * sin(a) - trunk.mid.y, want.z + trunk.reach * cos(a) - trunk.mid.z)
            var bar = want
            let highest = lifter.ceiling(trunk, y: root.y)
            if root.z > highest {
                root.z = highest
                let dy = root.y + trunk.mid.y - bar.y
                bar.z = max(low, root.z + trunk.mid.z - max(0, trunk.reach * trunk.reach - dy * dy).squareRoot())
            }
            return (root, bar)
        }

        /// How far behind the bar the shoulders are when the hips have come forward from well
        /// behind it until the legs meet it. (Further forward the bar would be through the
        /// legs and out behind them.) Never further in front of it than `most`.
        func meet(_ trunk: FreeWeightTrunk, _ want: V) -> Double {
            func free(_ angle: Double) -> Bool {
                let s = seat(trunk, angle, want)
                return lifter.room(s.bar, trunk, root: s.root) > FreeWeightLifter.touch
            }
            var angle = 30.0
            let front = -FreeWeightDeadliftStaging.most
            guard free(angle) else { return angle }
            while angle > front, free(max(front, angle - 3)) { angle -= 3 }
            guard angle > front else { return front }
            var clear = angle, met = max(front, angle - 3)
            for _ in 0..<8 {
                let between = (clear + met) / 2
                if free(between) { clear = between } else { met = between }
            }
            return clear
        }

        /// The frame, where the bar is, and how far the shoulders are behind it (the angle of
        /// the arms from straight down, in degrees).
        func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V, angle: Double) {
            let body = lifter.body
            let u = rise(pose)
            let want = V(0, line, low + (top - low) * u)
            let upright = lifter.trunk(body.rotations(pose))

            // With the trunk as the keyframes lean it, this body's arms may not reach a bar on
            // the floor unless the hips squat under it and the shoulders fall behind it. A
            // lifter keeps the shoulders over the bar until it is past the knees, and the knees
            // not much more bent than the keyframes have them: the trunk leans as far as that takes.
            let past = min(1, max(0, (u - 0.45) / 0.55))
            let limit = -FreeWeightDeadliftStaging.over + (FreeWeightDeadliftStaging.over + FreeWeightDeadliftStaging.behind) * past * past
            let bend = max(0, pose.angles["kneeFlex"] ?? 0) + FreeWeightDeadliftStaging.squat
            func fits(_ lean: Double) -> Double? {
                let trunk = upright.leaning(lean)
                let angle = meet(trunk, want)
                guard angle <= limit, lifter.knee(trunk, root: seat(trunk, angle, want).root) <= bend else { return nil }
                return angle
            }
            var lean = 0.0
            var angle = fits(0) ?? limit
            if fits(0) == nil {
                var little = 0.0, much = 50.0
                for _ in 0..<9 {
                    let between = (little + much) / 2
                    if fits(between) != nil { much = between } else { little = between }
                }
                lean = much
                angle = meet(upright.leaning(lean), want)
            }
            var leaning = pose
            leaning.angles["trunk", default: 0] += lean
            var g = body.rotations(leaning)
            let s = seat(upright.leaning(lean), angle, want)
            var h = lifter.legs(&g, root: s.root)

            // A bar that drifts forward swings out on the arms; the body stays where it was.
            var bar = s.bar
            let drift = min(40, max(0, course.off("shoulderFlex", pose)))
            if drift > 0, let r = h["humerus.r"], let l = h["humerus.l"] {
                let shoulders = (r + l) * 0.5
                bar = shoulders + M.x(-drift) * (bar - shoulders)
                bar.z = max(bar.z, low)
            }
            lifter.close(&g, h, on: bar) { m in V(-m * 0.3, 1, 0) }
            h = body.place(g, root: s.root)
            return (body.made(g, h, floor: 0), bar, angle)
        }
    }

    let pull: Pull
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let plan = Self.plan(for: guide, body),
              let lifter = FreeWeightLifter(body, plan.tool, stance: plan.stance, turnout: plan.turnout, grip: plan.grip),
              let lockout = guide.keyframes.min(by: { ($0.pose.angles["hipFlex"] ?? 0) < ($1.pose.angles["hipFlex"] ?? 0) })
        else { return nil }
        kinds = plan.tool.kinds
        // A dumbbell's heads are thicker than a bar, so its handle's line is that much further forward.
        var pull = Pull(lifter: lifter, course: FreeWeightCourse(guide.keyframes, drivers: ["hipFlex", "kneeFlex"]),
                        hips: FreeWeightRange(guide.keyframes, "hipFlex"), knees: FreeWeightRange(guide.keyframes, "kneeFlex"),
                        line: lifter.middle - (Self.ahead - 0.055) - (plan.tool.bulk - LegWeights.barRadius), low: plan.low, top: 3)
        // The top is as high as the legs can take the bar on long arms.
        pull.top = pull.solve(lockout.pose).bar.z
        self.pull = pull
    }

    /// Which deadlift from the floor this is, or nil for one this staging does not show
    /// honestly: every word of the name must be one it knows the meaning of.
    static func plan(for guide: HowToGuide, _ body: Body3D)
        -> (tool: FreeWeightTool, stance: Double, turnout: Double, grip: Double, low: Double)? {
        guard let hip = body.head["femur.l"] else { return nil }
        let words = LegLoad.words(guide)
        let plain: Set<String> = ["deadlift", "back", "front", "side", "pov", "view", "form", "check", "hips", "pause", "paused"]
        func only(_ more: String...) -> Bool { words.isSubset(of: plain.union(more)) }
        switch (guide.subtypeID, guide.equipment) {
        case (nil, "barbell"):
            guard only("barbell", "hook", "grip", "weighted", "clean", "snatch") else { return nil }
            // Feet under the hips, hands just outside the legs; a snatch grip is much wider.
            return (.barbell, hip.x + 0.015, 10, words.contains("snatch") ? 0.45 : 0.26, LegWeights.plateRadius)
        case ("sumo", "barbell"):
            guard only("barbell", "sumo") else { return nil }
            // Feet wide with the toes well out, as the keyframes spread the hips; hands inside the knees.
            let top = guide.keyframes.first?.pose.angles ?? [:]
            return (.barbell, hip.x + 0.47 * sin((top["hipAbd"] ?? 30) * .pi / 180), top["hipRot"] ?? 35, 0.15,
                    LegWeights.plateRadius)
        case (nil, "dumbbell"):
            guard only("dumbbell", "v", "2") else { return nil }
            // Dumbbells go down to the middle of the shins, not to the floor.
            return (.dumbbells, hip.x + 0.015, 10, 0.2, 0.2)
        default: return nil
        }
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar, _) = pull.solve(pose)
        return (frame, pull.lifter.tool.props(bar, half: pull.lifter.half))
    }
}

// MARK: - Romanian and stiff-leg deadlift

/// A Romanian or stiff-leg deadlift: the lifter stands balanced on flat feet with the knees
/// soft, as the keyframes bend them, and bows from the hips. The bar hangs from long arms and
/// is kept against the legs, so it slides down the thighs and past the knees as the trunk
/// goes over, and never reaches the floor.
struct FreeWeightHingeStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far behind straight down the arms may draw the bar in to the legs, in degrees.
    static let drawn = 38.0
    /// The bar's weight next to the body's, for the balance.
    static let mass = 0.6

    /// How far below the knees the bar goes at the bottom, and the furthest the trunk leans to
    /// take it there, in degrees.
    static let belowKnee = 0.12, flat = 88.0

    let lifter: FreeWeightLifter
    let course: FreeWeightCourse
    let hips: FreeWeightRange
    /// The trunk's extra lean at the bottom, in degrees: what this body's arms need.
    private(set) var sink = 0.0
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let tool = Self.tool(for: guide), let hip = body.head["femur.l"], let knee = body.head["shin.l"],
              let lifter = FreeWeightLifter(body, tool, stance: hip.x + 0.015, turnout: 10, grip: tool == .barbell ? 0.26 : 0.2),
              let bottom = guide.keyframes.max(by: { ($0.pose.angles["hipFlex"] ?? 0) < ($1.pose.angles["hipFlex"] ?? 0) })?.pose
        else { return nil }
        self.lifter = lifter
        course = FreeWeightCourse(guide.keyframes, drivers: ["hipFlex", "kneeFlex"])
        hips = FreeWeightRange(guide.keyframes, "hipFlex")
        kinds = tool.kinds
        // The keyframes' bow may leave the bar at the knees: the trunk goes over as much
        // further as brings it down the shins, short of level.
        var little = 0.0, much = max(0, Self.flat - (bottom.angles["trunk"] ?? 0))
        let want = knee.z - Self.belowKnee
        if solve(bottom).bar.z > want {
            for _ in 0..<8 {
                sink = (little + much) / 2
                if solve(bottom).bar.z > want { little = sink } else { much = sink }
            }
            sink = much
        }
    }

    static func tool(for guide: HowToGuide) -> FreeWeightTool? {
        guard guide.subtypeID == "romanian" else { return nil }
        let words = LegLoad.words(guide)
        let plain: Set<String> = ["romanian", "rdl", "deadlift", "stiff", "straight", "leg", "legs", "legged"]
        switch guide.equipment {
        case "barbell": return words.isSubset(of: plain.union(["barbell"])) ? .barbell : nil
        case "dumbbell": return words.isSubset(of: plain.union(["dumbbell", "v", "2", "3"])) ? .dumbbells : nil
        default: return nil
        }
    }

    /// The frame, and where the bar is.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V) {
        let body = lifter.body
        var bowed = pose
        let depth = hips(pose)
        bowed.angles["trunk", default: 0] += sink * depth * depth
        var g = body.rotations(bowed)
        let rel = body.place(g, root: V(0, 0, 0))
        let (mid, reach) = lifter.shoulders(rel)
        let knee = pose.angles["kneeFlex"] ?? 0
        let drift = min(40, max(0, course.off("shoulderFlex", pose)))

        // The body balances with the bar where it hangs, and the bar hangs where the body puts
        // its shoulders and legs: a few rounds settle the two.
        var load = mid + V(0, 0, -reach)
        var h = rel
        var root = V(0, 0, 0)
        var bar = load
        for _ in 0..<3 {
            h = body.stand(&g, on: lifter.feet, knee: knee, kneeTurn: lifter.kneeTurn, load: (load, Self.mass), sitBack: 0.3)
            root = h["pelvis"] ?? root
            bar = lifter.hang(g, h, back: Self.drawn)
            load = bar - root
        }
        if drift > 0 { bar = lifter.hang(g, h, back: Self.drawn, swing: drift) }
        bar.z = max(bar.z, lifter.tool.lowest)
        lifter.close(&g, h, on: bar) { m in V(-m * 0.3, 1, 0) }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose)
        return (frame, lifter.tool.props(bar, half: lifter.half))
    }
}

import Foundation

/// A fly machine: the pec deck, where the lifter sits against the back pad and hugs the two
/// handles together in front, and the reverse fly, where the lifter faces the machine with the
/// chest on a pad and opens the handles out to the sides. Each handle hangs from an arm that
/// turns about an upright axle over that shoulder, so the hands travel on level arcs with the
/// elbows held just short of straight, and the weight stack rises as they go.
struct MachineFlyStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.016, stackHeight = 1.75
    /// How far the axles are above the shoulders, and the handles below them.
    static let over = 0.5, under = 0.03

    let body: Body3D
    /// Facing the machine and pulling the handles apart.
    let reverse: Bool
    /// Handles that stand upright (palms facing) instead of lying level (palms down).
    let upright: Bool
    let chair: MachineChair
    let range: MachineRange
    let grips: [String: HandGrip]
    /// The foot of each axle at shoulder height, and the arms' length.
    let axles: [String: V]
    let radius: Double
    /// The arms' swing from straight out to the side, in degrees, with the arms open and closed.
    let swing: (open: Double, closed: Double)
    let baseTrunk: Double
    let column: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let reverse = guide.familyID == "rear-delt-fly"
        if reverse {
            guard guide.subtypeID == "machine",
                  words.isSubset(of: ["lever", "seated", "reverse", "fly", "parallel", "grip"]), words.contains("reverse")
            else { return nil }
        } else {
            guard guide.familyID == "chest-fly", guide.subtypeID == "pec-deck",
                  words.isSubset(of: ["lever", "seated", "fly", "pec", "deck"]) else { return nil }
        }
        let upright = !reverse || words.contains("parallel")
        guard let chair = MachineChair(body, lean: reverse ? 0 : 6),
              let r = body.grip("r", radius: Self.gripRadius, square: upright ? 0 : 0.4),
              let l = body.grip("l", radius: Self.gripRadius, square: upright ? 0 : 0.4),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.reverse = reverse
        self.upright = upright
        self.chair = chair
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, "shoulderFlex")
        baseTrunk = first.angles["trunk"] ?? 0

        // The machine is set to the shoulders, with the blades where a good rep holds them.
        let seated = chair.sit(first)
        guard let rs = seated.h["humerus.r"], let ls = seated.h["humerus.l"] else { return nil }
        let mid = (rs + ls) * 0.5
        let wide = abs(rs.x - ls.x) / 2
        axles = ["r": V(-wide, mid.y, mid.z), "l": V(wide, mid.y, mid.z)]
        let elbow = max(12, guide.keyframes.map { $0.pose.angles["elbowFlex"] ?? 15 }.min() ?? 15)
        let reach = body.reach("r", r, bend: elbow)
        let radius = max(0.3, reach * reach - Self.under * Self.under).squareRoot()
        self.radius = radius
        // Closed, the fists stop a hand's width apart; open, the arms are out to the sides.
        let gap = reverse ? 0.1 : 0.065
        let closed = 90 + asin(min(1, max(0, wide - gap) / radius)) * 180 / .pi
        swing = (reverse ? -6 : 8, closed)

        var p = chair.pieces(back: !reverse)
        let top = mid.z + Self.over
        // A column with the weight stack: behind the back pad, or in front of the lifter who
        // faces it, clear of the handles. A boom from its top carries the two axles.
        let column = reverse ? mid.y - radius - 0.32 : chair.rest.behind(0.3, 0.2).y + 0.14
        self.column = column
        let stack = column + (reverse ? -0.34 : 0.34)
        p.append(Plan.box(V(0, column, (top + 0.05) / 2), (0.09, 0.09, top + 0.05), .metal))
        p.append(Plan.box(V(0, (column + mid.y) / 2, top), (0.07, abs(column - mid.y) + 0.07, 0.06), .metal))
        p.append(Plan.rod(V(-wide - 0.03, mid.y, top), V(wide + 0.03, mid.y, top), 0.03, .metal))
        p.append(Plan.box(V(0, (stack - 0.2) / 2, 0.02), (0.08, abs(stack) + 0.4, 0.04), .metal))
        p.append(Plan.box(V(0, column, 0.02), (0.6, 0.07, 0.04), .metal))
        p += stackFrame(y: stack, height: Self.stackHeight)
        if reverse {
            // The chest pad, on a post that comes up between the knees.
            let hip = chair.rest.hip
            let pad = hip + V(0, -(MachineFit.front + 0.035), 0.34)
            p.append(Plan.box(pad, (0.28, 0.07, 0.26), .pad))
            p.append(Plan.rod(pad + V(0, -0.035, -0.05), V(0, pad.y - 0.16, 0.04), 0.03, .metal))
        }
        fixed = p
    }

    /// The handle of side `m` (1 right, -1 left) with the arms swung to `degrees`: where the
    /// hand holds it, the way the grip runs, and the way from the axle out to it.
    func handle(_ s: String, _ m: Double, _ degrees: Double) -> (at: V, grip: V, out: V) {
        let a = degrees * .pi / 180
        let out = V(-m * cos(a), -sin(a), 0)
        let at = (axles[s] ?? V(0, 0, 1)) + out * radius - V(0, 0, Self.under)
        return (at, upright ? V(0, 0, -1) : V(-m * sin(a), cos(a), 0), out)
    }

    /// The posed body, and how far the arms have swung.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, swing: Double) {
        // A trunk that swings back comes off the chest pad.
        let back = reverse ? min(0, (pose.angles["trunk"] ?? 0) - baseTrunk) : 0
        var (g, h, root) = chair.sit(pose, forward: back)
        let degrees = swing.open + (swing.closed - swing.open) * range(pose)
        let a = degrees * .pi / 180
        let thorax = g["thorax"] ?? .identity
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            let handle = handle(s, m, degrees)
            // The elbow points behind an arm that is out to the side, and outside one that
            // is out in front, a little below level either way.
            body.hold(s, grip, at: handle.at, across: handle.grip,
                      pole: thorax * V(-m * sin(a), cos(a), reverse ? -0.25 : -0.45), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), degrees)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, degrees) = solve(pose)
        var p: [PropPiece] = []
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let axle = axles[s] else { continue }
            let handle = handle(s, m, degrees)
            let hub = axle + V(0, 0, Self.over), elbow = hub + handle.out * radius
            // Out from the axle over the head's height, then down to the grip.
            p.append(Plan.rod(hub, elbow, 0.02, .metal))
            p.append(Plan.ball(elbow, 0.02, .metal))
            p.append(Plan.disc(hub, axis: V(0, 0, 1), radius: 0.05, thickness: 0.08, .dark))
            if upright {
                p.append(Plan.rod(elbow, handle.at + V(0, 0, 0.07), 0.016, .metal))
                p.append(Plan.rod(handle.at + V(0, 0, 0.07), handle.at - V(0, 0, 0.07), Self.gripRadius, .dark))
            } else {
                // A level grip on the end of a drop that comes down just outside the hand.
                let end = handle.at + handle.grip * 0.085
                p.append(Plan.rod(elbow + handle.grip * 0.085, end, 0.016, .metal))
                p.append(Plan.rod(elbow, elbow + handle.grip * 0.085, 0.016, .metal))
                p.append(Plan.ball(end, 0.016, .metal))
                p.append(Plan.rod(end, handle.at - handle.grip * 0.07, Self.gripRadius, .dark))
            }
        }
        // The plates the arms lift: most at the squeeze, which is closed for a fly and open
        // for a reverse fly.
        let turned = abs(degrees - (reverse ? swing.closed : swing.open)) * .pi / 180
        let stack = column + (reverse ? -0.34 : 0.34)
        p += liftedPlates(y: stack, height: Self.stackHeight, travel: turned * 0.3)
        return (frame, p)
    }
}

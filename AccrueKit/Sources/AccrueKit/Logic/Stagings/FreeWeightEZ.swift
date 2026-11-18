import Foundation

// MARK: - EZ bar

/// An EZ curl bar: a short bar whose middle is bent into a shallow W, so the hands hold it on a
/// slope with the wrists turned part of the way in. The exercise is drawn as it would be with a
/// straight bar, and then the bar is given its bends and each hand is turned onto the slope it
/// holds: the inner pair of slopes for a close grip, the outer pair for any other.
struct FreeWeightEZStaging: LoopStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// Half of the bar's bent middle, from its centre outward: how far along the bar, and how
    /// far off its line. The ends beyond are straight, on the line.
    static let bends: [(along: Double, off: Double)] = [(0, 0), (0.03, 0), (0.095, -0.026), (0.195, 0.012), (0.235, 0)]
    /// The inner and the outer slope, as places in `bends`, and how near their ends a hand's middle may be.
    static let inner = 1, outer = 2, margin = 0.03
    /// Hands nearer the middle than this are on the inner slopes.
    static let close = 0.125
    /// The bar as the plain equipment draws an EZ bar: its half length, where the plates and
    /// collars are, and how big.
    static let half = 0.65, plates = 0.45, collars = 0.38, plateRadius = 0.15, radius = 0.014

    /// Families whose keyframes stand upright and work the arms with one bar.
    static let families: Set<String> = ["biceps-curl", "overhead-press", "triceps-extension", "upright-row", "front-raise"]
    /// Versions done lying or on a pad, with something else as well, or that turn the bar.
    static let elsewhere: Set<String> = ["lying", "prone", "supine", "incline", "decline", "preacher", "spider", "concentration",
                                         "blaster", "band", "twist", "kneeling", "ball", "bent", "over", "gravity"]

    let body: Body3D
    let plan: PropPlan
    let hands: Handhold
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.equipment == "ez-bar", Self.families.contains(guide.familyID),
              LegLoad.words(guide).isDisjoint(with: Self.elsewhere),
              !["lying", "preacher", "concentration", "chest-supported"].contains(guide.subtypeID ?? "") else { return nil }
        // A version a later group seats or lays down is left as that group draws it.
        let later: [(HowToGuide, Body3D) -> (any BodyStaging)?] = [FloorStagings.make, CardioStagings.make, PostureStagings.make]
        guard !later.contains(where: { $0(guide, body) != nil }) else { return nil }
        let plan = PropPlan(guide: guide, body: body, plain: true)
        // The plain picture has both hands on one EZ bar.
        guard plan.kinds.contains(.ezBar), let hands = plan.hands, hands.bar != nil, hands.grips["r"] != nil, hands.grips["l"] != nil
        else { return nil }
        self.body = body
        self.plan = plan
        self.hands = hands
        kinds = plan.kinds
        fixed = plan.fixed
    }

    /// How far off the bar's line it is, `x` along it from the centre.
    static func off(_ x: Double) -> Double {
        let x = abs(x)
        for (a, b) in zip(bends, bends.dropFirst()) where x <= b.along {
            return a.off + (b.off - a.off) * (x - a.along) / (b.along - a.along)
        }
        return 0
    }

    /// The bar's centre, the way it runs (to the body's left) and the way its bends lie, and
    /// where each hand's middle is along it.
    struct Bar {
        var mid, axis, bend: V
        var at: [String: Double]

        func point(_ x: Double) -> V { mid + axis * x + bend * FreeWeightEZStaging.off(x) }
    }

    func solve(_ pose: JointPose, at t: Double) -> (frame: BodyFrame, bar: Bar?) {
        let (plain, held) = hands.frame(pose, at: t)
        var g = plain.rotations.mapValues { M($0) }
        var h = plain.heads.mapValues { V($0) }
        guard let straight = held.bar, let root = h["pelvis"], let right = held.grips["r"], let left = held.grips["l"] else { return (plain, nil) }
        let axis = straight.axis.dot(left.point - right.point) < 0 ? straight.axis * -1 : straight.axis

        // The slopes lie the way the palms face, so that turning onto them is a turn of the
        // forearm and not a bend of the wrist: going outward, the slope a hand holds comes
        // toward its palm.
        var palm = right.palm + left.palm
        palm = palm - axis * palm.dot(axis)
        guard palm.length > 1e-6 else { return (plain, nil) }
        let apart = abs((left.point - right.point).dot(axis)) / 2
        let slope = apart < Self.close ? Self.inner : Self.outer
        let from = Self.bends[slope], to = Self.bends[slope + 1]
        let bend = palm.unit * (to.off > from.off ? 1 : -1)
        let x = min(to.along - Self.margin, max(from.along + Self.margin, apart))
        // The hands stay on the line they were on; the bar's own line moves to pass through them.
        let line = straight.mid + axis * ((right.point + left.point) * 0.5 - straight.mid).dot(axis)
        let bar = Bar(mid: line - bend * Self.off(x), axis: axis, bend: bend, at: ["r": -x, "l": x])

        for (s, side) in [("r", -1.0), ("l", 1.0)] {
            guard let grip = hands.grips[s], let shoulder = h["humerus.\(s)"], let was = held.grips[s] else { continue }
            let outward = (axis * (side * (to.along - from.along)) + bend * (to.off - from.off)).unit
            let across = outward * (was.across.dot(axis * side) < 0 ? -1 : 1)
            let point = bar.point(side * x)
            // The elbow keeps bending the way the keyframes turned it.
            let hinge = (g["humerus.\(s)"] ?? .identity) * body.hingeAxis(s)
            body.hold(s, grip, at: point, across: across, pole: (point - shoulder).cross(hinge), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: plain.floor), bar)
    }

    /// The bar's pieces: the bent middle first, then the straight ends, the collars and the plates.
    static func pieces(_ bar: Bar) -> [PropPiece] {
        var out: [PropPiece] = []
        for side in [-1.0, 1.0] {
            for (a, b) in zip(bends, bends.dropFirst()) {
                out.append(PropPlan.rod(bar.point(side * a.along), bar.point(side * b.along), radius, .metal))
                out.append(PropPlan.ball(bar.point(side * b.along), radius, .metal))
            }
        }
        for side in [-1.0, 1.0] {
            out.append(PropPlan.rod(bar.point(side * (bends.last?.along ?? 0)), bar.point(side * half), radius, .metal))
            out.append(PropPlan.disc(bar.point(side * collars), axis: bar.axis, radius: 0.03, thickness: 0.03, .metal))
            out.append(PropPlan.disc(bar.point(side * plates), axis: bar.axis, radius: plateRadius, thickness: 0.07, .plate))
        }
        return out
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) { frame(pose, at: 0) }

    func frame(_ pose: JointPose, at t: Double) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose, at: t)
        return (frame, bar.map(Self.pieces) ?? [])
    }
}

import Foundation

// MARK: - Standing barbell press

/// A strict standing press. The lifter stands balanced on flat feet under the bar. The bar
/// starts at the top of the chest, under the chin, in hands just outside the shoulders with
/// the elbows under it; it goes up close in front of the face, and once it is over the head
/// it comes back to finish on long arms above the shoulders. How far it has gone is how far
/// the keyframes have straightened the elbows.
struct FreeWeightPressStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The bar's middle at the start, from the joint at the base of the neck, in the rib
    /// cage's own axes: in front of the collarbones, as near as folded arms can hold it.
    static let onChest = V(0, -0.15, -0.05)
    /// How near the bar may come to the face and the head.
    static let clear = 0.02
    /// The bar's weight next to the body's, for the balance.
    static let mass = 0.5

    let lifter: FreeWeightLifter
    let progress: PullProgress
    let course: FreeWeightCourse
    let kinds: [PropKind] = [.barbell]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.subtypeID == nil, guide.equipment == "barbell", let hip = body.head["femur.l"] else { return nil }
        // Every word of the name must be one this staging knows the meaning of.
        let words = LegLoad.words(guide)
        guard words.contains("standing"), words.contains("press"),
              words.isSubset(of: ["barbell", "standing", "military", "press", "shoulder", "shoulders", "overhead", "front",
                                  "without", "rack", "wide", "close", "grip"])
        else { return nil }
        let grip = words.contains("wide") ? 0.42 : words.contains("close") ? 0.24 : 0.31
        guard let lifter = FreeWeightLifter(body, .barbell, stance: hip.x + 0.03, turnout: 12, grip: grip) else { return nil }
        self.lifter = lifter
        progress = PullProgress(guide.keyframes)
        course = FreeWeightCourse(guide.keyframes, drivers: ["elbowFlex"])
    }

    /// The frame, and where the bar is.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V) {
        let body = lifter.body
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let thorax = g["thorax"] ?? .identity
        let (mid, reach) = lifter.shoulders(rel)
        let neck = rel["neck"] ?? mid
        let up = 1 - progress(pose)

        // From the chest to straight above the shoulders. A press that stops short leaves the
        // bar out in front, as far as the keyframes leave the arms short of upright.
        let short = min(45, max(0, -course.off("shoulderFlex", pose)))
        let rack = neck + thorax * Self.onChest
        let top = mid + thorax * (M.x(short) * V(0, 0, reach))
        var bar = mix(rack, top, up)
        bar.x = 0
        // The straight way there goes through the face: the bar stays in front of the chest,
        // the face and the head, and comes back over the top of the head.
        let rods = lifter.rods(g, rel)
        if lifter.room(bar, rods) < Self.clear {
            var inside = 0.0, out = 0.4
            for _ in 0..<10 {
                let between = (inside + out) / 2
                if lifter.room(bar + V(0, -between, 0), rods) < Self.clear { inside = between } else { out = between }
            }
            bar = bar + V(0, -out, 0)
        }

        // Knees just off locked: a leg at its full length is past what a planted foot can
        // reach exactly, and the feet would creep.
        var h = body.stand(&g, on: lifter.feet, knee: max(3, pose.angles["kneeFlex"] ?? 0), kneeTurn: lifter.kneeTurn,
                           load: (bar, Self.mass), sitBack: 0.1)
        let root = h["pelvis"] ?? V(0, 0, 0)
        bar = root + bar
        // Elbows under the bar and a little in front of it, pointing out to the sides.
        lifter.close(&g, h, on: bar) { m in thorax * V(-m * 0.5, -0.5, -1) }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose)
        return (frame, lifter.tool.props(bar, half: lifter.half))
    }
}

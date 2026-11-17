import Foundation

// MARK: - Bent-over row

/// A bent-over barbell row. The lifter stands balanced on flat feet, knees soft, bowed over
/// from the hips as the keyframes bow the trunk, and holds that still: only the arms and the
/// shoulder blades move. The bar hangs from long arms under the shoulders and is pulled in a
/// straight line to the lower ribs, as far as the keyframes bend the elbows, with the elbows
/// going up past the back.
struct FreeWeightRowStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The bar's weight next to the body's, for the balance.
    static let mass = 0.5

    let lifter: FreeWeightLifter
    let progress: PullProgress
    /// An underhand grip keeps the elbows in by the ribs.
    let palmsUp: Bool
    let kinds: [PropKind]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.subtypeID == nil, guide.equipment == "barbell", let hip = body.head["femur.l"] else { return nil }
        // Every word of the name must be one this staging knows the meaning of.
        let words = LegLoad.words(guide)
        guard words.contains("row"),
              words.isSubset(of: ["barbell", "bent", "over", "row", "wide", "narrow", "grip", "reverse", "back", "form", "check"])
        else { return nil }
        palmsUp = words.contains("reverse")
        let grip = words.contains("wide") ? 0.42 : words.contains("narrow") ? 0.16 : palmsUp ? 0.22 : 0.3
        guard let lifter = FreeWeightLifter(body, .barbell, stance: hip.x + 0.03, turnout: 12, grip: grip) else { return nil }
        self.lifter = lifter
        progress = PullProgress(guide.keyframes)
        kinds = [.barbell]
    }

    /// Where the bar touches the front of the body at the squeeze, at the bottom of the rib
    /// cage: a point at rest, carried by the rib cage.
    static let atRibs = V(0, -0.155, 1.13)

    /// The frame, and where the bar is.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V) {
        let body = lifter.body
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let (mid, reach) = lifter.shoulders(rel)
        // The body balances with the bar somewhere under the shoulders, and does not shift as
        // the bar comes up.
        var h = body.stand(&g, on: lifter.feet, knee: pose.angles["kneeFlex"] ?? 0, kneeTurn: lifter.kneeTurn,
                           load: (mid + V(0, 0, -0.7 * reach), Self.mass), sitBack: 0.3)
        let root = h["pelvis"] ?? V(0, 0, 0)
        let thorax = g["thorax"] ?? .identity
        let rods = lifter.rods(g, h)

        // From hanging under the shoulders, clear of the knees, to the lower ribs.
        let low = lifter.hang(g, h, back: 0)
        var high = low
        if let ribs = h["thorax"], let rest = body.head["thorax"] { high = ribs + thorax * (Self.atRibs - rest) }
        high.x = 0
        var bar = mix(low, high, progress(pose))
        bar.z = max(bar.z, lifter.tool.lowest)
        // It stops at the skin wherever it would go in, moving out the way the chest faces.
        var front = thorax * Body3D.forward
        front = V(0, front.y, front.z).unit
        if lifter.room(bar, rods) < FreeWeightLifter.touch {
            var inside = 0.0, out = 0.25
            for _ in 0..<9 {
                let between = (inside + out) / 2
                if lifter.room(bar + front * between, rods) < FreeWeightLifter.touch { inside = between } else { out = between }
            }
            bar = bar + front * out
        }
        // Overhand the elbows flare out to the sides as they come up; underhand they stay in.
        let flare = palmsUp ? 0.25 : 0.8
        lifter.close(&g, h, on: bar, palmsUp: palmsUp) { m in thorax * V(-m * flare, 1, 0) }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose)
        return (frame, lifter.tool.props(bar, half: lifter.half))
    }
}

import Foundation

// MARK: - Kettlebell swing

/// A two-handed kettlebell swing. The lifter stands balanced on flat feet set wide enough for
/// the bell to pass between the legs, and hinges and stands as the keyframes do. Both hands
/// stay closed side by side on the handle, on long arms that swing from the shoulders as far
/// as the keyframes raise them: back between the thighs when the hips are back, out in front
/// when the hips have snapped through. The bell flies on in line with the arms.
struct FreeWeightSwingStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// Half the distance between the middles of the two hands on the handle.
    static let hands = 0.047
    /// Half the handle's length.
    static let handle = 0.11
    /// From the handle to the middle of the ball, and the ball's radius, as the bell is drawn.
    static let toBall = 0.145, ball = 0.1
    /// How much further back than the keyframes the arms go at the bottom, in degrees, to
    /// carry the bell high between the thighs.
    static let hike = 7.0
    /// The bell's weight next to the body's, for the balance.
    static let mass = 0.2

    let lifter: FreeWeightLifter
    let hinge: FreeWeightRange
    let kinds: [PropKind] = [.kettlebell]
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.subtypeID == nil, guide.equipment == "kettlebell", let hip = body.head["femur.l"] else { return nil }
        // Every word of the name must be one this staging knows the meaning of: one-arm,
        // banded and side swings, and swings into a squat, are other movements.
        let words = LegLoad.words(guide)
        guard words.contains("swing"), words.isSubset(of: ["kettlebell", "swing", "overhand", "grip", "russian", "two", "hand", "handed"]),
              let lifter = FreeWeightLifter(body, .dumbbells, stance: hip.x + 0.17, turnout: 22, grip: Self.hands)
        else { return nil }
        self.lifter = lifter
        hinge = FreeWeightRange(guide.keyframes, "hipFlex")
    }

    /// The frame, the middle of the handle, and the way the bell lies from it.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, handle: V, toward: V) {
        let body = lifter.body
        var g = body.rotations(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let thorax = g["thorax"] ?? .identity
        let (mid, reach) = lifter.shoulders(rel)

        // The arms swing in the plane the body bends in, as far from the trunk as the
        // keyframes raise them, and a little further back at the bottom of the hinge.
        let raised = (pose.angles["shoulderFlex"] ?? 0) - Self.hike * hinge(pose)
        var toward = thorax * (M.x(-raised) * V(0, 0, -1))
        toward = V(0, toward.y, toward.z).unit
        var at = mid + toward * reach

        // The body balances over the middle of the feet with the bell where it is.
        var h = body.stand(&g, on: lifter.feet, knee: max(3, pose.angles["kneeFlex"] ?? 0), kneeTurn: lifter.kneeTurn,
                           load: (at + toward * Self.toBall, Self.mass), sitBack: 0.35)
        let root = h["pelvis"] ?? V(0, 0, 0)
        at = root + at
        lifter.close(&g, h, on: at) { m in V(-m, 0.3, 0) }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), at, toward)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, at, toward) = solve(pose)
        return (frame, PropPlan.kettlebell(handle: at, across: V(1, 0, 0), half: Self.handle, toward: toward))
    }
}

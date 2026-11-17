import Foundation

/// A movement done lying on the left side on the floor: lifting the upper leg, opening the
/// upper knee, turning the upper arm. The keyframes stand, so the standing pose is turned onto
/// its side and laid down. The lower leg keeps the bend the keyframes start with and stays on
/// the floor, the lower arm lies out in front, and the upper side does what the keyframes say.
struct PostureSideStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How far the skin presses into the floor, and how thick a mat is.
    static let sink = 0.005, matTop = 0.008
    /// How far the upper leg is brought in to rest on the lower one (degrees).
    static let stack = 6.0
    /// What the body lies on: the trunk, the lower leg and the lower arm.
    static let rests = FloorSkin.trunk + ["femur.l", "shin.l", "foot.l", "toes.l", "humerus.l", "ulna.l", "hand.l"]

    let body: Body3D
    /// The plain picture of the same exercise: what its hands hold.
    let plan: PropPlan
    /// The lower leg's bend at the hip and the knee, held through the loop.
    let lowerHip, lowerKnee: Double
    let level: Double
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let first = guide.keyframes.first?.pose else { return nil }
        let plan = PropPlan(guide: guide, body: body, plain: true)
        // One weight in the upper hand at most: a bar in both hands is another picture.
        guard plan.hands?.bar == nil else { return nil }
        self.body = body
        self.plan = plan
        lowerHip = first.angles["hipFlexL"] ?? first.angles["hipFlex"] ?? 0
        lowerKnee = first.angles["kneeFlexL"] ?? first.angles["kneeFlex"] ?? 0
        let mat = plan.kinds.contains(.mat)
        level = mat ? Self.matTop : 0
        kinds = plan.kinds.filter { ![.bench, .stabilityBall, .box, .step].contains($0) }
        if mat {
            let h = settle(first).h
            let ends = ["head", "toes.r", "toes.l", "foot.l"].compactMap { h[$0]?.x }
            if let low = ends.min(), let high = ends.max() {
                fixed = [Plan.box(V((low + high) / 2, -0.05, Self.matTop / 2), (max(1.85, high - low + 0.3), 0.66, Self.matTop), .accent)]
            }
        }
    }

    /// The body for `pose` on its left side, its head toward +x and its front toward the viewer.
    func settle(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V) {
        var pose = pose
        // The lower leg lies still, in line with the trunk as seen from above.
        pose.angles["hipFlexL"] = lowerHip
        pose.angles["kneeFlexL"] = lowerKnee
        pose.angles["hipAbdL"] = 0
        pose.angles["hipRotL"] = 0
        // The upper leg comes down onto the lower one: standing, they are a hip's width apart.
        pose.angles["hipAbd"] = (pose.angles["hipAbd"] ?? 0) - Self.stack
        // The lower arm lies on the floor straight out in front of the shoulder.
        pose.angles["shoulderFlexL"] = 90
        pose.angles["shoulderAbdL"] = 0
        pose.angles["shoulderRotL"] = 0
        pose.angles["elbowFlexL"] = 8
        let standing = body.rotations(pose)
        let upright = body.heads(standing)
        let turn = M.y(90)
        let g = standing.mapValues { turn * $0 }
        var h = upright.mapValues { turn * $0 }
        let pelvis = h["pelvis"] ?? V(0, 0, 0)
        let drop = V(-pelvis.x, -pelvis.y, level - Self.sink - body.floorLow(Self.rests, g, h))
        for (k, v) in h { h[k] = v + drop }
        return (g, h, h["pelvis"] ?? V(0, 0, 0))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h, root) = settle(pose)
        var held = Held()
        // A weight is held in the upper hand only.
        if let hands = plan.hands, hands.each, let grip = hands.grips["r"], let hand = g["hand.r"] {
            for (bone, turn) in grip.turns { g[bone] = hand * turn }
            h = body.place(g, root: root)
            if let c = hands.centre("r", g, h) {
                held.grips["r"] = PropPlan.Grip(point: c, across: hand * grip.across, palm: hand * grip.palm, fingers: hand * grip.along)
            }
        }
        let frame = body.made(g, h, floor: 0)
        return (frame, plan.moving(frame, held))
    }
}

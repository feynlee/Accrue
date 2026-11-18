import Foundation

/// A side plank on the right forearm: the body in one line on its side, facing the viewer,
/// the elbow under the shoulder with the forearm flat on the floor pointing forward, and the
/// outer edge of the lower foot (or the side of the lower knee) on the floor. The legs carry
/// the body's line, so the hips sag or pike as a mistake bends it.
struct FloorSidePlankStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How far the middle of the elbow sits above the floor it rests on, and how far the
    /// skin of the lower leg presses into it.
    static let elbowPad = 0.045, sink = 0.006
    /// The legs the body rests on.
    static let lower = ["femur.r", "shin.r", "foot.r", "toes.r"]

    let body: Body3D
    let hand: HandPress
    /// How high the lower shoulder is held, and from there to the wrist with the forearm down.
    let height: Double
    let reach: V
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let hand = body.flatHand("r", spread: 1.3), let shoulder = body.head["humerus.r"],
              let elbow = body.head["ulna.r"], let wrist = body.head["hand.r"] else { return nil }
        self.body = body
        self.hand = hand
        // The forearm lies along the floor and the upper arm stands on it at a right angle.
        let upper = (elbow - shoulder).length, fore = (wrist - elbow).length
        let dip = asin(min(1, max(-1, (Self.elbowPad - hand.wristLift) / fore)))
        height = Self.elbowPad + upper * cos(dip)
        reach = V(0, upper * sin(dip) - fore * cos(dip), -upper * cos(dip) - fore * sin(dip))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var posed = pose
        posed.angles["trunk"] = 0
        // Hips that drop bend the body sideways at the hips: both legs swing the same way.
        let drop = -min(0, pose.angles["hipAbd"] ?? 0)
        // The upper leg comes down onto the lower one, and the upper arm lies along the side.
        posed.angles["hipAbdL"] = (pose.angles["hipAbdL"] ?? max(0, pose.angles["hipAbd"] ?? 0)) + drop - 4.5
        posed.angles["shoulderAbdL"] = 7
        posed.angles["shoulderFlexL"] = 0
        posed.angles["elbowFlexL"] = 12
        posed.angles["shoulderAbd"] = 90
        posed.angles["shoulderFlex"] = 0
        let standing = body.rotations(posed)
        let upright = body.heads(standing)

        /// The body turned onto its right side, its head toward -x and raised by `rise` degrees.
        func laid(_ rise: Double) -> (g: [String: M], h: [String: V]) {
            let turn = M.y(rise - 90)
            return (standing.mapValues { turn * $0 }, upright.mapValues { turn * $0 })
        }
        // The line rises from the feet until the lower shoulder is as high as the upper arm holds it.
        let rise = floorCross(-10...50) { rise in
            let (g, h) = laid(rise)
            return (h["humerus.r"]?.z ?? 0) - body.floorLow(Self.lower, g, h) - Self.sink - height
        }
        var (g, h) = laid(rise)
        if let foot = body.floorLowest(Self.lower, g, h)?.at {
            let shift = V(0.55, 0, -Self.sink) - foot
            for (k, p) in h { h[k] = p + shift }
        }
        let root = h["pelvis"] ?? V(0, 0, 0)
        if let shoulder = h["humerus.r"] {
            let wrist = shoulder + reach
            let rest = body.pressWrist(hand, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
            body.press("r", hand, at: V(wrist.x - rest.x, wrist.y - rest.y, 0), fingers: Body3D.forward, pole: V(0, 1, -1), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), [])
    }
}

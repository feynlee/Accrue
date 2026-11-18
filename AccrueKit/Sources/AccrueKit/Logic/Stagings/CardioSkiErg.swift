import Foundation

/// A ski ergometer: a tall post with the flywheel at its top and a cord down to a handle in
/// each hand. The feet stay flat where they stand; the hips, knees and trunk fold as the
/// keyframes say, and each arm is fitted to its handle where the keyframes carry it, the
/// handle held like the grip of a ski pole with its cord leaving the thumb side for the pulley.
struct CardioSkiErgStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.014, halfHandle = 0.065
    /// How far out from the middle each pulley is, and the least each hand is: wide enough
    /// that a cord drawn down past the shoulder stays outside it.
    static let pulleyX = 0.2, handX = 0.26

    let body: Body3D
    let grips: [String: HandGrip]
    /// Each ankle, fixed over its place on the floor.
    let ankles: [String: V]
    /// Where each cord comes out at the top of the post.
    let pulleys: [String: V]
    let kinds: [PropKind] = [.skiErg]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "ski-erg",
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let ar = body.head["foot.r"], let al = body.head["foot.l"] else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        let ankles = ["r": V(ar.x, 0, body.ankleHeight), "l": V(al.x, 0, body.ankleHeight)]
        self.ankles = ankles
        // The post stands clear of the hands at their farthest forward, and is taller than
        // their highest reach.
        var front = 0.0, top = 1.9
        for i in 0..<24 {
            let stood = Self.stand(Figure.smooth(guide.keyframes, at: Double(i) / 24), body: body, ankles: ankles)
            for s in ["r", "l"] {
                guard let c = Self.carried(s, stood.g, stood.h, grips) else { continue }
                front = min(front, c.y)
                top = max(top, c.z)
            }
        }
        let post = V(0, front - 0.3, 0)
        let high = top + 0.22
        pulleys = ["r": V(-Self.pulleyX, post.y + 0.1, high), "l": V(Self.pulleyX, post.y + 0.1, high)]

        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        p.append(Plan.box(V(0, post.y, (high + 0.1) / 2), (0.1, 0.08, high + 0.1), .metal))
        // Its foot: a bar across the front and a runner back between the feet.
        p.append(Plan.box(V(0, post.y, 0.02), (0.6, 0.08, 0.04), .metal))
        p.append(Plan.box(V(0, post.y / 2 + 0.1, 0.015), (0.08, -post.y + 0.2, 0.03), .metal))
        p.append(Plan.box(V(0, 0.2, 0.015), (0.5, 0.07, 0.03), .metal))
        // The flywheel in its cage at the top, the monitor at eye height, and the pulleys' arm.
        p.append(Plan.disc(V(0, post.y - 0.05, high - 0.3), axis: side, radius: 0.24, thickness: 0.14, .dark))
        p.append(Plan.disc(V(0, post.y - 0.05, high - 0.3), axis: side, radius: 0.1, thickness: 0.16, .metal))
        p.append(Plan.box(V(0, post.y + 0.07, 1.5), (0.16, 0.03, 0.12), x: side, z: V(0, 0.3, 1), .dark))
        p.append(Plan.rod(V(-Self.pulleyX - 0.03, post.y + 0.1, high), V(Self.pulleyX + 0.03, post.y + 0.1, high), 0.016, .metal))
        p.append(Plan.rod(V(0, post.y, high), V(0, post.y + 0.1, high), 0.02, .metal))
        for x in [-Self.pulleyX, Self.pulleyX] { p.append(Plan.disc(V(x, post.y + 0.1, high), axis: side, radius: 0.04, thickness: 0.025, .dark)) }
        fixed = p
    }

    /// The posed body standing on its fixed feet. The knees' bend gives the legs their length,
    /// and the hips go where that length and the body's balance put them: its weight over the
    /// middle of the feet, however the trunk folds.
    static func stand(_ pose: JointPose, body: Body3D, ankles: [String: V]) -> (g: [String: M], h: [String: V], root: V) {
        var g = body.rotations(pose)
        guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return (g, body.heads(g), V(0, 0, 0)) }
        let knee = min(140, max(2, (CardioStagings.angle(pose, "kneeFlex") + CardioStagings.angle(pose, "kneeFlexL")) / 2))
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: knee)
        let out = abs(rHip.x - pelvis.x) - abs(ankles["r"]?.x ?? rAnkle.x)
        var root = V(0, 0, body.ankleHeight + leg)
        var h = body.place(g, root: root)
        for _ in 0..<3 {
            root.y += -0.06 - body.balance(g, h).y
            root.z = body.ankleHeight + max(0.01, leg * leg - root.y * root.y - out * out).squareRoot()
            h = body.place(g, root: root)
            for s in ["r", "l"] {
                guard let ankle = ankles[s] else { continue }
                body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -1, 0.3), &g, h)
            }
            h = body.place(g, root: root)
        }
        return (g, h, root)
    }

    /// The middle of the handle where the keyframes' arm carries the closed hand.
    static func carried(_ s: String, _ g: [String: M], _ h: [String: V], _ grips: [String: HandGrip]) -> V? {
        guard let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"], let grip = grips[s] else { return nil }
        return wrist + hand * grip.centre
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h, root) = Self.stand(pose, body: body, ankles: ankles)
        let thorax = g["thorax"] ?? .identity
        var p: [PropPiece] = []
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let pulley = pulleys[s], let shoulder = h["humerus.\(s)"],
                  var at = Self.carried(s, g, h, grips) else { continue }
            // The hands keep to their own side of the body, a little outside the cords.
            at.x = -m * max(Self.handX, abs(at.x))
            // The handle lies square across the arm, its top turned toward the pulley, or
            // forward where the arm points along the cord.
            let arm = (at - shoulder).unit
            let cord = (pulley - at).unit, ahead = thorax * Body3D.forward
            let top = ((cord - arm * cord.dot(arm)) + (ahead - arm * ahead.dot(arm)) * 0.35).unit
            body.hold(s, grip, at: at, across: top * -1, pole: thorax * V(-m * 0.7, -0.2, -0.7), &g, h)
            p.append(Plan.rod(at - top * Self.halfHandle, at + top * Self.halfHandle, Self.gripRadius, .dark))
            p.append(Plan.rod(at + top * Self.halfHandle, pulley, 0.004, .cable))
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), p)
    }
}

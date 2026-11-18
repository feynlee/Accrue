import Foundation

// MARK: - Face pull

/// A standing face pull: the rope on a pulley at face height, held palms down with the thumbs
/// toward the pulley. It starts at arm's length with the hands together and comes to the face
/// with the elbows high and the ends pulled apart, the hands turning back beside the ears. The
/// keyframes place the arms, so elbows that drop and hands that never turn out show as written;
/// the rope only brings the hands as near each other as its length asks.
struct FacePullStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The station's height, and how far beyond the outstretched hands the pulley stands.
    static let top = 2.2, away = 0.62
    /// Half the distance between the hands at arm's length, and the most the rope lets them
    /// spread at the face.
    static let together = 0.08, apart = 0.24
    /// How far in front of the face and the chest the rope's swivel stops.
    static let clear = 0.06

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    /// Standing, sitting on a bench, or kneeling.
    let footing: CableKit.Footing
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []
    private(set) var pulley = V(0, -1.3, 1.6)
    private(set) var column = -1.6
    /// The cable's length out of the wheel at arm's length, where the stack rests.
    private(set) var slack = 0.0

    init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support? = nil) {
        guard let first = guide.keyframes.first?.pose, let footing = CableKit.Footing(guide, body, on: support),
              let r = body.grip("r", radius: CableKit.rope), let l = body.grip("l", radius: CableKit.rope) else { return nil }
        self.body = body
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        self.footing = footing
        kinds = footing.kinds
        // The pulley is set level with the eyes, a step beyond the outstretched hands. The
        // cable leaves from under the wheel.
        let start = reach(first)
        let hand = start.hands["r"] ?? V(0, -0.65, 1.45)
        let eyes = (start.h["neck"]?.z ?? 1.45) + 0.11
        pulley = V(0, hand.y - Self.away, eyes + CableKit.wheel)
        let station = CableKit.mastStation(pulley: pulley, top: Self.top)
        fixed = station.pieces + footing.pieces
        column = station.column
        slack = (layout(first).eye - pulley).length
    }

    /// The body standing on its feet, where each hand holds the rope, and where its elbow goes.
    func reach(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V, hands: [String: V], poles: [String: V]) {
        let (g, h, root) = footing.settle(body, pose)
        let thorax = g["thorax"] ?? .identity
        let u = progress(pose), ease = u * u * (3 - 2 * u)
        // Where the keyframes' arms would hold. The upper arm is theirs as it stands. The forearm
        // is turned about it by the shoulder's rotation as a coach counts it for an arm held
        // out to the side: pointing forward with none, straight up at 90 degrees.
        let limit = Self.together + (Self.apart - Self.together) * ease
        var out = 0.0, y = 0.0, z = 0.0, n = 0.0
        for (s, side) in [("r", ""), ("l", "L")] {
            guard let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"], let grip = grips[s],
                  let rElbow = body.head["ulna.\(s)"], let rWrist = body.head["hand.\(s)"] else { continue }
            func angle(_ key: String) -> Double { (pose.angles[key + side] ?? pose.angles[key] ?? 0) * .pi / 180 }
            let upper = (elbow - shoulder).unit
            let turn = angle("shoulderRot"), bend = angle("elbowFlex")
            var toward = thorax * (Body3D.forward * cos(turn) + Body3D.up * sin(turn))
            toward = toward - upper * toward.dot(upper)
            if toward.length < 1e-6 { toward = thorax * Body3D.up }
            let c = grip.centre
            let length = (rWrist - rElbow).length + (c - grip.across * c.dot(grip.across)).length
            var d = (upper * cos(bend) + toward.unit * sin(bend)) * length
            // The rope keeps the hands together at arm's length and lets them spread at the
            // face: a hand brought in swings about its elbow.
            let wide = abs(elbow.x + d.x)
            if wide > limit {
                let dx = abs(elbow.x) - limit
                let rest = max(1e-6, (d.y * d.y + d.z * d.z).squareRoot())
                let k = max(0.01, length * length - dx * dx).squareRoot() / rest
                d = V(0, d.y * k, d.z * k)
                out += limit
            } else {
                out += wide
            }
            y += elbow.y + d.y
            z += elbow.z + d.z
            n += 1
        }
        guard n > 0 else { return (g, h, root, [:], [:]) }
        (out, y, z) = (out / n, y / n, z / n)
        // The swivel hangs ahead of the hands, and stops short of the face and the chest.
        let front = CableKit.front(h, at: z)
        let tops = max(0, out - 0.04)
        let ahead = max(0.0004, CableKit.strand * CableKit.strand - tops * tops).squareRoot()
        y = min(y, front - Self.clear + ahead)

        var hands: [String: V] = [:], poles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"], let grip = grips[s] else { continue }
            hands[s] = CableKit.within(body, s, grip, shoulder: shoulder, V(-m * out, y, z))
            // The elbow goes where the keyframes carry it: out to the side and high.
            poles[s] = (elbow - shoulder).unit + thorax * V(-m * 0.5, 0.1, -0.25)
        }
        return (g, h, root, hands, poles)
    }

    struct Layout {
        var frame: BodyFrame
        /// The rope's middle line in each hand, and its direction from thumb to little finger.
        var hands: [String: V]
        var across: [String: V]
        /// The way the rope runs through each fist toward its end.
        var run: [String: V]
        /// The rope's swivel, and where the cable leaves the wheel.
        var eye, rim: V
    }

    func layout(_ pose: JointPose) -> Layout {
        var (g, h, root, hands, poles) = reach(pose)
        let held = CableKit.holdRope(body, grips, hands: hands, poles: poles, pulley: pulley, side: V(0, 0, -1), &g, h, root: root)
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: held.across, run: held.run, eye: held.eye, rim: held.rim)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        var p = CableKit.ropePieces(eye: at.eye, hands: at.hands, run: at.run)
        p.append(Plan.rod(at.eye, at.rim, CableKit.cable, .cable))
        p += liftedPlates(y: column, height: Self.top, travel: max(0, (at.eye - pulley).length - slack))
        return (at.frame, p)
    }
}

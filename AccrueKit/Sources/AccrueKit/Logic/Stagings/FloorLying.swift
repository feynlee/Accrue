import Foundation

/// An exercise done lying on the back on the floor: crunch, sit-up, leg raise, reverse crunch,
/// flutter kick, V-up, glute bridge, dead bug, hollow hold. The part of the trunk that stays
/// down rests on the floor on its own skin and rolls there without sliding; planted feet and
/// hands stay on their spots; the head lies on the floor until the shoulders lift it.
struct FloorLyingStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    enum Feet: Sendable, Equatable {
        /// The legs move as the keyframes have them, and never go under the floor.
        case free
        /// Feet flat on the floor with the knees bent as they are in the lying keyframe.
        case planted
        /// Feet flat on the floor where the shins stand upright with the hips at their highest.
        case underKnees
    }

    enum Arms: Sendable, Equatable {
        /// As the keyframes have them.
        case free
        /// Fingertips behind the ears, elbows wide.
        case byHead
        /// Along the sides, palms on the floor.
        case onFloor
    }

    struct Setup: Sendable {
        var anchor = FloorSupine.Anchor.hips
        /// With the hips down: the hips follow the trunk up once it is well off the floor (a
        /// sit-up), instead of staying flat while the chest curls (a crunch).
        var sitsUp = false
        var feet = Feet.free
        var arms = Arms.free
        /// The one leg that stays planted when the other is held up (a single-leg bridge).
        var plantedOnly: String?
    }

    let body: Body3D
    let supine: FloorSupine
    let setup: Setup
    /// The chest's tip when the whole back lies flat.
    let flatChest: Double
    let hipLine, armLine, kneeLine: FloorLine
    let hands: [String: HandPress]
    private(set) var ankles: [String: V] = [:]
    /// Where the middle knuckle of each hand rests on the floor, and which way its fingers point.
    private(set) var spots: [String: V] = [:]
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D, _ setup: Setup) {
        guard let first = guide.keyframes.first?.pose, let r = body.flatHand("r", spread: 1.2),
              let l = body.flatHand("l", spread: 1.2) else { return nil }
        self.body = body
        self.setup = setup
        supine = FloorSupine(body)
        hands = ["r": r, "l": l]
        hipLine = FloorLine("hipFlex", against: "trunk", guide.keyframes)
        armLine = FloorLine("shoulderFlex", against: "trunk", guide.keyframes)
        kneeLine = FloorLine("kneeFlex", against: "trunk", guide.keyframes)
        flatChest = supine.chestRest(supine.flat(first), hips: 0)

        // The feet go down once, from the body as it lies at the start (or, for a bridge, at
        // the top), and stay there.
        let lying = guide.keyframes.min { abs(($0.pose.angles["trunk"] ?? 0) + 90) < abs(($1.pose.angles["trunk"] ?? 0) + 90) }?.pose ?? first
        let top = guide.keyframes.min { ($0.pose.angles["trunk"] ?? 0) < ($1.pose.angles["trunk"] ?? 0) }?.pose ?? first
        let shapes = guide.keyframes.map { trunk($0.pose).h }
        if setup.feet != .free {
            let from = setup.feet == .underKnees ? top : lying
            let (_, h) = trunk(from)
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                if let only = setup.plantedOnly, only != s { continue }
                guard let hip = h["femur.\(s)"], let rHip = body.head["femur.\(s)"], let rKnee = body.head["shin.\(s)"],
                      let rAnkle = body.head["foot.\(s)"] else { continue }
                let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
                let wide = setup.feet == .underKnees ? 0.14 : 0.11, aside = wide - abs(hip.x)
                let forward: Double
                if setup.feet == .underKnees {
                    let rise = body.ankleHeight + shin - hip.z
                    forward = max(0.04, thigh * thigh - rise * rise - aside * aside).squareRoot()
                } else {
                    let leg = Body3D.span(thigh, shin, bend: from.angles["kneeFlex"] ?? 90)
                    let drop = hip.z - body.ankleHeight
                    forward = max(0.04, leg * leg - drop * drop - aside * aside).squareRoot()
                }
                var ankle = V(-m * wide, hip.y - forward, body.ankleHeight)
                // Near enough that the leg still reaches it wherever the loop takes the hips.
                ankle.y = max(ankle.y, Self.within(body.legSpan(bend: 8), of: shapes.compactMap { $0["femur.\(s)"] }, x: ankle.x, z: ankle.z))
                ankles[s] = ankle
            }
        }
        if setup.arms == .onFloor {
            // Arms long beside the hips, a little out from the body.
            let (_, h) = trunk(lying)
            let reach = body.armSpan("r", bend: 14)
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let shoulder = h["humerus.\(s)"], let hand = hands[s] else { continue }
                let fingers = Self.floorFingers(m)
                let wrist = body.pressWrist(hand, at: V(0, 0, 0), fingers: fingers, normal: Body3D.up)
                let out = 0.1, drop = shoulder.z - wrist.z
                let along = max(0.05, reach * reach - out * out - drop * drop).squareRoot()
                let x = shoulder.x - m * out
                let y = max(shoulder.y - along, Self.within(body.armSpan(s, bend: 8), of: shapes.compactMap { $0["humerus.\(s)"] }, x: x, z: wrist.z))
                spots[s] = V(x - wrist.x, y - wrist.y, 0)
            }
        }
    }

    /// The furthest toward the feet (the least y) a point at `x`, `z` may lie and still be
    /// within `reach` of every one of `joints`.
    static func within(_ reach: Double, of joints: [V], x: Double, z: Double) -> Double {
        joints.map { joint in
            let dx = x - joint.x, dz = z - joint.z
            return joint.y - max(0, reach * reach - dx * dx - dz * dz).squareRoot()
        }.max() ?? -.infinity
    }

    /// Which way the fingers of a hand on the floor point: toward the feet, a little outward.
    static func floorFingers(_ m: Double) -> V { V(-m * 0.12, -1, 0).unit }

    /// The trunk and head for `pose`, with the limbs still as the keyframes have them.
    func trunk(_ pose: JointPose) -> (g: [String: M], h: [String: V]) {
        var lift = (pose.angles["trunk"] ?? -90) + 90
        let bend = pose.angles["lumbar"] ?? 0
        var posed = pose
        switch setup.arms {
        case .free:
            break
        case .byHead:
            // Arms that swing forward leave the head as far as they have swung.
            let swing = min(1, max(0, armLine.excess(pose) / 50))
            set(&posed, "shoulderAbd", 95 * (1 - swing) + (pose.angles["shoulderAbd"] ?? 0) * swing)
            set(&posed, "shoulderFlex", (pose.angles["shoulderFlex"] ?? 0) * swing)
        case .onFloor:
            set(&posed, "shoulderAbd", 12)
            set(&posed, "shoulderFlex", 0)
        }
        let flat = supine.flat(posed)
        var g: [String: M], h: [String: V]
        var held = 0.0
        switch setup.anchor {
        case .hips:
            // Hips that bend more than the keyframes ask pull the whole trunk up from the hips.
            let pull = max(0, hipLine.excess(pose)) * 0.8
            var hips = pull
            if setup.sitsUp {
                let late = min(1, max(0, (lift - 20) / 40))
                hips += (lift - bend / 2) * late * late * (3 - 2 * late)
            }
            let rest = supine.chestRest(flat, hips: hips)
            let chest = max(rest, lift + bend / 2 + flatChest, hips - 10)
            (g, h) = supine.shape(flat, hips: hips, chest: chest, anchor: .hips)
            held = (chest - rest) / 6
        case .chest:
            // Hips that stay bent at the top of a bridge hang lower.
            if setup.feet != .free { lift = min(0, lift + max(0, hipLine.excess(pose)) * 0.6) }
            lift = min(0, lift)
            // An arched back lifts the low ribs; a rounded one curls the tailbone up.
            let chest = flatChest + lift + min(0, bend) / 2
            let want = lift - (bend < 0 ? bend / 2 : bend * 1.4)
            let hips = min(supine.hipsRest(flat, chest: chest), want)
            (g, h) = supine.shape(flat, hips: hips, chest: chest, anchor: .chest)
        }
        supine.layHead(&g, &h, nod: pose.angles["neck"] ?? 0, held: held)
        return (g, h)
    }

    private func set(_ pose: inout JointPose, _ key: String, _ value: Double) {
        pose.angles[key] = value
        pose.angles[key + "L"] = nil
    }

    func solve(_ pose: JointPose) -> (g: [String: M], h: [String: V]) {
        var (g, h) = trunk(pose)
        let root = h["pelvis"] ?? V(0, 0, 0)

        // Legs.
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            if var ankle = ankles[s] {
                // Feet set too far away, or knees that fall in, are mistakes the feet and knees show.
                ankle.y += min(0, kneeLine.excess(pose)) * 0.007
                let cave = min(0, pose.angles[s == "l" ? "hipAbdL" : "hipAbd"] ?? pose.angles["hipAbd"] ?? 0)
                body.plant(s, ankle: ankle, foot: .identity, pole: V(m * cave * 0.02, -0.3, 1), &g, h)
            } else {
                supine.keepLegUp(s, &g, h)
            }
        }
        h = body.place(g, root: root)

        // Arms.
        let swing = min(1, max(0, armLine.excess(pose) / 50))
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = hands[s] else { continue }
            switch setup.arms {
            case .free:
                break
            case .onFloor:
                guard let spot = spots[s] else { continue }
                body.press(s, hand, at: spot, fingers: Self.floorFingers(m), pole: V(-m, 0.2, 0.5), &g, h)
            case .byHead:
                guard let skull = h["head"], let turn = g["head"], let rSkull = body.head["head"],
                      let rWrist = body.head["hand.\(s)"], let rTip = body.tail["f3c.\(s)"],
                      let swung = h["hand.\(s)"], let swungTurn = g["hand.\(s)"] else { continue }
                // The middle fingertip behind the ear, the hand lying in round the back of the head.
                let tip = skull + turn * (V(-m * 0.072, 0.068, 1.6) - rSkull)
                let fingers = turn * V(m, 0.5, 0.12).unit
                var rotation = Body3D.frameMap(hand.along, hand.palm, to: fingers, turn * V(m * 0.8, -0.6, 0))
                var wrist = tip - rotation * (rTip - rWrist)
                if swing > 0 {
                    // Arms thrown forward let go of the head.
                    rotation = body.part(from: rotation, to: swungTurn, share: swing)
                    wrist = mix(wrist, swung, swing)
                }
                body.arm(s, wrist: wrist, hand: rotation, pole: (g["thorax"] ?? .identity) * V(-m, -0.35, 0.1), &g, h)
                for f in 1...5 { for seg in ["a", "b", "c"] { g["f\(f)\(seg).\(s)"] = rotation } }
            }
        }
        h = body.place(g, root: root)
        return (g, h)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (g, h) = solve(pose)
        return (body.made(g, h, floor: 0), [])
    }
}

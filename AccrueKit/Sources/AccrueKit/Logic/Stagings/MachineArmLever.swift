import Foundation

/// A curl or a triceps extension in a lever machine: seated, the upper arms lying on two
/// sloping pads in front of the chest, the elbows on the lever's axle, both hands on its
/// handle. Only the forearms move: they turn about the elbows and the lever turns with them.
struct MachineArmLeverStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How far forward of straight down the upper arms slope on the pads, in degrees.
    static let slope = 60.0
    static let gripRadius = 0.016, armX = 0.36

    let body: Body3D
    let chair: MachineChair
    let grips: [String: HandGrip]
    /// Handles that stand up from the lever's bar, for palms that face each other.
    let upright: Bool
    /// Palms down on the bar: a triceps extension or a reverse curl.
    let over: Bool
    let elbows: [String: V]
    /// The way the upper arms lie, and the under side of them.
    let along: V, under: V
    /// From the elbow to the middle of the grip.
    let radius: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let extend = guide.familyID == "triceps-extension"
        guard guide.equipment == "machine" else { return nil }
        if extend {
            guard guide.subtypeID == "machine", words.isSubset(of: ["lever", "triceps", "extension", "v", "2", "3"]) else { return nil }
        } else {
            guard guide.familyID == "biceps-curl", guide.subtypeID == nil || guide.subtypeID == "preacher", words.contains("curl"),
                  words.isSubset(of: ["lever", "bicep", "biceps", "curl", "preacher", "v", "2", "plate", "loaded", "hammer",
                                      "grip", "reverse"]) else { return nil }
        }
        upright = words.contains("hammer")
        over = extend || words.contains("reverse")
        guard let chair = MachineChair(body, lean: -6),
              let r = body.grip("r", radius: Self.gripRadius, square: upright ? 0 : 0.5),
              let l = body.grip("l", radius: Self.gripRadius, square: upright ? 0 : 0.5),
              let first = guide.keyframes.first?.pose,
              let rShoulder = body.head["humerus.r"], let rElbow = body.head["ulna.r"] else { return nil }
        self.body = body
        self.chair = chair
        grips = ["r": r, "l": l]
        let a = Self.slope * .pi / 180
        let along = V(0, -sin(a), -cos(a)), under = V(0, cos(a), -sin(a))
        self.along = along
        self.under = under
        let upper = (rElbow - rShoulder).length
        radius = body.reach("r", r, bend: 0) - upper

        let seated = chair.sit(first)
        var elbows: [String: V] = [:]
        var p = chair.pieces(back: false)
        for s in ["r", "l"] {
            guard let shoulder = seated.h["humerus.\(s)"] else { return nil }
            let elbow = shoulder + along * upper
            elbows[s] = elbow
            // A pad under the lower half of each upper arm, clear of the chest between them.
            let pad = shoulder + along * (upper * 0.5 + 0.13) + under * (0.05 + 0.03) + V(shoulder.x > 0 ? 0.015 : -0.015, 0, 0)
            p.append(Plan.box(pad, (0.14, 0.26, 0.06), z: under, .pad))
        }
        self.elbows = elbows
        guard let re = elbows["r"], let le = elbows["l"] else { return nil }
        let mid = (re + le) * 0.5
        // The pads' beam, on a post that stands between the knees, and the axle's two posts.
        let beam = mid - along * 0.1 + under * 0.14
        p.append(Plan.rod(beam - V(0.27, 0, 0), beam + V(0.27, 0, 0), 0.03, .metal))
        p.append(Plan.rod(beam, V(0, beam.y, 0.04), 0.035, .metal))
        for m in [-1.0, 1.0] {
            let x = m * (Self.armX + 0.05)
            p.append(Plan.box(V(x, mid.y, (mid.z + 0.04) / 2), (0.06, 0.06, mid.z + 0.04), .metal))
            p.append(Plan.box(V(x, mid.y + 0.25, 0.02), (0.07, 0.9, 0.04), .metal))
        }
        p.append(Plan.box(V(0, mid.y, 0.02), (2 * Self.armX + 0.16, 0.07, 0.04), .metal))
        fixed = p
    }

    /// The way the forearms point when the elbows are bent by `bend` degrees.
    func forearm(_ bend: Double) -> V { M.x(-bend) * along }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h, root) = chair.sit(pose)
        let bend = min(140, max(4, pose.angles["elbowFlex"] ?? 0))
        let reach = forearm(bend)
        guard let re = elbows["r"], let le = elbows["l"] else { return (body.made(g, h, floor: 0), []) }
        let mid = (re + le) * 0.5
        let bar = mid + reach * radius
        // Standing grips point out of the lever's plane, away from the lifter's face.
        let stand = M.x(-bend - 90) * along
        var p = [Plan.rod(mid - V(Self.armX, 0, 0), mid + V(Self.armX, 0, 0), 0.02, .metal)]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let elbow = elbows[s] else { continue }
            let at = elbow + reach * radius
            let across = upright ? stand * -1 : V(over ? -m : m, 0, 0)
            body.hold(s, grip, at: at, across: across, pole: along + under * 0.4, &g, h)
            let hinge = mid + V(-m * Self.armX, 0, 0), end = bar + V(-m * Self.armX, 0, 0)
            p.append(Plan.rod(hinge, end, 0.02, .metal))
            p.append(Plan.ball(end, 0.022, .metal))
            if upright {
                p.append(Plan.rod(at - stand * 0.07, at + stand * 0.07, Self.gripRadius, .dark))
            }
            // The plates, on the lever's far side from the hands.
            let peg = hinge - reach * 0.26
            p.append(Plan.rod(hinge, peg, 0.02, .metal))
            p.append(Plan.disc(peg + V(-m * 0.05, 0, 0), axis: V(1, 0, 0), radius: 0.12, thickness: 0.05, .plate))
        }
        p.append(Plan.rod(bar - V(Self.armX, 0, 0), bar + V(Self.armX, 0, 0), upright ? 0.014 : Self.gripRadius, upright ? .metal : .dark))
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), p)
    }
}

import Foundation

/// A hack squat: the back lies on a pad that slides on steep rails, the shoulders under two
/// pads on the same carriage, hands on the grips beside them, both feet flat on a plate fixed
/// at the foot of the rails. It is a leg press turned over: here the plate stays and the body
/// rides the carriage down and up as the knees bend and straighten.
struct MachineHackSquatStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let railX = 0.36, gripRadius = 0.015

    let body: Body3D
    /// How far the rails lean back from upright: 30 degrees for a hack squat, nearly flat for
    /// a sled that is squatted lying down.
    let lean: Double
    /// The legs' work, solved as a press with the plate square to the line of the back.
    let press: MachineLegPressStaging
    let grips: [String: HandGrip]
    /// From the solved press to the room with the plate on the floor.
    let lift: V
    /// Where the shoulder joints are on the carriage, in the solved press.
    let shoulders: [String: V]
    let far: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.equipment == "machine" else { return nil }
        let words = MachineStagings.words(guide)
        let lying = words.contains("lying")
        switch (guide.familyID, guide.subtypeID) {
        case ("leg-press", "hack"), ("squat", nil), ("squat", "sumo"):
            guard words.contains("squat"), !words.isDisjoint(with: ["hack", "pendulum"]) else { return nil }
        case ("leg-press", nil):
            guard words.isSuperset(of: ["sled", "lying", "squat"]) else { return nil }
        case ("calf-raise", nil):
            // The same carriage ridden with the legs long and only the ankles working.
            guard words.isSuperset(of: ["hack", "calf", "raise"]) || words.isSuperset(of: ["sled", "lying", "calf", "press"])
            else { return nil }
        default: return nil
        }
        let calves = guide.familyID == "calf-raise"
        // A pendulum squat swings its carriage on arms instead of sliding it on rails; the
        // body, the pads and the plate are the same.
        guard words.isSubset(of: ["sled", "lever", "leverage", "hack", "squat", "closer", "full", "legs", "form", "check", "wide",
                                  "linear", "pendulum", "plate", "loaded", "lying", "one", "single", "leg", "on", "machine",
                                  "calf", "raise", "press"])
        else { return nil }
        let lean = lying ? 78.0 : 30.0
        self.lean = lean
        var setup = MachineLegPressStaging.Setup()
        // The plate is square to the back pad and below it; the feet stand well in front of
        // the line of the hips, so the knees stay behind the toes.
        (setup.rise, setup.recline, setup.hipHeight, setup.high) = (-(90 - lean), lean, 1.0, lying ? 0.1 : 0.27)
        // One leg works; the other is held in front, just off the plate.
        setup.single = !words.isDisjoint(with: ["one", "single"])
        setup.free = (0.3, 0.3)
        if calves { (setup.calves, setup.apart, setup.turnout) = (true, 0.02, 8) }
        if words.contains("closer") { (setup.apart, setup.turnout) = (-0.015, 6) }
        if words.contains("wide") { (setup.apart, setup.turnout) = (0.15, 25) }
        guard let press = MachineLegPressStaging(guide, body, setup: setup),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.press = press
        grips = ["r": r, "l": l]
        far = press.far
        let rest = press.rest
        let seated = rest.settle(first).h
        guard let rs = seated["humerus.r"], let ls = seated["humerus.l"] else { return nil }
        shoulders = ["r": rs, "l": ls]

        // The plate's lower edge stands just off the floor.
        let plate = MachineLegPressStaging.plate
        let face = press.probe.plateLine(0)
        let low = (face - press.toes * (plate.tall / 2) + press.push * plate.thick).z
        let lift = V(0, 0, 0.05 - min(low, (face - press.toes * (plate.tall / 2)).z))
        self.lift = lift

        var p = [Plan.box(face + lift + press.push * (plate.thick / 2), (plate.wide, plate.tall, plate.thick), z: press.push, .dark)]
        // Two rails behind the pad, from the floor to above the carriage's highest place,
        // each on a post, with the plate braced to their feet.
        let line = rest.behind(0, 0.12) + lift
        let bottom = max((0.05 - line.z) / rest.up.z, -(far + 0.3)), top = far + 0.95
        for m in [-1.0, 1.0] {
            let a = line + rest.up * bottom + V(m * Self.railX, 0, 0), b = line + rest.up * top + V(m * Self.railX, 0, 0)
            p.append(Plan.rod(a, b, 0.025, .metal))
            p.append(Plan.box(V(b.x, b.y, b.z / 2), (0.06, 0.06, b.z), .metal))
            if a.z > 0.12 { p.append(Plan.box(V(a.x, a.y, a.z / 2), (0.06, 0.06, a.z), .metal)) }
            p.append(Plan.box(V(a.x, (a.y + b.y) / 2 - 0.25, 0.025), (0.07, abs(b.y - a.y) + 0.7, 0.05), .metal))
            p.append(Plan.rod(a, face + lift + press.push * 0.04 + V(m * Self.railX, 0, 0), 0.02, .metal))
        }
        let end = line + rest.up * top
        p.append(Plan.box(V(0, end.y, end.z), (2 * Self.railX + 0.06, 0.06, 0.06), .metal))
        fixed = p
    }

    /// Where each hand's grip is on the carriage, in the solved press: in front of the
    /// shoulder pad, outside the shoulder.
    func grip(_ s: String, _ m: Double) -> V {
        (shoulders[s] ?? press.rest.hip) + V(-m * 0.13, 0, 0) + press.rest.out * 0.2 + press.rest.up * 0.05
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let solved = press.solve(pose)
        // The plate stays, so the carriage and the body on it go the other way.
        let move = lift - press.push * solved.travel
        var g = solved.frame.rotations.mapValues { M($0) }
        var h = solved.frame.heads.mapValues { V($0) }
        guard let root = h["pelvis"] else { return (solved.frame, []) }
        for (key, at) in h { h[key] = at + move }
        let rest = press.rest
        var p = [rest.backPad(from: 0.02, to: 0.6),
                 rest.backPad(from: 0.62, to: 0.84, width: 0.26, thick: 0.07 + MachineFit.back - MachineFit.head,
                              proud: MachineFit.back - MachineFit.head)]
        let spineLow = rest.behind(0.05, 0.12), spineHigh = rest.behind(0.8, 0.12)
        p.append(Plan.box((spineLow + spineHigh) * 0.5, (2 * Self.railX + 0.08, (spineHigh - spineLow).length, 0.05), z: rest.out, .metal))
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let shoulder = shoulders[s] else { continue }
            // A pad on the muscle over each shoulder, on an arm from the carriage.
            let pad = V(-m * 0.15, shoulder.y, shoulder.z) + rest.up * 0.085 + rest.out * 0.02
            p.append(Plan.box(pad, (0.11, 0.07, 0.2), x: V(1, 0, 0), z: rest.out, .pad))
            p.append(Plan.rod(pad + rest.up * 0.04, rest.behind((pad - rest.hip).dot(rest.up) + 0.04, 0.1, x: pad.x), 0.02, .metal))
            // The grip stands out in front of the pad.
            let at = grip(s, m)
            p.append(Plan.rod(pad + rest.up * 0.04 + rest.out * 0.08 + V(-m * 0.06, 0, 0), at - rest.out * 0.07, 0.012, .metal))
            p.append(Plan.rod(at - rest.out * 0.07, at + rest.out * 0.07, Self.gripRadius, .dark))
            if let hand = grips[s] {
                body.hold(s, hand, at: at + move, across: rest.out * -1, pole: V(-m * 0.6, 0.2, -1), &g, h)
            }
            // The carriage's sleeve on its rail, and the plates it carries behind the pad.
            let sleeve = rest.behind(0.45, 0.12, x: m * Self.railX)
            p.append(Plan.rod(sleeve - rest.up * 0.14, sleeve + rest.up * 0.14, 0.04, .dark))
            let horn = rest.behind(0.5, 0.12, x: m * (Self.railX + 0.05))
            p.append(Plan.rod(horn, horn + V(m * 0.2, 0, 0), 0.025, .metal))
            p.append(Plan.disc(horn + V(m * 0.1, 0, 0), axis: V(1, 0, 0), radius: 0.2, thickness: 0.07, .plate))
        }
        h = body.place(g, root: root + move)
        return (body.made(g, h, floor: 0), p.map { MachineSmithStaging.moved($0, by: move) })
    }
}

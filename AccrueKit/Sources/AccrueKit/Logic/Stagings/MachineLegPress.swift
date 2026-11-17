import Foundation

/// A leg press: the back on a reclined pad, the hips in the corner of the seat, both feet flat
/// on a plate that slides away along its rails as the legs straighten and comes back as the
/// knees bend. The hips and the back never move; the plate goes wherever the feet push it.
/// The same machine with the legs kept long and only the ankles working is a calf press.
struct MachineLegPressStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Which press this is.
    struct Setup: Sendable, Equatable {
        /// How steeply the rails climb away from the seat, in degrees: 45 for a sled, level
        /// for a seated press.
        var rise = 45.0
        /// How far the back pad lies back from upright.
        var recline = 60.0
        var hipHeight = 0.48
        /// How far outside its hip each foot stands, and how far the toes turn out.
        var apart = 0.05, turnout = 15.0
        /// How far above the line of the hips the ankles are on the plate.
        var high = 0.03
        /// A calf press: legs long, the balls of the feet on the plate's lower edge.
        var calves = false
        /// Only the right leg presses; the left is held off the plate.
        var single = false
        /// Each leg has its own plate, and the left keeps its plate at legs' length
        /// while the right one works.
        var alternate = false
        /// Where the leg that does not press keeps its ankle, from its hip joint: along the
        /// rails and across them.
        var free = (push: 0.34, toes: -0.36)

        static func == (a: Setup, b: Setup) -> Bool {
            a.rise == b.rise && a.recline == b.recline && a.hipHeight == b.hipHeight && a.apart == b.apart
                && a.turnout == b.turnout && a.high == b.high && a.calves == b.calves && a.single == b.single
                && a.alternate == b.alternate && a.free.push == b.free.push && a.free.toes == b.free.toes
        }
    }

    static let plate = (wide: 0.7, tall: 0.52, thick: 0.03)
    static let railX = 0.42, railDrop = 0.36, gripRadius = 0.015

    let body: Body3D
    let setup: Setup
    let rest: MachineRest
    let range: MachineRange
    let grips: [String: HandGrip]
    /// Along the rails away from the seat, and up the plate from heel to toe.
    let push: V, toes: V
    /// Each foot flat on the plate: its rotation, where the ball of the foot is with the plate
    /// drawn right up to the hips, and the handle that side's hand holds.
    let flat: [String: M]
    let balls: [String: V]
    let handles: [String: V]
    /// How far the plate is along the rails with the legs long.
    let far: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let setup = Self.setup(for: guide) else { return nil }
        self.init(guide, body, setup: setup)
    }

    /// The press set up as `setup` says, whatever the exercise is called: other machines that
    /// press with the legs (a hack squat) are built on it.
    init?(_ guide: HowToGuide, _ body: Body3D, setup: Setup) {
        guard let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let hipL = body.head["femur.l"], let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        self.setup = setup
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, setup.calves ? "ankleDorsi" : "kneeFlex")
        let hip = V(0, 0, setup.hipHeight)
        let rest = MachineRest(body, hip: hip, lean: setup.recline)
        self.rest = rest
        let a = setup.rise * .pi / 180
        let push = V(0, -cos(a), sin(a)), toes = V(0, sin(a), cos(a))
        self.push = push
        self.toes = toes

        var flat: [String: M] = [:], balls: [String: V] = [:], handles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let ankle = body.head["foot.\(s)"], let ball = body.head["toes.\(s)"], let tip = body.tail["toes.\(s)"]
            else { return nil }
            // The foot already points a little outward at rest.
            let heading = atan2(-m * (tip.x - ankle.x), -(tip.y - ankle.y)) * 180 / .pi
            let foot = M.x(-(90 + setup.rise)) * M.z(-m * (setup.turnout - heading))
            flat[s] = foot
            let side = -m * (hipL.x - pelvis.x + setup.apart)
            balls[s] = hip + V(side, 0, 0) + toes * setup.high + foot * (ball - ankle)
            // A post beside each hip, standing square to the seat.
            handles[s] = hip + V(-m * 0.29, 0, 0) + push * 0.03 - toes * 0.02
        }
        self.flat = flat
        self.balls = balls
        self.handles = handles

        // The machine is as long as the legs: found from the loop's longest reach.
        let probe = Probe(body: body, setup: setup, rest: rest, range: range, push: push, toes: toes, flat: flat, balls: balls)
        far = guide.keyframes.map { probe.travel($0.pose) }.max() ?? 0.7
        fixed = Self.frame(setup, rest: rest, push: push, toes: toes, handles: handles, far: far)
    }

    /// Which leg press the name describes, or nil for one this machine does not show honestly.
    static func setup(for guide: HowToGuide) -> Setup? {
        let words = MachineStagings.words(guide)
        var setup = Setup()
        let known: Set<String>
        switch guide.familyID {
        case "leg-press":
            guard guide.subtypeID == nil, words.contains("press") else { return nil }
            known = ["sled", "lever", "45", "degrees", "angled", "leg", "press", "side", "back", "pov", "seated",
                     "horizontal", "wide", "narrow", "stance", "glute", "dominant", "v", "2",
                     "one", "single", "alternate", "alternating", "negative", "outdoor", "vertical"]
        case "calf-raise":
            guard guide.subtypeID == nil || guide.subtypeID == "seated", words.contains("press") else { return nil }
            known = ["sled", "lever", "45", "degrees", "calf", "press", "on", "leg", "seated", "v", "2",
                     "one", "single", "squat", "raise", "machine"]
            setup.calves = true
            setup.turnout = 8
            setup.apart = 0.02
        case "squat", "single-leg-squat":
            // A seated squat machine: upright against the back pad, pushing a plate that is
            // below the hips and in front of them.
            guard guide.subtypeID == nil || guide.subtypeID == "sumo", words.isSuperset(of: ["lever", "seated", "squat"])
            else { return nil }
            known = ["lever", "seated", "squat", "wide", "one", "leg"]
            (setup.rise, setup.recline, setup.hipHeight) = (-20, 18, 0.85)
        default: return nil
        }
        guard words.isSubset(of: known) else { return nil }
        setup.alternate = !words.isDisjoint(with: ["alternate", "alternating"])
        setup.single = !setup.alternate && !words.isDisjoint(with: ["one", "single"])
        if words.contains("vertical") {
            // Lying under the plate, which goes straight up.
            (setup.rise, setup.recline, setup.hipHeight) = (90, 90, 0.25)
        }
        // "Side" and "back" are only known as the camera's place, never as a way to press.
        if !words.isDisjoint(with: ["side", "back"]), !words.contains("pov") { return nil }
        if !words.isDisjoint(with: ["seated", "horizontal"]), !words.contains("squat") || setup.calves {
            // A seated press: the plate straight ahead, the seat back nearer upright.
            setup.rise = 0
            setup.recline = 28
            setup.hipHeight = 0.54
        }
        if words.contains("wide") { (setup.apart, setup.turnout) = (0.17, 28) }
        if words.contains("narrow") { (setup.apart, setup.turnout) = (-0.015, 6) }
        if words.contains("glute") { setup.high = 0.13 }
        return setup
    }

    /// The part of the staging that finds the body, apart from the frame that is built from it.
    struct Probe: Sendable {
        let body: Body3D
        let setup: Setup
        let rest: MachineRest
        let range: MachineRange
        let push: V, toes: V
        let flat: [String: M]
        let balls: [String: V]

        /// How far the heels are off the plate, in degrees about the balls of the feet. A calf
        /// press works through it, below the plate's edge and above; a leg press keeps the
        /// heels down unless they lift by mistake.
        func heel(_ pose: JointPose) -> Double {
            if setup.calves { return -(pose.angles["ankleDorsi"] ?? 0) }
            return min(30, max(0, -range.off("ankleDorsi", pose) - 3))
        }

        /// One foot on the plate with its heel raised by `heel`: its rotation, and the ankle
        /// joint from the ball of the foot.
        func foot(_ s: String, heel: Double) -> (turn: M, toAnkle: V) {
            guard let flat = flat[s], let ankle = body.head["foot.\(s)"], let ball = body.head["toes.\(s)"],
                  let tip = body.tail["toes.\(s)"] else { return (.identity, V(0, 0, 0)) }
            let along = flat * (tip - ball)
            let turn = M.axis((push * -1).cross(along), heel) * flat
            return (turn, turn * (ankle - ball))
        }

        /// How far along the rails the plate is for this pose: where the legs' bend puts the feet.
        func travel(_ pose: JointPose, hips: [String: V]? = nil) -> Double {
            let h = hips ?? rest.settle(pose).h
            guard let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"] else { return 0 }
            let heel = heel(pose)
            var sum = 0.0, n = 0.0
            for (s, key) in [("r", "kneeFlex"), ("l", "kneeFlexL")] {
                guard let hip = h["femur.\(s)"], let ball = balls[s] else { continue }
                // A calf press keeps the legs long whatever the seated calf raise's keyframes
                // say of the knees, unless they bend to help.
                let bend = setup.calves ? 8 + max(0, range.off("kneeFlex", pose))
                    : pose.angles[key] ?? pose.angles["kneeFlex"] ?? 0
                let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: max(1, bend))
                let o = ball + foot(s, heel: heel).toAnkle - hip
                let along = o.dot(push)
                sum += -along + max(0, along * along - o.dot(o) + leg * leg).squareRoot()
                n += 1
            }
            return n > 0 ? sum / n : 0
        }

        /// The middle of the plate's face for a plate `travel` along the rails.
        func plateLine(_ travel: Double) -> V {
            guard let r = balls["r"], let l = balls["l"], let ball = body.head["toes.r"], let tip = body.tail["toes.r"]
            else { return rest.hip }
            // The ball of the foot is a finger's width above the sole.
            let lift = ball.z - (tip.z - 0.01)
            let mid = (r + l) * 0.5 + push * (travel + lift)
            // A leg press has the whole foot on the plate; a calf press only its front, so
            // the heels hang off the lower edge.
            return mid + toes * (setup.calves ? MachineLegPressStaging.plate.tall / 2 - 0.04 : -0.06)
        }
    }

    var probe: Probe {
        Probe(body: body, setup: setup, rest: rest, range: range, push: push, toes: toes, flat: flat, balls: balls)
    }

    /// The seat, the pads, the rails and the handles.
    static func frame(_ setup: Setup, rest: MachineRest, push: V, toes: V, handles: [String: V], far: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        let hip = rest.hip
        // The back pad, a rest for the head, and the seat square to the rails, so the thighs
        // lie along it when the legs are long.
        p.append(rest.backPad(from: -0.17, to: 0.66))
        p.append(rest.backPad(from: 0.68, to: 0.9, width: 0.26, thick: 0.07 + MachineFit.back - MachineFit.head,
                              proud: MachineFit.back - MachineFit.head))
        let seat = hip - toes * (MachineFit.seat + 0.035) + push * 0.06
        p.append(Plan.box(seat, (0.4, 0.34, 0.07), z: toes, .pad))
        // What holds them: a spine under the pads down to two runners on the floor.
        let low = rest.behind(-0.1, 0.1), high = rest.behind(0.6, 0.1)
        p.append(Plan.box((low + high) * 0.5, (0.08, (high - low).length + 0.1, 0.06), z: rest.out, .metal))
        let under = seat - toes * 0.065
        p.append(Plan.box(under, (0.08, 0.3, 0.06), z: toes, .metal))
        for at in [high, under, low] where at.z > 0.12 {
            p.append(Plan.box(V(0, at.y, at.z / 2), (0.07, 0.07, at.z), .metal))
        }
        // The rails the plate's carriage runs on, either side of the legs and under the feet.
        let base = hip - toes * railDrop
        let from = 0.16, to = far + 0.55
        var ends: [V] = []
        let back = high.y + 0.1
        for x in [-railX, railX] {
            let a = base + push * from + V(x, 0, 0), b = base + push * to + V(x, 0, 0)
            p.append(Plan.rod(a, b, 0.025, .metal))
            ends.append(b)
            // A post under each end, and a runner along the floor.
            for end in [a, b] { p.append(Plan.rod(V(x, end.y, 0), end + V(0, 0, 0.03), 0.03, .metal)) }
            p.append(Plan.box(V(x, (back + b.y) / 2, 0.025), (0.07, back - b.y, 0.05), .metal))
        }
        if let a = ends.first, let b = ends.last { p.append(Plan.rod(a, b, 0.025, .metal)) }
        for y in [high.y, under.y, low.y] { p.append(Plan.box(V(0, y, 0.025), (2 * railX, 0.07, 0.05), .metal)) }
        // A seated press lifts a weight stack beyond the plate; a sled carries its own plates.
        if abs(push.z) < 0.1 {
            let y = (base + push * to).y - 0.12
            p.append(Plan.box(V(0, y, 0.6), (0.3, 0.14, 1.2), .dark))
            p.append(Plan.box(V(0, y, 0.6), (0.4, 0.06, 1.24), .metal))
        }
        // A post beside each hip to hold on to.
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let at = handles[s] else { continue }
            p.append(Plan.rod(at - toes * 0.065, at + toes * 0.065, gripRadius, .dark))
            let foot = at - toes * 0.065
            p.append(Plan.rod(foot, foot - toes * 0.06 + V(m * 0.06, 0, 0), 0.012, .metal))
            p.append(Plan.rod(foot - toes * 0.06 + V(m * 0.06, 0, 0), seat - toes * 0.02 + V(-m * 0.18, 0, 0), 0.012, .metal))
        }
        return p
    }

    /// The posed body, and how far the plate is along the rails.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, travel: Double) {
        var (g, h) = rest.settle(pose)
        let root = h["pelvis"] ?? rest.hip
        let probe = probe
        let travel = probe.travel(pose, hips: h)
        let heel = probe.heel(pose)
        // Knees track over the toes; knees that cave in point inside them.
        let turn = min(60, max(-25, setup.turnout + (setup.calves ? 0 : range.off("hipAbd", pose) + range.off("hipRot", pose))))
        let k = turn * .pi / 180
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let ball = balls[s] else { continue }
            if s == "l", setup.single, let hip = h["femur.l"] {
                // The leg that rests: its foot on the floor in front of a seat that stands on
                // the floor, or tucked off the plate with the knee up.
                if abs(setup.rise) < 1 {
                    let out = (body.head["femur.l"]?.x ?? 0.09) - (body.head["pelvis"]?.x ?? 0)
                    body.plant(s, ankle: V(out + 0.05, rest.hip.y - 0.36, body.ankleHeight), foot: .identity, pole: V(0, -0.3, 1), &g, h)
                } else {
                    body.plant(s, ankle: hip + push * setup.free.push + toes * setup.free.toes, foot: flat[s] ?? .identity,
                               pole: toes + push * 0.3, &g, h)
                }
                continue
            }
            // A leg with its own plate holds it at legs' length while the other works.
            let own = s == "l" && setup.alternate ? far : travel
            let foot = probe.foot(s, heel: s == "l" && setup.alternate ? 0 : heel)
            body.plant(s, ankle: ball + push * own + foot.toAnkle, foot: foot.turn,
                       pole: toes * cos(k) + V(-m * sin(k), 0, 0), &g, h)
            // The toes stay flat on the plate when the heel comes up.
            if let flat = flat[s] { g["toes.\(s)"] = flat }
        }
        h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let at = handles[s] else { continue }
            body.hold(s, grip, at: at, across: toes * -1, pole: V(-m * 0.5, 1, -0.6), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), travel)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, travel) = solve(pose)
        return (frame, carriage(travel))
    }

    /// The plate and the carriage that carries it along the rails.
    func carriage(_ travel: Double) -> [PropPiece] {
        if setup.alternate { return half(1, travel) + half(-1, far) }
        let face = probe.plateLine(travel)
        let size = Self.plate
        var p = [Plan.box(face + push * (size.thick / 2), (size.wide, size.tall, size.thick), z: push, .dark)]
        p.append(Plan.box(face + push * (size.thick + 0.03), (size.wide - 0.1, 0.07, 0.06), z: push, .metal))
        // Sleeves on the rails behind the plate, braced to its back, with the weight on horns.
        let along = (face - rest.hip).dot(push) + 0.12
        for m in [-1.0, 1.0] {
            let sleeve = rest.hip - toes * Self.railDrop + push * along + V(m * Self.railX, 0, 0)
            p.append(Plan.rod(sleeve - push * 0.13, sleeve + push * 0.13, 0.036, .dark))
            let brace = face + push * (size.thick + 0.03) + V(m * (size.wide / 2 - 0.08), 0, 0)
            p.append(Plan.rod(sleeve, brace, 0.022, .metal))
            p.append(Plan.rod(sleeve, brace - toes * (size.tall / 2 - 0.06) - push * 0.03, 0.022, .metal))
        }
        // A sled carries its own plates, on a horn behind the footplate where they hide nothing.
        if abs(push.z) > 0.1 {
            let horn = face + push * (size.thick + 0.06)
            p.append(Plan.rod(horn, horn + push * 0.3, 0.025, .metal))
            for k in 0..<3 {
                p.append(Plan.disc(horn + push * (0.06 + 0.075 * Double(k)), axis: push, radius: 0.225, thickness: 0.07, .plate))
            }
            p.append(Plan.disc(horn + push * 0.265, axis: push, radius: 0.03, thickness: 0.03, .metal))
        }
        return p
    }

    /// One leg's own plate on its own sleeve, for a press whose legs work one at a time.
    func half(_ m: Double, _ travel: Double) -> [PropPiece] {
        let size = Self.plate
        let face = probe.plateLine(travel) + V(-m * 0.185, 0, 0)
        var p = [Plan.box(face + push * (size.thick / 2), (0.34, size.tall, size.thick), z: push, .dark)]
        let along = (face - rest.hip).dot(push) + 0.12
        let sleeve = rest.hip - toes * Self.railDrop + push * along + V(-m * Self.railX, 0, 0)
        p.append(Plan.rod(sleeve - push * 0.13, sleeve + push * 0.13, 0.036, .dark))
        let brace = face + push * (size.thick + 0.02) + V(-m * 0.08, 0, 0)
        p.append(Plan.rod(sleeve, brace, 0.022, .metal))
        p.append(Plan.rod(sleeve, brace - toes * (size.tall / 2 - 0.06), 0.022, .metal))
        if push.z > 0.1 {
            let horn = face + push * (size.thick + 0.02)
            p.append(Plan.rod(horn, horn + push * 0.2, 0.025, .metal))
            p.append(Plan.disc(horn + push * 0.1, axis: push, radius: 0.16, thickness: 0.07, .plate))
        }
        return p
    }
}

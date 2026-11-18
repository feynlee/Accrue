import Foundation

/// Standing or kneeling at a cable stack: pushdown, face pull, cable curl, cable fly, woodchop, and the rest of the pulldown and seated row families.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum CableStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        guard guide.equipment == "cable-stack" else { return nil }
        let name = guide.exerciseName
        let said = words(name)
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }

        switch guide.familyID {
        case "triceps-extension":
            // Standing at the high pulley with both hands on one handle, pushing it straight
            // down. Lying, kneeling, overhead, one arm and across the body are other pictures.
            if guide.subtypeID == "lying" {
                // Lying on a bench with the low pulley beyond the head, both hands on one
                // handle. The floor, an incline and the pullover are other pictures.
                guard said.isSubset(of: ["cable", "lying", "triceps", "extension", "with", "rope", "low"]) else { return nil }
                return StandingCableStaging(guide, body, move: .lyingExtension, handle: said.contains("rope") ? .rope : .bar,
                                            on: .supine(tilt: 0))
            }
            guard guide.subtypeID == nil, has("pushdown", "push down") else { return nil }
            // One arm alone on a stirrup, the other hanging.
            if ["cable one arm tricep pushdown", "cable standing one arm triceps pushdown (overhand grip)"].contains(name) {
                return StandingCableStaging(guide, body, move: .pushdown, handle: .stirrup)
            }
            if has("incline", "floor", "one arm", "single arm", "side", "kneeling", "seated", "cross") { return nil }
            let reverse = has("reverse", "underhand", "supinated")
            let handle: StandingCableStaging.Handle = said.contains("rope") ? .rope
                : has("v-bar", "v bar") ? .vBar : said.contains("sz") || said.contains("ez") ? .ezBar : .bar
            // Palms up is a grip for a bar, not for a rope or a V.
            if reverse, handle == .rope || handle == .vBar { return nil }
            return StandingCableStaging(guide, body, move: .pushdown, handle: handle, underhand: reverse)
        case "biceps-curl":
            // Standing square to a low pulley and curling one handle with both hands: only the
            // names that say no more than the handle and the grip. One arm, seated, lying,
            // squatting, the bench and the drag are other pictures.
            if ["cable one arm curl", "cable unilateral bicep curl", "cable reverse one arm curl"].contains(name) {
                // One arm alone on a stirrup, the other hanging.
                return StandingCableStaging(guide, body, move: .curl, handle: .stirrup, underhand: !said.contains("reverse"))
            }
            if guide.subtypeID == "overhead", said.isSubset(of: ["cable", "lying", "close", "regular", "grip", "bicep", "curl"]), said.contains("lying") {
                // Lying on a bench with the feet toward the low wheel, the bar curled from over
                // the thighs to the shoulders.
                return StandingCableStaging(guide, body, move: .curl, handle: .bar, underhand: true, close: said.contains("close"),
                                            on: .supine(tilt: 0))
            }
            if guide.subtypeID == "incline", ["cable incline biceps curl", "cable seated incline curl", "cable two arm curl on incline bench"].contains(name) {
                // Lying back on an incline bench between two low wheels, a stirrup in each hand.
                return CableHandlesStaging(guide, body, on: .supine(tilt: 50), pulleys: .low)
            }
            guard [nil, "hammer", "reverse"].contains(guide.subtypeID),
                  said.isSubset(of: ["cable", "standing", "seated", "biceps", "bicep", "curl", "close", "grip", "reverse", "hammer",
                                     "with", "rope", "attachment", "sz", "ez", "straight", "bar"]) else { return nil }
            // Seated is the same curl from the end of a bench that faces the low pulley.
            let seat: PostureStaging.Support? = said.contains("seated") ? .seat(back: false) : nil
            if said.contains("rope") || said.contains("hammer") {
                // A rope is held with the palms facing each other whatever the name adds.
                return said.contains("reverse") ? nil : StandingCableStaging(guide, body, move: .curl, handle: .rope, on: seat)
            }
            return StandingCableStaging(guide, body, move: .curl, handle: said.contains("sz") || said.contains("ez") ? .ezBar : .bar,
                                        underhand: !said.contains("reverse"), close: said.contains("close"), on: seat)
        case "lat-pulldown" where guide.subtypeID == "kneeling":
            // On both knees under a high wheel, one arm pulling a stirrup down beside the shoulder.
            guard ["cable kneeling one arm lat pulldown", "cable kneeling single lat pulldown"].contains(name) else { return nil }
            return SeatedRowGripStaging(guide, body, handle: .single, seat: .knees, from: .overhead)
        case "lat-pulldown":
            // Seated at the pulldown machine with both hands on one handle, pulling it down in
            // front of the face: only the names that say no more than the grip. Behind the neck,
            // one arm, ropes, twists, kneeling and the floor are other pictures.
            guard guide.subtypeID == nil,
                  said.isSubset(of: ["cable", "bar", "lateral", "lat", "pulldown", "pro", "wide", "grip", "close", "front",
                                     "underhand", "reverse", "narrow", "twin", "handle", "parallel", "neutral", "with",
                                     "v", "full", "range", "of", "motion"]) else { return nil }
            let narrow = said.contains("narrow") || said.contains("close"), wide = said.contains("wide")
            if said.contains("v") {
                return PulldownGripStaging(guide, body, grip: .neutral, handle: .vHandle, halfGrip: 0)
            }
            if said.contains("neutral") || said.contains("parallel") {
                return PulldownGripStaging(guide, body, grip: .neutral, handle: .parallelBar, halfGrip: wide ? 0.32 : narrow ? 0.14 : 0.22)
            }
            if said.contains("underhand") || said.contains("reverse") {
                return PulldownGripStaging(guide, body, grip: .under, handle: .latBar, halfGrip: narrow ? 0.1 : wide ? 0.3 : 0.19)
            }
            return PulldownGripStaging(guide, body, grip: .over, handle: .latBar,
                                       halfGrip: narrow ? 0.12 : wide ? 0.41 : PulldownStaging.halfGrip)
        case "row":
            // Seated on the row bench with the feet on the plates and both hands on one handle
            // from the low pulley. High pulleys, the floor, one arm, twists, standing and
            // kneeling are other pictures.
            guard guide.subtypeID == "seated" else { return nil }
            // The other seats and pulleys, each by its own name: a high wheel pulled down to
            // the chest, the floor with the legs out, and the knees.
            switch name {
            case "cable seated high row (v-bar)":
                return SeatedRowGripStaging(guide, body, handle: .close, from: .high)
            case "cable reverse-grip straight back seated high row":
                return SeatedRowGripStaging(guide, body, handle: .barUnder, halfGrip: 0.19, from: .high)
            case "cable rope elevated seated row":
                return SeatedRowGripStaging(guide, body, handle: .rope, from: .high)
            case "cable high row (kneeling)":
                return SeatedRowGripStaging(guide, body, handle: .rope, seat: .knees, from: .high)
            case "cable floor seated wide-grip row":
                return SeatedRowGripStaging(guide, body, handle: .barOver, halfGrip: 0.36, seat: .floor)
            case "cable seated on floor row with rope":
                return SeatedRowGripStaging(guide, body, handle: .rope, seat: .floor)
            case "cable seated row (bent bar)":
                return SeatedRowGripStaging(guide, body, handle: .barOver, halfGrip: 0.27, bent: true)
            // One arm alone on a stirrup: on the bench, or on the knees.
            case "cable seated single arm lats focused row", "cable one arm twisting seated row", "cable sitting bench single arm twisting row":
                return SeatedRowGripStaging(guide, body, handle: .single)
            case "cable kneeling one arm row", "cable kneeling single arm horizontal row":
                return SeatedRowGripStaging(guide, body, handle: .single, seat: .knees)
            case "cable one arm straight back high row (kneeling)":
                return SeatedRowGripStaging(guide, body, handle: .single, seat: .knees, from: .high)
            default:
                break
            }
            guard said.isSubset(of: ["cable", "seated", "row", "low", "straight", "back", "with", "v", "bar", "lats", "focused",
                                     "wide", "grip", "supine", "rope"]) else { return nil }
            if said.contains("rope") { return SeatedRowGripStaging(guide, body, handle: .rope) }
            if said.contains("supine") { return SeatedRowGripStaging(guide, body, handle: .barUnder, halfGrip: 0.19) }
            if said.contains("wide") { return SeatedRowGripStaging(guide, body, handle: .barOver, halfGrip: 0.36) }
            // Every other name here is the starter row over again: the close handle to the belly.
            return SeatedRowStaging(guide, body)
        case "front-raise", "upright-row":
            // Lying on a bench with the feet toward the low wheel, a bar raised or rowed up from
            // over the thighs with the palms down. The keyframes carry the arms.
            let bars = ["cable lying front raise": StandingCableStaging.Handle.bar, "cable lying upright row": .bar,
                        "cable lying upright row (sz bar)": .ezBar]
            guard let bar = bars[name] else { return nil }
            return StandingCableStaging(guide, body, move: .curl, handle: bar, on: .supine(tilt: 0))
        case "shrug":
            // Sitting at the row with the arms long: only the shoulder blades draw the handle back.
            guard guide.subtypeID == "retraction", ["cable seated scapular retraction", "cable seated horizontal shrug"].contains(name) else { return nil }
            return SeatedRowGripStaging(guide, body, handle: .close)
        case "pallof-anti-rotation":
            // Side-on to a pulley at chest height, the handle pressed straight out from the
            // breastbone: standing, or on one knee. Pressing overhead, a chop and lying down
            // are other pictures.
            switch name {
            case "cable horizontal pallof press":
                return CablePallofStaging(guide, body)
            case "cable split stance horizontal pallof press":
                return CablePallofStaging(guide, body, stagger: 0.35)
            case "cable half kneeling pallof press":
                return CablePallofStaging(guide, body, on: .kneel(half: true))
            case "cable half kneeling adductor pallof press":
                return CablePallofStaging(guide, body, on: .kneel(half: true), byRaisedKnee: true)
            default:
                return nil
            }
        case "crunch-sit-up":
            // On both knees under the high pulley, the rope held beside the head.
            guard guide.subtypeID == "kneeling-cable" else { return nil }
            if said == ["cable", "kneeling", "crunch"] { return CableCrunchStaging(guide, body, on: .kneel(half: false)) }
            // Sitting, the same keyframes fold the chest into the thighs.
            return nil
        case "bench-press":
            // A handle in each hand between two pulleys: sitting upright with the wheels at
            // chest height behind, or lying on a bench with them near the floor either side.
            // One arm, a ball and a decline are other pictures.
            switch guide.subtypeID {
            case "seated" where said == ["cable", "seated", "chest", "press"]:
                return CableHandlesStaging(guide, body, on: .seat(back: true), pulleys: .chest)
            case "incline" where said == ["cable", "incline", "bench", "press"]:
                return CableHandlesStaging(guide, body, on: .supine(tilt: 30), pulleys: .low)
            case "standing" where said.isSubset(of: ["cable", "bench", "press", "lying", "close"]) && has("bench", "lying"):
                return CableHandlesStaging(guide, body, on: .supine(tilt: 0), pulleys: .low)
            default:
                return nil
            }
        case "overhead-press":
            // On both knees between two low pulleys, a handle pressed up in each hand.
            guard guide.subtypeID == nil, said == ["cable", "kneeling", "shoulder", "press"] else { return nil }
            return CableHandlesStaging(guide, body, on: .kneel(half: false), pulleys: .low)
        case "chest-fly" where guide.subtypeID != "cable-standing":
            // The fly done on a bench between the stacks: lying or on an incline with the wheels
            // low, or sitting upright with them at chest height.
            if guide.subtypeID == nil, said == ["cable", "lying", "fly"] { return CableHandlesStaging(guide, body, on: .supine(tilt: 0), pulleys: .low) }
            if guide.subtypeID == nil, said == ["cable", "incline", "fly"] { return CableHandlesStaging(guide, body, on: .supine(tilt: 30), pulleys: .low) }
            if guide.subtypeID == "pec-deck", said == ["cable", "seated", "chest", "fly"] {
                return CableHandlesStaging(guide, body, on: .seat(back: true), pulleys: .chest)
            }
            return nil
        case "chest-fly":
            // Standing between two high pulleys with a handle in each hand, hugging them
            // together in front. One arm, low pulleys, kneeling and alternating are other pictures.
            guard guide.subtypeID == "cable-standing" else { return nil }
            // The same hug from the high pulleys down, on both knees.
            if said == ["cable", "kneeling", "high", "to", "low", "fly"] { return CableFlyStaging(guide, body, on: .kneel(half: false)) }
            // One arm alone, the other hanging.
            if name == "cable standing single arm fly" { return CableFlyStaging(guide, body, oneArm: true) }
            guard said.isSubset(of: ["cable", "standing", "fly", "crossover", "crossovers", "cross", "over", "variation",
                                     "neutral", "grip", "up", "straight"]) else { return nil }
            return CableFlyStaging(guide, body)
        case "face-pull":
            // Square to a pulley at face height with both hands on the rope: standing, sitting
            // on the end of a bench, or on the knees.
            guard guide.subtypeID == nil, !has("one arm", "single arm", "supinated", "lying") else { return nil }
            let rest = said.subtracting(["cable", "face", "pull", "with", "rope", "external", "rotation"])
            if rest == ["seated"] { return FacePullStaging(guide, body, on: .seat(back: false)) }
            if rest == ["kneeling"] || rest == ["half", "kneeling"] { return FacePullStaging(guide, body, on: .kneel(half: rest.contains("half"))) }
            guard has("standing") || rest.isEmpty, !has("seated", "kneeling") else { return nil }
            return FacePullStaging(guide, body)
        default:
            return nil
        }
    }

    /// The words of an exercise name: "cable pushdown (with rope attachment)" is cable, pushdown,
    /// with, rope, attachment.
    static func words(_ name: String) -> Set<String> {
        Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

/// What the cable stagings share: feet that stay planted, the pulley a cable runs over, and the
/// small parts every handle hangs from.
enum CableKit {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The pulley wheel's size, as `stackFrame` draws the one over the stack.
    static let wheel = 0.055, wheelThickness = 0.025, cable = 0.004

    /// Two feet flat on the floor, where the first pose of the loop puts them under the hips.
    /// The body stands on them all loop long: the hips move over the feet as the knees and the
    /// trunk bend, and the feet never slide or tip.
    struct Stance: Sendable {
        let ankles: [String: V]
        let feet: [String: M]

        /// `toeOut` turns each foot outward (degrees); `stagger` puts the left foot that far
        /// ahead of the right.
        init(_ body: Body3D, first pose: JointPose, toeOut: Double = 7, stagger: Double = 0) {
            let g = body.rotations(pose)
            let rel = body.place(g, root: V(0, 0, 0))
            let r = rel["foot.r"] ?? V(-0.08, 0, 0), l = rel["foot.l"] ?? V(0.08, 0, 0)
            let z = body.ankleHeight
            ankles = ["r": V(r.x, stagger / 2, z), "l": V(l.x, -stagger / 2, z)]
            feet = ["r": M.z(-toeOut), "l": M.z(toeOut)]
        }

        /// How far ahead of the ankles the body's weight rests: over the arch of the foot.
        static let arch = 0.06

        /// Stands the posed body on the feet: carries the hips where the keyframes' own legs
        /// would, then shifts them until the body's weight is over the feet (a trunk that
        /// leans forward sends the hips back), poses both legs to reach the ankles, and
        /// returns the bone heads.
        func stand(_ body: Body3D, _ g: inout [String: M]) -> (root: V, heads: [String: V]) {
            let rel = body.place(g, root: V(0, 0, 0))
            var sum = V(0, 0, 0), middle = 0.0, n = 0.0
            for s in ["r", "l"] {
                guard let ankle = ankles[s], let own = rel["foot.\(s)"] else { continue }
                sum = sum + (ankle - own)
                middle += ankle.y
                n += 1
            }
            guard n > 0 else { return (V(0, 0, 0.9), body.place(g, root: V(0, 0, 0.9))) }
            var root = sum * (1 / n)
            let weight = body.balance(g, body.place(g, root: root))
            root.y += min(0.3, max(-0.3, middle / n - Self.arch - weight.y))
            // Never higher than the legs can reach with the knees still soft.
            let leg = body.legReach(bend: 4)
            for s in ["r", "l"] {
                guard let ankle = ankles[s], let hip = rel["femur.\(s)"] else { continue }
                let dx = hip.x + root.x - ankle.x, dy = hip.y + root.y - ankle.y
                root.z = min(root.z, ankle.z + max(0.01, leg * leg - dx * dx - dy * dy).squareRoot() - hip.z)
            }
            let h = body.place(g, root: root)
            for s in ["r", "l"] {
                guard let ankle = ankles[s], let foot = feet[s] else { continue }
                body.plant(s, ankle: ankle, foot: foot, pole: V(0, -1, 0.3), &g, h)
            }
            return (root, body.place(g, root: root))
        }
    }

    /// One foot ahead of the other: the front foot flat, the back foot on its ball with the
    /// heel up, the hips between them and low enough for the back leg to reach. The keyframes
    /// keep the trunk; the legs are fitted to the feet.
    struct SplitStance: Sendable {
        let front: String
        let ankles: [String: V]
        let feet: [String: M]
        let toes: [String: M]
        /// Midway between the two hip joints.
        let hips: V

        /// `length` is from the front ankle back to the ball of the back foot; `heel` is how
        /// far the back heel is raised (degrees).
        init?(_ body: Body3D, front: String, length: Double = 0.42, heel: Double = 28, toeOut: Double = 5) {
            let back = front == "r" ? "l" : "r"
            guard let fAnkle = body.head["foot.\(front)"], let bAnkle = body.head["foot.\(back)"],
                  let ball = body.head["toes.\(back)"], let hip = body.head["femur.r"], let knee = body.head["shin.r"] else { return nil }
            self.front = front
            let out = ["r": M.z(-toeOut), "l": M.z(toeOut)]
            let lifted = (out[back] ?? .identity) * M.x(heel)
            // The back foot turns about its ball, which stays on the floor.
            let onFloor = V(bAnkle.x, 0.28, body.ankleHeight - (bAnkle.z - ball.z))
            let raised = onFloor + lifted * (bAnkle - ball)
            let planted = V(fAnkle.x, 0.28 - length, body.ankleHeight)
            ankles = [front: planted, back: raised]
            feet = [front: out[front] ?? .identity, back: lifted]
            toes = out
            // The hips sit a little behind the front ankle, as high as leaves the back knee soft.
            let y = planted.y + 0.1
            let leg = Body3D.span((knee - hip).length, (fAnkle - knee).length, bend: 12)
            let dy = raised.y - y
            hips = V(0, y, raised.z + max(0.1, leg * leg - dy * dy).squareRoot())
        }

        func stand(_ body: Body3D, _ g: inout [String: M]) -> (root: V, heads: [String: V]) {
            let rel = body.place(g, root: V(0, 0, 0))
            let joints = ["r", "l"].compactMap { rel["femur.\($0)"] }
            let mid = joints.reduce(V(0, 0, 0), +) * (1 / Double(max(1, joints.count)))
            let root = hips - V(0, mid.y, mid.z)
            let h = body.place(g, root: root)
            for s in ["r", "l"] {
                guard let ankle = ankles[s], let foot = feet[s] else { continue }
                body.plant(s, ankle: ankle, foot: foot, pole: V(0, -1, 0.2), &g, h)
                g["toes.\(s)"] = toes[s]
            }
            return (root, body.place(g, root: root))
        }
    }

    /// Pieces built about the origin, turned and moved to where they stand.
    static func moved(_ pieces: [PropPiece], turn: M, by: V) -> [PropPiece] {
        pieces.map { piece in
            var p = piece
            p.center = (turn * V(piece.center) + by).array
            p.rotation = (turn * M(piece.rotation)).quat
            return p
        }
    }

    /// Where a cable from `point` touches the rim of a pulley wheel at `centre` that turns about
    /// `axis`: of the two tangents, the one whose touching point lies further toward `side`.
    static func rim(_ centre: V, axis: V = V(1, 0, 0), radius: Double = wheel, from point: V, side: V) -> V {
        let a = axis.unit
        var d = point - centre
        d = d - a * d.dot(a)
        let far = d.length
        guard far > radius + 1e-6 else { return centre + (far > 1e-9 ? d.unit : side.unit) * radius }
        let along = d.unit, across = a.cross(along)
        let c = radius / far, s = (1 - c * c).squareRoot()
        let one = centre + (along * c + across * s) * radius, other = centre + (along * c - across * s) * radius
        return one.dot(side) >= other.dot(side) ? one : other
    }

    /// A cable station for a pulley overhead: the weight stack at `column` in front of the
    /// body, a boom from its top back to the wheel at `pulley`, and the cable from that wheel
    /// over to the one above the stack. `top` is the station's height.
    static func highStation(pulley: V, column: Double, top: Double) -> [PropPiece] {
        let side = V(1, 0, 0)
        var p = stackFrame(y: column, height: top)
        // A foot under the boom, so the station does not look as if it would tip toward the body.
        p.append(Plan.box(V(0, (column + pulley.y + 0.3) / 2, 0.025), (0.09, pulley.y + 0.3 - column, 0.05), .metal))
        p.append(Plan.box(V(0, (column + pulley.y + 0.1) / 2, top - 0.03), (0.07, pulley.y + 0.1 - column, 0.06), .metal))
        // The wheel hangs under the boom between two cheek plates.
        p.append(Plan.disc(pulley, axis: side, radius: wheel, thickness: wheelThickness, .dark))
        for x in [-0.02, 0.02] {
            p.append(Plan.box(V(x, pulley.y, (pulley.z + top - 0.06) / 2), (0.006, 0.05, top - 0.06 - pulley.z + 0.04), .metal))
        }
        p.append(Plan.rod(V(0, pulley.y, pulley.z + wheel), V(0, column + wheel, top - 0.13 + wheel), cable, .cable))
        return p
    }

    /// A cable station whose pulley rides up and down a mast: the wheel at `pulley` between the
    /// mast's two rails, the weight stack just beyond it, and the cable from under the wheel up
    /// the mast and over to the stack. The body stands on the +y side.
    static func mastStation(pulley: V, top: Double) -> (pieces: [PropPiece], column: Double) {
        let side = V(1, 0, 0)
        let rise = pulley.y - wheel, column = rise - wheel - 0.21
        var p = stackFrame(y: column, height: top)
        // The mast's rails, tied to the stack's frame at the top and along the floor.
        for x in [-0.045, 0.045] {
            p.append(Plan.box(V(x, rise, top / 2), (0.03, 0.06, top), .metal))
            p.append(Plan.box(V(x, (rise + column) / 2, top - 0.03), (0.03, rise - column, 0.06), .metal))
            // The carriage that holds the wheel, and its pin through the rail.
            p.append(Plan.box(V(x * 0.85, pulley.y - 0.02, pulley.z), (0.012, 0.15, 0.1), .dark))
        }
        p.append(Plan.box(V(0, (column + pulley.y + 0.45) / 2, 0.025), (0.09, pulley.y + 0.45 - column, 0.05), .metal))
        p.append(Plan.disc(pulley, axis: side, radius: wheel, thickness: wheelThickness, .dark))
        p.append(Plan.rod(pulley - side * 0.05, pulley + side * 0.05, 0.008, .metal))
        // Up the mast to a wheel at its head, and over to the wheel above the stack.
        let head = V(0, rise - wheel, top - 0.13)
        p.append(Plan.disc(head, axis: side, radius: wheel, thickness: wheelThickness, .dark))
        p.append(Plan.rod(V(0, rise, pulley.z), V(0, rise, head.z), cable, .cable))
        p.append(Plan.rod(V(0, head.y, head.z + wheel), V(0, column + wheel, head.z + wheel), cable, .cable))
        return (p, column)
    }

    // MARK: The body's front

    /// How far forward (the least y) the skin of the face, the trunk and the thighs reaches at
    /// height `z`, for a body standing or sitting upright, so a handle can stop short of it.
    static func front(_ h: [String: V], at z: Double) -> Double {
        if let neck = h["neck"], z > neck.z { return z < neck.z + 0.27 ? neck.y - 0.15 : .infinity }
        let parts: [(String, String, Double)] = [
            ("femur.r", "shin.r", 0.1), ("femur.l", "shin.l", 0.1), ("pelvis", "lumbar", 0.13),
            ("lumbar", "thorax", 0.14), ("thorax", "neck", 0.17),
        ]
        var front = Double.infinity
        for (a, b, thick) in parts {
            guard let p = h[a], let q = h[b], abs(q.z - p.z) > 1e-6 else { continue }
            let t = (z - p.z) / (q.z - p.z)
            guard t >= -0.05, t <= 1.05 else { continue }
            front = min(front, p.y + (q.y - p.y) * min(1, max(0, t)) - thick)
        }
        return front
    }

    // MARK: The rope

    /// The rope handle: how thick it is, how long each half is from the swivel to where it
    /// enters the fist, and half the width of the fist that holds it.
    static let rope = 0.013, strand = 0.26, fist = 0.05

    /// Closes both hands on the ends of a rope, with the grip's middle line of each hand at
    /// `hands`. With `thumbsIn` the thumbs are toward the swivel and the end knobs beyond the
    /// little fingers; without, the knobs are beyond the thumbs. Each half of the rope runs
    /// straight from the swivel to the edge of its fist; a fist cannot hold a rope that runs
    /// along the forearm, so the rope bends where it leaves the fist and the part in the hand
    /// lies as the wrist allows. `poles` say where the elbows go. `lean` tips the
    /// little-finger end of each fist that way: down for palms that face each other, nothing
    /// for palms that face down. Returns the line of the rope in each hand from thumb to
    /// little finger, the way it runs through the fist toward its knob, the swivel, and where
    /// the cable leaves the wheel.
    static func holdRope(_ body: Body3D, _ grips: [String: HandGrip], hands: [String: V], poles: [String: V],
                         pulley: V, side: V, thumbsIn: Bool = true, lean: V = V(0, 0, 0),
                         _ g: inout [String: M], _ h: [String: V], root: V)
        -> (across: [String: V], run: [String: V], eye: V, rim: V) {
        let all = ["r", "l"].compactMap { hands[$0] }
        guard all.count == 2 else { return ([:], [:], pulley, pulley) }
        let way = thumbsIn ? 1.0 : -1.0
        var mid = (all[0] + all[1]) * 0.5, apart = (all[0] - all[1]).length / 2
        var rim = CableKit.rim(pulley, from: mid, side: side)
        var eye = mid + (rim - mid).unit * max(0.02, pow(strand + fist, 2) - apart * apart).squareRoot()
        var across: [String: V] = [:]
        func hold() {
            for s in ["r", "l"] {
                guard let grip = grips[s], let at = hands[s], let line = across[s], let pole = poles[s] else { continue }
                // Both passes start from the shoulders `h` holds, so one arm never moves the other.
                var turned = g
                body.hold(s, grip, at: at, across: line, pole: pole, &turned, h)
                for (bone, turn) in turned where bone.hasSuffix(".\(s)") { g[bone] = turn }
            }
        }
        for s in ["r", "l"] { across[s] = hands[s].map { (($0 - eye).unit * way + lean).unit } }
        hold()
        let posed = body.place(g, root: root)
        for s in ["r", "l"] {
            guard let grip = grips[s], let line = across[s], let wrist = posed["hand.\(s)"],
                  let elbow = posed["ulna.\(s)"] else { continue }
            let rest = acos(min(1, max(-1, grip.across.dot(body.forearmAxis(s))))) * 180 / .pi
            across[s] = keep(line, from: wrist - elbow, within: (rest - 35)...(rest + 30))
        }
        hold()
        let run = across.mapValues { $0 * way }
        let edges = ["r", "l"].compactMap { s in hands[s].flatMap { p in run[s].map { p - $0 * fist } } }
        if edges.count == 2 {
            mid = (edges[0] + edges[1]) * 0.5
            apart = (edges[0] - edges[1]).length / 2
            rim = CableKit.rim(pulley, from: mid, side: side)
            eye = mid + (rim - mid).unit * max(0.02, strand * strand - apart * apart).squareRoot()
        }
        return (across, run, eye, CableKit.rim(pulley, from: eye, side: side))
    }

    /// The rope's two halves from the swivel through the fists to their end knobs, and the
    /// swivel. `run` is the way the rope goes through each fist.
    static func ropePieces(eye: V, hands: [String: V], run: [String: V]) -> [PropPiece] {
        var p: [PropPiece] = []
        for s in ["r", "l"] {
            guard let hand = hands[s], let line = run[s] else { continue }
            let edge = hand - line * fist, end = hand + line * (fist + 0.02)
            p.append(Plan.rod(eye, edge, rope, .dark))
            p.append(Plan.ball(edge, rope, .dark))
            p.append(Plan.rod(edge, end, rope, .dark))
            p.append(Plan.ball(end + line * 0.012, 0.024, .rubber))
        }
        p.append(Plan.ball(eye, 0.016, .metal))
        return p
    }

    /// `point` brought in toward `shoulder` until an arm bent at least `bend` degrees reaches it.
    static func within(_ body: Body3D, _ s: String, _ grip: HandGrip, shoulder: V, _ point: V, bend: Double = 6) -> V {
        let most = body.reach(s, grip, bend: bend)
        let d = point - shoulder
        return d.length > most ? shoulder + d.unit * most : point
    }

    /// The swivel a handle hangs from, at `eye`, on a short stem from `from`.
    static func swivel(from: V, eye: V) -> [PropPiece] {
        [Plan.rod(from, eye, 0.007, .metal), Plan.ball(eye, 0.014, .metal)]
    }

    /// `a` turned toward or away from `f`, in the plane of the two, until the angle between
    /// them is within `range` (degrees).
    static func keep(_ a: V, from f: V, within range: ClosedRange<Double>) -> V {
        let a = a.unit, f = f.unit
        let angle = acos(min(1, max(-1, a.dot(f)))) * 180 / .pi
        guard !range.contains(angle) else { return a }
        var off = a - f * a.dot(f)
        if off.length < 1e-6 { off = f.cross(abs(f.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0)) }
        let to = min(max(angle, range.lowerBound), range.upperBound) * .pi / 180
        return f * cos(to) + off.unit * sin(to)
    }
}

extension Body3D {
    /// The leg's length from hip to ankle with the knee bent `degrees`.
    func legReach(bend degrees: Double) -> Double {
        guard let hip = head["femur.r"], let knee = head["shin.r"], let ankle = head["foot.r"] else { return 0.75 }
        return Self.span((knee - hip).length, (ankle - knee).length, bend: degrees)
    }
}

import Foundation

/// A lift done in a Smith machine: the same lift as with a free bar, but the bar runs on two
/// upright rails, so it only goes straight up and down. The lift is staged as its free-bar
/// version first; then either the body is moved to the bar's line with its feet left where
/// they stand (squats, standing presses, deadlifts, calf raises), or the body stays where it
/// rests and the arms carry the bar on the rails' line (bench presses, rows, seated presses).
struct MachineSmithStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How the body follows a bar that cannot leave its line.
    enum Follow: Sendable { case feet, arms }

    static let height = 2.2

    let body: Body3D
    let inner: any BodyStaging
    let follow: Follow
    /// The rails' line: the bar is always this far in front of the body's origin.
    let railY: Double
    /// Each rail's distance from the middle.
    let railX: Double
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.smith]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.equipment == "smith-machine", let (inner, follow) = Self.freeBar(guide, body) else { return nil }
        self.body = body
        self.inner = inner
        self.follow = follow

        // Where the free bar goes through the loop.
        var path: [(y: Double, z: Double)] = []
        var half = 1.1, radius = 0.014, plates = 9.0
        for k in 0...24 {
            let props = inner.frame(Figure.smooth(guide.keyframes, at: Double(k) / 24)).props
            guard let bar = Self.bar(props) else { return nil }
            path.append((bar.center[1], bar.center[2]))
            half = bar.size[2] / 2
            radius = bar.size[0] / 2
            for p in props where p.shape == .cylinder && p.size[0] > 0.2 { plates = min(plates, abs(p.center[0]) - p.size[2] / 2) }
        }
        guard let low = path.min(by: { $0.z < $1.z }), let high = path.max(by: { $0.z < $1.z }) else { return nil }
        switch follow {
        case .feet:
            // The body sways least when the rails stand in the middle of the free bar's path.
            railY = ((path.map(\.y).min() ?? 0) + (path.map(\.y).max() ?? 0)) / 2
        case .arms:
            // The rails stand where the bar meets the body: on the chest for a press, at the
            // belly for a row.
            railY = guide.familyID == "row" ? high.y : low.y
        }
        // The rails run inside the plates.
        railX = min(max(0.56, (plates < 9 ? plates : half * 0.62) - 0.09), half - 0.2)
        guard let r = body.grip("r", radius: radius, square: 0.5), let l = body.grip("l", radius: radius, square: 0.5) else { return nil }
        grips = ["r": r, "l": l]

        // A free bar's rack would stand where the rails do: only what the body rests on stays.
        fixed = inner.fixed.filter { abs($0.center[0]) < 0.42 } + Self.rails(x: railX, y: railY)
    }

    /// The two rails, the posts behind them and the frame that joins them.
    static func rails(x railX: Double, y railY: Double) -> [PropPiece] {
        var pieces: [PropPiece] = []
        let back = railY + 0.2
        for m in [-1.0, 1.0] {
            let x = m * railX
            pieces.append(Plan.rod(V(x, railY, 0.05), V(x, railY, Self.height), 0.014, .metal))
            pieces.append(Plan.box(V(x, back, Self.height / 2), (0.06, 0.06, Self.height), .metal))
            pieces.append(Plan.box(V(x, railY + 0.1, Self.height), (0.06, 0.26, 0.06), .metal))
            pieces.append(Plan.box(V(x, railY + 0.1, 0.025), (0.08, 1.3, 0.05), .metal))
        }
        pieces.append(Plan.box(V(0, back, Self.height), (2 * railX + 0.06, 0.06, 0.06), .metal))
        return pieces
    }

    /// Smith lifts whose names differ from the free-bar lift that is the same movement.
    static let sameLift = [
        "smith chair squat": "barbell bench squat", "smith squat to bench": "barbell bench squat",
        "smith shoulder press": "barbell standing shoulder press",
        "smith narrow row v. 2": "barbell narrow row", "smith bent over narrow pronated grip row": "barbell narrow row",
        "smith calf raise (with block)": "barbell standing leg calf raise",
    ]

    /// The same lift with a free bar, as another group stages it, and how the body follows
    /// the rails. Nil for a lift whose bar could not stay on rails as staged.
    static func freeBar(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging, Follow)? {
        // One hand on a bar that cannot tip, or a band on it, is not the free-bar lift.
        let words = MachineStagings.words(guide)
        guard words.isDisjoint(with: ["single", "one", "band", "banded"]) else { return nil }
        var free = guide
        free.equipment = "barbell"
        free.exerciseName = sameLift[guide.exerciseName] ?? guide.exerciseName
            .replacingOccurrences(of: "smith machine", with: "barbell").replacingOccurrences(of: "smith", with: "barbell")
        guard let inner = Stagings.make(free, body) else { return nil }
        switch guide.familyID {
        case "squat", "calf-raise", "deadlift", "step-up":
            return (inner, .feet)

        case "overhead-press":
            // Seated, the free bar is staged too near the head for a straight line to clear it.
            return guide.subtypeID == "seated" ? nil : (inner, .feet)
        case "bench-press", "row":
            return (inner, .arms)
        default:
            // A hip thrust's bar swings on the hips, a good morning's goes forward with the
            // shoulders, and a split squat's free bar is staged in the hands: none of those
            // would stay on rails as staged.
            return nil
        }
    }

    /// The bar among the pieces that move: the long thin rod.
    static func bar(_ props: [PropPiece]) -> PropPiece? {
        props.first { $0.shape == .cylinder && $0.size[2] > 1.2 && $0.size[0] < 0.08 }
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let made = inner.frame(pose)
        guard let bar = Self.bar(made.props) else { return made }
        var g = made.body.rotations.mapValues { M($0) }
        var h = made.body.heads.mapValues { V($0) }
        guard let root = h["pelvis"] else { return made }
        var move = V(0, railY - bar.center[1], 0)
        var props = made.props

        switch follow {
        case .feet:
            // The body and the bar it carries move to the rails; the feet stay where they
            // stand, and the hips ride as high as the legs then reach.
            var drop = 0.0
            var legs: [(s: String, ankle: V, foot: M, toes: M, pole: V)] = []
            for s in ["r", "l"] {
                guard let hip = h["femur.\(s)"], let knee = h["shin.\(s)"], let ankle = h["foot.\(s)"] else { continue }
                let reach = (hip - ankle).length
                let flat = V(hip.x - ankle.x, hip.y + move.y - ankle.y, 0)
                let up = (max(0, reach * reach - flat.dot(flat))).squareRoot()
                drop = min(drop, ankle.z + (hip.z >= ankle.z ? up : -up) - hip.z)
                legs.append((s, ankle, g["foot.\(s)"] ?? .identity, g["toes.\(s)"] ?? .identity, knee - (hip + ankle) * 0.5))
            }
            move.z = drop
            for (key, at) in h { h[key] = at + move }
            for leg in legs {
                let pole = leg.pole.length > 0.02 ? leg.pole : V(0, -1, 0)
                body.plant(leg.s, ankle: leg.ankle, foot: leg.foot, pole: pole, &g, h)
                g["toes.\(leg.s)"] = leg.toes
            }
            h = body.place(g, root: root + move)
            props = props.map { Self.moved($0, by: move) }

        case .arms:
            // The body stays; the hands carry the bar on the rails' line, as high as the
            // arms then reach.
            let line = V(0, railY, bar.center[2])
            var holds: [(s: String, x: Double, across: V, pole: V)] = []
            var top = line.z
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let grip = grips[s], let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"],
                      let wrist = h["hand.\(s)"], let knuckle = h["f3a.\(s)"] else { continue }
                let across = V(((g["hand.\(s)"] ?? .identity) * V(m, 0, 0)).x < 0 ? -1 : 1, 0, 0)
                holds.append((s, knuckle.x, across, elbow - (shoulder + wrist) * 0.5))
                // A bar above the shoulders can be no higher than straight arms put it.
                let reach = body.reach(s, grip, bend: 6)
                let flat = V(knuckle.x - shoulder.x, railY - shoulder.y, 0)
                let up = (max(0, reach * reach - flat.dot(flat))).squareRoot()
                if line.z > shoulder.z { top = min(top, shoulder.z + up) } else { top = max(top, shoulder.z - up) }
            }
            move.z = top - line.z
            for hold in holds {
                guard let grip = grips[hold.s] else { continue }
                let pole = hold.pole.length > 0.02 ? hold.pole : V(0, 0.3, -1)
                body.hold(hold.s, grip, at: V(hold.x, railY, top), across: hold.across, pole: pole, &g, h)
            }
            h = body.place(g, root: root)
            // The bar and what is loaded on it move; anything else is left where it was.
            props = props.map { p in
                abs(p.center[1] - bar.center[1]) < 0.02 && abs(p.center[2] - bar.center[2]) < 0.02 ? Self.moved(p, by: move) : p
            }
        }

        // The sleeves that run on the rails.
        let z = bar.center[2] + move.z
        for m in [-1.0, 1.0] {
            props.append(Plan.rod(V(m * railX, railY, z - 0.07), V(m * railX, railY, z + 0.07), 0.032, .dark))
        }
        return (body.made(g, h, floor: made.body.floor), props)
    }

    static func moved(_ piece: PropPiece, by move: V) -> PropPiece {
        var piece = piece
        piece.center = [piece.center[0] + move.x, piece.center[1] + move.y, piece.center[2] + move.z]
        return piece
    }
}

// MARK: - Standing lifts with no free-bar staging

/// A Smith machine lift that stands still and moves only the arms or the shoulders: a shrug
/// with the bar in front of the thighs or behind them, an upright row, a curl, a press from
/// behind the neck. The body stands as its keyframes pose it; the bar is on the rails' line at
/// the height the hands carry it, and both hands close on it there.
struct MachineSmithStandStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Where the rails stand: in front of the thighs, behind them, or behind the head.
    enum Place: Sendable { case front, back, neck }

    static let barRadius = 0.014, barHalf = 1.1, railX = 0.62

    let body: Body3D
    let place: Place
    /// Palms up under the bar, for a curl.
    let under: Bool
    /// Each hand's distance from the middle of the bar.
    let half: Double
    let railY: Double
    /// How far under the shoulders the bar stops at the least: a row or a curl ends at the chest.
    let below: Double?
    let grips: [String: HandGrip]
    let kinds: [PropKind] = [.smith]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.equipment == "smith-machine", guide.subtypeID == nil else { return nil }
        below = guide.familyID == "upright-row" ? 0.1 : guide.familyID == "biceps-curl" ? 0.08 : nil
        switch guide.familyID {
        case "shrug":
            guard words.isSubset(of: ["smith", "shrug", "wide", "back"]) else { return nil }
            (place, under, half) = (words.contains("back") ? .back : .front, false, words.contains("wide") ? 0.42 : 0.3)
        case "upright-row":
            guard words.isSubset(of: ["smith", "upright", "row"]) else { return nil }
            (place, under, half) = (.front, false, 0.2)
        case "biceps-curl":
            guard words.isSubset(of: ["smith", "machine", "bicep", "biceps", "curl", "drag"]) else { return nil }
            (place, under, half) = (.front, true, 0.24)
        case "overhead-press":
            guard words.contains("behind"),
                  words.isSubset(of: ["smith", "behind", "neck", "head", "press", "standing", "military"]) else { return nil }
            (place, under, half) = (.neck, false, 0.38)
        default:
            return nil
        }
        guard let r = body.grip("r", radius: Self.barRadius, square: 0.5), let l = body.grip("l", radius: Self.barRadius, square: 0.5),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        let stood = body.posed(first, contacts: ["feet"]).h
        // The neck is furthest back when the trunk leans back under the bar.
        let necks = (0...12).compactMap { k in
            body.posed(Figure.smooth(guide.keyframes, at: Double(k) / 12), contacts: ["feet"]).h["neck"]?.y
        }
        guard let pelvis = stood["pelvis"], let neck = necks.max() else { return nil }
        switch place {
        case .front: railY = pelvis.y - 0.16
        case .back: railY = pelvis.y + 0.17
        case .neck: railY = neck + 0.12
        }
        fixed = MachineSmithStaging.rails(x: Self.railX, y: railY)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h, floor) = body.posed(pose, contacts: ["feet"])
        guard let root = h["pelvis"] else { return (body.made(g, h, floor: floor), []) }
        // The bar is as high as the posed hands would carry it, within the arms' reach of
        // the rails' line.
        var sum = 0.0, n = 0.0
        for s in ["r", "l"] {
            guard let grip = grips[s], let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"] else { continue }
            sum += (wrist + hand * grip.centre).z
            n += 1
        }
        var z = n > 0 ? sum / n : 1
        if let below, let r = h["humerus.r"], let l = h["humerus.l"] { z = min(z, min(r.z, l.z) - below) }
        // Behind the neck the bar comes down to the base of the skull.
        if place == .neck, let neck = h["neck"] { z = max(neck.z + 0.04, z - 0.1) }
        var poles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"], let wrist = h["hand.\(s)"]
            else { continue }
            poles[s] = elbow - (shoulder + wrist) * 0.5
            let reach = body.reach(s, grip, bend: 5)
            let flat = V(-m * half - shoulder.x, railY - shoulder.y, 0)
            let up = max(0, reach * reach - flat.dot(flat)).squareRoot()
            z = z > shoulder.z ? min(z, shoulder.z + up) : max(z, shoulder.z - up)
        }
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            // Elbows under the bar behind the neck; otherwise as the pose bends them, out and back.
            var pole = place == .neck ? V(-m, 0.1, -0.5) : poles[s] ?? V(0, 0, 0)
            if pole.length < 0.03 { pole = V(-m, 0.6, 0) }
            // An upright row leads with the elbows: out, and above the hands.
            if below != nil, !under { pole = V(-m, 0.2, 0.5) }
            body.hold(s, grip, at: V(-m * half, railY, z), across: V(under ? m : -m, 0, 0), pole: pole, &g, h)
        }
        h = body.place(g, root: root)

        var p = [Plan.rod(V(-Self.barHalf, railY, z), V(Self.barHalf, railY, z), Self.barRadius, .metal)]
        for m in [-1.0, 1.0] {
            p.append(Plan.rod(V(m * 0.8, railY, z), V(m * Self.barHalf, railY, z), 0.025, .metal))
            p.append(Plan.disc(V(m * 0.86, railY, z), axis: V(1, 0, 0), radius: 0.2, thickness: 0.045, .plate))
            p.append(Plan.rod(V(m * Self.railX, railY, z - 0.07), V(m * Self.railX, railY, z + 0.07), 0.032, .dark))
        }
        return (body.made(g, h, floor: floor), p)
    }
}

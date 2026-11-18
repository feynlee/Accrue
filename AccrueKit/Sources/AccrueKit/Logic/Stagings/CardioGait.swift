import Foundation

extension Body3D {
    /// The height of the pelvis that stands the posed body on a floor: the lowest part of
    /// either foot (toe tip, ball or heel) just touches it. `slope` is how much the floor
    /// rises for each metre forward, for a deck that is tilted up.
    func cardioStand(_ g: [String: M], floor: Double = 0, slope: Double = 0) -> Double {
        let rel = place(g, root: V(0, 0, 0))
        let points = contactPoints("feet", g, rel) + contactPoints("toes", g, rel)
        let low = points.map { $0.0.z - $0.1 + slope * $0.0.y }.min() ?? -0.85
        return floor - low
    }
}

/// Running and walking, shown on the spot: the hips stay over one place and the legs go
/// through the keyframes' gait with whichever foot is lowest on the floor, so nothing drifts
/// and nothing sinks in. On a treadmill the floor is the belt.
struct CardioGaitStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let deck = 0.18
    /// How far behind the hips the deck's back end is.
    static let back = 0.8

    let body: Body3D
    let loop: CardioLoop
    /// The floor under the feet, and how much it rises for each metre forward.
    let floor: Double, slope: Double
    let kinds: [PropKind]
    let fixed: [PropPiece]
    /// Whether a rucksack is worn.
    let pack: Bool
    /// The moments of the loop when both feet are off the ground (a run has two a stride, a
    /// walk none), and how high the hips rise at the middle of each.
    let flights: [(from: Double, to: Double, rise: Double)]
    /// The height of the hips as each flight starts and ends, standing on the foot that is down.
    let leaps: [(from: Double, to: Double)]

    /// `treadmills` also stages the treadmill family. A staged plan has no `lift`: the staging
    /// raises the body onto the deck itself.
    init?(_ guide: HowToGuide, _ body: Body3D, treadmills: Bool = false) {
        let words = CardioStagings.words(guide)
        var slope = 0.0
        var pack = false
        switch guide.familyID {
        case "treadmill-run":
            // Walking backward has no keyframes of its own, and would be shown going forward.
            guard treadmills, guide.subtypeID != "backward" else { return nil }
            if guide.subtypeID == "incline-walk" { slope = 0.105 }
            // A tilted deck keeps its back end down and lifts its front.
            floor = Self.deck + Self.back * slope
            kinds = [.treadmill]
        case "run", "walk":
            // Only bare running and walking: nothing carried, pushed or leaned on, and no
            // other move mixed in that the gait's keyframes do not show.
            // A ruck, or a run with a backpack, is the same gait with the pack on the back.
            pack = guide.subtypeID == "ruck" || words.contains("backpack")
            guard guide.equipment == nil || guide.equipment == "none" || (pack && guide.equipment == "weighted"),
                  words.isDisjoint(with: ["wall", "backwards", "backward", "band", "push", "wheel", "kick", "hop", "jump",
                                          "jack", "squat", "bend", "skips", "prancing", "nordic", "pole", "poles"])
            else { return nil }
            floor = 0
            kinds = []
        default: return nil
        }
        self.body = body
        self.slope = slope
        self.pack = pack
        loop = CardioLoop(guide)
        fixed = kinds.isEmpty ? [] : Self.treadmill(slope: slope)
        let flights = Self.flights(guide, loop)
        self.flights = flights
        let closed = loop.closed, ground = floor
        func stand(_ t: Double) -> Double {
            body.cardioStand(body.rotations(Figure.smooth(closed, at: t)), floor: ground, slope: slope)
        }
        leaps = flights.map { (stand($0.from), stand($0.to)) }
    }

    /// Where the runner is in the air: from each keyframe named a toe-off to the next one named
    /// a landing or a contact. Between those the body rises and falls as a thrown thing does for
    /// as long as the flight lasts. A walk has a foot down at every moment, and none.
    static func flights(_ guide: HowToGuide, _ loop: CardioLoop) -> [(from: Double, to: Double, rise: Double)] {
        let keys = loop.closed
        func named(_ k: Keyframe, _ words: [String]) -> Bool {
            let phase = (k.phase ?? "").lowercased()
            return words.contains { phase.contains($0) }
        }
        var out: [(from: Double, to: Double, rise: Double)] = []
        for (i, off) in keys.enumerated() where named(off, ["toe-off", "toe off"]) {
            // The loop closes on its first keyframe, so the landing after the last toe-off is there.
            guard let land = keys[(i + 1)...].first(where: { named($0, ["lands", "contact", "strike"]) }),
                  land.t - off.t < 0.3 else { continue }
            let time = (land.t - off.t) * guide.seconds
            // Up for half the time and down for half: g t² / 8.
            out.append((off.t, land.t, min(0.08, 9.81 * time * time / 8)))
        }
        return out
    }

    /// The height of the hips at `t` of a body that would stand at `standing`: in a flight they
    /// go from where the back foot left them to where the front foot takes them, over a low arc,
    /// and neither foot touches.
    func height(at t: Double, standing: Double) -> Double {
        for (f, leap) in zip(flights, leaps) where t >= f.from && t <= f.to {
            let u = (t - f.from) / (f.to - f.from)
            // Never under the ground: a foot that reaches lower than the arc allows stays on it.
            return max(standing, leap.from + (leap.to - leap.from) * u + f.rise * 4 * u * (1 - u))
        }
        return standing
    }

    /// The deck with its belt, the uprights, the console and the hand rails. The body's hips
    /// are over y = 0; the deck tilts about its back end.
    static func treadmill(slope: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        let up = V(0, slope, 1).unit, along = V(0, -1, slope).unit
        let centre = V(0, back - 0.9, deck + 0.9 * slope)
        p.append(Plan.box(centre - up * (deck / 2), (0.75, 1.8, deck), x: side, z: up, .dark))
        p.append(Plan.box(centre + up * 0.001, (0.5, 1.6, 0.004), x: side, z: up, .rubber))
        // A tilted deck stands on its front legs.
        let front = centre + along * 0.85
        if slope > 0 {
            for x in [-0.34, 0.34] { p.append(Plan.box(V(x, front.y, (front.z - deck) / 2), (0.06, 0.08, max(0.01, front.z - deck)), .metal)) }
        }
        for x in [-0.36, 0.36] {
            let foot = front + side * x
            p.append(Plan.rod(foot, foot + V(0, 0, 1.15), 0.025, .metal))
            // A rail back from each upright, at hand height.
            p.append(Plan.rod(foot + V(0, 0, 0.95), foot + V(0, 0.5, 0.95), 0.02, .dark))
        }
        p.append(Plan.box(front + V(0, 0, 1.2), (0.75, 0.12, 0.3), x: side, z: V(0, 0.4, 1), .dark))
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let clean = loop.clean(pose)
        let g = body.rotations(clean.pose)
        let h = body.place(g, root: V(0, 0, height(at: clean.t, standing: body.cardioStand(g, floor: floor, slope: slope))))
        return (body.made(g, h, floor: 0), pack ? rucksack(g, h) : [])
    }

    /// A rucksack high on the back with a strap over each shoulder. It is carried by the
    /// ribcage, so it leans with the trunk; the places are measured on the body at rest.
    func rucksack(_ g: [String: M], _ h: [String: V]) -> [PropPiece] {
        guard let at = h["thorax"], let rest = body.head["thorax"] else { return [] }
        let turn = g["thorax"] ?? .identity
        func p(_ x: Double, _ y: Double, _ z: Double) -> V { at + turn * (V(x, y, z) - rest) }
        let side = turn * V(1, 0, 0), up = turn * V(0, 0, 1)
        var out = [Plan.box(p(0, 0.18, 1.21), (0.24, 0.13, 0.4), x: side, z: up, .dark),
                   Plan.box(p(0, 0.26, 1.13), (0.18, 0.04, 0.2), x: side, z: up, .rubber)]
        for m in [-1.0, 1.0] {
            // From the top of the pack over the shoulder, down the front of the chest, and back
            // under the arm to the bottom of the pack.
            let path = [p(m * 0.085, 0.125, 1.4), p(m * 0.085, 0.03, 1.462), p(m * 0.09, -0.09, 1.4), p(m * 0.105, -0.145, 1.29),
                        p(m * 0.165, -0.06, 1.17), p(m * 0.125, 0.125, 1.06)]
            for (a, b) in zip(path, path.dropFirst()) { out.append(Plan.rod(a, b, 0.012, .rubber)) }
            for corner in path.dropFirst().dropLast() { out.append(Plan.ball(corner, 0.012, .rubber)) }
        }
        return out
    }
}

import Foundation

/// Jumps onto, over and off a box. The loop is a string of stands (on the floor, or on the top
/// of the box) with a flight between each two: the feet stand flat where they are, and in a
/// flight they fly in an arc that carries them clear of the box's edges. A long jump and a
/// bound from side to side are the same stands and flights with no box.
struct CardioBoxJumpStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The height of a box's top, and of a low one for one-legged jumps and jumps over it.
    static let top = 0.5, low = 0.3
    /// A box's size along the jump and across it.
    static let deep = 0.5, wide = 0.6
    /// The clear floor between the toes and the box before a jump onto it.
    static let gap = 0.25
    /// How far a long jump goes, and a frog hop, toes to toes.
    static let far = 1.0, hop = 0.6
    /// How far apart the two feet land in a bound from side to side.
    static let stride = 1.2
    /// How far off the floor a bound keeps the foot that is not standing.
    static let free = 0.04
    /// How far behind the toes a band's post stands, and how high the band is tied to it.
    static let post = (behind: 1.1, tie: 0.85, height: 1.0)
    /// A band's thickness, as the plain plan draws it.
    static let band = 0.007

    /// Which feet carry the body in a stand.
    enum Feet: Sendable {
        case both, right, left

        var bearing: [String: Double] {
            switch self {
            case .both: return ["r": 1, "l": 1]
            case .right: return ["r": 1, "l": 0]
            case .left: return ["r": 0, "l": 1]
            }
        }
    }

    /// A stretch of the loop spent standing: when, where the ball of the standing foot (or
    /// the middle of both) is, how high the surface is, and on which feet.
    struct Stand: Sendable {
        let from: Double, to: Double
        let ball: V
        let floor: Double
        let feet: Feet
    }

    /// What is done with the box.
    enum Course: Equatable {
        /// From the floor onto the top.
        case up
        /// From the floor, over the box, to the floor behind it.
        case over
        /// From the top down to the floor in front.
        case down
        /// A step off the top, a landing, and with `rebound` a jump straight up from it.
        case depth(rebound: Bool)
        /// Along the floor with no box, `far` from toes to toes.
        case leap(far: Double)
        /// From the right foot to the left and back, side to side with no box.
        case bound
    }

    let body: Body3D
    let loop: CardioLoop
    let course: Course
    let stands: [Stand]
    /// The stand whose landing the how-to's mistakes are about.
    let landing: Int
    /// How far each flight rises above a plain line from one stand's surface to the next's.
    private(set) var rises: [Double]
    /// The height of this box's top.
    let height: Double
    /// The middle of the box, the way the jump goes and the way across it.
    let centre: V, way: V, across: V
    /// How much the left leg is held up off the floor, knee bent, before the mistakes' flight
    /// and after it: a jump from one leg, or onto one.
    let lifted: (before: Double, after: Double)
    /// For a drop that is landed and held: the moment the landing is deepest, and the moment
    /// of the loop the body rises back to after it, in place of the keyframes' rebound.
    let rewind: (absorb: Double, back: Double)?
    /// The grips of a dumbbell in each hand, how far they reach and how far outside the
    /// shoulders they hang.
    let grips: [String: HandGrip]
    let reach: [String: Double]
    private(set) var out = 0.0
    /// Where a band round the hips is tied behind the jump.
    let anchor: V?
    let kinds: [PropKind]
    let fixed: [PropPiece]

    /// When the feet leave for the flight the mistakes are about, and when they land.
    var off: Double { stands[landing - 1].to }
    var land: Double { stands[landing].from }

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "box-jump" || guide.familyID == "broad-jump-bound" else { return nil }
        let words = CardioStagings.words(guide)
        var way = V(0, -1, 0)
        var course = Course.up
        var height = Self.top
        var lifted = (before: 0.0, after: 0.0)
        var weights = false, band = false
        // The words that say no more than "a jump onto a box".
        let plain: Set<String> = ["jump", "box", "on", "fit", "v", "2"]
        if guide.familyID == "broad-jump-bound" {
            height = 0
            switch guide.subtypeID {
            case nil:
                if words == ["resistance", "band", "long", "jump"], guide.equipment == "band" {
                    band = true
                } else {
                    // A jump that goes on into another one is not in the keyframes.
                    guard [["forward", "jump"], ["standing", "long", "jump"]].contains(words) else { return nil }
                }
                course = .leap(far: Self.far)
            case "frog":
                guard words == ["frog", "hops"] else { return nil }
                course = .leap(far: Self.hop)
            case "lateral-bound":
                // Off the right foot toward the body's left, and back.
                guard words == ["lateral", "bound"] else { return nil }
                (course, way) = (.bound, V(1, 0, 0))
            default: return nil
            }
        } else {
        switch guide.subtypeID {
        case nil:
            let name = guide.exerciseName
            if name.hasPrefix("2 to 1 "), words.isSubset(of: plain.union(["to", "1"])) {
                // Off two feet, onto one.
                lifted = (0, 1)
            } else if name.hasPrefix("1 to 2 "), words.isSubset(of: plain.union(["to", "1"])) {
                lifted = (1, 0)
            } else if words == ["dumbbell", "jump", "box"], guide.equipment == "dumbbell" {
                weights = true
            } else if words == ["jump", "box", "over"] {
                (course, height) = (.over, Self.low)
            } else if words == ["jump", "step", "box"] {
                // A step box is a low one.
                height = Self.low
            } else if words == ["jump", "pistol", "squat", "box"] {
                // Off one leg from a deep one-legged squat, and onto it.
                (lifted, height) = ((1, 1), Self.low)
            } else {
                // A plain jump onto a box, facing it.
                guard words.isSuperset(of: ["jump", "box"]), words.isSubset(of: plain) else { return nil }
            }
        case "lateral":
            // Side-on to the box, which is on the body's left.
            guard words == ["lateral", "box", "jump"] else { return nil }
            way = V(1, 0, 0)
        case "single-leg":
            if words == ["single", "leg", "box", "jump"] {
                (lifted, height) = ((1, 1), Self.low)
            } else if words == ["box", "jump", "down", "with", "one", "leg", "stabilization"] {
                // Off the box on two feet, landed and held on one.
                (course, lifted, height) = (.down, (0, 1), Self.low)
            } else {
                return nil
            }
        case "depth":
            if words.contains("land"), words.isSubset(of: ["box", "jump", "drop", "2", "foot", "land"]) {
                course = .depth(rebound: false)
            } else if words.isSubset(of: ["depth", "jump", "box", "drop", "bodyweight", "squat"]) {
                course = .depth(rebound: true)
            } else {
                // A hop over a hurdle or a broad jump after the landing is not in the keyframes.
                return nil
            }
        default: return nil
        }
        }
        guard guide.equipment == nil || guide.equipment == "none" || weights || band
                || (guide.equipment == "box" && guide.familyID == "box-jump") else { return nil }
        func moment(_ phase: String) -> Double? { guide.keyframes.first { $0.phase == phase }?.t }
        guard let ball = body.head["toes.r"], let tip = body.tail["toes.r"], let ankle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        self.course = course
        self.way = way
        self.height = height
        self.lifted = lifted
        across = way.cross(V(0, 0, 1))
        // Sampled finely: the moment of take-off has to be found to a few thousandths.
        loop = CardioLoop(guide, steps: 480)
        // How far the two feet reach from the middle of their balls, toward the box and away
        // from it: the toes and the heels, or half the stance and half a foot's width.
        let ahead = way.y < 0 ? ball.y - tip.y : abs(ball.x) + 0.06
        let behind = way.y < 0 ? ankle.y + 0.045 - ball.y : abs(ball.x) + 0.06
        // The spot on the floor where the hips are over the origin.
        let home = V(0, ball.y - pelvis.y, 0)
        let before: Feet = lifted.before > 0.5 ? .right : .both, after: Feet = lifted.after > 0.5 ? .right : .both
        var rewind: (absorb: Double, back: Double)?
        var least: [Double]
        let middle: V
        switch course {
        case .up, .over:
            guard let off = moment("Jump"), let land = moment("Land"), off < land else { return nil }
            // A dumbbell hangs a little ahead of the toes in the dip, and wants more room.
            let face = ahead + Self.gap + (weights ? 0.2 : 0)
            middle = home + way * (face + Self.deep / 2)
            if course == .up {
                // Lands in the middle of the top.
                let onTop = middle + way * ((behind - ahead) / 2) + V(0, 0, height)
                stands = [Stand(from: 0, to: off, ball: home, floor: 0, feet: before),
                          Stand(from: land, to: 1, ball: onTop, floor: height, feet: after)]
            } else {
                let far = home + way * (face + Self.deep + Self.gap + behind)
                stands = [Stand(from: 0, to: off, ball: home, floor: 0, feet: before),
                          Stand(from: land, to: 1, ball: far, floor: 0, feet: after)]
            }
            least = [0.2]
        case .down:
            guard let off = moment("Jump"), let land = moment("Land"), off < land else { return nil }
            // The box is behind the landing, far enough for a free leg held up behind to be
            // clear of it; the jump starts at its front edge.
            let face = behind + (lifted.after > 0 ? 0.65 : 0.3)
            middle = home - way * (face + Self.deep / 2)
            let edge = home - way * (face + ahead + 0.02) + V(0, 0, height)
            stands = [Stand(from: 0, to: off, ball: edge, floor: height, feet: before),
                      Stand(from: land, to: 1, ball: home, floor: 0, feet: after)]
            least = [0.08]
        case .depth(let rebound):
            guard let contact = moment("Contact"), let absorb = moment("Absorb"), let push = moment("Rebound"),
                  contact < absorb, absorb < push else { return nil }
            let face = behind + 0.2
            middle = home - way * (face + Self.deep / 2)
            // The keyframes step off with the right foot: the left stands at the edge.
            let edge = home - way * (face + ahead + 0.02) + V(0, 0, height)
            var all = [Stand(from: 0, to: contact * 0.25, ball: edge, floor: height, feet: .left)]
            if rebound {
                // The rebound comes down again halfway to the last keyframe, which is the
                // landing at its deepest.
                all.append(Stand(from: contact, to: push, ball: home, floor: 0, feet: .both))
                all.append(Stand(from: push + (1 - push) * 0.5, to: 1, ball: home, floor: 0, feet: .both))
                least = [0.02, 0.3]
            } else {
                all.append(Stand(from: contact, to: 1, ball: home, floor: 0, feet: .both))
                rewind = (absorb, contact)
                least = [0.02]
            }
            stands = all
        case .leap(let far):
            guard let off = moment("Drive"), let land = moment("Land"), off < land else { return nil }
            // Half the jump is behind the middle of the floor and half ahead of it.
            middle = home
            stands = [Stand(from: 0, to: off, ball: home - way * (far / 2), floor: 0, feet: .both),
                      Stand(from: land, to: 1, ball: home + way * (far / 2), floor: 0, feet: .both)]
            least = [0.25 * far]
        case .bound:
            let pushes = guide.keyframes.filter { $0.phase == "Push" }.map(\.t)
            guard let land = moment("Land"), pushes.count == 2, pushes[0] < land - 0.12, land < pushes[1], pushes[1] < 0.88 else { return nil }
            // The foot comes down a little before the landing is at its deepest.
            middle = home
            let right = home - way * (Self.stride / 2), left = home + way * (Self.stride / 2)
            stands = [Stand(from: 0, to: pushes[0], ball: right, floor: 0, feet: .right),
                      Stand(from: land - 0.1, to: pushes[1], ball: left, floor: 0, feet: .left),
                      Stand(from: 0.9, to: 1, ball: right, floor: 0, feet: .right)]
            least = [0.1, 0.1]
        }
        landing = 1
        self.rewind = rewind
        centre = middle + V(0, 0, height / 2)
        if height > 0 {
            fixed = [Plan.box(centre, (way.y < 0 ? Self.wide : Self.deep, way.y < 0 ? Self.deep : Self.wide, height), .wood)]
            anchor = nil
        } else if band {
            // The band is tied to a post behind the take-off.
            let foot = stands[0].ball - way * Self.post.behind
            fixed = [Plan.rod(V(foot.x, foot.y, 0), V(foot.x, foot.y, Self.post.height), 0.03, .metal)]
            anchor = V(foot.x, foot.y, Self.post.tie)
        } else {
            (fixed, anchor) = ([], nil)
        }
        rises = least

        var grips: [String: HandGrip] = [:], reach: [String: Double] = [:]
        if weights {
            for s in ["r", "l"] {
                guard let grip = body.grip(s, radius: LegWeights.dumbbellGrip, square: 0) else { return nil }
                grips[s] = grip
                reach[s] = body.reach(s, grip, bend: 4)
            }
        }
        self.grips = grips
        self.reach = reach
        kinds = height > 0 ? (weights ? [.box, .dumbbell] : [.box]) : (band ? [.band] : [])

        // The lowest arcs that carry the feet over the edges, with every mistake too.
        let faults: [JointPose?] = [nil] + loop.faults.map { Optional($0) }
        for i in rises.indices {
            while rises[i] < 0.8, !faults.allSatisfy({ clears($0, flight: i) }) { rises[i] += 0.025 }
        }
        // The dumbbells hang far enough out to pass the thighs at every moment of the loop.
        if weights {
            var out = 0.0
            for i in 0..<48 {
                let (g, root) = solve(at: Double(i) / 48, fault: nil)
                let h = body.place(g, root: root)
                let rods = body.bulk(g, h, walls: false)
                for (s, m) in CarryStaging.sides {
                    out = max(out, CarryStaging.clearance(.dumbbell, shoulder: h["humerus.\(s)"], m, reach: reach[s] ?? 0.6, swing: 0, rods))
                }
            }
            self.out = out
        }
    }

    /// The feet stay out of the box through the whole of a flight, and of a little room round
    /// its edges.
    func clears(_ fault: JointPose?, flight: Int) -> Bool {
        guard height > 0 else { return true }
        let from = stands[flight].to, to = stands[flight + 1].from
        for i in 1..<32 {
            let (g, root) = solve(at: from + (to - from) * Double(i) / 32, fault: fault)
            let h = body.place(g, root: root)
            for (p, skin) in body.contactPoints("feet", g, h) + body.contactPoints("toes", g, h) {
                let d = p - centre
                let along = d.dot(way), aside = d.dot(across)
                guard abs(aside) < Self.wide / 2 + 0.03, abs(along) < Self.deep / 2 + 0.04 else { continue }
                if p.z - skin < height - 0.001 { return false }
            }
        }
        return true
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        let solved = solve(at: found.t, fault: found.fault)
        var g = solved.g
        let root = solved.root
        var h = body.place(g, root: root)
        var props: [PropPiece] = []
        if !grips.isEmpty {
            // A dumbbell in each hand hangs straight down from its shoulder, beside the leg.
            for (s, m) in CarryStaging.sides {
                guard let grip = grips[s], let shoulder = h["humerus.\(s)"] else { continue }
                let point = CarryStaging.hanging(shoulder, m, off: out, reach: reach[s] ?? 0.6, swing: 0)
                body.hold(s, grip, at: point, across: V(0, 1, 0), pole: V(-m * 0.3, 1, 0), &g, h)
                props += CarryStaging.weight(.dumbbell, at: point, across: V(0, 1, 0), toward: V(0, 0, -1))
            }
            h = body.place(g, root: root)
        }
        if let anchor, let hips = h["pelvis"], let turn = g["pelvis"] {
            // The band goes round the front of the hips and back from each side to the post.
            let round = [V(-0.18, 0.02, 0.06), V(-0.13, -0.11, 0.06), V(0.13, -0.11, 0.06), V(0.18, 0.02, 0.06)].map { hips + turn * $0 }
            for (a, b) in zip(round, round.dropFirst()) { props.append(Plan.rod(a, b, Self.band, .accent)) }
            props.append(Plan.rod(round[0], anchor, Self.band, .accent))
            props.append(Plan.rod(round[3], anchor, Self.band, .accent))
        }
        return (body.made(g, h, floor: 0), props)
    }

    /// The moment of the keyframes shown at `t`: a held landing rises back the way it came
    /// down instead of going on to the rebound.
    func clock(_ t: Double) -> Double {
        guard let rewind, t > rewind.absorb else { return t }
        return rewind.absorb + (rewind.back - rewind.absorb) * CardioStagings.ease(t, from: rewind.absorb, to: 1)
    }

    /// How much the left leg is held up at `t`.
    func lift(at t: Double) -> Double {
        if t <= off { return lifted.before }
        if t >= land { return lifted.after }
        // Up, or down again, well before the landing.
        return lifted.before + (lifted.after - lifted.before) * CardioStagings.ease(t, from: off, to: off + 0.45 * (land - off))
    }

    /// The loop's pose at `t` with a mistake on it. The mistakes are all ways of landing
    /// badly, so one comes on as the body flies, is whole as the feet land, and goes again
    /// as the body stands up: the dip and the take-off stay as they should be.
    func pose(at t: Double, fault: JointPose?) -> JointPose {
        var pose = Figure.smooth(loop.closed, at: clock(t))
        let up = lift(at: t)
        if up > 0 {
            // The free leg hangs from a hip that follows the standing one a little, its knee
            // bent to keep the foot up behind.
            let hip = CardioStagings.angle(pose, "hipFlex")
            for (key, held) in [("hipFlexL", 0.4 * max(0, hip) + 5), ("kneeFlexL", 120), ("ankleDorsiL", 0)] {
                let own = CardioStagings.angle(pose, key)
                pose.angles[key] = own + (held - own) * up
            }
        }
        if !grips.isEmpty {
            // Hands that hold dumbbells do not swing overhead.
            for side in ["", "L"] { pose.angles.merge(["shoulderFlex" + side: 0, "shoulderAbd" + side: 0, "elbowFlex" + side: 8]) { $1 } }
        }
        guard var fault, t > off else { return pose }
        let end = stands[landing].to
        let share = t < land ? CardioStagings.ease((t - off) / (land - off), from: 0.2, to: 0.9)
            : 1 - CardioStagings.ease(t, from: land + 0.05, to: end)
        fault.angles = fault.angles.mapValues { $0 * share }
        if up > 0 { for key in ["hipFlexL", "kneeFlexL", "ankleDorsiL"] { fault.angles[key] = (fault.angles[key] ?? 0) * (1 - up) } }
        fault.scapula = nil
        pose = CardioStagings.applying(fault, to: pose)
        // A knee stops at straight.
        for key in ["kneeFlex", "kneeFlexL"] { if let v = pose.angles[key] { pose.angles[key] = max(0, v) } }
        return pose
    }

    /// The posed body with its feet on a surface at height `floor`, the ball of the standing
    /// foot (or the middle of both) over `ball`: `air` 0 standing on it, 1 flying above it.
    /// `tuck` bends a knee further by so many degrees, and `feet`, where given, are the feet
    /// the body's height is taken from in place of those that bear it.
    func placed(at t: Double, fault: JointPose?, ball: V, floor: Double, air: Double, bearing: [String: Double],
                tuck: [String: Double] = [:], feet: [String: Double]? = nil) -> (g: [String: M], root: V) {
        var pose = pose(at: t, fault: fault)
        for (key, more) in tuck where more > 0 { pose.angles[key] = CardioStagings.angle(pose, key) + more }
        var g = body.rotations(pose)
        if grips.isEmpty { CardioFooting.steadyArms(body, &g, pose) }
        // A foot with no weight on it is in the air wherever the other is.
        g = CardioFooting.settle(g, air: bearing.mapValues { 1 - (1 - air) * $0 })
        return (g, CardioFooting.root(body, g, ball: ball, floor: floor, bearing: feet ?? bearing))
    }

    /// A bound's stand on one foot. The keyframes reach the other leg out for the landing
    /// while this one is still pushing, which would put its foot through the floor: its knee
    /// bends as much further as keeps the foot clear. With the body, the knee and its extra bend.
    func bounded(at t: Double, fault: JointPose?, stand: Stand) -> (body: (g: [String: M], root: V), knee: String, more: Double) {
        let (word, knee) = stand.feet == .right ? ("left", "kneeFlexL") : ("right", "kneeFlex")
        func tried(_ more: Double) -> (body: (g: [String: M], root: V), gap: Double) {
            let out = placed(at: t, fault: fault, ball: stand.ball, floor: stand.floor, air: 0, bearing: stand.feet.bearing, tuck: [knee: more])
            let h = body.place(out.g, root: out.root)
            let points = body.contactPoints(word + " feet", out.g, h) + body.contactPoints(word + " toes", out.g, h)
            return (out, (points.map { $0.0.z - $0.1 }.min() ?? 1) - stand.floor)
        }
        let plain = tried(0)
        if plain.gap >= Self.free { return (plain.body, knee, 0) }
        var from = 0.0, to = 80.0
        for _ in 0..<10 {
            let mid = (from + to) / 2
            if tried(mid).gap >= Self.free { to = mid } else { from = mid }
        }
        return (tried(to).body, knee, to)
    }

    func solve(at t: Double, fault: JointPose?) -> (g: [String: M], root: V) {
        if let stand = stands.first(where: { t >= $0.from && t <= $0.to }) {
            if course == .bound { return bounded(at: t, fault: fault, stand: stand).body }
            return placed(at: t, fault: fault, ball: stand.ball, floor: stand.floor, air: 0, bearing: stand.feet.bearing)
        }
        guard let next = stands.firstIndex(where: { t < $0.from }), next > 0 else {
            let last = stands[stands.count - 1]
            return placed(at: t, fault: fault, ball: last.ball, floor: last.floor, air: 0, bearing: last.feet.bearing)
        }
        // In flight the feet lead, as if the floor under them rose or fell from one surface
        // to the other and a little over, and the legs are the keyframes' own, so the hips
        // are wherever the tuck leaves them above the feet. Going up the feet rise first and
        // cross later; going down they cross first, and drop once they are past the edge.
        let a = stands[next - 1], b = stands[next]
        let u = (t - a.to) / (b.from - a.to)
        let air = CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.25)
        let climb = b.floor > a.floor ? 1 - (1 - u) * (1 - u) : u * u
        let cross = b.floor > a.floor ? u * u : b.floor < a.floor ? 1 - (1 - u) * (1 - u) : u
        let floor = a.floor + (b.floor - a.floor) * climb + 4 * rises[next - 1] * u * (1 - u)
        // The weight changes feet once a leg that lifts or comes down has done so.
        let share = CardioStagings.ease(u, from: 0.45, to: 0.8)
        var bearing: [String: Double] = [:]
        for s in ["r", "l"] {
            let was = a.feet.bearing[s] ?? 0, will = b.feet.bearing[s] ?? 0
            bearing[s] = was + (will - was) * share
        }
        guard course == .bound else {
            return placed(at: t, fault: fault, ball: mix(a.ball, b.ball, cross), floor: floor, air: air, bearing: bearing)
        }
        // In a bound the free leg comes out of its tuck as the body leaves the floor, and the
        // leg that pushed off goes into its own before the other lands. Whichever foot is
        // lower is the one on the arc.
        let before = bounded(at: a.to, fault: fault, stand: a), after = bounded(at: b.from, fault: fault, stand: b)
        let leaves = CardioStagings.ease(u, from: 0, to: 0.5), arrives = CardioStagings.ease(u, from: 0.5, to: 1)
        var weight: [String: Double] = [:]
        for s in ["r", "l"] { weight[s] = (a.feet.bearing[s] ?? 0) * (1 - arrives) + (b.feet.bearing[s] ?? 0) * leaves }
        var out = placed(at: t, fault: fault, ball: mix(a.ball, b.ball, cross), floor: floor, air: air, bearing: weight,
                         tuck: [before.knee: before.more * (1 - leaves), after.knee: after.more * arrives], feet: ["r": 1, "l": 1])
        do {
            // The two feet of a bound stand far apart, so each flies to its own spot: the hips
            // go from over the one that pushed off to over the one that lands.
            let rel = body.place(out.g, root: V(0, 0, 0))
            func over(_ stand: Stand) -> V {
                var mid = V(0, 0, 0), weight = 0.0
                for (s, w) in stand.feet.bearing where w > 0 { mid = mid + (rel["toes.\(s)"] ?? V(0, 0, 0)) * w; weight += w }
                return stand.ball - mid * (1 / max(weight, 1e-9))
            }
            let from = over(a), to = over(b)
            out.root = V(from.x + (to.x - from.x) * u, from.y + (to.y - from.y) * u, out.root.z)
        }
        return out
    }
}

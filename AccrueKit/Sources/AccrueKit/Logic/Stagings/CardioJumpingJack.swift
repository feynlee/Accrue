import Foundation

/// Jumping jacks. The body hops on the spot: the feet leave the floor, land wide, leave it
/// again and land together, and while they are down they stay where they landed. A squat jack
/// lands wide in a squat; a star jump is one high jump with the legs wide in the air; a step
/// jack has no flight at all, one foot stepping out to the side and back, then the other.
struct CardioJumpingJackStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How high the feet come off the floor in a hop, and how long each hop is, as a share of the loop.
    static let height = 0.06, flight = 0.3
    /// How high a star jump is, how long it is in the air, and how much wider than the
    /// keyframes' landing the legs open in it.
    static let star = 0.25, starFlight = 0.44, starSpread = 1.5
    /// How far a stepping foot's knee and hip bend to carry it clear of the floor, in degrees.
    static let stepKnee = 16.0, stepHip = 8.0

    enum Style: Sendable { case hops, star, steps }

    let body: Body3D
    let loop: CardioLoop
    let style: Style
    /// The middle of the hop out and the middle of the hop back in (or of the one star jump),
    /// and the moment the legs are widest.
    let out: Double, back: Double, wide: Double
    /// How far the legs are spread while the feet stand wide, in degrees.
    let spread: Double
    /// Where the balls of the feet, taken together, stay, and where each stands when they are together.
    let spot: V
    let stood: [String: V]
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "jumping-jack", guide.equipment == nil || guide.equipment == "none",
              let ball = body.head["toes.r"], let left = body.head["toes.l"], let pelvis = body.head["pelvis"] else { return nil }
        let words = CardioStagings.words(guide)
        let frames = guide.keyframes
        func moment(_ phase: String) -> Double? { frames.first { $0.phase == phase }?.t }
        // The keyframe that stands widest, and how wide.
        guard let wide = frames.max(by: { CardioStagings.angle($0.pose, "hipAbd") < CardioStagings.angle($1.pose, "hipAbd") }),
              wide.t > 0, wide.t < 1 else { return nil }
        let style: Style
        var out = wide.t / 2, back = (1 + wide.t) / 2
        switch guide.subtypeID {
        case nil:
            // The plain jack: jacks mixed with lunges or high knees are other movements.
            guard [["jumping", "jack"], ["astride", "jumps", "male"]].contains(words),
                  let o = moment("Out"), let b = moment("In") else { return nil }
            (style, out, back) = (.hops, o, b)
        case "squat-jack":
            guard [["squat", "jacks"], ["squat", "jack"], ["low", "jacks"], ["plyo", "jacks"]].contains(words) else { return nil }
            style = .hops
        case "star":
            guard [["star", "jump", "male"], ["jack", "jump", "male"]].contains(words) else { return nil }
            (style, out, back) = (.star, wide.t, wide.t)
        case "step-jack":
            guard [["jack", "step"], ["alternating", "step", "out"]].contains(words) else { return nil }
            style = .steps
        default: return nil
        }
        let span = style == .star ? Self.starFlight : Self.flight
        guard out - span / 2 > 0, back + span / 2 < 1, style == .star || out + span / 2 < back - span / 2 else { return nil }
        self.body = body
        self.style = style
        self.out = out
        self.back = back
        self.wide = wide.t
        spread = CardioStagings.angle(wide.pose, "hipAbd")
        loop = CardioLoop(guide, steps: 384)
        spot = V(0, ball.y - pelvis.y, 0)
        stood = ["r": V(ball.x - pelvis.x, ball.y - pelvis.y, 0), "l": V(left.x - pelvis.x, left.y - pelvis.y, 0)]
    }

    /// How high the feet are at `t`, and how far into the air (0 on the floor, 1 well off it).
    func hop(at t: Double) -> (height: Double, air: Double) {
        switch style {
        case .steps: return (0, 0)
        case .star:
            let u = (t - out) / Self.starFlight + 0.5
            guard u > 0, u < 1 else { return (0, 0) }
            return (4 * Self.star * u * (1 - u), CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.2))
        case .hops:
            for middle in [out, back] {
                let u = (t - middle) / Self.flight + 0.5
                if u > 0, u < 1 { return (4 * Self.height * u * (1 - u), CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.25)) }
            }
            return (0, 0)
        }
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        if style == .steps { return stepping(at: found.t, fault: found.fault) }
        let clean = Figure.smooth(loop.closed, at: found.t)
        var pose = found.fault.map { CardioStagings.applying($0, to: clean) } ?? clean
        let (height, air) = hop(at: found.t)
        // Feet on the floor do not slide: the legs keep the spread they landed with, and
        // open or close only in the air. A star jump lands as it took off, feet together.
        let landed = style == .hops && found.t > out && found.t < back ? spread : 0
        let wider = style == .star ? Self.starSpread : 1
        for key in ["hipAbd", "hipAbdL"] {
            let own = CardioStagings.angle(clean, key)
            pose.angles[key] = CardioStagings.angle(pose, key) - own + own * wider * air + landed * (1 - air)
        }
        let g = CardioFooting.settle(body.rotations(pose), air: ["r": air, "l": air])
        let root = CardioFooting.root(body, g, ball: spot, floor: height)
        return (body.made(g, body.place(g, root: root), floor: 0), [])
    }

    /// A step jack at `t`. The loop's one jack is gone through twice, so that each foot has a
    /// turn: the first time the right foot steps out and back, the second time the left. The
    /// other foot stays where it stands, and the hips move over between the two.
    func stepping(at t: Double, fault: JointPose?) -> (body: BodyFrame, props: [PropPiece]) {
        let (side, other, time) = t < 0.5 ? ("", "L", 2 * t) : ("L", "", 2 * t - 1)
        var clean = Figure.smooth(loop.closed, at: time)
        // The loop's end is not quite its start (the knees give a little more as the feet
        // come together); gone through twice in a row, the end runs into the start.
        if let first = loop.closed.first?.pose, let last = loop.closed.last?.pose {
            let share = CardioStagings.ease(time, from: 0.75, to: 1)
            for key in loop.keys {
                clean.angles[key] = CardioStagings.angle(clean, key) + (CardioStagings.angle(first, key) - CardioStagings.angle(last, key)) * share
            }
        }
        var pose = fault.map { CardioStagings.applying($0, to: clean) } ?? clean
        // The foot is put down wide a little before the legs are widest and stays there a
        // little after, and likewise together: it does not slide while it is down.
        let own = spread > 0 ? CardioStagings.angle(clean, "hipAbd") / spread : 0
        let open = CardioStagings.ease(own, from: 0.15, to: 0.75)
        // Off the floor as soon as it moves, and level so that the toes do not drag.
        let lift = CardioStagings.ease(open * (1 - open), from: 0, to: 0.06)
        for key in ["hipAbd", "hipAbdL"] {
            pose.angles[key] = CardioStagings.angle(pose, key) - CardioStagings.angle(clean, key) + spread * open
        }
        // With no jump there is no push off the toes: the heels stay down.
        for key in ["ankleDorsi", "ankleDorsiL"] { pose.angles[key] = max(0, CardioStagings.angle(pose, key)) }
        pose.angles["kneeFlex" + side] = CardioStagings.angle(pose, "kneeFlex" + side) + Self.stepKnee * lift
        pose.angles["hipFlex" + side] = CardioStagings.angle(pose, "hipFlex" + side) + Self.stepHip * lift
        let stepper = side == "" ? "r" : "l", stander = other == "" ? "r" : "l"
        var g = CardioFooting.settle(body.rotations(pose), air: [stepper: 0, stander: 0])
        // A foot that is carried across is held level, so its toes do not drag.
        if lift > 0, let foot = g["foot.\(stepper)"] {
            let f = foot * V(0, -1, 0)
            let flat = V(f.x, f.y, 0).length > 1e-6 ? V(f.x, f.y, 0).unit : V(0, -1, 0)
            let level = CardioBurpeeStaging.between(foot, Body3D.frameMap(V(0, -1, 0), V(0, 0, 1), to: flat, V(0, 0, 1)), lift)
            g["foot.\(stepper)"] = level
            g["toes.\(stepper)"] = level
        }
        let root = CardioFooting.root(body, g, ball: stood[stander] ?? spot, floor: 0, bearing: [stander: 1, stepper: 0])
        return (body.made(g, body.place(g, root: root), floor: 0), [])
    }
}

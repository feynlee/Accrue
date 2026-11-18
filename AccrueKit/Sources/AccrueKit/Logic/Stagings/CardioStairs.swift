import Foundation

/// Climbing stairs on the spot: the steps come down and back under the body as a stepmill's
/// do, two to a loop. Each foot lands flat on a step in front, rides it down until the leg is
/// long under the hips, then lifts and swings up over the next step's edge to land again. The
/// hips stay where they are. Plain stairs are shown the same way, without the machine.
struct CardioStairsStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let rise = 0.18, run = 0.26, width = 0.7
    /// The share of its cycle each foot spends on a step.
    static let stance = 0.6
    static let hipHeight = 1.15

    let body: Body3D
    let mill: Bool
    let loop: CardioLoop
    let feet: [String: CardioFoot]
    /// Each ankle where its foot lands, and where the hips stay.
    let landing: [String: V]
    let hip: V
    let kinds: [PropKind] = [.stairs]
    let fixed: [PropPiece]

    /// A step's travel in one step's time: down and back.
    static let step = V(0, run, -rise)

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "stair-climb", guide.subtypeID == nil,
              let fr = CardioFoot(body, "r"), let fl = CardioFoot(body, "l"),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"] else { return nil }
        let words = CardioStagings.words(guide)
        if words == ["walking", "on", "stepmill"] {
            mill = true
        } else if words == ["stair", "up"] {
            mill = false
        } else {
            return nil
        }
        self.body = body
        feet = ["r": fr, "l": fl]
        loop = CardioLoop(guide)
        hip = V(0, 0, Self.hipHeight)

        // Where a foot lands: the leg bent as the keyframes bend it at contact, and long (but
        // not locked) when the step has carried it to where it lifts off.
        let bends = guide.keyframes.map { CardioStagings.angle($0.pose, "kneeFlex") }
        let thigh = (rKnee - rHip).length, shin = (rAnkle - rKnee).length
        let short = Body3D.span(thigh, shin, bend: min(90, max(50, bends.first ?? 70)))
        let long = Body3D.span(thigh, shin, bend: 14)
        let ride = Self.step * (2 * Self.stance)
        // |a| = short and |a + ride| = long, for a landing in front of the hips.
        let k = (long * long - short * short - ride.dot(ride)) / 2
        let turn = atan2(ride.y, -ride.z), reach = hypot(ride.y, ride.z) * short
        let angle = acos(min(1, max(-1, k / reach))) - turn
        let a = V(0, -short * sin(angle), -short * cos(angle))
        landing = ["r": hip + V(rHip.x, 0, 0) + a, "l": hip + V(-rHip.x, 0, 0) + a]
        fixed = mill ? Self.machine(top: hip.z + a.z - body.ankleHeight, at: a.y) : []
    }

    /// How far through its own cycle each foot is at moment `t` of the loop: 0 as it lands.
    /// The keyframes give the right foot more of the loop than the left, so the loop's time
    /// is eased to bring the left foot's landing to the half-way point.
    static func cycle(_ s: String, at t: Double) -> Double {
        let even = t - 0.1 * sin(.pi * t) * sin(.pi * t)
        let own = s == "r" ? even : even + 0.5
        return own - own.rounded(.down)
    }

    /// One ankle and its foot's rotation, `own` of the way through the foot's cycle. `heel`
    /// lifts the heel while the foot is on its step, in degrees.
    func foot(_ s: String, at own: Double, heel: Double) -> (ankle: V, turn: M) {
        guard let land = landing[s], let foot = feet[s] else { return (hip, .identity) }
        if own < Self.stance {
            let turn = M.x(heel)
            // The ball of the foot stays on the step when the heel comes up.
            return (land + Self.step * (2 * own) - foot.toAnkle + turn * foot.toAnkle, turn)
        }
        // Up first, to clear the edge of the next step, and then forward and down onto it.
        let u = (own - Self.stance) / (1 - Self.stance)
        let from = land + Self.step * (2 * Self.stance)
        let up = CardioStagings.ease(u, from: 0, to: 0.5), on = CardioStagings.ease(u, from: 0.32, to: 1)
        let ankle = V(land.x, from.y + (land.y - from.y) * on, from.z + (land.z - from.z) * up + 0.1 * sin(.pi * u))
        return (ankle, M.x(heel * (1 - u) + 22 * sin(.pi * u)))
    }

    /// The steps there are to see at moment `t`: each a block down to the floor.
    func steps(at t: Double) -> [PropPiece] {
        guard let land = landing["r"], let foot = feet["r"] else { return [] }
        let moved = 2 * Self.cycle("r", at: t)
        let top = land.z - foot.ankleHeight
        // The heel stands just inside the step's near edge.
        let edge = land.y + 0.075
        var p: [PropPiece] = []
        for j in -4...8 {
            let below = moved - Double(j)
            let z = top - below * Self.rise
            guard z > 0.1, below > -2.6 else { continue }
            let y = edge + below * Self.run
            p.append(Plan.box(V(0, y - Self.run / 2, z / 2), (Self.width, Self.run, z), .dark))
        }
        return p
    }

    /// A stepmill's base, hand rails and console round the moving steps.
    static func machine(top: Double, at y: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        let x = width / 2 + 0.03
        let front = y - 3 * run, back = y + 3.2 * run
        for m in [-1.0, 1.0] {
            // A rail each side, from a post at the foot of the flight up to the console.
            p.append(Plan.rod(V(m * x, back - 0.1, 0.06), V(m * x, back - 0.1, 0.25), 0.025, .metal))
            p.append(Plan.rod(V(m * x, back - 0.1, 0.25), V(m * x, y + 0.45, top + 0.75), 0.02, .metal))
            p.append(Plan.rod(V(m * x, y + 0.45, top + 0.75), V(m * x, front + 0.1, top + 1.05), 0.02, .dark))
            p.append(Plan.rod(V(m * x, front + 0.1, 0.06), V(m * x, front + 0.1, top + 1.05), 0.025, .metal))
        }
        p.append(Plan.box(V(0, (front + back) / 2, 0.03), (2 * x + 0.1, back - front, 0.06), .metal))
        p.append(Plan.rod(V(-x, front + 0.1, top + 1.05), V(x, front + 0.1, top + 1.05), 0.02, .metal))
        p.append(Plan.box(V(0, front + 0.1, top + 1.15), (0.3, 0.05, 0.2), x: side, z: V(0, 0.4, 1), .dark))
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        var good = Figure.smooth(loop.closed, at: found.t)
        // The legs are fitted to the steps; a mistake still shows in the trunk, the head and
        // the arms, and in the knees and heels as far as the steps allow.
        let fault = found.fault?.angles ?? [:]
        for (key, value) in fault where !["hipFlex", "kneeFlex", "ankleDorsi", "hipFlexL", "kneeFlexL", "ankleDorsiL"].contains(key) {
            good.angles[key] = (good.angles[key] ?? 0) + value
        }
        var g = body.rotations(good)
        var h = body.place(g, root: hip)
        let caved = min(0, (fault["hipAbd"] ?? 0) + (fault["hipRot"] ?? 0)) * 0.014
        let heel = max(0, -(fault["ankleDorsi"] ?? 0))
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            let on = foot(s, at: Self.cycle(s, at: found.t), heel: heel)
            body.plant(s, ankle: on.ankle, foot: on.turn, pole: V(-m * caved, -1, 0.3), &g, h)
            if heel > 0, Self.cycle(s, at: found.t) < Self.stance { g["toes.\(s)"] = .identity }
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), steps(at: found.t))
    }
}

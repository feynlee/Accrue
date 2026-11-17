import Foundation

/// An exercise bike: the hips on the saddle, the balls of the feet on pedals that go round on
/// their cranks, the hands on the handlebar. The saddle is set to the legs (the knee keeps the
/// bend the keyframes give it at the bottom of the stroke), and the pedals turn once per loop;
/// the legs follow the pedals. An air bike's handles rock against the legs.
struct CardioBikeStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    enum Style: Sendable { case upright, air }

    static let crank = 0.17, gripRadius = 0.016, axleHeight = 0.33
    /// The hip joints of a sitting body are this far above what it sits on.
    static let sit = 0.095
    static let pedal = (wide: 0.1, long: 0.09, thick: 0.025)
    /// How far back the seat tube leans, in degrees.
    static let lean = 17.0

    let body: Body3D
    let style: Style
    let phase: CardioLoop
    let grips: [String: HandGrip]
    let feet: [String: CardioFoot]
    /// The middle of the hip joints with the saddle at the right height, and the crank's axle.
    let hip: V, axle: V
    /// From the hips to the axle, and the way a pedal goes on from the top of its circle.
    let down: V, push: V
    /// The middle of the handlebar, and half the distance between the hands.
    let bar: V
    let halfGrip: Double
    let kinds: [PropKind] = [.bike]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let style = Self.style(for: guide),
              let r = body.grip("r", radius: Self.gripRadius, square: 0.3), let l = body.grip("l", radius: Self.gripRadius, square: 0.3),
              let fr = CardioFoot(body, "r"), let fl = CardioFoot(body, "l"),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.style = style
        grips = ["r": r, "l": l]
        feet = ["r": fr, "l": fl]
        phase = CardioLoop(guide, keys: ["hipFlex", "kneeFlex", "hipFlexL", "kneeFlexL"])
        let a = Self.lean * .pi / 180
        let down = V(0, -sin(a), -cos(a))
        let push = down.cross(V(1, 0, 0))
        self.down = down
        self.push = push

        // The saddle's height: at the far side of the pedal's circle the knee is bent as much
        // as the keyframes bend it at the bottom of the stroke.
        let least = guide.keyframes.map { CardioStagings.angle($0.pose, "kneeFlex") }.min() ?? 30
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: min(45, max(20, least)))
        func farthest(_ distance: Double) -> Double {
            (0..<48).map { i in
                let t = Double(i) / 48
                let ankle = Self.foot("r", at: t, heel: 0, axle: down * distance, down: down, push: push, fr).ankle
                return (ankle - V(rHip.x - (body.head["pelvis"]?.x ?? 0), 0, 0)).length
            }.max() ?? distance
        }
        var low = 0.3, high = 1.2
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if farthest(mid) < leg { low = mid } else { high = mid }
        }
        let hip = V(0, 0, Self.axleHeight - down.z * low)
        let axle = hip + down * low
        self.hip = hip
        self.axle = axle

        // The handlebar is where the keyframes' arms hold the hands.
        let g = body.rotations(first)
        let h = body.place(g, root: hip)
        var mid = V(0, 0, 0), half = 0.0
        for s in ["r", "l"] {
            guard let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"], let grip = grips[s] else { return nil }
            let c = wrist + hand * grip.centre
            mid = mid + c * 0.5
            half += abs(c.x) / 2
        }
        mid.x = 0
        bar = mid
        halfGrip = min(0.24, max(0.17, half))
        fixed = Self.frame(style, hip: hip, axle: axle, down: down, bar: bar, halfGrip: halfGrip)
    }

    /// Which bike the name describes, or nil for one this staging does not show honestly:
    /// a recumbent and an arm crank are other machines, and a bicycle on the road has wheels.
    static func style(for guide: HowToGuide) -> Style? {
        guard guide.familyID == "stationary-bike", guide.subtypeID == "upright" else { return nil }
        let words = CardioStagings.words(guide)
        if !words.isDisjoint(with: ["assault", "air", "airdyne"]) { return .air }
        return .upright
    }

    /// One foot on its pedal at moment `t` of the loop: the pedal's axle, the foot's rotation
    /// and where the ankle is. `heel` lifts the heel further, in degrees.
    static func foot(_ s: String, at t: Double, heel: Double, axle: V, down: V, push: V, _ foot: CardioFoot)
        -> (pedal: V, turn: M, ankle: V) {
        let m = s == "r" ? 1.0 : -1.0
        let own = 2 * Double.pi * (s == "r" ? t : t + 0.5)
        let x = -m * (abs(foot.ball.x) + 0.015)
        let pedal = axle + V(x, 0, 0) + (down * -cos(own) + push * sin(own)) * crank
        // The foot is nearly level over the top and points its toes down round the bottom.
        let turn = M.x(9 - 11 * cos(own - 0.25) + heel)
        let ball = pedal + turn * V(0, 0, 1) * (Self.pedal.thick / 2 + foot.ballHeight)
        return (pedal, turn, ball + turn * foot.toAnkle)
    }

    /// Each handle of an air bike at moment `t`: it rocks about a pivot low on the frame,
    /// forward as the same side's pedal comes back.
    func handle(_ s: String, at t: Double) -> (grip: V, pivot: V) {
        let m = s == "r" ? 1.0 : -1.0
        var rest = bar + V(-m * halfGrip, 0, 0)
        guard style == .air else { return (rest, rest) }
        // Nearer than a fixed bar would be, so the arm still has reach at the front of the swing.
        rest.y += 0.04
        let pivot = V(rest.x, axle.y - 0.2, axle.z + 0.16)
        let own = 2 * Double.pi * (s == "r" ? t : t + 0.5)
        return (pivot + M.x(-8 * sin(own)) * (rest - pivot), pivot)
    }

    /// The base, the frame, the flywheel or fan, and a fixed handlebar.
    static func frame(_ style: Style, hip: V, axle: V, down: V, bar: V, halfGrip: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        let radius = style == .air ? 0.31 : 0.24
        let wheel = V(0, axle.y - (style == .air ? 0.6 : 0.5), radius + 0.06)
        let rear = hip.y + 0.3, front = wheel.y - 0.14
        // Two feet across and a beam between them.
        for y in [rear, front] { p.append(Plan.box(V(0, y, 0.025), (0.52, 0.07, 0.05), .metal)) }
        p.append(Plan.box(V(0, (rear + front) / 2, 0.05), (0.07, rear - front, 0.05), .metal))
        // The seat tube up from the axle, and its stays.
        let collar = hip + down * 0.3
        p.append(Plan.rod(axle + down * 0.05, collar, 0.03, .metal))
        p.append(Plan.rod(axle, V(0, rear, 0.05), 0.025, .metal))
        p.append(Plan.rod(V(0, axle.y, 0.05), axle, 0.03, .metal))
        // The wheel in front, in its fork, and the post up to the handlebar.
        p.append(Plan.disc(wheel, axis: side, radius: radius, thickness: style == .air ? 0.1 : 0.05, .dark))
        p.append(Plan.disc(wheel, axis: side, radius: radius * 0.45, thickness: style == .air ? 0.12 : 0.07, .metal))
        p.append(Plan.rod(axle, wheel, 0.025, .metal))
        p.append(Plan.rod(V(0, front, 0.05), wheel, 0.025, .metal))
        let head = V(0, bar.y + 0.12, bar.z - 0.32)
        p.append(Plan.rod(wheel, head, 0.03, .metal))
        p.append(Plan.rod(axle, head, 0.025, .metal))
        // The chainring on the axle.
        p.append(Plan.rod(axle - side * 0.08, axle + side * 0.08, 0.014, .metal))
        p.append(Plan.disc(axle - side * 0.05, axis: side, radius: 0.1, thickness: 0.012, .metal))
        switch style {
        case .upright:
            p.append(Plan.rod(head, bar + V(0, 0.03, -0.02), 0.02, .metal))
            p.append(Plan.rod(bar + V(0, 0.03, -0.02), bar, 0.014, .metal))
            p.append(Plan.rod(bar - side * (halfGrip + 0.07), bar + side * (halfGrip + 0.07), gripRadius, .dark))
        case .air:
            // A monitor where the handlebar would be.
            let screen = bar + V(0, 0.02, 0.05)
            p.append(Plan.rod(head, screen, 0.02, .metal))
            p.append(Plan.box(screen, (0.16, 0.03, 0.11), x: side, z: V(0, 0.3, 1), .dark))
            // The shaft the two handles' levers rock on, on a strut from the frame.
            let shaft = V(0, axle.y - 0.2, axle.z + 0.16)
            p.append(Plan.rod(shaft - side * (halfGrip + 0.11), shaft + side * (halfGrip + 0.11), 0.016, .metal))
            p.append(Plan.rod(axle, shaft, 0.022, .metal))
        }
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let t = phase(pose)
        // A saddle set too low or too high: the hips sit where the knees' extra bend puts them.
        let bent = (phase.off("kneeFlex", pose, at: t) + phase.off("kneeFlexL", pose, at: t)) / 2
        let root = hip + down * (min(25, max(-25, bent)) * 0.004)
        // Knees that cave in point inside the feet.
        let caved = min(0, phase.off("hipAbd", pose, at: t) + phase.off("hipRot", pose, at: t)) * 0.012
        var h = body.place(g, root: root)
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let foot = feet[s] else { continue }
            let heel = -0.6 * phase.off(s == "r" ? "ankleDorsi" : "ankleDorsiL", pose, at: t)
            let on = Self.foot(s, at: t, heel: heel, axle: axle, down: down, push: push, foot)
            body.plant(s, ankle: on.ankle, foot: on.turn, pole: V(-m * caved, -1, 0.5), &g, h)
            // The crank from the axle, the pedal's spindle and the pedal under the foot.
            let inner = V(-m * 0.08, axle.y, axle.z), outer = V(-m * 0.08, on.pedal.y, on.pedal.z)
            p.append(Plan.rod(inner, outer, 0.013, .metal))
            p.append(Plan.rod(outer, on.pedal, 0.008, .metal))
            p.append(Plan.box(on.pedal, (Self.pedal.wide, Self.pedal.long, Self.pedal.thick), x: side, z: on.turn * V(0, 0, 1), .dark))
        }
        h = body.place(g, root: root)
        let thorax = g["thorax"] ?? .identity
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            let lever = handle(s, at: t)
            body.hold(s, grip, at: lever.grip, across: V(-m, 0, 0), pole: thorax * V(-m * 0.7, 0.2, -1), &g, h)
            guard style == .air else { continue }
            // The handle's lever up from its pivot, cranked in over the grip.
            let top = lever.grip + V(-m * 0.09, 0, 0)
            p.append(Plan.rod(lever.pivot + V(-m * 0.09, 0, 0), top, 0.016, .metal))
            p.append(Plan.rod(top, lever.grip + V(m * 0.06, 0, 0), Self.gripRadius, .dark))
            p.append(Plan.ball(lever.pivot + V(-m * 0.09, 0, 0), 0.03, .metal))
        }
        h = body.place(g, root: root)
        // The saddle on its post, under the hips.
        let top = root + V(0, 0.02, -Self.sit)
        p.append(Plan.box(top + V(0, 0.02, -0.03), (0.17, 0.16, 0.06), .dark))
        p.append(Plan.box(top + V(0, -0.12, -0.03), (0.07, 0.16, 0.05), .dark))
        p.append(Plan.rod(hip + down * 0.32, top + V(0, 0, -0.05), 0.018, .metal))
        return (body.made(g, h, floor: 0), p)
    }
}

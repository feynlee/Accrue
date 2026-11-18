import Foundation

/// A rowing machine: the hips on a seat that rolls along a rail, the feet on fixed footplates,
/// both hands on one handle that a chain draws out of the flywheel housing. The knees' bend
/// decides where the seat is, so the legs push the body away and the seat goes with it; the
/// trunk swings as the keyframes say, and the handle comes from long arms to the lower ribs
/// as the elbows bend.
struct CardioRowerStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let seatTop = 0.36, handleRadius = 0.016, halfHandle = 0.26
    /// How steeply the footplates stand, and how far the hip joints sit above the ankles.
    static let tilt = 45.0, drop = 0.14
    /// The hip joints of a sitting body are this far above what it sits on.
    static let sit = 0.095

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    let feet: [String: CardioFoot]
    /// The ball of each foot, fixed on its plate.
    let balls: [String: V]
    let halfGrip: Double
    /// Where the chain leaves the flywheel housing.
    let exit: V
    let kinds: [PropKind] = [.rower]
    let fixed: [PropPiece]

    var hipHeight: Double { Self.seatTop + Self.sit }

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "row-erg",
              let r = body.grip("r", radius: Self.handleRadius, square: 0.5),
              let l = body.grip("l", radius: Self.handleRadius, square: 0.5),
              let fr = CardioFoot(body, "r"), let fl = CardioFoot(body, "l"),
              let hipR = body.head["femur.r"], let shoulder = body.head["humerus.r"] else { return nil }
        self.body = body
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        feet = ["r": fr, "l": fl]
        halfGrip = min(0.2, abs(shoulder.x))
        let flat = M.x(-Self.tilt)
        var balls: [String: V] = [:]
        for (s, m, foot) in [("r", 1.0, fr), ("l", -1.0, fl)] {
            let ankle = V(-m * (abs(hipR.x) + 0.03), 0, Self.seatTop + Self.sit - Self.drop)
            balls[s] = ankle - flat * foot.toAnkle
        }
        self.balls = balls

        // The machine is as long as the body: the chain comes out a hand's length beyond the
        // handle at the catch, and the rail runs on past the seat at the finish.
        var exit = V(0, -0.8, Self.seatTop + Self.sit + 0.25)
        var reach = (front: 0.0, back: 0.0)
        for _ in 0..<2 {
            let probe = Probe(body: body, progress: progress, grips: grips, feet: feet, balls: balls, halfGrip: halfGrip, exit: exit)
            let loop = (0...24).map { probe.solve(Figure.smooth(guide.keyframes, at: Double($0) / 24)) }
            reach = (loop.map(\.handle.y).min() ?? -0.5, loop.map(\.seat).max() ?? 0.8)
            exit.y = reach.front - 0.13
        }
        self.exit = exit
        fixed = Self.frame(balls: balls, feet: feet, exit: exit, back: reach.back)
    }

    /// The part of the staging that finds the body, apart from the machine that is built from it.
    struct Probe: Sendable {
        let body: Body3D
        let progress: PullProgress
        let grips: [String: HandGrip]
        let feet: [String: CardioFoot]
        let balls: [String: V]
        let halfGrip: Double
        let exit: V

        /// The posed body, the middle of the handle, and how far back the hip joints are.
        func solve(_ pose: JointPose) -> (g: [String: M], h: [String: V], handle: V, seat: Double) {
            var g = body.rotations(pose)
            let hipHeight = CardioRowerStaging.seatTop + CardioRowerStaging.sit
            let knee = min(150, max(2, (CardioStagings.angle(pose, "kneeFlex") + CardioStagings.angle(pose, "kneeFlexL")) / 2))
            // Far forward the ankles cannot bend enough to keep the heels down: they lift.
            let heel = 22 * CardioStagings.ease(knee, from: 70, to: 125)
            let turn = M.x(-CardioRowerStaging.tilt + heel)

            // The seat rolls to where the knees' bend puts the hips.
            let rel = body.place(g, root: V(0, 0, 0))
            var ankles: [String: V] = [:]
            var sum = 0.0, n = 0.0
            for s in ["r", "l"] {
                guard let ball = balls[s], let foot = feet[s], let hip = rel["femur.\(s)"],
                      let rHip = body.head["femur.\(s)"], let rKnee = body.head["shin.\(s)"], let rAnkle = body.head["foot.\(s)"]
                else { continue }
                let ankle = ball + turn * foot.toAnkle
                ankles[s] = ankle
                let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: knee)
                let a = ankle - (V(0, 0, hipHeight) + hip)
                sum += a.y + max(0, leg * leg - a.x * a.x - a.z * a.z).squareRoot()
                n += 1
            }
            let seat = n > 0 ? sum / n : 0.5
            let root = V(0, seat, hipHeight)
            var h = body.place(g, root: root)
            for s in ["r", "l"] {
                guard let ankle = ankles[s] else { continue }
                body.plant(s, ankle: ankle, foot: turn, pole: V(0, -0.3, 1), &g, h)
                // The toes stay on the plate when the heel comes up.
                g["toes.\(s)"] = M.x(-CardioRowerStaging.tilt)
            }
            h = body.place(g, root: root)

            // Arms long: the handle on the line from the shoulders to where the chain comes out.
            // At the finish: against the lower ribs.
            let thorax = g["thorax"] ?? .identity
            let u = progress(pose)
            let shoulders = ["r", "l"].compactMap { h["humerus.\($0)"] }
            var mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
            let wide = shoulders.first.map { abs($0.x - mid.x) } ?? 0.17
            mid.x = 0
            let reach = ["r", "l"].compactMap { s in grips[s].map { body.reach(s, $0, bend: 6) } }.reduce(0, +) / 2
            let lateral = wide - halfGrip
            let far = mid + (exit - mid).unit * max(0, reach * reach - lateral * lateral).squareRoot()
            let ribs = (h["thorax"] ?? root) + (g["lumbar"] ?? .identity) * V(0, -0.2, 0.02)
            let handle = mix(far, ribs, u)
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let grip = grips[s] else { continue }
                body.hold(s, grip, at: handle + V(-m * halfGrip, 0, 0), across: V(-m, 0, 0),
                          pole: thorax * V(-m * 0.5, 1, -0.45), &g, h)
            }
            h = body.place(g, root: root)
            return (g, h, handle, seat)
        }
    }

    var probe: Probe {
        Probe(body: body, progress: progress, grips: grips, feet: feet, balls: balls, halfGrip: halfGrip, exit: exit)
    }

    /// The rail on its legs, the footplates, and the flywheel in its housing with the monitor over it.
    static func frame(balls: [String: V], feet: [String: CardioFoot], exit: V, back: Double) -> [PropPiece] {
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        let railTop = seatTop - 0.07
        let rear = back + 0.4, front = -0.12
        p.append(Plan.box(V(0, (rear + front) / 2, railTop - 0.03), (0.09, rear - front, 0.06), .metal))
        // The rear leg and its foot.
        p.append(Plan.box(V(0, rear - 0.06, (railTop - 0.06) / 2), (0.06, 0.05, railTop - 0.06), .metal))
        p.append(Plan.box(V(0, rear - 0.06, 0.02), (0.42, 0.06, 0.04), .metal))
        // A footplate under each sole, standing on a brace across the rail's front end.
        let flat = M.x(-tilt)
        let normal = flat * V(0, 0, 1), along = flat * V(0, -1, 0)
        for s in ["r", "l"] {
            guard let ball = balls[s], let foot = feet[s] else { continue }
            let heel = ball + flat * foot.toHeel
            let under = ball - normal * foot.ballHeight
            let centre = V(ball.x, (under.y + heel.y) / 2, (under.z + heel.z) / 2) + along * 0.02 - normal * 0.012
            p.append(Plan.box(centre, (0.13, 0.33, 0.024), x: side, z: normal, .dark))
            // The heel cup the foot stands in.
            p.append(Plan.box(heel - along * 0.012 + normal * 0.02, (0.11, 0.02, 0.06), x: side, z: normal, .dark))
            p.append(Plan.rod(centre - normal * 0.012, V(ball.x * 0.3, centre.y - 0.02, railTop - 0.03), 0.018, .metal))
        }
        // The flywheel's housing in front, on its own foot, joined to the rail.
        let wheel = V(0, exit.y - 0.24, 0.42)
        p.append(Plan.disc(wheel, axis: side, radius: 0.27, thickness: 0.16, .dark))
        p.append(Plan.disc(wheel, axis: side, radius: 0.2, thickness: 0.18, .metal))
        p.append(Plan.box(V(0, (front + wheel.y) / 2, railTop - 0.04), (0.07, front - wheel.y, 0.06), .metal))
        p.append(Plan.box(V(0, wheel.y, 0.1), (0.07, 0.07, 0.2), .metal))
        p.append(Plan.box(V(0, wheel.y, 0.02), (0.5, 0.06, 0.04), .metal))
        // The chain's guide out of the top of the housing, and the monitor on its arm.
        p.append(Plan.rod(wheel + V(0, 0, 0.2), exit, 0.022, .dark))
        p.append(Plan.ball(exit, 0.024, .dark))
        let screen = V(0, exit.y - 0.05, exit.z + 0.36)
        p.append(Plan.rod(wheel + V(0, 0.05, 0.25), screen, 0.014, .metal))
        p.append(Plan.box(screen, (0.17, 0.03, 0.13), x: side, z: V(0, -0.35, 1), .dark))
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (g, h, handle, seat) = probe.solve(pose)
        var p: [PropPiece] = []
        // The seat on its rollers.
        p.append(Plan.box(V(0, seat + 0.03, Self.seatTop - 0.025), (0.3, 0.26, 0.05), .dark))
        for y in [-0.07, 0.13] {
            p.append(Plan.rod(V(-0.06, seat + y, Self.seatTop - 0.06), V(0.06, seat + y, Self.seatTop - 0.06), 0.018, .metal))
        }
        // The handle and its chain.
        p.append(Plan.rod(handle - V(Self.halfHandle, 0, 0), handle + V(Self.halfHandle, 0, 0), Self.handleRadius, .dark))
        p.append(Plan.rod(handle, exit, 0.004, .cable))
        return (body.made(g, h, floor: 0), p)
    }
}

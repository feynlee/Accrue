import Foundation

/// An elliptical cross trainer, built as the real linkage: each pedal bar hangs by its back
/// end from a crank on the flywheel and by its front end from the foot of a handle lever, so
/// the foot plate between them goes round a flat oval and the handle rocks the other way.
/// The cranks turn once per loop; the feet stay on their plates and the hands on the handles.
struct CardioEllipticalStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let crank = 0.19, bar = 1.15, gripRadius = 0.017
    /// How far along its bar, from the crank, each foot plate is.
    static let plateAt = 0.75
    /// The lever below its pivot, and the handle's middle above it.
    static let lower = 0.65, upper = 0.42
    static let plate = (wide: 0.14, long: 0.36, thick: 0.03)
    static let footX = 0.125, pivotX = 0.13, gripX = 0.2

    let body: Body3D
    let loop: CardioLoop
    let grips: [String: HandGrip]
    let feet: [String: CardioFoot]
    /// The crank's axle and the levers' pivot, in the middle of the machine.
    let axle: V, pivot: V
    let hip: V
    let kinds: [PropKind] = [.elliptical]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "elliptical", guide.equipment == "elliptical" || guide.equipment == "machine",
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let fr = CardioFoot(body, "r"), let fl = CardioFoot(body, "l"),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        feet = ["r": fr, "l": fl]
        loop = CardioLoop(guide, keys: ["hipFlex", "kneeFlex", "hipFlexL", "kneeFlexL"])
        // The body stands over the middle of the plates' travel.
        let axle = V(0, Self.plateAt - 0.03, 0.3)
        let pivot = V(0, axle.y - Self.bar, axle.z + Self.lower)
        self.axle = axle
        self.pivot = pivot

        // The hips' height: at the bottom of the oval the knee keeps the bend the keyframes
        // give the pushing leg.
        let least = guide.keyframes.map { CardioStagings.angle($0.pose, "kneeFlex") }.min() ?? 25
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: min(40, max(15, least)))
        let ankles = (0..<48).map { Self.side("r", at: Double($0) / 48, heel: 0, axle: axle, pivot: pivot, fr).ankle }
        let joint = rHip - pelvis
        func farthest(_ z: Double) -> Double { ankles.map { ($0 - (V(0, 0, z) + V(joint.x, joint.y, 0))).length }.max() ?? z }
        var low = 0.6, high = 1.6
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if farthest(mid) < leg { low = mid } else { high = mid }
        }
        hip = V(0, 0, low)
        fixed = Self.frame(axle: axle, pivot: pivot)
    }

    /// One side of the linkage at moment `t` of the loop.
    struct Side {
        /// The bar's two ends, and along it and square up from it.
        var back, front, along, normal: V
        /// The foot's rotation, the ankle joint and the middle of the foot plate.
        var turn: M
        var ankle, plate: V
        /// The handle's lever: its pivot, the way the handle runs up from it, and the grip's middle.
        var pivot, up, grip: V
    }

    static func side(_ s: String, at t: Double, heel: Double, axle: V, pivot: V, _ foot: CardioFoot) -> Side {
        let m = s == "r" ? 1.0 : -1.0
        let own = 2 * Double.pi * (s == "r" ? t : t + 0.5)
        let x = V(-m * footX, 0, 0)
        // The crank is forward when the foot is forward, and goes on down and back from there.
        let back = axle + V(0, -cos(own), -sin(own)) * crank
        // The front end is where the lever's foot can be while the bar keeps its length: the
        // lower of the two places the two circles meet.
        let between = back - pivot
        let d = between.length, e = between.unit
        let a = (lower * lower - bar * bar + d * d) / (2 * d)
        let h = max(0, lower * lower - a * a).squareRoot()
        var across = V(0, -e.z, e.y)
        if across.z > 0 { across = across * -1 }
        let front = pivot + e * a + across * h
        let along = (front - back).unit
        let normal = along.cross(V(1, 0, 0))
        let pitch = atan2(-along.z, -along.y) * 180 / .pi
        let turn = M.x(pitch + heel)
        let plate = back + along * plateAt + normal * (0.02 + Self.plate.thick / 2)
        let ball = plate + normal * (Self.plate.thick / 2 + foot.ballHeight) + along * 0.06
        // The handle leans back toward the body above the pivot.
        let up = M.x(-12) * ((pivot - front).unit)
        let grip = V(-m * gripX, pivot.y, pivot.z) + up * upper
        return Side(back: back + x, front: front + x, along: along, normal: normal, turn: turn,
                    ankle: ball + x + turn * foot.toAnkle, plate: plate + x,
                    pivot: pivot + V(-m * pivotX, 0, 0), up: up, grip: grip)
    }

    /// The base, the flywheel behind, and the mast in front with the levers' shaft and the console.
    static func frame(axle: V, pivot: V) -> [PropPiece] {
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        let rear = axle.y + 0.32, front = pivot.y - 0.3
        for y in [rear, front] { p.append(Plan.box(V(0, y, 0.025), (0.6, 0.07, 0.05), .metal)) }
        p.append(Plan.box(V(0, (rear + front) / 2, 0.05), (0.08, rear - front, 0.06), .metal))
        // The flywheel in its housing, and the cranks' axle through it.
        p.append(Plan.disc(axle, axis: side, radius: 0.27, thickness: 0.09, .dark))
        p.append(Plan.disc(axle, axis: side, radius: 0.1, thickness: 0.11, .metal))
        p.append(Plan.box(V(0, axle.y, axle.z / 2), (0.07, 0.1, axle.z), .metal))
        p.append(Plan.rod(axle - side * 0.1, axle + side * 0.1, 0.016, .metal))
        // The mast, the shaft the levers rock on, and the console.
        let mast = V(0, pivot.y - 0.08, 0)
        p.append(Plan.rod(mast + V(0, 0, 0.05), mast + V(0, 0, 1.5), 0.035, .metal))
        p.append(Plan.rod(mast + V(0, 0, pivot.z), pivot, 0.025, .metal))
        p.append(Plan.rod(pivot - side * (pivotX + 0.02), pivot + side * (pivotX + 0.02), 0.018, .metal))
        p.append(Plan.box(mast + V(0, 0.02, 1.52), (0.22, 0.04, 0.15), x: side, z: V(0, 0.3, 1), .dark))
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let t = loop(pose)
        var h = body.place(g, root: hip)
        var p: [PropPiece] = []
        let side = V(1, 0, 0)
        var sides: [String: Side] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let foot = feet[s] else { continue }
            // Riding on tiptoe lifts the heels off the plates.
            let heel = max(0, -0.7 * loop.off(s == "r" ? "ankleDorsi" : "ankleDorsiL", pose, at: t))
            let on = Self.side(s, at: t, heel: heel, axle: axle, pivot: pivot, foot)
            sides[s] = on
            body.plant(s, ankle: on.ankle, foot: on.turn, pole: V(0, -1, 0.2), &g, h)
            // The toes stay flat on the plate when the heel comes up.
            g["toes.\(s)"] = M.x(atan2(-on.along.z, -on.along.y) * 180 / .pi)
            // The crank, the bar with its foot plate, and the lever with its handle.
            let inner = V(-m * 0.1, 0, 0)
            p.append(Plan.rod(V(0, axle.y, axle.z) + inner, V(0, on.back.y, on.back.z) + inner, 0.015, .metal))
            p.append(Plan.rod(V(0, on.back.y, on.back.z) + inner, on.back, 0.012, .metal))
            p.append(Plan.rod(on.back, on.front, 0.02, .metal))
            p.append(Plan.box(on.plate, (Self.plate.wide, Self.plate.long, Self.plate.thick), x: side, z: on.normal, .dark))
            p.append(Plan.rod(on.front, on.pivot, 0.018, .metal))
            p.append(Plan.rod(on.pivot, on.grip - on.up * 0.07, 0.016, .metal))
            p.append(Plan.rod(on.grip - on.up * 0.07, on.grip + on.up * 0.08, Self.gripRadius, .dark))
        }
        h = body.place(g, root: hip)
        let thorax = g["thorax"] ?? .identity
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let on = sides[s] else { continue }
            body.hold(s, grip, at: on.grip, across: on.up * -1, pole: thorax * V(-m * 0.4, 0.5, -1), &g, h)
        }
        h = body.place(g, root: hip)
        return (body.made(g, h, floor: 0), p)
    }
}

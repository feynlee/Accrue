import Foundation

/// A pull-up or a dip in an assisted machine: the same hang or dip as on the plain bars, but
/// kneeling on a pad (or standing on a step) that the weight stack pushes up under the body.
/// The pad is carried on two arms from a carriage that rides the stack's frame, so it goes
/// straight up and down with the knees, and the stack's top plates rise as the body sinks.
struct MachineAssistStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// How far forward of straight down the thighs of the kneeling body point, in degrees.
    static let tilt = 18.0
    /// How high the middle of a knee is above the pad it kneels on, and the ankle of the foot
    /// lying behind it on its instep; and how far that foot is turned over (degrees).
    static let kneePad = 0.055, instep = 0.05, footOver = 172.0
    /// The stack stands behind the body, where it does not hide it from the front.
    static let stackY = 0.95, stackHeight = 1.9

    let body: Body3D
    /// The same lift on plain bars, as the bodyweight group stages it.
    let inner: any BodyStaging
    let kneeling: Bool
    let thigh, shin: Double
    /// The lowest and highest the pad's top goes through the loop.
    let low, high: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.equipment == "machine", words.contains("assisted"),
              guide.familyID == "pull-up" || guide.familyID == "dip",
              words.isSubset(of: ["assisted", "lever", "pull", "up", "chin", "parallel", "close", "grip", "standing",
                                  "chest", "triceps", "dip", "kneeling", "wide"]),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"]
        else { return nil }
        var plain = guide
        plain.equipment = nil
        plain.subtypeID = nil
        plain.exerciseName = guide.exerciseName
            .replacingOccurrences(of: "lever ", with: "").replacingOccurrences(of: "assisted ", with: "")
            .replacingOccurrences(of: "standing ", with: "").replacingOccurrences(of: " (kneeling)", with: "")
        guard let inner = Stagings.make(plain, body), inner is BarHangStaging || inner is DipStaging else { return nil }
        self.body = body
        self.inner = inner
        kneeling = !words.contains("standing")
        thigh = (rKnee - rHip).length
        shin = (rAnkle - rKnee).length

        var tops: [Double] = []
        for k in 0...24 {
            let f = inner.frame(Figure.smooth(guide.keyframes, at: Double(k) / 24)).body
            guard let top = Self.rest(body, f.heads.mapValues { V($0) }, kneeling: kneeling, thigh: thigh, shin: shin)?.top
            else { return nil }
            tops.append(top.z)
        }
        guard let low = tops.min(), let high = tops.max(), low > 0.09, high < Self.stackHeight - 0.2, high - low > 0.1
        else { return nil }
        self.low = low
        self.high = high
        fixed = inner.fixed + stackFrame(y: Self.stackY, height: Self.stackHeight)
    }

    /// How thick the kneeling pad is, or the step.
    var thick: Double { kneeling ? 0.07 : 0.04 }

    /// Where the legs rest: the middle of the pad's top, and where each knee and ankle go.
    static func rest(_ body: Body3D, _ h: [String: V], kneeling: Bool, thigh: Double, shin: Double)
        -> (top: V, knees: [String: V], ankles: [String: V])? {
        var knees: [String: V] = [:], ankles: [String: V] = [:]
        if kneeling {
            guard let r = h["femur.r"], let l = h["femur.l"] else { return nil }
            // Both knees at one height, under hips that may not be level.
            let a = tilt * .pi / 180
            let z = min(r.z, l.z) - thigh * cos(a), y = (r.y + l.y) / 2 - thigh * sin(a)
            let drop = kneePad - instep
            for (s, hip) in [("r", r), ("l", l)] {
                let knee = V(hip.x, y, z)
                knees[s] = knee
                ankles[s] = knee + V(0, (shin * shin - drop * drop).squareRoot(), -drop)
            }
            return (V(0, y + shin * 0.5, z - kneePad), knees, ankles)
        }
        guard let r = h["foot.r"], let l = h["foot.l"] else { return nil }
        // Standing: a step under the soles, wherever the hanging legs hold them.
        return (V(0, (r.y + l.y) / 2 - 0.06, min(r.z, l.z) - body.ankleHeight), knees, ["r": r, "l": l])
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let plain = inner.frame(pose)
        var g = plain.body.rotations.mapValues { M($0) }
        var h = plain.body.heads.mapValues { V($0) }
        guard let root = h["pelvis"],
              let rest = Self.rest(body, h, kneeling: kneeling, thigh: thigh, shin: shin) else { return plain }
        if kneeling {
            for s in ["r", "l"] {
                guard let ankle = rest.ankles[s] else { continue }
                body.plant(s, ankle: ankle, foot: M.x(Self.footOver), pole: V(0, -1, -1), &g, h)
            }
        } else {
            // Feet flat on the step, both at its height.
            for s in ["r", "l"] {
                guard let ankle = rest.ankles[s] else { continue }
                body.plant(s, ankle: V(ankle.x, ankle.y, rest.top.z + body.ankleHeight), foot: .identity, pole: V(0, -1, 0.2), &g, h)
            }
        }
        h = body.place(g, root: root)
        let top = rest.top
        var p = plain.props
        let depth = kneeling ? shin + 0.16 : 0.34
        let mid = top - V(0, 0, thick / 2)
        p.append(Plan.box(mid, (0.46, depth, thick), kneeling ? .pad : .dark))
        // The carriage on the stack's uprights, and the two arms that carry the pad.
        let ride = V(0, Self.stackY - 0.07, mid.z)
        p.append(Plan.box(ride, (0.54, 0.06, 0.1), .dark))
        for x in [-0.2, 0.2] {
            p.append(Plan.rod(V(x, ride.y, mid.z), V(x, mid.y + depth / 2 - 0.03, mid.z), 0.02, .metal))
        }
        // The stack helps: its plates are up when the body is down.
        p += liftedPlates(y: Self.stackY, height: Self.stackHeight, travel: high - top.z)
        return (body.made(g, h, floor: 0), p)
    }
}

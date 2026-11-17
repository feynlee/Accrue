import Foundation

/// A seated hip abduction or adduction machine: sitting against the back pad with the knees
/// bent square, each leg on an arm that swings about an upright axle under its hip. A pad
/// lies outside each knee to push apart, or inside it to squeeze together, and each foot
/// stands on a rest that swings with its arm. Hands hold the grips beside the hips.
struct MachineHipSwingStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015, rest = 0.12

    let body: Body3D
    /// Pads outside the knees (abduction) or inside them (adduction).
    let apart: Bool
    let seat: MachineRest
    let grips: [String: HandGrip]
    let handles: [String: V]
    let thigh, shin: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let apart = guide.familyID == "hip-abduction"
        guard guide.equipment == "machine",
              apart ? guide.subtypeID == "seated" && words.contains("abduction")
                    : guide.familyID == "hip-adduction" && guide.subtypeID == nil && words.contains("adduction"),
              words.isSubset(of: ["lever", "seated", "hip", "abduction", "adduction", "v", "2"]),
              // The keyframes must open and close the hips, or there is nothing to show.
              MachineRange(guide.keyframes, "hipAbd").high - MachineRange(guide.keyframes, "hipAbd").low > 10,
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"]
        else { return nil }
        self.body = body
        self.apart = apart
        grips = ["r": r, "l": l]
        thigh = (rKnee - rHip).length
        shin = (rAnkle - rKnee).length
        // The feet stand on rests a little off the floor.
        let hip = V(0, 0, body.ankleHeight + shin + Self.rest)
        let seat = MachineRest(body, hip: hip, lean: 15)
        self.seat = seat
        handles = ["r": hip + V(-0.3, 0.03, -0.02), "l": hip + V(0.3, 0.03, -0.02)]

        let top = hip.z - MachineFit.seat
        var p = [seat.backPad(from: 0.02, to: 0.66),
                 Plan.box(V(0, -0.02, top - 0.035), (0.42, 0.34, 0.07), .pad),
                 Plan.box(V(0, 0.02, (top - 0.07) / 2), (0.12, 0.12, top - 0.07), .metal)]
        let low = seat.behind(0, 0.1), high = seat.behind(0.62, 0.1)
        p.append(Plan.box((low + high) * 0.5, (0.08, (high - low).length, 0.06), z: seat.out, .metal))
        p.append(Plan.box(V(0, high.y, high.z / 2), (0.07, 0.07, high.z), .metal))
        p.append(Plan.box(V(0, (high.y - 0.3) / 2, 0.02), (0.09, high.y + 0.5, 0.04), .metal))
        p.append(Plan.box(V(0, high.y, 0.02), (0.7, 0.08, 0.04), .metal))
        // The weight stack, behind the seat.
        p.append(Plan.box(V(0, high.y + 0.16, 0.55), (0.28, 0.12, 1.1), .dark))
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let at = handles[s] else { continue }
            p.append(Plan.rod(at - V(0, 0.065, 0), at + V(0, 0.065, 0), Self.gripRadius, .dark))
            p.append(Plan.rod(at + V(0, 0.065, 0), V(-m * 0.2, 0.1, top - 0.05), 0.012, .metal))
        }
        fixed = p
    }

    /// How far each leg is turned out from straight ahead, in degrees.
    func turn(_ pose: JointPose) -> Double { min(48, max(4, pose.angles["hipAbd"] ?? 0)) }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h) = seat.settle(pose)
        let root = h["pelvis"] ?? seat.hip
        let a = turn(pose) * .pi / 180
        var p: [PropPiece] = []
        let under = seat.hip.z - MachineFit.seat - 0.12
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let rHip = body.head["femur.\(s)"], let pelvis = body.head["pelvis"] else { continue }
            // The leg swings level about the upright line through its hip.
            let hip = seat.hip + V(rHip.x - pelvis.x, 0, 0)
            let out = V(-m * sin(a), -cos(a), 0), side = V(-m * cos(a), sin(a), 0)
            let knee = hip + out * thigh, ankle = knee - V(0, 0, shin)
            body.plant(s, ankle: ankle, foot: M.z(-m * a * 180 / .pi), pole: out + V(0, 0, 0.4), &g, h)
            // The arm from the axle under the hip, out under the thigh to the knee.
            let axle = V(hip.x, hip.y, under), end = V(knee.x, knee.y, under) + out * 0.04
            p.append(Plan.disc(axle, axis: V(0, 0, 1), radius: 0.05, thickness: 0.06, .dark))
            p.append(Plan.rod(axle, end, 0.022, .metal))
            // The pad beside the knee, on the side the leg pushes.
            let push = side * (apart ? 1 : -1)
            let pad = knee - out * 0.09 + push * (0.075 + 0.03) - V(0, 0, 0.01)
            p.append(Plan.box(pad, (0.17, 0.06, 0.15), x: out, .pad))
            let post = end + push * 0.14
            p.append(Plan.rod(end, post, 0.018, .metal))
            p.append(Plan.rod(post, pad + push * 0.03, 0.018, .metal))
            // The foot rest under the sole.
            let sole = ankle - V(0, 0, body.ankleHeight + 0.012) + out * 0.07
            p.append(Plan.box(sole, (0.22, 0.11, 0.024), x: out, .dark))
            p.append(Plan.rod(end, sole - out * 0.06, 0.016, .metal))
        }
        h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let at = handles[s] else { continue }
            body.hold(s, grip, at: at, across: V(0, 1, 0), pole: V(-m * 0.4, 1, -0.4), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), p)
    }
}

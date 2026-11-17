import Foundation

/// A hip extension on a glute ham bench: face down with the thighs on the round pad, the hip
/// joints just clear of its front so the trunk can fold, the ankles held between two rollers
/// and the soles against the foot plate. The legs stay level and still; the trunk hangs down
/// from the hips and comes up level with them.
struct MachineGluteHamStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let padRadius = 0.15, roller = 0.045

    let body: Body3D
    /// The middle of the hip joints, which is the hinge.
    let hip: V
    let ankles: [String: V]
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.equipment == "machine", guide.familyID == "back-extension", guide.subtypeID == "horizontal",
              words.isSuperset(of: ["glute", "ham"]),
              words.isSubset(of: ["glute", "ham", "developer", "hip", "extension", "hyperextension", "twist"]),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        // High enough for the head to hang clear of the floor.
        let hip = V(0, 0, 1.02)
        self.hip = hip
        let leg = Body3D.span((rKnee - rHip).length, (rAnkle - rKnee).length, bend: 6)
        let out = pelvis.x - rHip.x
        ankles = ["r": hip + V(-out, leg, 0), "l": hip + V(out, leg, 0)]

        // The pad under the thighs, far enough back that the belly clears it when the trunk hangs.
        let pad = hip + V(0, 0.27, -(MachineFit.thighTop + Self.padRadius))
        var p = [Plan.disc(pad, axis: V(1, 0, 0), radius: Self.padRadius, thickness: 0.52, .pad)]
        p.append(Plan.box(V(0, pad.y, (pad.z - 0.05) / 2), (0.1, 0.1, pad.z - 0.05), .metal))
        // The rollers over and under the ankles, and the plate the soles push on.
        let ankle = hip + V(0, leg, 0)
        let over = ankle + V(0, -0.03, MachineFit.shinBack + Self.roller)
        let under = ankle + V(0, -0.05, -(MachineFit.shinFront + Self.roller))
        for at in [over, under] {
            p.append(Plan.disc(at, axis: V(1, 0, 0), radius: Self.roller, thickness: 0.5, .pad))
        }
        let plate = ankle + V(0, body.ankleHeight + 0.025, -0.1)
        p.append(Plan.box(plate, (0.56, 0.03, 0.42), .dark))
        for m in [-1.0, 1.0] {
            let x = m * 0.29
            p.append(Plan.box(V(x, plate.y, (over.z + 0.06) / 2), (0.05, 0.06, over.z + 0.06), .metal))
            p.append(Plan.rod(V(x, over.y, over.z), V(x, plate.y, over.z), 0.02, .metal))
            p.append(Plan.rod(V(x, under.y, under.z), V(x, plate.y, under.z), 0.02, .metal))
            p.append(Plan.box(V(x, (pad.y + plate.y) / 2 - 0.15, 0.025), (0.06, plate.y - pad.y + 0.9, 0.05), .metal))
        }
        p.append(Plan.box(V(0, pad.y, 0.025), (0.64, 0.06, 0.05), .metal))
        p.append(Plan.box(V(0, plate.y, 0.025), (0.64, 0.06, 0.05), .metal))
        fixed = p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        // The trunk and the pelvis turn together about the hip joints, which stay.
        var g = body.rotations(pose)
        let loose = body.place(g, root: V(0, 0, 0))
        let joints = ((loose["femur.r"] ?? V(0, 0, 0)) + (loose["femur.l"] ?? V(0, 0, 0))) * 0.5
        let root = hip - joints
        var h = body.place(g, root: root)
        for (s, key) in [("r", "ankleDorsi"), ("l", "ankleDorsiL")] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, 0.2, -1), &g, h)
            // Toes down, soles on the plate.
            let foot = (g["shin.\(s)"] ?? .identity) * M.x(-(pose.angles[key] ?? pose.angles["ankleDorsi"] ?? 0))
            g["foot.\(s)"] = foot
            g["toes.\(s)"] = foot
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), [])
    }
}

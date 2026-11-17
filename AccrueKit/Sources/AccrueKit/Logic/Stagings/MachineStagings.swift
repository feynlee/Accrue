import Foundation

/// Sitting or lying in a machine: leg press, leg curl, leg extension, pec deck, machine press, seated calf raise.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum MachineStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        // Only what is done in a machine with its own seat, pads and levers. Cable stations,
        // Smith machines and free weights belong to other groups.
        if guide.equipment == "smith-machine" { return MachineSmithStaging(guide, body) }
        guard guide.equipment == "machine" else { return nil }
        switch guide.familyID {
        case "leg-press": return MachineLegPressStaging(guide, body) ?? MachineHackSquatStaging(guide, body)
        case "squat": return MachineHackSquatStaging(guide, body)
        case "back-extension": return MachineGluteHamStaging(guide, body)
        case "leg-extension": return MachineSeatedLegStaging(guide, body)
        case "leg-curl": return MachineSeatedLegStaging(guide, body) ?? MachineLyingLegCurlStaging(guide, body)
        case "calf-raise":
            return MachineLegPressStaging(guide, body) ?? MachineSeatedCalfStaging(guide, body)
                ?? MachineStandingCalfStaging(guide, body)
        case "bench-press", "overhead-press", "row", "lat-pulldown": return MachinePressStaging(guide, body)
        case "chest-fly", "rear-delt-fly": return MachineFlyStaging(guide, body)
        default: return nil
        }
    }

    /// The words of an exercise's name. A staging claims an exercise only when it knows the
    /// meaning of every one of them, so a variation it cannot show keeps the plain fallback.
    static func words(_ guide: HowToGuide) -> Set<String> {
        Set(guide.exerciseName.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

/// How far the body's skin lies from its joints where it rests on a pad, measured on the model
/// at rest. Pads are built to these, so the body touches them without sinking in.
enum MachineFit {
    /// Under the hip joints of a sitting body.
    static let seat = 0.095
    /// Behind the hip joints, along the whole back: the plane the buttocks and the shoulder
    /// blades both touch.
    static let back = 0.135
    /// The back of the head, behind the same line.
    static let head = 0.1
    /// In front of the hip joints for a body lying face down: the belly and the chest.
    static let front = 0.135
    /// Above and below the line of the thigh bone, and in front of the hip.
    static let thighTop = 0.095, thighUnder = 0.085
    /// In front of the shin bone a hand above the ankle, and behind it there.
    static let shinFront = 0.032, shinBack = 0.072
}

/// How far a movement has gone, read from one joint angle of the keyframes: 0 where the angle
/// is lowest, 1 where it is highest. It also knows what the other joints do at each stage when
/// the movement is done well, so a mistake that changes them can be told from the movement.
struct MachineRange: Sendable {
    let key: String
    let low, high: Double
    private let start: JointPose, end: JointPose

    init(_ keys: [Keyframe], _ key: String) {
        self.key = key
        let values = keys.map { $0.pose.angles[key] ?? 0 }
        low = values.min() ?? 0
        high = max(values.max() ?? 1, low + 1)
        start = keys.min { ($0.pose.angles[key] ?? 0) < ($1.pose.angles[key] ?? 0) }?.pose ?? JointPose()
        end = keys.max { ($0.pose.angles[key] ?? 0) < ($1.pose.angles[key] ?? 0) }?.pose ?? JointPose()
    }

    func callAsFunction(_ pose: JointPose) -> Double {
        min(1, max(0, ((pose.angles[key] ?? 0) - low) / (high - low)))
    }

    /// How far the pose's `other` angle is from where good form has it at this stage, in degrees.
    func off(_ other: String, _ pose: JointPose) -> Double {
        let a = start.angles[other] ?? 0, b = end.angles[other] ?? 0
        return (pose.angles[other] ?? 0) - (a + (b - a) * self(pose))
    }
}

/// A back pad and the body that rests on it. The pad leans back by `lean` degrees from upright
/// (90 is a body lying on its back); `hip` is where the hip joints' middle is when the body
/// sits square against it.
struct MachineRest: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    let body: Body3D
    let hip: V
    let lean: Double
    /// Along the pad toward the head, and out of it toward the chest.
    let up: V, out: V
    /// Where the base of the rib cage rests.
    private let chest: V

    init(_ body: Body3D, hip: V, lean: Double) {
        self.body = body
        self.hip = hip
        self.lean = lean
        let t = lean * .pi / 180
        up = V(0, sin(t), cos(t))
        out = V(0, -cos(t), sin(t))
        let pelvis = body.head["pelvis"] ?? V(0, 0, 0)
        chest = hip + M.x(-lean) * ((body.head["thorax"] ?? pelvis) - pelvis)
    }

    /// The pose's rotations and bone heads with the rib cage lying on the pad whatever the
    /// lower back does: a spine that rounds or arches moves the hips, not the shoulders.
    /// `forward` leans the trunk off the pad from the hips by that many degrees, and `shift`
    /// moves the whole body (hips that lift off the seat).
    func settle(_ pose: JointPose, forward: Double = 0, shift: V = V(0, 0, 0)) -> (g: [String: M], h: [String: V]) {
        var pose = pose
        pose.angles["trunk"] = -lean - (pose.angles["lumbar"] ?? 0) / 2
        let rel = body.place(body.rotations(pose), root: V(0, 0, 0))
        let root = chest - (rel["thorax"] ?? V(0, 0, 0)) + shift
        pose.angles["trunk"] = (pose.angles["trunk"] ?? 0) + forward
        let g = body.rotations(pose)
        return (g, body.place(g, root: root))
    }

    /// The pad itself, from `from` to `to` above the hip joints along the trunk.
    func backPad(from: Double, to: Double, width: Double = 0.34, thick: Double = 0.07, proud: Double = 0) -> PropPiece {
        let mid = hip - out * (MachineFit.back - proud + thick / 2) + up * ((from + to) / 2)
        return PropPlan.box(mid, (width, to - from, thick), z: out, .pad)
    }

    /// A point of the frame behind the pad: `along` above the hip joints, `behind` the pad's face.
    func behind(_ along: Double, _ behind: Double, x: Double = 0) -> V {
        hip - out * (MachineFit.back + behind) + up * along + V(x, 0, 0)
    }
}

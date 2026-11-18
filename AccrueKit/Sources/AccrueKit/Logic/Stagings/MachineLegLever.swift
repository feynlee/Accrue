import Foundation

/// The swinging arm of a leg extension or leg curl machine: a hub on the line through the
/// knees, an arm down each side of the legs, and a padded roller between them that lies on the
/// shins and goes wherever they take it.
enum MachineLegLever {
    typealias V = Body3D.V
    typealias Plan = PropPlan

    static let roller = 0.05, armX = 0.27, postX = 0.31
    /// How far down the shin from the knee the roller lies, as a share of the shin.
    static let reach = 0.82

    /// The arm for a roller whose middle is at `roller`, turning about `pivot` (both on the
    /// body's middle line).
    static func arm(pivot: V, roller at: V) -> [PropPiece] {
        var p = [Plan.disc(at, axis: V(1, 0, 0), radius: roller, thickness: 0.42, .pad),
                 Plan.rod(at - V(armX, 0, 0), at + V(armX, 0, 0), 0.012, .metal)]
        for x in [-armX, armX] {
            p.append(Plan.rod(pivot + V(x, 0, 0), at + V(x, 0, 0), 0.018, .metal))
            p.append(Plan.ball(at + V(x, 0, 0), 0.018, .metal))
        }
        return p
    }

    /// What carries the arm: a post each side of the knees up to the hub.
    static func posts(pivot: V) -> [PropPiece] {
        var p: [PropPiece] = []
        for m in [-1.0, 1.0] {
            let hub = pivot + V(m * postX, 0, 0)
            p.append(Plan.rod(V(hub.x, hub.y, 0), hub, 0.025, .metal))
            p.append(Plan.disc(pivot + V(m * (postX - 0.02), 0, 0), axis: V(1, 0, 0), radius: 0.06, thickness: 0.04, .dark))
            p.append(Plan.box(V(hub.x, hub.y, 0.02), (0.07, 0.4, 0.04), .metal))
        }
        return p
    }

    /// A weight stack in its housing, standing on the body's left where it hides nothing.
    static func stack(y: Double) -> [PropPiece] {
        [Plan.box(V(0.56, y, 0.5), (0.2, 0.3, 1.0), .dark),
         Plan.box(V(0.56, y, 0.5), (0.24, 0.08, 1.04), .metal),
         Plan.box(V(0.28, y, 0.03), (0.5, 0.07, 0.06), .metal)]
    }
}

// MARK: - Leg extension and seated leg curl

/// A leg extension or a seated leg curl: hips on the seat, back on the pad, hands on the
/// handles. The knees sit on the machine's axis and do not move; the shins swing about it and
/// take the roller with them, in front of the shins for an extension, behind the calves for a
/// curl, where a second pad across the thighs holds them down.
struct MachineSeatedLegStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015

    let body: Body3D
    let curl: Bool
    /// One leg works; the other hangs where it started.
    let single: Bool
    let rest: MachineRest
    let range: MachineRange
    let grips: [String: HandGrip]
    let handles: [String: V]
    /// The machine's axis, on the body's middle line, and how far the thighs rise to it (degrees).
    let pivot: V
    let tilt: Double
    let thigh, shin: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        let curl = guide.familyID == "leg-curl"
        guard curl ? guide.subtypeID == "seated" && words.contains("curl") : guide.subtypeID == nil && words.contains("extension"),
              words.isSubset(of: curl ? ["lever", "seated", "leg", "curl", "plate", "loaded", "one", "single"]
                             : ["lever", "seated", "leg", "extension", "plate", "loaded", "v", "2", "3", "inward", "toes",
                                "one", "single"]),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"]
        else { return nil }
        self.body = body
        self.curl = curl
        single = !words.isDisjoint(with: ["one", "single"])
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, "kneeFlex")
        thigh = (rKnee - rHip).length
        shin = (rAnkle - rKnee).length
        // High enough that the feet swing clear of the floor.
        let hip = V(0, 0, curl ? 0.72 : 0.66)
        let lean = min(25, max(5, -(guide.keyframes.first?.pose.angles["trunk"] ?? -10)))
        let rest = MachineRest(body, hip: hip, lean: lean)
        self.rest = rest
        tilt = curl ? 0 : 4
        let t = tilt * .pi / 180
        let along = V(0, -cos(t), sin(t)), normal = V(0, sin(t), cos(t))
        pivot = hip + along * thigh

        var p: [PropPiece] = []
        // The seat: under the hips and the thighs, short of the knees (shorter still for a
        // curl, whose calves fold in under it), and the back pad.
        let front = curl ? 0.2 : 0.3, behind = MachineFit.back + 0.03
        let seat = hip + along * ((front - behind) / 2) - normal * (MachineFit.seat + 0.035)
        p.append(Plan.box(seat, (0.44, front + behind, 0.07), z: normal, .pad))
        p.append(rest.backPad(from: 0.0, to: 0.6))
        let spine = rest.behind(0.3, 0.1)
        p.append(Plan.box(spine, (0.08, 0.66, 0.06), z: rest.out, .metal))
        p.append(Plan.box(V(0, seat.y, (seat.z - 0.035) / 2), (0.1, 0.1, seat.z - 0.035), .metal))
        p.append(Plan.rod(V(0, seat.y + 0.03, seat.z - 0.06), rest.behind(0.12, 0.1), 0.03, .metal))
        p.append(Plan.box(V(0, (spine.y + 0.1 + pivot.y) / 2, 0.02), (0.09, spine.y + 0.1 - pivot.y, 0.04), .metal))
        p.append(Plan.box(V(0, pivot.y, 0.02), (2 * MachineLegLever.postX, 0.07, 0.04), .metal))
        p += MachineLegLever.posts(pivot: pivot)
        p += MachineLegLever.stack(y: spine.y + 0.1)

        var handles: [String: V] = [:]
        if curl {
            // A roller across the thighs just above the knees, with a grip on each end.
            let pad = hip + along * (thigh * 0.74) + normal * (MachineFit.thighTop + 0.045)
            p.append(Plan.disc(pad, axis: V(1, 0, 0), radius: 0.045, thickness: 0.4, .pad))
            p.append(Plan.rod(pad - V(MachineLegLever.postX, 0, 0), pad + V(MachineLegLever.postX, 0, 0), 0.012, .metal))
            for m in [-1.0, 1.0] {
                let end = pad + V(m * MachineLegLever.postX, 0, 0)
                p.append(Plan.rod(end, pivot + V(m * MachineLegLever.postX, 0, 0), 0.018, .metal))
                p.append(Plan.rod(pad + V(m * 0.21, 0, 0), pad + V(m * 0.3, 0, 0), Self.gripRadius, .dark))
            }
            handles = ["r": pad + V(-0.255, 0, 0), "l": pad + V(0.255, 0, 0)]
        } else {
            // A grip beside each hip, on a bracket from under the seat.
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                let at = hip + V(-m * 0.28, -0.1, -0.03)
                handles[s] = at
                p.append(Plan.rod(at + V(0, 0.065, 0), at - V(0, 0.065, 0), Self.gripRadius, .dark))
                p.append(Plan.rod(at + V(0, 0.065, 0), at + V(0, 0.1, -0.05), 0.012, .metal))
                p.append(Plan.rod(at + V(0, 0.1, -0.05), V(-m * 0.2, at.y + 0.1, seat.z - 0.02), 0.012, .metal))
            }
        }
        self.handles = handles
        fixed = p
    }

    /// The way a shin points when its knee is bent by `bend` degrees, and the way its front faces.
    func shinAxes(_ bend: Double) -> (along: V, front: V) {
        let a = (tilt - bend) * .pi / 180
        return (V(0, -cos(a), sin(a)), V(0, sin(a), cos(a)))
    }

    /// The middle of the roller when the working leg is bent by `bend`.
    func roller(_ bend: Double) -> V {
        let (along, front) = shinAxes(bend)
        let off = curl ? -(MachineFit.shinBack + MachineLegLever.roller) : MachineFit.shinFront + MachineLegLever.roller
        return pivot + along * (shin * MachineLegLever.reach) + front * off
    }

    /// The posed body, and the working knee's bend.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bend: Double) {
        // Hips that lift turn the thighs up about the knees, which the machine holds; a curl's
        // thigh pad keeps them down, and the trunk comes off the back pad instead.
        let wrong = range.off("hipFlex", pose)
        let lift = curl ? 0 : min(25, max(0, -wrong - 3))
        let forward = curl ? min(30, max(0, wrong - 3)) * 0.6 : 0
        var (g, h) = rest.settle(pose, forward: forward, shift: rest.up * (thigh * sin(lift * .pi / 180)))
        let root = h["pelvis"] ?? rest.hip
        let bend = max(1, pose.angles["kneeFlex"] ?? 0)
        for (s, key) in [("r", "ankleDorsi"), ("l", "ankleDorsiL")] {
            guard let hip = body.head["femur.\(s)"], let pelvis = body.head["pelvis"] else { continue }
            let own = single && s == "l" ? (curl ? range.low : range.high) : bend
            let ankle = pivot + V(hip.x - pelvis.x, 0, 0) + shinAxes(own).along * shin
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.5, 1), &g, h)
            let foot = (g["shin.\(s)"] ?? .identity) * M.x(-(pose.angles[key] ?? pose.angles["ankleDorsi"] ?? 0))
            g["foot.\(s)"] = foot
            g["toes.\(s)"] = foot
        }
        h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let at = handles[s] else { continue }
            body.hold(s, grip, at: at, across: curl ? V(-m, 0, 0) : V(0, 1, 0),
                      pole: curl ? V(-m * 0.6, 0.6, -0.6) : V(-m * 0.4, 1, -0.4), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bend)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bend) = solve(pose)
        return (frame, MachineLegLever.arm(pivot: pivot, roller: roller(bend)))
    }
}

// MARK: - Lying leg curl

/// A lying leg curl: face down on a bench that is humped under the hips, the knees just off
/// its end on the machine's axis, hands on the grips under its head. The heels come up toward
/// the buttocks and take the roller, which lies on the back of the ankles, with them.
struct MachineLyingLegCurlStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let gripRadius = 0.015
    /// How far the chest end and the thigh end of the bench slope down from the hump, in degrees.
    static let chestSlope = 5.0, thighSlope = 12.0

    let body: Body3D
    let single: Bool
    let range: MachineRange
    let grips: [String: HandGrip]
    let handles: [String: V]
    let hip: V
    let pivot: V
    let thigh, shin: Double
    let kinds: [PropKind] = [.machine]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let words = MachineStagings.words(guide)
        guard guide.familyID == "leg-curl", guide.subtypeID == nil, words.contains("lying"),
              words.isSubset(of: ["lever", "lying", "leg", "curl", "knee", "flexion", "single"]),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius),
              let rHip = body.head["femur.r"], let rKnee = body.head["shin.r"], let rAnkle = body.head["foot.r"],
              let pelvis = body.head["pelvis"], let shoulder = body.head["humerus.r"]
        else { return nil }
        self.body = body
        single = words.contains("single")
        grips = ["r": r, "l": l]
        range = MachineRange(guide.keyframes, "kneeFlex")
        thigh = (rKnee - rHip).length
        shin = (rAnkle - rKnee).length
        let hip = V(0, 0, 0.76)
        self.hip = hip
        let (toHead, down) = Self.trunkAxes(0)
        let (toKnee, under) = Self.thighAxes()
        pivot = hip + toKnee * thigh

        var p: [PropPiece] = []
        // Two pads meeting under the hips: one for the belly and chest, stopping short of the
        // throat, and one for the thighs, stopping short of the knees.
        let chest = hip + toHead * 0.27 + down * (MachineFit.front + 0.035)
        p.append(Plan.box(chest, (0.36, 0.54, 0.07), x: V(1, 0, 0), z: down * -1, .pad))
        let lap = hip + toKnee * 0.13 + under * (MachineFit.thighTop + 0.035)
        p.append(Plan.box(lap, (0.4, 0.32, 0.07), x: V(1, 0, 0), z: under * -1, .pad))
        for at in [chest + toHead * 0.14, lap] {
            p.append(Plan.box(V(0, at.y, (at.z - 0.035) / 2), (0.09, 0.09, at.z - 0.035), .metal))
            p.append(Plan.box(V(0, at.y, 0.02), (0.55, 0.07, 0.04), .metal))
        }
        p.append(Plan.box(V(0, (chest.y - 0.5 + pivot.y) / 2, 0.02), (0.09, pivot.y - chest.y + 0.5, 0.04), .metal))
        p.append(Plan.box((chest + lap) * 0.5 - V(0, 0, 0.06), (0.08, (lap - chest).length, 0.05), .metal))
        p += MachineLegLever.posts(pivot: pivot)
        p += MachineLegLever.stack(y: lap.y - 0.1)
        // A grip each side under the head end, on a post from the floor.
        let reach = hip + toHead * ((shoulder - pelvis).z + 0.25) + down * 0.3
        p.append(Plan.box(V(0, reach.y, reach.z / 2), (0.07, 0.07, reach.z), .metal))
        p.append(Plan.rod(reach - V(0.33, 0, 0), reach + V(0.33, 0, 0), 0.012, .metal))
        var handles: [String: V] = [:]
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            let at = reach + V(-m * 0.26, 0, 0)
            handles[s] = at
            p.append(Plan.rod(at - V(0.07, 0, 0), at + V(0.07, 0, 0), Self.gripRadius, .dark))
        }
        self.handles = handles
        fixed = p
    }

    /// Along the lying trunk toward the head, and out of its front toward the bench, when the
    /// hips have lifted the trunk's hip end by `lift` degrees.
    static func trunkAxes(_ lift: Double) -> (toHead: V, down: V) {
        let turn = M.x(90 + chestSlope + lift)
        return (turn * V(0, 0, 1), turn * V(0, -1, 0))
    }

    /// Along the thighs toward the knees, and out of their fronts toward the bench.
    static func thighAxes() -> (toKnee: V, under: V) {
        let a = thighSlope * .pi / 180
        return (V(0, cos(a), -sin(a)), V(0, -sin(a), -cos(a)))
    }

    /// The way a shin points from a knee bent by `bend` degrees, and the way its calf faces.
    func shinAxes(_ bend: Double) -> (along: V, back: V) {
        let a = (Self.thighSlope - bend) * .pi / 180
        return (V(0, cos(a), -sin(a)), V(0, sin(a), cos(a)))
    }

    func roller(_ bend: Double) -> V {
        let (along, back) = shinAxes(bend)
        return pivot + along * (shin * MachineLegLever.reach) + back * (MachineFit.shinBack + MachineLegLever.roller)
    }

    /// The posed body, and the working knee's bend.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bend: Double) {
        // Hips that lift off the pad hinge the body between the chest, which stays down, and
        // the knees, which the machine holds.
        let lift = min(16, max(0, range.off("hipFlex", pose) - 3) * 0.5)
        var pose = pose
        pose.angles["trunk"] = 90 + Self.chestSlope + lift
        pose.angles["neck"] = (pose.angles["neck"] ?? 0) - 12
        var g = body.rotations(pose)
        let rested = Self.trunkAxes(0).toHead, lifted = Self.trunkAxes(lift).toHead
        let root = hip + (rested - lifted) * 0.4
        var h = body.place(g, root: root)
        let bend = max(1, pose.angles["kneeFlex"] ?? 0)
        for (s, key) in [("r", "ankleDorsi"), ("l", "ankleDorsiL")] {
            guard let rHip = body.head["femur.\(s)"], let pelvis = body.head["pelvis"], let own = h["femur.\(s)"] else { continue }
            // The knee is on the machine's axis, or as near as a lifted hip leaves it.
            let axis = pivot + V(rHip.x - pelvis.x, 0, 0)
            let knee = own + (axis - own).unit * thigh
            let flex = single && s == "l" ? range.low : bend
            body.plant(s, ankle: knee + shinAxes(flex).along * shin, foot: .identity, pole: V(0, 0.2, -1), &g, h)
            let foot = (g["shin.\(s)"] ?? .identity) * M.x(-(pose.angles[key] ?? pose.angles["ankleDorsi"] ?? 0))
            g["foot.\(s)"] = foot
            g["toes.\(s)"] = foot
        }
        h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let at = handles[s] else { continue }
            body.hold(s, grip, at: at, across: V(-m, 0, 0), pole: V(-m, 0.3, -0.2), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bend)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bend) = solve(pose)
        return (frame, MachineLegLever.arm(pivot: pivot, roller: roller(bend)))
    }
}

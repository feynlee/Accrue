import Foundation

/// A point on the side-view figure, in body heights: x forward (the way the person faces), y up.
public struct FigurePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: FigurePoint, b: FigurePoint) -> FigurePoint { FigurePoint(a.x + b.x, a.y + b.y) }
}

/// The joints the side view draws. `L` ones are the far (left) side.
public enum FigureJoint: String, CaseIterable, Hashable, Sendable {
    case hip, midBack, shoulder, neck, head
    case knee, ankle, heel, toe
    case kneeL, ankleL, heelL, toeL
    case elbow, wrist, hand
    case elbowL, wristL, handL
}

/// One frame of the side-view figure.
public struct FigurePose: Hashable, Sendable {
    public var joints: [FigureJoint: FigurePoint]
    /// Ground height when something rests on the floor, nil when hanging or floating.
    public var groundY: Double?

    public subscript(_ joint: FigureJoint) -> FigurePoint { joints[joint] ?? FigurePoint(0, 0) }
}

/// Turns a family's joint angles (Catalog/families/README.md) into a side-view stick figure.
/// Arms and legs are worked out in 3D, so a raised-to-the-side arm still shows overhead,
/// then the body is tilted by `trunk` and seen from its right side.
public enum Figure {
    // Segment lengths as a share of standing height (Winter's anthropometric table, rounded).
    static let thigh = 0.245, shank = 0.246, footLength = 0.12, heelBack = 0.035, ankleHeight = 0.039
    static let lowerTrunk = 0.15, upperTrunk = 0.14, neckLength = 0.05, headRadius = 0.065
    static let upperArm = 0.186, forearm = 0.146, hand = 0.07
    public static let headSize = headRadius

    private struct V3 {
        var x, y, z: Double
        static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: V3, b: V3) -> V3 { V3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: V3, s: Double) -> V3 { V3(x: a.x * s, y: a.y * s, z: a.z * s) }
        func dot(_ b: V3) -> Double { x * b.x + y * b.y + z * b.z }
        var length: Double { dot(self).squareRoot() }
        var normalized: V3 { length > 1e-9 ? self * (1 / length) : self }
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }

    /// A limb's direction from straight down: abduction out to the side, then flexion forward.
    private static func limb(flex: Double, abd: Double) -> V3 {
        let f = rad(flex), a = rad(abd)
        return V3(x: cos(a) * sin(f), y: -cos(a) * cos(f), z: sin(a))
    }

    /// Bends `u` by `angle` toward `toward` (kept at right angles to `u`).
    private static func bend(_ u: V3, toward: V3, by angle: Double, fallback: V3) -> V3 {
        var w = toward - u * toward.dot(u)
        if w.length < 1e-6 { w = fallback - u * fallback.dot(u) }
        let a = rad(angle)
        return (u * cos(a) + w.normalized * sin(a)).normalized
    }

    /// Turns a body-frame vector by the trunk lean (forward about the side-to-side axis).
    private static func tilt(_ v: V3, _ degrees: Double) -> FigurePoint {
        let t = rad(degrees)
        return FigurePoint(v.x * cos(t) + v.y * sin(t), -v.x * sin(t) + v.y * cos(t))
    }

    /// The figure for one pose, with the hip at the origin and nothing grounded yet.
    public static func raw(_ pose: JointPose) -> [FigureJoint: FigurePoint] {
        let a = pose.angles
        func v(_ key: String, _ side: String = "") -> Double { a[key + side] ?? a[key] ?? 0 }
        let trunk = v("trunk"), lumbar = v("lumbar")
        let pelvisTilt = trunk - lumbar / 2, chestTilt = trunk + lumbar / 2
        let up = V3(x: 0, y: 1, z: 0), forward = V3(x: 1, y: 0, z: 0)

        var j: [FigureJoint: FigurePoint] = [:]
        let hip = FigurePoint(0, 0)
        j[.hip] = hip
        j[.midBack] = hip + tilt(up * lowerTrunk, pelvisTilt)
        // Shoulder blades: elevation lifts the shoulder, protraction moves it forward.
        let scap = pose.scapula
        let shoulderOffset = V3(x: 0.025 * (scap?.protraction ?? 0), y: upperTrunk + 0.025 * (scap?.elevation ?? 0), z: 0)
        let shoulder = j[.midBack]! + tilt(shoulderOffset, chestTilt)
        j[.shoulder] = shoulder
        let neckTop = shoulder + tilt(up * neckLength, chestTilt + v("neck"))
        j[.neck] = neckTop
        j[.head] = neckTop + tilt(up * headRadius, chestTilt + v("neck"))

        for side in ["", "L"] {
            let near = side.isEmpty
            // Legs: flexion forward, abduction out, knee bends back, ankle sets the foot.
            let thighDir = limb(flex: v("hipFlex", side), abd: v("hipAbd", side))
            let backward = V3(x: -thighDir.y, y: thighDir.x, z: 0) * -1  // thigh turned 90° back
            let shankDir = bend(thighDir, toward: backward, by: v("kneeFlex", side), fallback: forward * -1)
            let footDir = bend(shankDir, toward: forward, by: 90 + v("ankleDorsi", side), fallback: forward)
            let knee = hip + tilt(thighDir * thigh, pelvisTilt)
            let ankle = knee + tilt(shankDir * shank, pelvisTilt)
            j[near ? .knee : .kneeL] = knee
            j[near ? .ankle : .ankleL] = ankle
            j[near ? .toe : .toeL] = ankle + tilt(footDir * footLength + shankDir * ankleHeight, pelvisTilt)
            j[near ? .heel : .heelL] = ankle + tilt(footDir * -heelBack + shankDir * ankleHeight, pelvisTilt)

            // Arms: an arm raised to the side bends its forearm up, a hanging arm bends it forward.
            let upperDir = limb(flex: v("shoulderFlex", side), abd: v("shoulderAbd", side))
            let k = min(1, max(0, (v("shoulderAbd", side) - 30) / 60))
            let bendTarget = (forward * (1 - k) + up * k).normalized
            let foreDir = bend(upperDir, toward: bendTarget, by: v("elbowFlex", side), fallback: up)
            let elbow = shoulder + tilt(upperDir * upperArm, chestTilt)
            let wrist = elbow + tilt(foreDir * forearm, chestTilt)
            j[near ? .elbow : .elbowL] = elbow
            j[near ? .wrist : .wristL] = wrist
            j[near ? .hand : .handL] = wrist + tilt(foreDir * hand, chestTilt)
        }
        return j
    }

    /// The joints that rest on the floor (or hang from a bar) for a family's `contacts` words.
    static func contactJoints(_ contacts: [String]) -> (ground: [FigureJoint], hang: Bool) {
        let groups = contactGroups(contacts)
        let ground = groups.flatMap { $0 }
        let hang = ground.isEmpty && contacts.contains { $0.lowercased() == "bar" }
        return (ground, hang)
    }

    /// The floor contacts one word at a time, so a plank's hands and feet can both be planted.
    static func contactGroups(_ contacts: [String]) -> [[FigureJoint]] {
        var groups: [[FigureJoint]] = []
        for c in contacts.map({ $0.lowercased() }) {
            var ground: [FigureJoint] = []
            if c.contains("foot") || c.contains("feet") || c.contains("heel") {
                ground += [.heel, .toe, .heelL, .toeL]
            } else if c.contains("toe") {
                ground += [.toe, .toeL]
            } else if c.contains("knee") || c.contains("shin") {
                ground += [.knee, .kneeL]
            } else if c.contains("forearm") || c.contains("arm") {
                ground += [.elbow, .wrist, .elbowL, .wristL]
            } else if c.contains("hand") {
                ground += [.hand, .handL]
            } else if c.contains("hip") || c.contains("side") {
                ground += [.hip]
            } else if c.contains("back") || c.contains("shoulder") {
                ground += [.hip, .midBack, .shoulder]
            }
            if !ground.isEmpty { groups.append(ground) }
        }
        return groups
    }

    /// The figure placed in the scene: the lowest contact sits on the floor and the first one
    /// stays put across frames, or the hands hang from a fixed bar.
    public static func pose(_ pose: JointPose, contacts: [String]) -> FigurePose {
        var j = raw(pose)
        let (ground, hang) = contactJoints(contacts)
        var shift = FigurePoint(0, 0)
        var groundY: Double?
        if hang {
            let hands = j[.hand]!
            shift = FigurePoint(-hands.x, 1.0 - hands.y)
        } else if let anchor = ground.first {
            let lowest = ground.compactMap { j[$0]?.y }.min() ?? 0
            shift = FigurePoint(-(j[anchor]!.x), -lowest)
            groundY = 0
        }
        for (key, p) in j { j[key] = p + shift }
        if !hang { plantSecondContact(&j, contacts: contacts) }
        return FigurePose(joints: j, groundY: groundY)
    }

    /// When the body spans two floor contacts (hands and feet in a plank), tips it about the
    /// first contact so the far one rests on the floor too, as a sagging or piking body would.
    /// Only small tips are made, so poses where the far contact is meant to lift stay as drawn.
    static func plantSecondContact(_ j: inout [FigureJoint: FigurePoint], contacts: [String]) {
        let groups = contactGroups(contacts)
        guard groups.count >= 2, let pivot = groups[0].compactMap({ j[$0] }).min(by: { $0.y < $1.y }) else { return }
        let far = groups.dropFirst().flatMap { $0 }.compactMap { j[$0] }
            .filter { abs($0.x - pivot.x) > 0.3 }
            .min { $0.y < $1.y }
        guard let far else { return }
        let dx = far.x - pivot.x, dy = far.y - pivot.y
        let angle = -atan2(dy, abs(dx)) * (dx < 0 ? -1 : 1)
        guard abs(angle) > 1e-6, abs(angle) < 25 * .pi / 180 else { return }
        let c = cos(angle), s = sin(angle)
        for (key, p) in j {
            let x = p.x - pivot.x, y = p.y - pivot.y
            j[key] = FigurePoint(pivot.x + x * c - y * s, pivot.y + x * s + y * c)
        }
        // Keep everything on or above the floor.
        let lowest = groups.flatMap { $0 }.compactMap { j[$0]?.y }.min() ?? 0
        for (key, p) in j { j[key] = FigurePoint(p.x, p.y - lowest) }
    }

    /// The pose at `t` (0...1) of a loop, easing between keyframes.
    public static func interpolate(_ keys: [Keyframe], at t: Double) -> JointPose {
        guard let first = keys.first else { return JointPose() }
        guard keys.count > 1 else { return first.pose }
        let t = min(1, max(0, t))
        var i = 0
        while i + 1 < keys.count - 1 && keys[i + 1].t <= t { i += 1 }
        let a = keys[i], b = keys[i + 1]
        let span = b.t - a.t
        var f = span > 0 ? (t - a.t) / span : 1
        f = min(1, max(0, f))
        f = f * f * (3 - 2 * f)
        return blend(a.pose, b.pose, f)
    }

    /// Angles mixed by `f`; a key missing on one side counts as 0 (upright), as the README says.
    public static func blend(_ a: JointPose, _ b: JointPose, _ f: Double) -> JointPose {
        var angles: [String: Double] = [:]
        for key in Set(a.angles.keys).union(b.angles.keys) {
            let x = a.angles[key] ?? 0, y = b.angles[key] ?? 0
            angles[key] = x + (y - x) * f
        }
        func mix(_ x: Double?, _ y: Double?) -> Double? {
            x == nil && y == nil ? nil : (x ?? 0) + ((y ?? 0) - (x ?? 0)) * f
        }
        let scap = Scapula(protraction: mix(a.scapula?.protraction, b.scapula?.protraction),
                           elevation: mix(a.scapula?.elevation, b.scapula?.elevation),
                           upRot: mix(a.scapula?.upRot, b.scapula?.upRot))
        return JointPose(angles: angles, scapula: scap)
    }

    /// A pose with a mistake's angle changes added on top ("hips sag": hipFlex -12).
    public static func applying(_ fault: JointPose, to pose: JointPose) -> JointPose {
        var p = pose
        for (key, value) in fault.angles { p.angles[key] = (p.angles[key] ?? 0) + value }
        return p
    }
}

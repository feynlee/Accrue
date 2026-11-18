import Foundation

/// The value in `range` where `gap` (which grows with it) crosses zero; the nearer end of the
/// range if it never does.
func floorCross(_ range: ClosedRange<Double>, _ gap: (Double) -> Double) -> Double {
    var low = range.lowerBound, high = range.upperBound
    if gap(low) >= 0 { return low }
    if gap(high) <= 0 { return high }
    for _ in 0..<16 {
        let mid = (low + high) / 2
        if gap(mid) < 0 { low = mid } else { high = mid }
    }
    return (low + high) / 2
}

/// What one angle of the pose is at each stage of a movement, as the keyframes have it, read
/// against the angle that drives the movement. A mistake pushes the angle off this line, and
/// `excess` says by how much.
struct FloorLine: Sendable {
    let key, driver: String
    /// (driver, angle) pairs in order of the driver.
    let marks: [(Double, Double)]

    init(_ key: String, against driver: String, _ keys: [Keyframe]) {
        self.key = key
        self.driver = driver
        var marks: [(Double, Double)] = []
        for k in keys.sorted(by: { ($0.pose.angles[driver] ?? 0) < ($1.pose.angles[driver] ?? 0) }) {
            let d = k.pose.angles[driver] ?? 0, a = k.pose.angles[key] ?? 0
            if let last = marks.last, abs(last.0 - d) < 0.5 {
                marks[marks.count - 1].1 = (last.1 + a) / 2
            } else {
                marks.append((d, a))
            }
        }
        self.marks = marks
    }

    func expected(_ pose: JointPose) -> Double {
        guard let first = marks.first, let last = marks.last else { return pose.angles[key] ?? 0 }
        let d = pose.angles[driver] ?? first.0
        if d <= first.0 { return first.1 }
        for (a, b) in zip(marks, marks.dropFirst()) where d <= b.0 {
            return a.1 + (b.1 - a.1) * (d - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    /// How many degrees the pose is past the keyframes' own value, beyond a few degrees of
    /// slack for the curve the loop is smoothed on.
    func excess(_ pose: JointPose, slack: Double = 4) -> Double {
        let off = (pose.angles[key] ?? 0) - expected(pose)
        return off > 0 ? max(0, off - slack) : min(0, off + slack)
    }
}

/// How a bone's skin rolls along the floor as the bone tips up from lying on its back, without
/// sliding: sitting up, a body rolls from the back of its hips onto its seat, and the place it
/// rests on moves along the floor as far as the skin has rolled over it.
struct FloorRoll: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    static let step = 0.5
    let from: Double
    /// Where the bone's head is at each pitch, with the place it rests on at pitch 0 at the origin.
    let origins: [V]

    /// `points` are the bone's skin at rest, measured from the bone's head. `range` is the
    /// pitches to cover, in degrees up from lying flat on the back.
    init(_ points: [V], over range: ClosedRange<Double>) {
        func turned(_ pitch: Double) -> [V] {
            let r = M.x(pitch - 90)
            return points.map { r * $0 }
        }
        func lowest(_ q: [V]) -> Int { q.indices.min { q[$0].z < q[$1].z } ?? 0 }
        func roll(steps: Int, by step: Double) -> [V] {
            var q = turned(0)
            guard !q.isEmpty else { return Array(repeating: V(0, 0, 0), count: steps + 1) }
            var k = lowest(q)
            var contact = 0.0
            var out = [V(0, contact, 0) - q[k]]
            for i in 1...max(1, steps) {
                q = turned(Double(i) * step)
                // Tip about the point that bears, then let whatever is lowest now take over.
                let origin = V(0, contact, 0) - q[k]
                k = lowest(q)
                contact = origin.y + q[k].y
                out.append(V(0, contact, 0) - q[k])
            }
            return out
        }
        let down = Int((-min(0, range.lowerBound) / Self.step).rounded(.up))
        let up = Int((max(0, range.upperBound) / Self.step).rounded(.up))
        from = -Double(down) * Self.step
        origins = roll(steps: down, by: -Self.step).dropFirst().reversed() + roll(steps: up, by: Self.step)
    }

    /// Where the bone's head is when the bone is tipped up by `pitch` degrees.
    func callAsFunction(_ pitch: Double) -> V {
        guard let first = origins.first, let last = origins.last else { return V(0, 0, 0) }
        let at = (pitch - from) / Self.step
        if at <= 0 { return first }
        if at >= Double(origins.count - 1) { return last }
        let i = Int(at)
        return mix(origins[i], origins[i + 1], at - Double(i))
    }
}

/// A body lying on its back on the floor, its head toward +y. The hips and the chest each tip
/// up from lying flat by their own angle, with the low back bending between them; one of the
/// two is the part that stays on the floor and rolls on its own skin, and the other is carried.
struct FloorSupine: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// Which part of the trunk stays down.
    enum Anchor: Sendable { case hips, chest }

    /// How far the skin presses into the floor.
    static let sink = 0.006

    let body: Body3D
    let hipsRoll, chestRoll: FloorRoll
    let hipBones, chestBones: [String]

    init(_ body: Body3D) {
        self.body = body
        func points(_ bone: String) -> [V] {
            guard let rest = body.head[bone] else { return [] }
            return (FloorSkin.rest[bone] ?? []).map { $0 - rest }
        }
        hipsRoll = FloorRoll(points("pelvis"), over: -70...110)
        chestRoll = FloorRoll(points("thorax"), over: -70...110)
        hipBones = ["pelvis"] + body.floorBranch("femur.r") + body.floorBranch("femur.l")
        chestBones = body.floorBranch("thorax")
    }

    /// The rotations of `pose` with the trunk laid flat on its back, before `shape` tips it.
    func flat(_ pose: JointPose) -> [String: M] {
        var pose = pose
        pose.angles["trunk"] = -90
        pose.angles["lumbar"] = 0
        pose.angles["roll"] = 0
        return body.rotations(pose)
    }

    /// The body with its hips tipped up by `hips` degrees and its chest by `chest`, resting on
    /// the anchor at the origin.
    func shape(_ flat: [String: M], hips: Double, chest: Double, anchor: Anchor) -> (g: [String: M], h: [String: V]) {
        var g = flat
        body.floorTurn(hipBones, by: M.x(hips), &g)
        body.floorTurn(["lumbar"], by: M.x((hips + chest) / 2), &g)
        body.floorTurn(chestBones, by: M.x(chest), &g)
        var h = body.heads(g)
        let bone = anchor == .hips ? "pelvis" : "thorax"
        let at = (anchor == .hips ? hipsRoll(hips) : chestRoll(chest)) - V(0, 0, Self.sink)
        if let now = h[bone] {
            let shift = at - now
            for (k, p) in h { h[k] = p + shift }
        }
        return (g, h)
    }

    /// With the hips down: the tip of the chest at which the back lies on the floor.
    func chestRest(_ flat: [String: M], hips: Double) -> Double {
        floorCross(-30...40) { chest in
            let (g, h) = shape(flat, hips: hips, chest: chest, anchor: .hips)
            return body.floorLow(["thorax", "lumbar"], g, h) + Self.sink
        }
    }

    /// With the chest down: the tip of the hips at which they lie on the floor. Tipped less
    /// than this (the tailbone curling up) they are off it.
    func hipsRest(_ flat: [String: M], chest: Double) -> Double {
        -floorCross(-40...70) { tucked in
            let (g, h) = shape(flat, hips: -tucked, chest: chest, anchor: .chest)
            return body.floorLow(["pelvis"], g, h) + Self.sink
        }
    }

    /// Sets the head. Lying down, it rests on the floor, the neck giving as far as that takes;
    /// `held` (0...1) is how far the shoulders have come up, where the neck holds the head at
    /// `nod` degrees instead. The head never goes into the floor.
    func layHead(_ g: inout [String: M], _ h: inout [String: V], nod: Double, held: Double) {
        guard let thorax = g["thorax"], let neck = h["neck"], let rNeck = body.head["neck"],
              let rHead = body.head["head"] else { return }
        let skin = (FloorSkin.rest["head"] ?? []).map { $0 - rHead }
        func base(_ nod: Double) -> V { neck + thorax * M.x(nod / 2) * (rHead - rNeck) }
        let onFloor = floorCross(-35...45) { nod in
            let at = base(nod), turn = thorax * M.x(nod)
            return (skin.map { (at + turn * $0).z }.min() ?? 0) + Self.sink
        }
        let angle = max(onFloor, -35 + (nod + 35) * min(1, max(0, held)))
        g["neck"] = thorax * M.x(angle / 2)
        g["head"] = thorax * M.x(angle)
        h["head"] = base(angle)
    }

    /// Lifts a leg that hangs free until no part of it is under the floor.
    func keepLegUp(_ s: String, _ g: inout [String: M], _ h: [String: V]) {
        guard let hip = h["femur.\(s)"] else { return }
        let bones = ["femur", "shin", "foot", "toes"].map { "\($0).\(s)" }
        let skin = bones.flatMap { body.floorSkin($0, g, h) }
        func low(_ lift: Double) -> Double {
            let turn = M.x(-lift)
            return skin.map { (hip + turn * ($0 - hip)).z }.min() ?? 0
        }
        guard low(0) < 0 else { return }
        let lift = floorCross(0...70, low)
        body.floorTurn(body.floorBranch("femur.\(s)"), by: M.x(-lift), &g)
    }
}

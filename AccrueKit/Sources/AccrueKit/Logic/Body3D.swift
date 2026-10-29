import Foundation

/// The 3D body's skeleton as exported from Blender (`Body/anatomy/export_app.py`): each
/// bone's head and tail at rest, in metres, Blender axes (x to the body's left, -y forward,
/// z up), parents before children. `rest` is the bone's own axes at rest (3×3, rows), which
/// are the joint axes in the app's model.
public struct BodyRig: Codable, Sendable {
    public struct Bone: Codable, Sendable {
        public var name: String
        public var parent: String?
        public var head: [Double]
        public var tail: [Double]
        public var rest: [Double]?
    }

    public var bones: [Bone]

    public init(bones: [Bone]) {
        self.bones = bones
    }

    public static func bundled() throws -> BodyRig {
        guard let url = Bundle.module.url(forResource: "body-rig", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        return try JSONDecoder().decode(BodyRig.self, from: Data(contentsOf: url))
    }
}

/// A rotation as a unit quaternion.
public struct BodyQuat: Hashable, Sendable {
    public var w, x, y, z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = BodyQuat(w: 1, x: 0, y: 0, z: 0)
}

/// Where every bone is in one frame. `local` is what the app sets on each joint: the turn away
/// from rest in the bone's own axes, so joint = rest joint × local. `root` is where the pelvis
/// head goes, in Blender axes. `rotations` (world axes) and `heads` are there for checking.
public struct BodyFrame: Sendable {
    public var local: [String: BodyQuat]
    public var root: [Double]
    public var rotations: [String: BodyQuat]
    public var heads: [String: [Double]]
    /// The floor height, or nil when nothing rests on the floor (a hang).
    public var floor: Double?
}

/// Poses the 3D skeleton from a family's joint angles (Catalog/families/README.md), so every
/// exercise the 2D figure draws can play on the anatomy model too. Angles are anatomical;
/// keys without "L" are the right side and also the left unless an "L" key is given.
public struct Body3D: Sendable {
    let rig: BodyRig
    private let index: [String: Int]
    private let head: [String: V]
    private let tail: [String: V]
    private let rest: [String: M]

    public init(rig: BodyRig) {
        self.rig = rig
        index = Dictionary(rig.bones.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
        head = Dictionary(rig.bones.map { ($0.name, V($0.head)) }, uniquingKeysWith: { a, _ in a })
        tail = Dictionary(rig.bones.map { ($0.name, V($0.tail)) }, uniquingKeysWith: { a, _ in a })
        rest = Dictionary(rig.bones.compactMap { b in
            b.rest.flatMap { r in r.count == 9 ? (b.name, M(r0: V(r[0], r[1], r[2]), r1: V(r[3], r[4], r[5]), r2: V(r[6], r[7], r[8]))) : nil }
        }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Small vector maths (no simd on Linux)

    struct V: Equatable {
        var x, y, z: Double
        init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
        init(_ a: [Double]) { self.init(a.count > 0 ? a[0] : 0, a.count > 1 ? a[1] : 0, a.count > 2 ? a[2] : 0) }
        static func + (a: V, b: V) -> V { V(a.x + b.x, a.y + b.y, a.z + b.z) }
        static func - (a: V, b: V) -> V { V(a.x - b.x, a.y - b.y, a.z - b.z) }
        static func * (a: V, s: Double) -> V { V(a.x * s, a.y * s, a.z * s) }
        func dot(_ b: V) -> Double { x * b.x + y * b.y + z * b.z }
        func cross(_ b: V) -> V { V(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
        var length: Double { dot(self).squareRoot() }
        var unit: V { length > 1e-12 ? self * (1 / length) : self }
        var array: [Double] { [x, y, z] }
    }

    /// 3×3 rotation, rows.
    struct M: Equatable {
        var r0, r1, r2: V
        static let identity = M(r0: V(1, 0, 0), r1: V(0, 1, 0), r2: V(0, 0, 1))
        var t: M { M(r0: V(r0.x, r1.x, r2.x), r1: V(r0.y, r1.y, r2.y), r2: V(r0.z, r1.z, r2.z)) }

        init(r0: V, r1: V, r2: V) { self.r0 = r0; self.r1 = r1; self.r2 = r2 }

        init(_ q: BodyQuat) {
            let (w, x, y, z) = (q.w, q.x, q.y, q.z)
            self.init(r0: V(1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)),
                      r1: V(2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)),
                      r2: V(2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)))
        }
        static func * (a: M, v: V) -> V { V(a.r0.dot(v), a.r1.dot(v), a.r2.dot(v)) }
        static func * (a: M, b: M) -> M {
            let c0 = V(b.r0.x, b.r1.x, b.r2.x), c1 = V(b.r0.y, b.r1.y, b.r2.y), c2 = V(b.r0.z, b.r1.z, b.r2.z)
            return M(r0: V(a.r0.dot(c0), a.r0.dot(c1), a.r0.dot(c2)),
                     r1: V(a.r1.dot(c0), a.r1.dot(c1), a.r1.dot(c2)),
                     r2: V(a.r2.dot(c0), a.r2.dot(c1), a.r2.dot(c2)))
        }

        /// Rotation by `degrees` about `axis` (right-handed).
        static func axis(_ axis: V, _ degrees: Double) -> M {
            let a = axis.unit, t = degrees * .pi / 180, c = cos(t), s = sin(t), k = 1 - c
            return M(r0: V(c + a.x * a.x * k, a.x * a.y * k - a.z * s, a.x * a.z * k + a.y * s),
                     r1: V(a.y * a.x * k + a.z * s, c + a.y * a.y * k, a.y * a.z * k - a.x * s),
                     r2: V(a.z * a.x * k - a.y * s, a.z * a.y * k + a.x * s, c + a.z * a.z * k))
        }

        static func x(_ d: Double) -> M { axis(V(1, 0, 0), d) }
        static func y(_ d: Double) -> M { axis(V(0, 1, 0), d) }
        static func z(_ d: Double) -> M { axis(V(0, 0, 1), d) }

        /// The smallest rotation turning direction `a` onto `b`.
        static func between(_ a: V, _ b: V) -> M {
            let a = a.unit, b = b.unit
            let c = a.dot(b), v = a.cross(b)
            if v.length < 1e-9 {
                if c > 0 { return .identity }
                let side = abs(a.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0)
                return axis(a.cross(side), 180)
            }
            return axis(v, atan2(v.length, c) * 180 / .pi)
        }

        var quat: BodyQuat {
            let t = r0.x + r1.y + r2.z
            let q: BodyQuat
            if t > 0 {
                let s = (t + 1).squareRoot() * 2
                q = BodyQuat(w: s / 4, x: (r2.y - r1.z) / s, y: (r0.z - r2.x) / s, z: (r1.x - r0.y) / s)
            } else if r0.x > r1.y && r0.x > r2.z {
                let s = (1 + r0.x - r1.y - r2.z).squareRoot() * 2
                q = BodyQuat(w: (r2.y - r1.z) / s, x: s / 4, y: (r0.y + r1.x) / s, z: (r0.z + r2.x) / s)
            } else if r1.y > r2.z {
                let s = (1 + r1.y - r0.x - r2.z).squareRoot() * 2
                q = BodyQuat(w: (r0.z - r2.x) / s, x: (r0.y + r1.x) / s, y: s / 4, z: (r1.z + r2.y) / s)
            } else {
                let s = (1 + r2.z - r0.x - r1.y).squareRoot() * 2
                q = BodyQuat(w: (r1.x - r0.y) / s, x: (r0.z + r2.x) / s, y: (r1.z + r2.y) / s, z: s / 4)
            }
            let n = (q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z).squareRoot() * (q.w < 0 ? -1 : 1)
            return BodyQuat(w: q.w / n, x: q.x / n, y: q.y / n, z: q.z / n)
        }
    }

    // Body axes at rest.
    static let forward = V(0, -1, 0), up = V(0, 0, 1), down = V(0, 0, -1)

    // MARK: Angles to bone rotations

    /// Each bone's rotation away from rest, with the pelvis turned by the trunk lean and roll.
    func rotations(_ pose: JointPose) -> [String: M] {
        let a = pose.angles
        func v(_ key: String, _ side: String = "") -> Double { a[key + side] ?? a[key] ?? 0 }
        let trunk = v("trunk"), lumbar = v("lumbar")
        var g: [String: M] = [:]
        let body = M.x(trunk) * M.z(v("roll"))
        g["pelvis"] = body * M.x(-lumbar / 2)
        g["lumbar"] = body * M.z(-v("trunkRot") / 2) * M.y(-v("trunkSide") / 2)
        let thorax = body * M.x(lumbar / 2) * M.z(-v("trunkRot")) * M.y(-v("trunkSide"))
        g["thorax"] = thorax
        g["neck"] = thorax * M.x(v("neck") / 2) * M.z(-v("neckRot") / 2) * M.y(-v("neckSide") / 2)
        g["head"] = thorax * M.x(v("neck")) * M.z(-v("neckRot")) * M.y(-v("neckSide"))

        for (s, side, m) in [("r", "", 1.0), ("l", "L", -1.0)] {
            let pelvis = g["pelvis"]!
            // Legs: hip flexion forward, abduction out, rotation outward; knee back; ankle up.
            let femur = pelvis * M.x(-v("hipFlex", side)) * M.y(m * v("hipAbd", side)) * M.z(-m * v("hipRot", side))
            g["femur.\(s)"] = femur
            let shin = femur * M.x(v("kneeFlex", side))
            g["shin.\(s)"] = shin
            let foot = shin * M.x(-v("ankleDorsi", side))
            g["foot.\(s)"] = foot
            g["toes.\(s)"] = foot * M.x(v("toeFlex", side))

            // Shoulder girdle.
            let scap = pose.scapula
            let clavicle = thorax * M.y(m * 15 * (scap?.elevation ?? 0)) * M.z(m * 12 * (scap?.protraction ?? 0))
            g["clavicle.\(s)"] = clavicle
            g["scapula.\(s)"] = clavicle * M.y(m * (scap?.upRot ?? 0) * 0.5)

            // Arm: direction from flexion and abduction (as the 2D figure), turned so the elbow
            // bends forward when the arm hangs and upward when it is out to the side.
            let flex = v("shoulderFlex", side), abd = v("shoulderAbd", side)
            let out = V(-m, 0, 0)
            let fr = flex * .pi / 180, ar = abd * .pi / 180
            let local = (Self.forward * (sin(fr) * cos(ar)) + out * sin(ar) + Self.down * (cos(fr) * cos(ar))).unit
            let dir = thorax * local
            let hum = "humerus.\(s)"
            let rest = (tail[hum] ?? Self.down) - (head[hum] ?? .init(0, 0, 0))
            let first = abd > abs(flex) ? thorax * M.y(m * abd) : thorax * M.x(-flex)
            var humerus = M.between(first * rest, dir) * first
            let k = min(1, max(0, (abd - 30) / 60))
            let target = thorax * (Self.forward * (1 - k) + Self.up * k).unit
            let hinge = hingeAxis(s)
            let want = dir.cross(target)
            if want.length > 1e-6 {
                humerus = M.axis(dir, twist(from: humerus * hinge, to: want, about: dir)) * humerus
            }
            humerus = M.axis(dir, m * v("shoulderRot", side)) * humerus
            g[hum] = humerus
            let ulna = humerus * M.axis(hinge, v("elbowFlex", side))
            g["ulna.\(s)"] = ulna
            // Forearm: at rest the palm faces forward (supinated); neutral grip is 90° pronated.
            let fore = forearmAxis(s)
            let radius = ulna * M.axis(fore, -m * (v("forearm", side) + 90))
            g["radius.\(s)"] = radius
            let hand = radius * M.axis(hinge, -v("wristExt", side))
            g["hand.\(s)"] = hand
            for f in 2...5 {
                for seg in ["a", "b", "c"] { g["f\(f)\(seg).\(s)"] = hand }
            }
        }
        return g
    }

    /// The elbow's hinge at rest: flexion turns the forearm toward the front.
    func hingeAxis(_ s: String) -> V {
        let f = forearmAxis(s)
        let h = f.cross(Self.forward)
        return h.length > 1e-6 ? h.unit : V(-1, 0, 0)
    }

    func forearmAxis(_ s: String) -> V {
        guard let elbow = tail["humerus.\(s)"], let wrist = tail["radius.\(s)"] else { return Self.down }
        return (wrist - elbow).unit
    }

    /// Signed angle (degrees) about `axis` that turns `a` toward `b`, both seen across the axis.
    func twist(from a: V, to b: V, about axis: V) -> Double {
        let n = axis.unit
        let pa = (a - n * a.dot(n)).unit, pb = (b - n * b.dot(n)).unit
        return atan2(n.dot(pa.cross(pb)), pa.dot(pb)) * 180 / .pi
    }

    // MARK: Placing the body

    /// Bone heads after rotating, with the pelvis where it rests.
    func heads(_ g: [String: M]) -> [String: V] {
        var h: [String: V] = [:]
        for bone in rig.bones {
            if let p = bone.parent, let hp = h[p], let gp = g[p], let restP = head[p], let rest = head[bone.name] {
                h[bone.name] = hp + gp * (rest - restP)
            } else {
                h[bone.name] = head[bone.name]
            }
        }
        return h
    }

    func tip(_ bone: String, _ g: [String: M], _ h: [String: V]) -> V? {
        guard let hb = h[bone], let t = tail[bone], let r = head[bone] else { return nil }
        return hb + (g[bone] ?? .identity) * (t - r)
    }

    /// Points that touch the floor for one contact word, each with how far the skin sits from it.
    func contactPoints(_ word: String, _ g: [String: M], _ h: [String: V]) -> [(V, Double)] {
        let c = word.lowercased()
        let sides = c.contains("left") ? ["l"] : c.contains("right") ? ["r"] : ["r", "l"]
        var out: [(V, Double)] = []
        for s in sides {
            if c.contains("foot") || c.contains("feet") || c.contains("heel") {
                if let toe = tip("toes.\(s)", g, h) { out.append((toe, 0.01)) }
                if let ankle = h["foot.\(s)"], let restAnkle = head["foot.\(s)"], let restToe = tail["toes.\(s)"] {
                    let heel = V(restAnkle.x, restAnkle.y + 0.045, restToe.z) - restAnkle
                    out.append((ankle + (g["foot.\(s)"] ?? .identity) * heel, 0.01))
                }
            } else if c.contains("toe") {
                if let toe = tip("toes.\(s)", g, h) { out.append((toe, 0.01)) }
                if let mtp = h["toes.\(s)"] { out.append((mtp, 0.02)) }
            } else if c.contains("knee") || c.contains("shin") {
                if let knee = h["shin.\(s)"] { out.append((knee, 0.05)) }
            } else if c.contains("forearm") || c.contains("arm") {
                if let elbow = h["ulna.\(s)"] { out.append((elbow, 0.04)) }
                if let wrist = h["hand.\(s)"] { out.append((wrist, 0.03)) }
            } else if c.contains("hand") {
                if let wrist = h["hand.\(s)"] { out.append((wrist, 0.03)) }
                if let knuckles = tip("hand.\(s)", g, h) { out.append((knuckles, 0.015)) }
            }
        }
        if c.contains("hip") || c.contains("side") || c.contains("seat") {
            if let p = h["pelvis"] { out.append((p, 0.1)) }
        } else if c.contains("back") || c.contains("shoulder") {
            for b in ["pelvis", "thorax", "neck"] { if let p = h[b] { out.append((p, 0.1)) } }
        }
        return out
    }

    /// One frame of the body: rotated, then placed so the lowest contact is on the floor with the
    /// first contact at the origin, the far contact tipped down onto the floor (a plank's feet),
    /// or the hands holding a bar overhead.
    public func frame(_ pose: JointPose, contacts: [String]) -> BodyFrame {
        var g = rotations(pose)
        var h = heads(g)
        let groups = contacts.map { contactPoints($0, g, h) }.filter { !$0.isEmpty }
        func shift(_ d: V) { for (k, p) in h { h[k] = p + d } }

        if groups.isEmpty, contacts.contains(where: { $0.lowercased().contains("bar") }) {
            let hands = [tip("hand.r", g, h), tip("hand.l", g, h)].compactMap { $0 }
            let mid = hands.reduce(V(0, 0, 0), +) * (1 / Double(max(1, hands.count)))
            shift(V(-mid.x, -mid.y, 2.3 - mid.z))
            return made(g, h, floor: nil)
        }

        var floorGroups = groups
        if floorGroups.isEmpty {
            // Nothing named: stand on whatever is lowest of the feet.
            floorGroups = [contactPoints("feet", g, h)]
        }
        let first = floorGroups[0]
        let centre = first.map(\.0).reduce(V(0, 0, 0), +) * (1 / Double(first.count))
        let lowest = floorGroups.flatMap { $0 }.map { $0.0.z - $0.1 }.min() ?? 0
        shift(V(-centre.x, -centre.y, -lowest))

        // A plank: tip about the first contact so the far one rests on the floor too.
        if floorGroups.count >= 2 {
            let points = contacts.map { contactPoints($0, g, h) }.filter { !$0.isEmpty }
            func bottom(_ c: (V, Double)) -> Double { c.0.z - c.1 }
            let pivotCandidate = points[0].min { bottom($0) < bottom($1) }
            let rest: [(V, Double)] = Array(points.dropFirst().joined())
            let farOnes = rest.filter { c in pivotCandidate.map { abs(c.0.y - $0.0.y) > 0.3 } ?? false }
            if let pivot = pivotCandidate, let far = farOnes.min(by: { bottom($0) < bottom($1) }) {
                let dy = far.0.y - pivot.0.y, dz = (far.0.z - far.1) - (pivot.0.z - pivot.1)
                let angle = atan2(dz, abs(dy)) * 180 / .pi * (dy < 0 ? 1 : -1)
                if abs(angle) > 0.01, abs(angle) < 25 {
                    let tilt = M.x(angle)
                    for (k, p) in h { h[k] = pivot.0 + tilt * (p - pivot.0) }
                    for (k, r) in g { g[k] = tilt * r }
                    let low = contacts.flatMap { contactPoints($0, g, h) }.map { $0.0.z - $0.1 }.min() ?? 0
                    shift(V(0, 0, -low))
                }
            }
        }
        // Whatever the contacts say, no part of the body sinks into the floor.
        let anywhere = ["feet", "toes", "knees", "hands", "forearms", "hips", "back"].flatMap { contactPoints($0, g, h) }
            + ["head", "humerus.r", "humerus.l", "femur.r", "femur.l"].compactMap { b in h[b].map { ($0, 0.08) } }
        let sunk = anywhere.map { $0.0.z - $0.1 }.min() ?? 0
        if sunk < -0.01 { shift(V(0, 0, -sunk)) }
        return made(g, h, floor: 0)
    }

    /// Each bone's turn in its own axes: rest⁻¹ · parent⁻¹ · own · rest.
    func made(_ g: [String: M], _ h: [String: V], floor: Double?) -> BodyFrame {
        var local: [String: BodyQuat] = [:]
        for bone in rig.bones {
            let own = g[bone.name] ?? .identity
            let parent = bone.parent.flatMap { g[$0] } ?? .identity
            let r = rest[bone.name] ?? .identity
            local[bone.name] = (r.t * parent.t * own * r).quat
        }
        let root = rig.bones.first.flatMap { h[$0.name] } ?? V(0, 0, 0)
        return BodyFrame(local: local, root: root.array, rotations: g.mapValues(\.quat),
                         heads: h.mapValues(\.array), floor: floor)
    }

    /// The frame at `t` (0...1) of a how-to guide's loop.
    public func frame(_ guide: HowToGuide, at t: Double, fault: JointPose? = nil) -> BodyFrame {
        var pose = Figure.interpolate(guide.keyframes, at: t)
        if let fault { pose = Figure.applying(fault, to: pose) }
        return frame(pose, contacts: guide.contacts)
    }
}

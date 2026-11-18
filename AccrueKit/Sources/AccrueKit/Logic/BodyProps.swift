import Foundation

/// One simple shape of gym equipment in the 3D demo, in the body's Blender axes (x to the
/// body's left, -y forward, z up), in metres.
public struct PropPiece: Hashable, Sendable {
    public enum Shape: String, Sendable { case box, cylinder, sphere }
    /// How it is painted: frame metal, dark rubber and plates, padded upholstery, the cable.
    public enum Finish: String, Sendable { case metal, dark, pad, plate, rubber, cable, accent, wood }

    public var shape: Shape
    public var finish: Finish
    public var center: [Double]
    /// Full sizes along the shape's own x, y and z. A cylinder's length runs along its own z.
    public var size: [Double]
    /// Turn from the shape's own axes to the body's axes.
    public var rotation: BodyQuat
}

/// The equipment an exercise uses, read from its catalog equipment, its name and its family.
public enum PropKind: String, CaseIterable, Sendable {
    case barbell, ezBar, trapBar, dumbbell, kettlebell, plate, medicineBall, sandbag, stone, dowel
    case band, cable, pulldown, smith, machine, landmine, suspension, rings
    case bench, box, step, stabilityBall, bosu, mat, foamRoller, abWheel
    case pullUpBar, dipBars, parallettes
    case treadmill, bike, rower, elliptical, skiErg, stairs, sled, reformer, climber
    case battleRope, jumpRope, heavyBag, poles
}

/// Places an exercise's equipment around the posed body: fixed pieces (a bench, a cable
/// tower) found once from the whole loop, and pieces held in the hands that move with them.
/// Some equipment raises the body (a treadmill deck, a bike saddle, dip bars), so frames
/// come from here rather than straight from Body3D.
public struct PropPlan: Sendable {
    public let kinds: [PropKind]
    /// How far the body is raised off the floor for the equipment under it.
    public let lift: Double
    let body: Body3D
    let guide: HowToGuide
    let fixed: [PropPiece]
    let cableTop: [Body3D.V]
    /// Where the camera looks, how much it must show, and from which side.
    public let framing: BodyFraming

    typealias V = Body3D.V
    typealias M = Body3D.M

    /// The exercise acted out on purpose-built equipment, for the exercises that have that.
    let staging: (any BodyStaging)?
    /// How the hands hold the plain equipment of every other exercise.
    let hands: Handhold?

    public init(guide: HowToGuide, body: Body3D) {
        self.init(guide: guide, body: body, plain: false)
    }

    /// `plain` leaves out any staging, so the plain equipment can be looked at for every exercise.
    init(guide: HowToGuide, body: Body3D, plain: Bool) {
        self.guide = guide
        self.body = body
        if !plain, let staging = Stagings.make(guide, body) {
            self.staging = staging
            hands = nil
            kinds = staging.kinds
            lift = 0
            fixed = staging.fixed
            cableTop = []
            let samples = (0...12).map { staging.frame(Figure.smooth(guide.keyframes, at: Double($0) / 12), in: Double($0) / 12) }
            framing = BodyFraming(guide: guide, samples: samples.map(\.body),
                                  pieces: staging.fixed + (samples.first?.props ?? []), forward: Body3D.forward, margin: 0.6, tight: true)
            return
        }
        staging = nil
        var kinds = Self.kinds(for: guide)
        let samples = (0...12).map { body.frame(guide, at: Double($0) / 12) }
        // Sitting the whole loop with nothing to sit on: a plain seat, not thin air.
        let seats: [PropKind] = [.bench, .machine, .smith, .stabilityBall, .bosu, .box, .bike, .rower, .reformer, .step, .foamRoller]
        if !kinds.contains(where: seats.contains), Self.sits(samples) { kinds.append(.bench) }
        self.kinds = kinds
        let lift = Self.lift(kinds, samples: samples, guide: guide)
        self.lift = lift
        // The fixed equipment is placed round the body as it ends up, with its hands on what it holds.
        let hands = Handhold(kinds: kinds, guide: guide, body: body, lift: lift)
        self.hands = hands
        let lifted = (0...12).map { i -> BodyFrame in
            let t = Double(i) / 12
            return hands.frame(Figure.interpolate(guide.keyframes, at: t), at: t).frame
        }
        var builder = Builder(kinds: kinds, guide: guide, samples: lifted)
        builder.buildFixed()
        fixed = builder.pieces
        cableTop = builder.cableTop
        framing = BodyFraming(guide: guide, samples: lifted, pieces: builder.pieces, forward: builder.forward)
    }

    /// The body at `t` with the equipment's lift, and every piece of equipment for that frame.
    public func frame(at t: Double, fault: JointPose? = nil) -> (body: BodyFrame, props: [PropPiece]) {
        if let staging {
            var pose = Figure.smooth(guide.keyframes, at: t)
            if let fault { pose = Figure.applying(fault, to: pose) }
            let staged = staging.frame(pose, in: t)
            return (staged.body, fixed + staged.props)
        }
        guard let hands else { return (Self.raise(body.frame(guide, at: t, fault: fault), by: lift), fixed) }
        var pose = Figure.interpolate(guide.keyframes, at: t)
        if let fault { pose = Figure.applying(fault, to: pose) }
        let (f, held) = hands.frame(pose, at: t)
        return (f, fixed + moving(f, held))
    }

    /// Hips at chair height over thighs that stay level, with the trunk up, all loop long.
    static func sits(_ samples: [BodyFrame]) -> Bool {
        samples.allSatisfy { f in
            guard f.floor != nil, let p = f.heads["pelvis"], let n = f.heads["neck"] else { return false }
            let level = ["r", "l"].allSatisfy { s in
                guard let hip = f.heads["femur.\(s)"], let knee = f.heads["shin.\(s)"] else { return false }
                let d = V(knee) - V(hip)
                return abs(d.z) < 0.4 * d.length
            }
            return (0.3...0.75).contains(p[2]) && n[2] - p[2] > 0.3 && level
        }
    }

    static func raise(_ f: BodyFrame, by lift: Double) -> BodyFrame {
        guard lift != 0 else { return f }
        var f = f
        f.root[2] += lift
        f.heads = f.heads.mapValues { [$0[0], $0[1], $0[2] + lift] }
        return f
    }

    // MARK: Which equipment

    static func kinds(for g: HowToGuide) -> [PropKind] {
        let name = g.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        var out: [PropKind] = []
        func add(_ k: PropKind) { if !out.contains(k) { out.append(k) } }

        // Whole machines a family is built around.
        switch g.familyID {
        case "treadmill-run": add(.treadmill)
        case "stationary-bike": add(.bike)
        case "row-erg": add(.rower)
        case "elliptical": add(.elliptical)
        case "ski-erg": add(.skiErg)
        case "stair-climb": add(.stairs)
        case "sled-push-pull": add(.sled)
        case "pilates-reformer": add(.reformer)
        case "climber-machine": add(.climber)
        case "battle-ropes": add(.battleRope)
        case "jump-rope": add(.jumpRope)
        case "box-jump", "step-up": add(.box)
        case "lat-pulldown": if g.equipment != "band" { add(.pulldown) }
        case "pull-up", "hanging-leg-raise":
            if has("ring") { add(.rings) } else if !has("lever", "machine") { add(.pullUpBar) }
        case "dip": if has("bench") { add(.bench) } else if has("ring") { add(.rings) } else { add(.dipBars) }
        case "xc-ski-snowshoe": if !has("inline", "snowshoe") { add(.poles) }
        case "kick", "punch": if has("bag") || g.equipment == "heavy-bag" { add(.heavyBag) }
        case "foam-roll": add(.foamRoller)
        case "ab-wheel-rollout": add(has("barbell") ? .barbell : has("ball") ? .stabilityBall : .abWheel)
        default: break
        }

        // A cardio machine is the whole picture.
        if let only = out.first, [.treadmill, .bike, .rower, .elliptical, .skiErg, .stairs, .sled, .reformer, .climber,
                                  .battleRope, .jumpRope].contains(only) {
            return out
        }

        // The exercise's own equipment, then what its name says.
        switch g.equipment {
        case "barbell": add(.barbell)
        case "ez-bar": add(.ezBar)
        case "trap-bar": add(.trapBar)
        case "dumbbell": add(.dumbbell)
        case "kettlebell": add(.kettlebell)
        case "plate": add(.plate)
        case "medicine-ball": add(.medicineBall)
        case "sandbag": add(.sandbag)
        case "strongman": add(.stone)
        case "band": add(.band)
        case "cable-stack": add(g.familyID == "lat-pulldown" ? .pulldown : .cable)
        case "smith-machine": add(.smith)
        case "machine": add(.machine)
        case "landmine": add(.landmine)
        case "suspension": add(.suspension)
        case "stability-ball": add(.stabilityBall)
        case "bosu": add(.bosu)
        case "foam-roller": add(.foamRoller)
        case "ab-wheel": add(.abWheel)
        case "stationary-bike", "arm-ergometer": add(.bike)
        case "elliptical": add(.elliptical)
        case "ski-erg": add(.skiErg)
        case "stepmill": add(.stairs)
        default: break
        }
        if out.isEmpty || g.equipment == nil {
            if has("ez bar", "ez-bar", "ez barbell") { add(.ezBar) }
            else if has("trap bar") { add(.trapBar) }
            else if has("barbell", "olympic bar") { add(.barbell) }
            if has("smith") { add(.smith) }
            if has("dumbbell") { add(.dumbbell) }
            if has("kettlebell") { add(.kettlebell) }
            if has("cable") { add(.cable) }
            if has("band") { add(.band) }
            if has("lever", "machine", "sled 45") { add(.machine) }
            if has("medicine ball") { add(.medicineBall) }
            if has("landmine") { add(.landmine) }
            if has("suspen", "trx") { add(.suspension) }
        }
        if has("stability ball", "exercise ball", "swiss ball", "on ball", "ball sit") { add(.stabilityBall) }
        if has("bosu") { add(.bosu) }
        if has("box") && !has("boxing") { add(.box) }
        if has("step") && g.familyID == "calf-raise" { add(.step) }
        if has("dowel", "stick") { add(.dowel) }
        if has("parallette") { add(.parallettes) }
        if has("bench") || needsBench(g, name: name) { add(.bench) }
        if ["yoga-pose", "pilates-mat"].contains(g.familyID) { add(.mat) }
        if out.isEmpty, let first = g.familyEquipment.first {
            switch first {
            case "barbell": add(.barbell)
            case "dumbbell": add(.dumbbell)
            case "kettlebell": add(.kettlebell)
            case "cable-stack": add(.cable)
            case "machine": add(.machine)
            case "mat": add(.mat)
            case "pull-up-bar": add(.pullUpBar)
            case "dip-bars": add(.dipBars)
            case "box": add(.box)
            default: break
            }
        }
        // A machine replaces a bench, and a cable tower that is a pulldown is not drawn twice.
        if out.contains(.machine) || out.contains(.smith) && g.familyID != "bench-press" { out.removeAll { $0 == .bench } }
        return out
    }

    /// Lying and seated presses, flies, pullovers and the like use a bench unless they say otherwise.
    static func needsBench(_ g: HowToGuide, name: String) -> Bool {
        if name.contains("floor") || name.contains("standing") || name.contains("stability") || name.contains("ball") { return false }
        switch g.familyID {
        case "bench-press": return true
        case "pullover": return !name.contains("pulldown")
        case "chest-fly": return !name.contains("cable") || name.contains("bench") || name.contains("incline") || name.contains("decline")
        case "hip-thrust-bridge": return name.contains("thrust") || g.subtypeID == nil && name.contains("barbell")
        case "triceps-extension", "rear-delt-fly", "row", "lateral-raise", "front-raise", "biceps-curl", "overhead-press":
            return name.contains("incline") || name.contains("decline") || name.contains("lying") || name.contains("seated")
                || name.contains("prone") || name.contains("preacher") || name.contains("chest supported")
        default: return false
        }
    }

    // MARK: Lift

    static func lift(_ kinds: [PropKind], samples: [BodyFrame], guide: HowToGuide) -> Double {
        func lowest(_ bone: String) -> Double { samples.compactMap { $0.heads[bone]?[2] }.min() ?? 0 }
        let hands = min(lowest("hand.r"), lowest("hand.l"))
        if kinds.contains(.dipBars) && samples.first?.floor != nil { return max(0, 1.2 - hands) }
        if kinds.contains(.parallettes) { return 0.1 }
        if kinds.contains(.treadmill) { return 0.18 }
        if kinds.contains(.elliptical) { return 0.3 }
        if kinds.contains(.stairs) { return 0.2 }
        if kinds.contains(.bike) || kinds.contains(.rower) {
            // The saddle or rowing seat sits under the hips.
            let seat = lowest("pelvis") - 0.1
            return max(0, (kinds.contains(.bike) ? 0.7 : 0.35) - seat)
        }
        if kinds.contains(.step) { return 0.12 }
        // A hip thrust keeps its feet on the floor; the bench goes under the shoulders.
        if (kinds.contains(.bench) || kinds.contains(.machine) || kinds.contains(.reformer)) && guide.familyID != "hip-thrust-bridge" {
            // A body lying or sitting on the floor goes up onto the bench.
            let supports = ["pelvis", "thorax"].map { lowest($0) - 0.1 }
            if let low = supports.min(), low < 0.15 { return (kinds.contains(.reformer) ? 0.3 : 0.44) - max(0, low) }
        }
        if kinds.contains(.stabilityBall) {
            let low = min(lowest("pelvis"), lowest("thorax")) - 0.1
            if low < 0.15 && guide.contacts.contains(where: { ["back", "hips"].contains($0) }) { return 0.5 - max(0, low) }
        }
        return 0
    }
}

// MARK: Building the pieces

extension PropPlan {
    typealias Piece = PropPiece

    static func box(_ c: V, _ size: (Double, Double, Double), x: V = V(1, 0, 0), z: V = V(0, 0, 1),
                    _ finish: Piece.Finish) -> Piece {
        let zz = z.unit
        var xx = (x - zz * x.dot(zz))
        if xx.length < 1e-6 { xx = abs(zz.x) < 0.9 ? V(1, 0, 0) : V(0, 1, 0) }
        xx = xx.unit
        let yy = zz.cross(xx)
        let m = M(r0: V(xx.x, yy.x, zz.x), r1: V(xx.y, yy.y, zz.y), r2: V(xx.z, yy.z, zz.z))
        return Piece(shape: .box, finish: finish, center: c.array, size: [size.0, size.1, size.2], rotation: m.quat)
    }

    static func rod(_ a: V, _ b: V, _ radius: Double, _ finish: Piece.Finish) -> Piece {
        let d = b - a
        let m = M.between(V(0, 0, 1), d.length > 1e-6 ? d : V(0, 0, 1))
        return Piece(shape: .cylinder, finish: finish, center: ((a + b) * 0.5).array,
                     size: [2 * radius, 2 * radius, max(0.001, d.length)], rotation: m.quat)
    }

    static func disc(_ c: V, axis: V, radius: Double, thickness: Double, _ finish: Piece.Finish) -> Piece {
        let a = axis.unit
        return rod(c - a * (thickness / 2), c + a * (thickness / 2), radius, finish)
    }

    static func ball(_ c: V, _ radius: Double, _ finish: Piece.Finish, squash: Double = 1) -> Piece {
        Piece(shape: .sphere, finish: finish, center: c.array, size: [2 * radius, 2 * radius, 2 * radius * squash],
              rotation: .identity)
    }

    /// Where a hand holds things: across the palm, just past the knuckles for an open hand, and
    /// the middle of the handle for a closed one.
    struct Grip {
        var point: V
        /// Across the palm, thumb side to little finger.
        var across: V
        /// Out of the palm.
        var palm: V
        /// Along the fingers.
        var fingers: V
    }

    static func grip(_ f: BodyFrame, _ s: String) -> Grip? {
        guard let w = f.heads["hand.\(s)"], let k = f.heads["f3a.\(s)"], let q = f.rotations["hand.\(s)"] else { return nil }
        let wrist = V(w), knuckle = V(k), r = M(q)
        let palm = r * V(0, -1, 0)
        let fingers = (knuckle - wrist).unit
        return Grip(point: knuckle + fingers * 0.01 + palm * 0.025, across: r * V(1, 0, 0), palm: palm, fingers: fingers)
    }

    static func grip(_ g: [String: M], _ h: [String: V], _ s: String) -> Grip? {
        guard let wrist = h["hand.\(s)"], let knuckle = h["f3a.\(s)"], let r = g["hand.\(s)"] else { return nil }
        let palm = r * V(0, -1, 0)
        let fingers = (knuckle - wrist).unit
        return Grip(point: knuckle + fingers * 0.01 + palm * 0.025, across: r * V(1, 0, 0), palm: palm, fingers: fingers)
    }

    /// A handle in a closed hand on a strap toward `anchor`: the grip, the two sides of its
    /// stirrup, and the eye the strap ties to.
    static func stirrup(_ g: Grip, toward anchor: V, _ finish: Piece.Finish) -> (pieces: [Piece], eye: V) {
        var dir = anchor - g.point
        dir = dir - g.across * dir.dot(g.across)
        dir = dir.length > 1e-6 ? dir.unit : g.fingers
        let eye = g.point + dir * 0.12
        let a = g.point - g.across * 0.065, b = g.point + g.across * 0.065
        return ([rod(a, b, 0.016, .dark), rod(a, eye, 0.005, finish), rod(b, eye, 0.005, finish), ball(eye, 0.009, .metal)], eye)
    }

    /// A gymnastic ring as a round of short rods.
    static func ring(_ centre: V, axis: V, radius: Double, _ finish: Piece.Finish) -> [Piece] {
        let n = axis.unit
        let u = n.cross(abs(n.z) < 0.9 ? V(0, 0, 1) : V(1, 0, 0)).unit, v = n.cross(u)
        let count = 14
        let points = (0..<count).map { i -> V in
            let a = 2 * Double.pi * Double(i) / Double(count)
            return centre + (u * cos(a) + v * sin(a)) * radius
        }
        return (0..<count).flatMap { i in
            [rod(points[i], points[(i + 1) % count], 0.014, finish), ball(points[i], 0.014, finish)]
        }
    }

    /// A kettlebell on a handle at `handle` running along `across`, its ball toward `toward`.
    static func kettlebell(handle: V, across: V, half: Double, toward: V) -> [Piece] {
        let centre = handle + toward * 0.145
        var out = [rod(handle - across * half, handle + across * half, 0.012, .dark), ball(centre, 0.1, .dark)]
        for side in [-1.0, 1.0] {
            let end = handle + across * (side * half)
            out.append(rod(end, centre + across * (side * 0.05) - toward * 0.07, 0.012, .dark))
            out.append(ball(end, 0.012, .dark))
        }
        return out
    }

    /// Which way a kettlebell lies from the hand that holds it: on from the fingers when they
    /// point down or level, drooping a little, and over the back of the wrist when the fist is up.
    static func bell(_ g: Grip) -> V {
        let down = V(0, 0, -1)
        var hang = down - g.across * down.dot(g.across)
        hang = hang.length > 0.3 ? hang.unit : g.fingers
        let up = min(1, max(0, -hang.dot(g.fingers)))
        let dir = g.fingers * (0.6 * (1 - up)) + hang * (0.4 + 0.1 * up) - g.palm * (0.85 * up)
        return dir.length > 1e-6 ? dir.unit : hang
    }

    /// Pieces that move with the body: what the hands hold and the cables to them.
    func moving(_ f: BodyFrame, _ held: Held) -> [Piece] {
        let r = held.grips["r"], l = held.grips["l"]
        let grips = [r, l].compactMap { $0 }
        guard !grips.isEmpty else { return [] }
        // A bar in both hands is where the hands were fitted to it; anything else follows them.
        let mid = held.bar?.mid ?? grips.map(\.point).reduce(V(0, 0, 0), +) * (1 / Double(grips.count))
        let apart = (r != nil && l != nil) ? (r!.point - l!.point).length : 0
        let barAxis = held.bar?.axis ?? (apart > 0.2 ? (l!.point - r!.point).unit : (r?.across ?? V(1, 0, 0)))
        let thoraxFwd = M(f.rotations["thorax"] ?? .identity) * V(0, -1, 0)
        let hipsLeft = (M(f.rotations["pelvis"] ?? .identity) * V(1, 0, 0)).flat
        let levelAxis = held.bar?.axis ?? (hipsLeft.length > 0.3 ? hipsLeft.unit : barAxis)
        var out: [Piece] = []

        func barbell(length: Double, plateRadius: Double) {
            let half = length / 2
            let a = levelAxis
            out.append(Self.rod(mid - a * half, mid + a * half, 0.014, .metal))
            for side in [-1.0, 1.0] {
                let c = mid + a * (side * (half - 0.2))
                out.append(Self.disc(c, axis: a, radius: plateRadius, thickness: 0.07, .plate))
                out.append(Self.disc(mid + a * (side * (half - 0.27)), axis: a, radius: 0.03, thickness: 0.03, .metal))
            }
        }

        for kind in kinds {
            switch kind {
            case .barbell: barbell(length: 2.0, plateRadius: 0.225)
            case .ezBar: barbell(length: 1.3, plateRadius: 0.15)
            case .dowel: out.append(Self.rod(mid - barAxis * 0.7, mid + barAxis * 0.7, 0.012, .wood))
            case .trapBar:
                let barAxis = levelAxis
                let fwd = barAxis.cross(V(0, 0, 1)).unit
                for side in [-1.0, 1.0] {
                    let c = mid + barAxis * (side * 0.33)
                    out.append(Self.rod(c - fwd * 0.3, c + fwd * 0.3, 0.015, .metal))
                    out.append(Self.rod(c, c + barAxis * (side * 0.45), 0.015, .metal))
                    out.append(Self.disc(c + barAxis * (side * 0.4), axis: barAxis, radius: 0.225, thickness: 0.07, .plate))
                }
                out.append(Self.rod(mid + fwd * 0.3 - barAxis * 0.33, mid + fwd * 0.3 + barAxis * 0.33, 0.015, .metal))
                out.append(Self.rod(mid - fwd * 0.3 - barAxis * 0.33, mid - fwd * 0.3 + barAxis * 0.33, 0.015, .metal))
            case .dumbbell:
                for g in grips {
                    out.append(Self.rod(g.point - g.across * 0.13, g.point + g.across * 0.13, 0.016, .metal))
                    for side in [-1.0, 1.0] {
                        out.append(Self.disc(g.point + g.across * (side * 0.1), axis: g.across, radius: 0.06, thickness: 0.07, .dark))
                    }
                }
            case .kettlebell:
                if let bar = held.bar {
                    // One bell in both hands, lying the way the hands point.
                    let along = grips.map(\.fingers).reduce(V(0, 0, 0), +)
                    let dir = along - bar.axis * along.dot(bar.axis)
                    out += Self.kettlebell(handle: mid, across: bar.axis, half: 0.11, toward: dir.length > 1e-6 ? dir.unit : V(0, 0, -1))
                } else {
                    // A bell at the shoulder or the hip hangs round its handle to the outside of
                    // the body, not into it.
                    let rods = body.bulk(f.rotations.mapValues { M($0) }, f.heads.mapValues { V($0) }, walls: false)
                    for g in grips {
                        let hang = Self.bell(g)
                        var toward = hang
                        // Of the ways it can hang round the handle, the nearest to its own that
                        // is clear of the body, or failing that the one least far into it.
                        let other = g.across.cross(hang)
                        var best = Double.infinity
                        for step in 0..<24 {
                            let turn = Double(step % 2 == 0 ? step / 2 : -(step + 1) / 2) * (Double.pi / 12)
                            let way = hang * cos(turn) + other * sin(turn)
                            let centre = g.point + way * 0.145
                            let depth = rods.map { rod -> Double in
                                let share = Body3D.nearest(centre, centre, rod.a, rod.b).1
                                return rod.ra + (rod.rb - rod.ra) * share + 0.1 - (centre - mix(rod.a, rod.b, share)).length
                            }.max() ?? 0
                            let cost = (depth < 0.005 ? 0 : 1 + depth) + abs(turn) * 0.01
                            if cost < best {
                                best = cost
                                toward = way
                            }
                        }
                        out += Self.kettlebell(handle: g.point, across: g.across, half: 0.06, toward: toward)
                    }
                }
            case .plate:
                if let bar = held.bar {
                    // Held by its rim at both sides, flat to the chest.
                    let square = thoraxFwd - bar.axis * thoraxFwd.dot(bar.axis)
                    out.append(Self.disc(mid, axis: square.length > 1e-6 ? square : thoraxFwd, radius: 0.22, thickness: 0.04, .plate))
                } else {
                    // One in each hand, held by the rim and hanging on from the fingers.
                    for g in grips { out.append(Self.disc(g.point + g.fingers * 0.2, axis: g.palm, radius: 0.22, thickness: 0.04, .plate)) }
                }
            case .medicineBall:
                out.append(Self.ball(apart > 0 && apart < 0.45 ? mid + thoraxFwd * 0.05 : grips[0].point + grips[0].palm * 0.1, 0.12, .accent))
            case .sandbag:
                out.append(Self.box(mid + thoraxFwd * 0.1, (0.55, 0.28, 0.28), x: barAxis, .dark))
            case .stone:
                out.append(Self.ball(mid + thoraxFwd * 0.18, 0.22, .rubber))
            case .abWheel:
                out.append(Self.disc(V(mid.x, mid.y, 0.09), axis: barAxis, radius: 0.09, thickness: 0.06, .dark))
                out.append(Self.rod(V(mid.x, mid.y, 0.09) - barAxis * 0.13, V(mid.x, mid.y, 0.09) + barAxis * 0.13, 0.012, .metal))
            case .band:
                // Standing on the band: from each hand down to that foot.
                for (g, s) in [(r, "r"), (l, "l")] {
                    guard let g, let foot = f.heads["toes.\(s)"] ?? f.heads["foot.\(s)"] else { continue }
                    let anchor = cableTop.first.map { $0 } ?? V(foot[0], foot[1], max(0.02, foot[2] - 0.05))
                    let handle = Self.stirrup(g, toward: anchor, .accent)
                    out += handle.pieces
                    out.append(Self.rod(handle.eye, anchor, 0.007, .accent))
                }
            case .cable, .pulldown, .skiErg, .suspension, .rings:
                // Cables run from each pulley to the hand on its side, or one cable to the middle.
                if cableTop.count >= 2, let r, let l {
                    for (g, top) in [(r, cableTop[0]), (l, cableTop[1])] {
                        if kind == .rings {
                            // The hand holds the ring at its lowest point from the strap.
                            var up = top - g.point
                            up = up - g.across * up.dot(g.across)
                            up = up.length > 1e-6 ? up.unit : g.fingers * -1
                            out += Self.ring(g.point + up * 0.09, axis: g.across.cross(up), radius: 0.09, .wood)
                            out.append(Self.rod(top, g.point + up * 0.18, 0.005, .cable))
                        } else {
                            let handle = Self.stirrup(g, toward: top, .cable)
                            out += handle.pieces
                            out.append(Self.rod(top, handle.eye, 0.005, .cable))
                        }
                    }
                } else if let top = cableTop.first {
                    if kind == .cable, let leg = hands?.ankle, let ankle = f.heads["foot.\(leg)"], let knee = f.heads["shin.\(leg)"] {
                        // A cuff round the ankle of the leg that works, and the cable from it.
                        let at = V(ankle), up = (V(knee) - at).unit
                        out.append(Self.rod(at + up * 0.03, at + up * 0.09, 0.05, .dark))
                        out.append(Self.rod(top, at + up * 0.06 + (top - at).unit * 0.05, 0.005, .cable))
                    } else if held.bar != nil {
                        out.append(Self.rod(top, mid, 0.005, .cable))
                        // A short bar for hands close together, the long one for a wide grip.
                        let half = kind == .pulldown ? 0.6 : apart > 0.3 ? 0.25 : apart / 2 + 0.1
                        out.append(Self.rod(mid - barAxis * half, mid + barAxis * half, 0.014, .metal))
                    } else if kind == .cable, Builder.rope(guide), apart > 0 {
                        // A rope attachment: an end in each fist with its stopper below the
                        // hand, and both ends meeting at the cable's clip.
                        // Hands that part wide (beside the head, in a face pull) take the
                        // clip further off, so the rope runs round the head and not through it.
                        let clip = mid + (top - mid).unit * min(max(0.15, apart * 0.9), (top - mid).length * 0.5)
                        for g in grips {
                            let side = (clip - g.point).dot(g.across) < 0 ? -1.0 : 1.0
                            let stop = g.point - g.across * (side * 0.065), leave = g.point + g.across * (side * 0.05)
                            out.append(Self.rod(stop, leave, 0.012, .dark))
                            out.append(Self.ball(stop, 0.021, .dark))
                            out.append(Self.rod(leave, clip, 0.012, .dark))
                        }
                        out.append(Self.ball(clip, 0.016, .metal))
                        out.append(Self.rod(top, clip, 0.005, .cable))
                    } else {
                        let handle = Self.stirrup(grips[0], toward: top, .cable)
                        out += handle.pieces
                        out.append(Self.rod(top, handle.eye, 0.005, .cable))
                    }
                }
            case .smith:
                out.append(Self.rod(mid - levelAxis * 0.85, mid + levelAxis * 0.85, 0.015, .metal))
                for side in [-1.0, 1.0] {
                    out.append(Self.disc(mid + levelAxis * (side * 0.6), axis: levelAxis, radius: 0.2, thickness: 0.06, .plate))
                }
            case .landmine:
                if let pivot = cableTop.first {
                    out.append(Self.rod(pivot, mid + (mid - pivot).unit * 0.3, 0.025, .metal))
                    out.append(Self.disc(mid + (mid - pivot).unit * 0.25, axis: mid - pivot, radius: 0.2, thickness: 0.06, .plate))
                }
            case .battleRope:
                for (i, g) in grips.enumerated() where i < cableTop.count {
                    // The rope's end lies through the fist and then runs off to its anchor.
                    let side = (cableTop[i] - g.point).dot(g.across) < 0 ? -1.0 : 1.0
                    let end = g.point + g.across * (side * 0.06)
                    out.append(Self.rod(g.point - g.across * (side * 0.07), end, 0.018, .dark))
                    out.append(Self.ball(end, 0.018, .dark))
                    out.append(Self.rod(end, cableTop[i], 0.018, .dark))
                }
            case .jumpRope:
                if let r, let l, let fr = f.heads["toes.r"], let fl = f.heads["toes.l"] {
                    let under = (V(fr) + V(fl)) * 0.5
                    let low = V(under.x, under.y + 0.05, -0.0) // just under the feet at the low point
                    // A handle in each fist, the rope from the outer end of each.
                    var ends: [V] = []
                    for (g, other) in [(r, l), (l, r)] {
                        let side = (other.point - g.point).dot(g.across) < 0 ? 1.0 : -1.0
                        out.append(Self.rod(g.point - g.across * (side * 0.06), g.point + g.across * (side * 0.07), 0.013, .dark))
                        ends.append(g.point + g.across * (side * 0.07))
                    }
                    out.append(Self.rod(ends[0], low + barAxis * -0.25, 0.006, .dark))
                    out.append(Self.rod(low + barAxis * -0.25, low + barAxis * 0.25, 0.006, .dark))
                    out.append(Self.rod(low + barAxis * 0.25, ends[1], 0.006, .dark))
                }
            case .poles:
                for g in grips {
                    let tip = V(g.point.x, g.point.y + 0.35, 0)
                    out.append(Self.rod(g.point + (g.point - tip).unit * 0.08, tip, 0.01, .metal))
                }
            case .rower:
                if let top = cableTop.first {
                    out.append(Self.rod(top, mid, 0.004, .cable))
                    out.append(Self.rod(mid - barAxis * 0.28, mid + barAxis * 0.28, 0.016, .dark))
                }
            case .elliptical:
                for g in grips {
                    out.append(Self.rod(g.point, V(g.point.x, g.point.y - 0.1, 0.35), 0.02, .metal))
                }
                for s in ["r", "l"] {
                    guard let a = f.heads["foot.\(s)"], let t = f.heads["toes.\(s)"] else { continue }
                    let c = (V(a) + V(t)) * 0.5
                    out.append(Self.box(V(c.x, c.y, lift - 0.03), (0.14, 0.38, 0.04), .dark))
                }
            case .bike:
                for s in ["r", "l"] {
                    guard let a = f.heads["foot.\(s)"], let t = f.heads["toes.\(s)"] else { continue }
                    let c = (V(a) * 0.4 + V(t) * 0.6)
                    out.append(Self.box(V(c.x, c.y, c.z - 0.06), (0.11, 0.14, 0.025), .dark))
                }
            default: break
            }
        }
        return out
    }
}

/// Works out where the fixed equipment goes from the whole loop.
struct Builder {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    let kinds: [PropKind]
    let guide: HowToGuide
    let samples: [BodyFrame]
    var pieces: [PropPiece] = []
    var cableTop: [V] = []

    init(kinds: [PropKind], guide: HowToGuide, samples: [BodyFrame]) {
        self.kinds = kinds
        self.guide = guide
        self.samples = samples
    }

    func head(_ b: String, _ i: Int = 0) -> V { samples[i].heads[b].map { V($0) } ?? V(0, 0, 0) }
    func lowest(_ b: String) -> Double { samples.compactMap { $0.heads[b]?[2] }.min() ?? 0 }
    func highest(_ b: String) -> Double { samples.compactMap { $0.heads[b]?[2] }.max() ?? 0 }
    func mean(_ b: String) -> V {
        let ps = samples.compactMap { $0.heads[b] }.map { V($0) }
        return ps.reduce(V(0, 0, 0), +) * (1 / Double(max(1, ps.count)))
    }
    func gripMean(_ s: String) -> V? {
        let ps = samples.compactMap { PropPlan.grip($0, s)?.point }
        return ps.isEmpty ? nil : ps.reduce(V(0, 0, 0), +) * (1 / Double(ps.count))
    }
    var hands: V { [gripMean("r"), gripMean("l")].compactMap { $0 }.reduce(V(0, 0, 0), +) * 0.5 }
    /// Which way the body faces at the start, flat on the floor: square to its hips, so a body
    /// lying on its back still has a front and a side.
    var forward: V {
        let r = M(samples[0].rotations["pelvis"] ?? .identity)
        let left = (r * V(1, 0, 0)).flat
        if left.length > 0.3 { return left.unit.cross(V(0, 0, 1)) }
        let f = (r * V(0, -1, 0)).flat
        return f.length > 0.3 ? f.unit : V(0, -1, 0)
    }
    var side: V { V(0, 0, 1).cross(forward).unit }  // to the body's left
    /// The trunk at its most upright, in degrees from flat.
    var trunkAngle: Double {
        let d = head("neck") - head("pelvis")
        return atan2(d.z, (d.x * d.x + d.y * d.y).squareRoot()) * 180 / .pi
    }

    mutating func add(_ p: PropPiece) { pieces.append(p) }

    mutating func buildFixed() {
        for kind in kinds {
            switch kind {
            case .bench: bench()
            case .machine: machine()
            case .cable: cable()
            case .pulldown: pulldown()
            case .smith: smith()
            case .box: box()
            case .step: step()
            case .stabilityBall: stabilityBall()
            case .bosu:
                let feet = (mean("foot.r") + mean("foot.l")) * 0.5
                add(Plan.ball(V(feet.x, feet.y, 0), 0.32, .accent, squash: 0.4))
            case .mat: mat()
            case .foamRoller: foamRoller()
            case .pullUpBar: pullUpBar()
            case .dipBars: dipBars()
            case .parallettes: parallettes()
            case .rings, .suspension: overheadStraps(kind)
            case .landmine: cableTop = [V(hands.x, hands.y, 0) + forward * 1.5]
            case .treadmill: treadmill()
            case .bike: bike()
            case .rower: rower()
            case .elliptical: elliptical()
            case .skiErg: skiErg()
            case .stairs: stairs()
            case .sled: sled()
            case .reformer: reformer()
            case .climber: climber()
            case .battleRope:
                let anchor = V(hands.x, hands.y, 0.15) + forward * 3
                cableTop = [anchor - side * 0.1, anchor + side * 0.1]
                add(Plan.box(anchor + V(0, 0, 0.1), (0.3, 0.3, 0.5), x: side, .dark))
            case .heavyBag:
                let c = mean("thorax") + forward * 0.75
                add(Plan.rod(V(c.x, c.y, 0.55), V(c.x, c.y, 1.65), 0.18, .rubber))
                add(Plan.rod(V(c.x, c.y, 1.65), V(c.x, c.y, 2.3), 0.008, .metal))
            default: break
            }
        }
    }

    // MARK: Benches and seats

    /// A flat or inclined bench under whatever of the hips and back rests on it.
    mutating func bench() {
        let i = samples.indices.min { lowest(at: $0) < lowest(at: $1) } ?? 0
        let f = samples[i]
        let pelvis = V(f.heads["pelvis"]!), neck = V(f.heads["neck"]!), thorax = V(f.heads["thorax"]!)
        let angle = trunkAngle
        if guide.familyID == "dip" {
            // Bench dips: hands on a bench behind.
            let h = hands
            add(Plan.box(V(h.x, h.y, (h.z - 0.03) / 2) - forward * 0.05, (0.9, 0.32, max(0.1, h.z - 0.03)), x: side, .pad))
            return
        }
        if guide.familyID == "hip-thrust-bridge" || guide.familyID == "pullover" {
            // Across the bench under the shoulder blades.
            let top = thorax.z * 0.3 + neck.z * 0.7 - 0.1
            let c = thorax * 0.3 + neck * 0.7
            add(Plan.box(V(c.x, c.y, max(0.1, top) / 2), (1.1, 0.3, max(0.1, top)), x: side, .pad))
            return
        }
        if angle < 25 {
            // Lying: a flat bench from the hips to the head.
            let a = V(pelvis.x, pelvis.y, 0) - (neck - pelvis).flat.unit * 0.25
            let b = V(neck.x, neck.y, 0) + (neck - pelvis).flat.unit * 0.15
            let top = min(pelvis.z, thorax.z) - 0.1
            padOnLegs(from: a, to: b, top: top)
        } else {
            // Sitting: a seat under the hips and, unless upright, a back pad along the trunk.
            seat(under: pelvis)
            let back = M(f.rotations["thorax"] ?? .identity) * V(0, 1, 0)
            if angle < 80 || guide.exerciseName.contains("seated") {
                let lowEnd = pelvis + back * 0.12 + (neck - pelvis).unit * 0.05
                let highEnd = neck + back * 0.12 + (neck - pelvis).unit * 0.1
                add(Plan.box((lowEnd + highEnd) * 0.5, (0.3, 0.06, (highEnd - lowEnd).length), x: side, z: highEnd - lowEnd, .pad))
                add(Plan.rod(V(lowEnd.x, lowEnd.y, 0), (lowEnd + highEnd) * 0.5 + back * 0.04, 0.03, .metal))
            }
        }
    }

    func lowest(at i: Int) -> Double {
        ["pelvis", "thorax"].compactMap { samples[i].heads[$0]?[2] }.min() ?? 0
    }

    /// A padded top at `top` from a to b on two legs.
    mutating func padOnLegs(from a: V, to b: V, top: Double) {
        let c = (a + b) * 0.5
        let along = (b - a).unit
        add(Plan.box(V(c.x, c.y, top - 0.04), (0.3, (b - a).length, 0.08), x: along.cross(V(0, 0, 1)), .pad))
        for e in [a + along * 0.12, b - along * 0.12] {
            add(Plan.box(V(e.x, e.y, (top - 0.08) / 2), (0.24, 0.05, max(0.02, top - 0.08)), x: along.cross(V(0, 0, 1)), .metal))
        }
    }

    mutating func seat(under pelvis: V) {
        let top = lowest("pelvis") - 0.11
        guard top > 0.08 else { return }
        let c = V(pelvis.x, pelvis.y, top - 0.04) + forward * 0.05
        add(Plan.box(c, (0.36, 0.36, 0.08), x: side, .pad))
        add(Plan.rod(V(c.x, c.y, 0), V(c.x, c.y, top - 0.08), 0.035, .metal))
        add(Plan.box(V(c.x, c.y, 0.015), (0.5, 0.5, 0.03), x: side, .metal))
    }

    // MARK: Machines

    mutating func machine() {
        let f = samples[0]
        let pelvis = V(f.heads["pelvis"]!), neck = V(f.heads["neck"]!)
        let name = guide.exerciseName
        switch guide.familyID {
        case "leg-press":
            // Back rest along the trunk, and the sled under the feet.
            bench()
            let feet = (head("toes.r") + head("toes.l") + head("foot.r") + head("foot.l")) * 0.25
            let push = (feet - pelvis).unit
            add(Plan.box(feet + push * 0.05, (0.7, 0.45, 0.05), x: side, z: push, .metal))
            add(Plan.rod(V(feet.x, feet.y, 0) + forward * 0.3, feet + push * 0.08, 0.05, .metal))
        case "leg-extension", "leg-curl":
            if trunkAngle < 25 {
                bench()
                let ankles = (head("foot.r") + head("foot.l")) * 0.5
                add(Plan.disc(ankles + V(0, 0, 0.08), axis: side, radius: 0.06, thickness: 0.4, .pad))
            } else {
                bench()
                let ankles = (mean("foot.r") + mean("foot.l")) * 0.5
                let pad = guide.familyID == "leg-extension" ? ankles + forward * 0.08 : ankles - forward * 0.08
                add(Plan.disc(pad, axis: side, radius: 0.06, thickness: 0.4, .pad))
                add(Plan.rod(V(pelvis.x, pelvis.y, lowest("pelvis") - 0.15) + forward * 0.25, pad, 0.025, .metal))
            }
        case "calf-raise":
            let shoulders = (head("humerus.r") + head("humerus.l")) * 0.5
            add(Plan.disc(shoulders + V(0, 0, 0.06), axis: side, radius: 0.07, thickness: 0.5, .pad))
            tower(at: V(pelvis.x, pelvis.y, 0) - forward * 0.35, height: 2.0)
        case "hip-abduction", "hip-adduction":
            bench()
            for s in ["r", "l"] {
                let k = mean("shin.\(s)")
                add(Plan.disc(k + side * (s == "r" ? -0.08 : 0.08), axis: forward, radius: 0.08, thickness: 0.25, .pad))
            }
        default:
            // Seated or chest-supported station: seat, back pad and handles on arms from a frame.
            if trunkAngle > 25 && lowest("pelvis") - 0.11 > 0.2 {
                bench()
            } else if trunkAngle < 25 || name.contains("lying") {
                bench()
            }
            let back = M(f.rotations["thorax"] ?? .identity) * V(0, 1, 0)
            let frameBase = V(pelvis.x, pelvis.y, 0) + back.flat.unit * 0.55
            tower(at: frameBase, height: max(1.6, neck.z + 0.4))
            for s in ["r", "l"] {
                guard let g = gripMean(s) else { continue }
                let pivot = V(frameBase.x, frameBase.y, max(0.9, g.z)) + side * (s == "r" ? -0.35 : 0.35)
                add(Plan.rod(pivot, g, 0.022, .metal))
            }
        }
    }

    /// An upright frame with a weight stack.
    mutating func tower(at base: V, height: Double) {
        add(Plan.box(V(base.x, base.y, height / 2), (0.08, 0.08, height), x: side, .metal))
        add(Plan.box(V(base.x, base.y, 0.015), (0.6, 0.6, 0.03), x: side, .metal))
        add(Plan.box(V(base.x, base.y, 0.45) - forward * 0.12, (0.26, 0.16, 0.7), x: side, .dark))
    }

    // MARK: Cables

    mutating func cable() {
        let name = guide.exerciseName
        let h = hands
        // Where the pulley is: high for pushdowns and face pulls, low for curls and raises,
        // at the side for chops and presses that resist turning, both sides for crossovers.
        let high = name.contains("pushdown") || name.contains("push down") || name.contains("face pull") || name.contains("high")
            || name.contains("overhead") || name.contains("kneeling") || guide.familyID == "face-pull" || name.contains("pulldown")
            || name.contains("crunch")
        let low = name.contains("low") || name.contains("curl") || name.contains("raise") || name.contains("upright")
            || name.contains("shrug") || name.contains("kickback") || name.contains("deadlift") || name.contains("pull through")
            || name.contains("squat") || name.contains("lunge")
        if Self.ankleCable(guide) {
            // A low pulley on the side the leg is pulled away from: out to its own side for
            // bringing it in, across the body for taking it out, in front for sending it back,
            // behind for bringing it forward, and past the feet for someone lying down.
            let leg = Self.strapped { s in samples.compactMap { $0.heads["foot.\(s)"].map { V($0) } } }
            let pelvis = mean("pelvis"), foot = mean("foot.\(leg)")
            let out = side * (leg == "r" ? -1.0 : 1.0)
            var away = forward, from = pelvis
            switch guide.familyID {
            case "hip-adduction": away = out
            case "hip-abduction": away = out * -1
            case "leg-extension", "hip-flexion": away = forward * -1
            default: break
            }
            let along = (foot - pelvis).flat
            if trunkAngle < 30, along.length > 0.3 {
                away = along.unit
                from = foot
            }
            let base = V(from.x, from.y, 0) + away * 1.1
            tower(at: base, height: 2.25)
            cableTop = [V(base.x, base.y, 0.15)]
            add(Plan.ball(cableTop[0], 0.05, .dark))
            return
        }
        let both = Self.twoCables(guide)
        let lateral = guide.familyID == "pallof-anti-rotation" || guide.familyID == "woodchop-rotation" || guide.familyID == "shoulder-rotation"
        let z = high ? 2.1 : low ? 0.15 : max(0.4, h.z)
        // Pull toward the body: the pulley is in front of what pulls, behind what pushes.
        var dir = forward
        if name.contains("pushdown") || name.contains("triceps") || name.contains("crunch") || guide.familyID == "triceps-extension" {
            dir = forward * 0.6
        }
        if guide.familyID == "overhead-press" || guide.familyID == "bench-press" || name.contains("press") && !lateral {
            dir = forward * -1
        }
        if both {
            for s in [-1.0, 1.0] {
                let base = V(h.x, h.y, 0) + side * (s * 1.1) + forward * 0.1
                tower(at: base, height: 2.25)
                cableTop.append(V(base.x, base.y, z))
            }
            // Right hand to the tower on the right (-side), left to the left.
            cableTop = [cableTop[0], cableTop[1]]
            return
        }
        let base = lateral ? V(h.x, h.y, 0) + side * -1.0 : V(h.x, h.y, 0) + dir * 1.0
        tower(at: base, height: 2.25)
        cableTop = [V(base.x, base.y, z)]
        add(Plan.ball(cableTop[0], 0.05, .dark))
    }

    /// A crossover, a cable fly and a cable raise have a pulley, and a handle, for each hand.
    static func twoCables(_ guide: HowToGuide) -> Bool {
        !rope(guide) && (guide.exerciseName.contains("cross") || ["chest-fly", "rear-delt-fly", "lateral-raise"].contains(guide.familyID))
    }

    /// Cable work for the legs straps the cable to an ankle; the hands hold nothing.
    static func ankleCable(_ guide: HowToGuide) -> Bool {
        ["hip-adduction", "hip-abduction", "glute-kickback", "leg-curl", "leg-extension", "hip-flexion"].contains(guide.familyID)
    }

    /// The leg a cable is strapped to: the one whose foot travels further through the loop.
    static func strapped(_ feet: (String) -> [V]) -> String {
        func spread(_ s: String) -> Double {
            let at = feet(s)
            return at.map { ($0 - at[0]).length }.max() ?? 0
        }
        return spread("r") >= spread("l") ? "r" : "l"
    }

    /// A rope attachment hangs from one pulley and puts one of its ends in each hand. A face
    /// pull is done with one: the hands part and come back beside the ears, where a bar would
    /// have to go through the head.
    static func rope(_ guide: HowToGuide) -> Bool {
        guide.exerciseName.contains("rope") || guide.familyID == "face-pull"
    }

    mutating func pulldown() {
        let pelvis = mean("pelvis")
        if lowest("pelvis") - 0.11 > 0.2 {
            seat(under: pelvis)
            // Thigh pads over the knees.
            let knees = (mean("shin.r") + mean("shin.l")) * 0.5
            add(Plan.disc(knees + V(0, 0, 0.1) - forward * 0.05, axis: side, radius: 0.055, thickness: 0.45, .pad))
        }
        let h = hands
        let topZ = max(2.2, highest("hand.r") + 0.4)
        let base = V(pelvis.x, pelvis.y, 0) + forward * 0.45
        tower(at: base, height: topZ + 0.1)
        add(Plan.box(V(base.x, base.y, topZ), (0.1, (V(h.x, h.y, 0) - base).length + 0.2, 0.08),
                     x: side, .metal))
        cableTop = [V(h.x, h.y, topZ)]
        add(Plan.ball(cableTop[0], 0.05, .dark))
    }

    mutating func smith() {
        let h = hands
        for s in [-1.0, 1.0] {
            let rail = V(h.x, h.y, 0) + side * (s * 0.75)
            add(Plan.rod(rail, rail + V(0, 0, 2.2), 0.025, .metal))
        }
        add(Plan.rod(V(h.x, h.y, 2.2) - side * 0.8, V(h.x, h.y, 2.2) + side * 0.8, 0.03, .metal))
        if kinds.contains(.bench) == false && trunkAngle < 25 { bench() }
    }

    // MARK: Boxes, balls, floor

    mutating func box() {
        // Under the foot that stays highest (a step-up), else in front of the feet.
        let rMin = lowest("toes.r"), lMin = lowest("toes.l")
        let s = rMin > lMin ? "r" : "l"
        let topFoot = max(rMin, lMin)
        if topFoot > 0.15 {
            let c = mean("foot.\(s)") * 0.5 + mean("toes.\(s)") * 0.5
            add(Plan.box(V(c.x, c.y, topFoot / 2 - 0.02), (0.5, 0.45, max(0.1, topFoot - 0.04)), x: side, .wood))
        } else {
            let feet = (mean("toes.r") + mean("toes.l")) * 0.5
            add(Plan.box(V(feet.x, feet.y, 0.25) + forward * 0.55, (0.6, 0.45, 0.5), x: side, .wood))
        }
    }

    mutating func step() {
        let feet = (mean("toes.r") + mean("toes.l")) * 0.5
        add(Plan.box(V(feet.x, feet.y, 0.06) - forward * 0.02, (0.6, 0.18, 0.12), x: side, .wood))
    }

    mutating func stabilityBall() {
        let pelvis = mean("pelvis"), thorax = mean("thorax")
        if guide.contacts.contains(where: { ["back", "hips"].contains($0) }) {
            let c = lowest("thorax") < lowest("pelvis") ? thorax : pelvis
            add(Plan.ball(V(c.x, c.y, 0.33), 0.33, .accent))
        } else {
            let feet = (mean("toes.r") + mean("toes.l")) * 0.5
            let z = max(0.33, min(lowest("toes.r"), lowest("toes.l")) - 0.3)
            add(Plan.ball(V(feet.x, feet.y, z), 0.33, .accent))
        }
    }

    mutating func mat() {
        let pts = ["pelvis", "neck", "toes.r", "toes.l", "hand.r", "hand.l"].map { mean($0) }
        let c = pts.reduce(V(0, 0, 0), +) * (1 / Double(pts.count))
        let along = (mean("neck") - mean("pelvis")).flat
        let x = along.length > 0.2 ? along.unit.cross(V(0, 0, 1)) : side
        add(Plan.box(V(c.x, c.y, 0.004), (0.66, 1.85, 0.008), x: x, .accent))
    }

    mutating func foamRoller() {
        // Under the lowest part of the body.
        let parts = ["thorax", "pelvis", "femur.r", "shin.r"]
        let f = samples[0]
        let low = parts.min { (f.heads[$0]?[2] ?? 9) < (f.heads[$1]?[2] ?? 9) } ?? "pelvis"
        let p = V(f.heads[low]!)
        let axis = (f.heads["femur.l"].map(V.init) ?? p + side) - (f.heads["femur.r"].map(V.init) ?? p)
        add(Plan.disc(V(p.x, p.y, 0.075), axis: axis.flat.length > 0.05 ? axis.flat : side, radius: 0.075, thickness: 0.9, .accent))
    }

    // MARK: Bars

    mutating func pullUpBar() {
        let z = samples.compactMap { PropPlan.grip($0, "r")?.point.z }.max() ?? 2.3
        let h = hands
        let a = V(h.x, h.y, z) - side * 0.75, b = V(h.x, h.y, z) + side * 0.75
        add(Plan.rod(a, b, 0.016, .metal))
        for e in [a, b] { add(Plan.rod(V(e.x, e.y, 0), e + V(0, 0, 0.02), 0.03, .metal)) }
    }

    mutating func dipBars() {
        for s in ["r", "l"] {
            guard let g = gripMean(s) else { continue }
            let z = samples.compactMap { PropPlan.grip($0, s)?.point.z }.min() ?? g.z
            let o = side * (s == "r" ? -0.03 : 0.03)
            let a = V(g.x, g.y, z - 0.02) + o - forward * 0.25, b = V(g.x, g.y, z - 0.02) + o + forward * 0.35
            add(Plan.rod(a, b, 0.022, .metal))
            for e in [a, b] { add(Plan.rod(V(e.x, e.y, 0), e, 0.025, .metal)) }
        }
    }

    mutating func parallettes() {
        for s in ["r", "l"] {
            guard let g = gripMean(s) else { continue }
            let a = V(g.x, g.y, 0.08) - forward * 0.15, b = V(g.x, g.y, 0.08) + forward * 0.15
            add(Plan.rod(a, b, 0.018, .metal))
            for e in [a, b] { add(Plan.rod(V(e.x, e.y, 0), e, 0.018, .metal)) }
        }
    }

    /// Rings or suspension straps hanging from a point overhead.
    mutating func overheadStraps(_ kind: PropKind) {
        let h = hands
        let z = max(2.4, highest("hand.r") + 0.4)
        let over = kind == .rings ? V(h.x, h.y, z) : V(h.x, h.y, z) + forward * 0.6
        cableTop = [over - side * 0.25, over + side * 0.25]
        add(Plan.rod(over - side * 0.5, over + side * 0.5, 0.03, .metal))
    }

    // MARK: Cardio machines

    mutating func treadmill() {
        let feet = (mean("toes.r") + mean("toes.l") + mean("foot.r") + mean("foot.l")) * 0.25
        let c = V(feet.x, feet.y, 0.09) + forward * 0.1
        add(Plan.box(c, (0.75, 1.8, 0.18), x: side, .dark))
        add(Plan.box(V(c.x, c.y, 0.181), (0.5, 1.6, 0.004), x: side, .rubber))
        let front = c + forward * 0.85
        for s in [-1.0, 1.0] { add(Plan.rod(front + side * (s * 0.36), front + side * (s * 0.36) + V(0, 0, 1.15), 0.025, .metal)) }
        add(Plan.box(front + V(0, 0, 1.2), (0.75, 0.12, 0.3), x: side, z: V(0, 0, 1) - forward * 0.4, .dark))
    }

    mutating func bike() {
        let pelvis = mean("pelvis")
        let saddle = V(pelvis.x, pelvis.y, lowest("pelvis") - 0.1)
        let crank = (mean("foot.r") + mean("foot.l")) * 0.5
        let bars = hands
        add(Plan.box(saddle - V(0, 0, 0.03), (0.16, 0.26, 0.06), x: side, .dark))
        add(Plan.rod(saddle - V(0, 0, 0.05), crank, 0.03, .metal))
        add(Plan.disc(crank, axis: side, radius: 0.1, thickness: 0.03, .metal))
        add(Plan.rod(crank, bars - V(0, 0, 0.05), 0.035, .metal))
        add(Plan.rod(bars - side * 0.22, bars + side * 0.22, 0.016, .dark))
        let wheel = V(crank.x, crank.y, 0.28) + forward * 0.35
        add(Plan.disc(wheel, axis: side, radius: 0.24, thickness: 0.06, .dark))
        add(Plan.box(V(crank.x, crank.y, 0.03) + forward * 0.1, (0.55, 1.1, 0.06), x: side, .metal))
    }

    mutating func rower() {
        let pelvis = mean("pelvis")
        let seatTop = lowest("pelvis") - 0.1
        let feet = (mean("foot.r") + mean("foot.l")) * 0.5
        let railStart = V(pelvis.x, pelvis.y, 0) - forward * 0.8
        let railEnd = V(feet.x, feet.y, 0) + forward * 0.5
        add(Plan.rod(V(railStart.x, railStart.y, seatTop - 0.08), V(railEnd.x, railEnd.y, seatTop - 0.08), 0.04, .metal))
        add(Plan.box(V(pelvis.x, pelvis.y, seatTop - 0.025), (0.3, 0.3, 0.05), x: side, .dark))
        add(Plan.box(feet + forward * 0.02 - V(0, 0, 0.02), (0.35, 0.05, 0.25), x: side, z: V(0, 0, 1) - forward * 0.6, .dark))
        let wheel = V(railEnd.x, railEnd.y, 0.5)
        add(Plan.disc(wheel, axis: side, radius: 0.27, thickness: 0.16, .dark))
        add(Plan.rod(V(railStart.x, railStart.y, 0), V(railStart.x, railStart.y, seatTop - 0.08), 0.03, .metal))
        add(Plan.rod(V(railEnd.x, railEnd.y, 0), V(railEnd.x, railEnd.y, 0.3), 0.04, .metal))
        cableTop = [wheel + V(0, 0, 0.1) - forward * 0.25]
    }

    mutating func elliptical() {
        let feet = (mean("foot.r") + mean("foot.l")) * 0.5
        add(Plan.box(V(feet.x, feet.y, 0.05), (0.6, 1.6, 0.1), x: side, .dark))
        let front = V(feet.x, feet.y, 0) + forward * 0.7
        add(Plan.rod(front, front + V(0, 0, 1.3), 0.04, .metal))
        add(Plan.disc(front + V(0, 0, 0.35), axis: side, radius: 0.22, thickness: 0.15, .dark))
    }

    mutating func skiErg() {
        let h = hands
        let base = V(h.x, h.y, 0) + forward * 0.6
        add(Plan.box(V(base.x, base.y, 1.1), (0.35, 0.25, 2.2), x: side, .dark))
        add(Plan.box(V(base.x, base.y, 0.02) - forward * 0.3, (0.7, 0.9, 0.04), x: side, .metal))
        cableTop = [V(base.x, base.y, 2.1) - side * 0.15 - forward * 0.13, V(base.x, base.y, 2.1) + side * 0.15 - forward * 0.13]
    }

    mutating func stairs() {
        let feet = (mean("toes.r") + mean("toes.l")) * 0.5
        for k in 0..<4 {
            let c = V(feet.x, feet.y, 0) + forward * (Double(k) * 0.26 - 0.1)
            let top = 0.2 + Double(k) * 0.18
            add(Plan.box(V(c.x, c.y, top / 2), (0.8, 0.26, top), x: side, .dark))
        }
        let front = V(feet.x, feet.y, 0) + forward * 1.1
        for s in [-1.0, 1.0] { add(Plan.rod(front + side * (s * 0.4), front + side * (s * 0.4) + V(0, 0, 1.8), 0.025, .metal)) }
    }

    mutating func sled() {
        let h = hands
        let c = V(h.x, h.y, 0) + forward * 0.25
        add(Plan.box(V(c.x, c.y, 0.08) + forward * 0.3, (0.7, 0.9, 0.06), x: side, .metal))
        for s in [-1.0, 1.0] { add(Plan.rod(V(c.x, c.y, 0.1) + side * (s * 0.25), V(h.x, h.y, h.z) + side * (s * 0.25), 0.025, .metal)) }
        add(Plan.disc(V(c.x, c.y, 0.2) + forward * 0.3, axis: V(0, 0, 1), radius: 0.22, thickness: 0.15, .plate))
    }

    mutating func reformer() {
        let pelvis = mean("pelvis"), neck = mean("neck")
        let along = (neck - pelvis).flat.length > 0.2 ? (neck - pelvis).flat.unit : forward * -1
        let feet = (mean("toes.r") + mean("toes.l")) * 0.5
        let c = V(pelvis.x, pelvis.y, 0) + along * 0.2
        add(Plan.box(V(c.x, c.y, 0.15), (0.7, 2.3, 0.3), x: along.cross(V(0, 0, 1)), .wood))
        add(Plan.box(V(c.x, c.y, 0.33), (0.6, 0.9, 0.06), x: along.cross(V(0, 0, 1)), .pad))
        add(Plan.rod(V(feet.x, feet.y, feet.z) - along.cross(V(0, 0, 1)) * 0.3 - along * 0.05,
                     V(feet.x, feet.y, feet.z) + along.cross(V(0, 0, 1)) * 0.3 - along * 0.05, 0.02, .metal))
    }

    mutating func climber() {
        let h = hands
        let base = V(h.x, h.y, 0) + forward * 0.35
        add(Plan.box(V(base.x, base.y, 1.2), (0.12, 0.12, 2.4), x: side, .metal))
        add(Plan.box(V(base.x, base.y, 0.02) - forward * 0.2, (0.7, 0.7, 0.04), x: side, .metal))
    }
}

extension Body3D.V {
    /// Flattened onto the floor.
    var flat: Body3D.V { Body3D.V(x, y, 0) }
}

/// How the camera frames an exercise: the middle of the body and its equipment over the
/// loop, a radius that holds them, and the angle the family is best seen from.
public struct BodyFraming: Sendable {
    /// Blender axes.
    public var center: [Double]
    public var radius: Double
    /// Turn about the vertical, in the app's Y-up axes: 0 looks at the body's front.
    public var yaw: Double
    /// Up from level, radians.
    public var pitch: Double
    /// The first of the family's views: "side", "front", "angle" or "back".
    public var view: String

    /// `margin` is how far past the body the equipment may stretch the view; `tight` measures
    /// each piece as it lies rather than by its longest side.
    init(guide: HowToGuide, samples: [BodyFrame], pieces: [PropPiece], forward f: Body3D.V, margin: Double = 0.35,
         tight: Bool = false) {
        var lo = [Double](repeating: .infinity, count: 3), hi = [Double](repeating: -.infinity, count: 3)
        func take(_ p: [Double], pad: Double) {
            for i in 0..<3 { lo[i] = min(lo[i], p[i] - pad); hi[i] = max(hi[i], p[i] + pad) }
        }
        // The skull reaches well past the joint at its base.
        for frame in samples { for (bone, h) in frame.heads { take(h, pad: tight && bone == "head" ? 0.24 : 0.14) } }
        // Equipment widens the view a little; a tall cable tower must not shrink the body.
        let bodyLo = lo, bodyHi = hi
        for piece in pieces {
            guard tight else { take(piece.center, pad: (piece.size.max() ?? 0) / 2); continue }
            let q = piece.rotation
            let rows = [[1 - 2 * (q.y * q.y + q.z * q.z), 2 * (q.x * q.y - q.w * q.z), 2 * (q.x * q.z + q.w * q.y)],
                        [2 * (q.x * q.y + q.w * q.z), 1 - 2 * (q.x * q.x + q.z * q.z), 2 * (q.y * q.z - q.w * q.x)],
                        [2 * (q.x * q.z - q.w * q.y), 2 * (q.y * q.z + q.w * q.x), 1 - 2 * (q.x * q.x + q.y * q.y)]]
            for i in 0..<3 {
                let half = (0..<3).reduce(0.0) { $0 + abs(rows[i][$1]) * piece.size[$1] / 2 }
                lo[i] = min(lo[i], piece.center[i] - half)
                hi[i] = max(hi[i], piece.center[i] + half)
            }
        }
        for i in 0..<3 { lo[i] = max(lo[i], bodyLo[i] - margin); hi[i] = min(hi[i], bodyHi[i] + margin) }
        lo[2] = max(lo[2], -0.02) - 0.12  // room for the floor disc seen from above
        center = (0..<3).map { (lo[$0] + hi[$0]) / 2 }
        let span = (0..<3).map { hi[$0] - lo[$0] }
        radius = max(0.45, (span[0] * span[0] + span[1] * span[1] + span[2] * span[2]).squareRoot() * (tight ? 0.46 : 0.42))
        view = guide.views.first ?? "side"
        // The app's axes are Blender's turned upright: (x, y, z) -> (x, z, -y).
        let front = atan2(f.x, -f.y)
        switch view {
        // Turned toward the viewer so the face and working side both show.
        case "front": yaw = front - 0.3
        case "angle": yaw = front - 0.6
        case "back": yaw = front + .pi + 0.5
        default: yaw = front - 0.95
        }
        let lying = samples.first.map { frame -> Bool in
            guard let p = frame.heads["pelvis"], let n = frame.heads["neck"] else { return false }
            return abs(n[2] - p[2]) < 0.25
        } ?? false
        pitch = lying ? 0.38 : 0.12
    }
}

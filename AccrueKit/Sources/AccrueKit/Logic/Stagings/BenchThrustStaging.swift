import Foundation

/// A barbell hip thrust: the upper back on the edge of a bench set across behind the body,
/// the feet flat, the bar in the crease of the hips with a hand on it each side. The trunk
/// tips about the bench's edge as the hips drop and drive up. A barbell glute bridge is the
/// same with the shoulders on the floor.
struct BenchThrustStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan
    typealias Skin = BenchStagings.Skin

    static let barRadius = 0.014
    /// The foam sleeve round the bar where it lies on the hips.
    static let sleeve = 0.04
    static let halfGrip = 0.31
    /// How far the back presses into what it lies on.
    static let sink = 0.015
    static let benchDepth = 0.3, benchWidth = 1.2, padThick = 0.07

    let body: Body3D
    let grips: [String: HandGrip]
    let travel: BenchStagings.Travel
    /// The hip angle the keyframes mean, to see hips that stop short of the top.
    let hipLine: BenchStagings.Expected
    /// The height of what the back rests on: the bench's top, or 0 for the floor.
    let top: Double
    /// The point of the back (its height on the standing body) that stays on the edge.
    let rests: Double
    /// Where that point stays.
    let edge: V
    /// The floor as something to lay the head on, for a bridge.
    let ground: BenchStagings.Recline?
    private(set) var ankles: [String: V] = [:]
    let kinds: [PropKind]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard guide.familyID == "hip-thrust-bridge", guide.equipment == "barbell", let first = guide.keyframes.first?.pose,
              !has("band", "staggered", "one leg", "single", "ball", "kas", "lifting") else { return nil }
        let onFloor: Bool
        switch guide.subtypeID {
        case nil where has("thrust"): onFloor = false
        case "glute-bridge" where !has("bench"): onFloor = true
        default: return nil
        }
        guard let r = body.grip("r", radius: Self.barRadius, square: 0.5),
              let l = body.grip("l", radius: Self.barRadius, square: 0.5) else { return nil }
        self.body = body
        grips = ["r": r, "l": l]
        travel = BenchStagings.Travel("trunk", guide.keyframes)
        hipLine = BenchStagings.Expected("hipFlex", guide.keyframes, along: travel)
        top = onFloor ? 0 : 0.36
        // On a bench, just under the shoulder blades; on the floor, the blades themselves.
        rests = onFloor ? 1.33 : 1.25
        edge = V(0, 0, top)
        ground = onFloor ? BenchStagings.Recline(body, lying: first, onFloor: true) : nil
        kinds = onFloor ? [.barbell] : [.barbell, .bench]

        var p: [PropPiece] = []
        if !onFloor {
            let depth = Self.benchDepth, width = Self.benchWidth, thick = Self.padThick
            p.append(Plan.box(V(0, depth / 2, top - thick / 2), (width, depth, thick), .pad))
            p.append(Plan.box(V(0, depth / 2, top - thick - 0.02), (width - 0.1, 0.07, 0.04), .metal))
            for x in [-(width / 2 - 0.12), width / 2 - 0.12] {
                p.append(Plan.box(V(x, depth / 2, (top - thick) / 2), (0.06, 0.06, top - thick), .metal))
                p.append(Plan.box(V(x, depth / 2, 0.02), (0.06, depth + 0.16, 0.04), .metal))
            }
        }
        fixed = p

        // The feet go where the shins stand upright at the top of the movement.
        let high = guide.keyframes.max(by: { travel($0.pose) < travel($1.pose) })?.pose ?? first
        let (_, h) = lie(high)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hip = h["femur.\(s)"], let rHip = body.head["femur.\(s)"], let rKnee = body.head["shin.\(s)"],
                  let rAnkle = body.head["foot.\(s)"] else { continue }
            let thigh = (rKnee - rHip).length, knee = body.ankleHeight + (rAnkle - rKnee).length
            let wide = 0.16, aside = wide - abs(hip.x), rise = knee - hip.z
            let forward = max(0.04, thigh * thigh - rise * rise - aside * aside).squareRoot()
            ankles[s] = V(-m * wide, hip.y - forward, body.ankleHeight)
        }
    }

    /// The posed trunk with its resting point on the edge, before the legs and arms are fitted.
    func lie(_ pose: JointPose) -> (g: [String: M], h: [String: V]) {
        var g = body.rotations(pose)
        // Hips that stay more bent than the keyframes have them hang lower.
        let sag = max(0, min(30, hipLine.excess(pose, at: travel(pose)) * 0.6))
        if sag > 0 {
            let turn = M.x(sag)
            for (k, m) in g { g[k] = turn * m }
        }
        var h = body.place(g, root: V(0, 0, 0))
        let behind = Skin.back.min { abs($0.1 - rests) < abs($1.1 - rests) }?.0 ?? 0.14
        let skin = body.benchSkin("thorax", back: behind, up: rests, g, h) ?? V(0, 0, 0)
        var root = edge - V(0, 0, Self.sink) - skin
        h = body.place(g, root: root)
        if let ground {
            // On the floor the back rolls onto the shoulders as the hips rise: whatever part of
            // it is lowest is the part that bears on the floor.
            let low = Skin.back.compactMap { body.benchSkin("thorax", back: $0.0, up: $0.1, g, h)?.z }.min() ?? -Self.sink
            root.z -= low + Self.sink
            h = body.place(g, root: root)
            ground.restHead(&g, &h, most: 45)
            // An arch too steep for the neck to follow carries the shoulders up with the head.
            let skull = Skin.skull.compactMap { body.benchSkin("head", back: $0.0, up: $0.1, g, h)?.z }.min() ?? 0
            if skull < 0 {
                root.z -= skull
                h = body.place(g, root: root)
            }
        }
        return (g, h)
    }

    /// The body for one pose, and the middle of the bar.
    func solve(_ pose: JointPose) -> (frame: BodyFrame, bar: V) {
        var (g, h) = lie(pose)
        let root = h["pelvis"] ?? V(0, 0, 0)
        for s in ["r", "l"] {
            guard let ankle = ankles[s] else { continue }
            body.plant(s, ankle: ankle, foot: .identity, pole: V(0, -0.3, 1), &g, h)
        }
        // The bar lies in the crease of the hips, on its sleeve.
        var bar = root
        if let rest = body.head["pelvis"], let turn = g["pelvis"] {
            bar = root + turn * (V(0, -(Skin.front(1.1) - 0.015 + Self.sleeve + 0.004), 0.93) - rest)
            bar.x = 0
        }
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s] else { continue }
            body.hold(s, grip, at: bar + V(-m * Self.halfGrip, 0, 0), across: V(-m, 0, 0), pole: V(-m, 0.3, 0.2), &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), bar)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let (frame, bar) = solve(pose)
        var p = BenchStagings.barbell(bar)
        p.append(Plan.rod(bar - V(0.2, 0, 0), bar + V(0.2, 0, 0), Self.sleeve, .dark))
        return (frame, p)
    }
}

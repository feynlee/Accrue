import Foundation

// MARK: - Hanging from a bar

/// The body hanging from a fixed bar by both hands, as PullUpStaging hangs it, for the other
/// grips: palms toward the face (a chin-up), palms facing each other on two handles, wide or
/// close hands. It pulls up until the chin is over the bar when the keyframes bend the elbows,
/// and just hangs with long arms when they do not (a dead hang, a hanging leg raise).
struct BarHangStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// Palms away from the face, toward it, or facing each other.
    enum Grip: Sendable { case over, under, neutral }

    static let barRadius = PullUpStaging.barRadius
    /// How far the toes of the hanging body stay off the floor, at the least.
    static let toesClear = 0.1
    /// How far in front of the bar a hand holds a handle of the neutral grip.
    static let handleOut = 0.21

    let body: Body3D
    let progress: PullProgress
    let grips: [String: HandGrip]
    let grip: Grip
    let halfGrip: Double
    let loaded: Bool
    let kinds: [PropKind] = [.pullUpBar]
    /// The pull-up's bar, or higher when this body would otherwise hang with its toes on the floor.
    private(set) var barHeight = PullUpStaging.barHeight
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D, grip: Grip, halfGrip: Double) {
        // A wide hand lies squarer across a straight bar than a narrow one.
        let square = grip == .neutral ? 0.0 : grip == .under ? 0.3 : halfGrip > 0.15 ? 0.6 : 0.3
        guard let r = body.grip("r", radius: Self.barRadius, square: square),
              let l = body.grip("l", radius: Self.barRadius, square: square) else { return nil }
        self.body = body
        self.grip = grip
        self.halfGrip = halfGrip
        progress = PullProgress(guide.keyframes)
        grips = ["r": r, "l": l]
        loaded = guide.equipment == "weighted" || guide.exerciseName.contains("weighted")
        // Hang the body from the pull-up's bar first; if its toes reach the floor, the bar goes up.
        if let first = guide.keyframes.first?.pose {
            let hung = frame(first).body
            let toes = ["r", "l"].compactMap { s -> Double? in
                guard let root = hung.heads["toes.\(s)"], let turn = hung.rotations["toes.\(s)"],
                      let a = body.head["toes.\(s)"], let b = body.tail["toes.\(s)"] else { return nil }
                return root[2] + (M(turn) * (b - a)).z
            }
            if let low = toes.min(), low < Self.toesClear { barHeight += Self.toesClear - low }
        }
        fixed = pieces()
    }

    /// The same bar and uprights as the pull-up's, with handles for the neutral grip.
    func pieces() -> [PropPiece] {
        let z = barHeight
        var pieces = [Plan.rod(V(-0.66, 0, z), V(0.66, 0, z), Self.barRadius, .metal)]
        for x in [-0.62, 0.62] {
            pieces.append(Plan.rod(V(x, 0, 0), V(x, 0, z + 0.04), 0.03, .metal))
            pieces.append(Plan.box(V(x, 0, 0.02), (0.09, 1.0, 0.04), .metal))
        }
        if grip == .neutral {
            // Two handles out from the bar toward the front, with rubber where the hands go.
            for x in [-halfGrip, halfGrip] {
                let tip = V(x, -Self.handleOut - 0.1, z)
                pieces.append(Plan.rod(V(x, 0, z), tip, Self.barRadius - 0.003, .metal))
                pieces.append(Plan.rod(V(x, -Self.handleOut + 0.08, z), tip, Self.barRadius, .dark))
                pieces.append(Plan.ball(tip, Self.barRadius, .dark))
            }
        }
        return pieces
    }

    /// Where the hand of side `s` holds: the bar's (or the handle's) centre under the palm.
    func hold(_ s: String) -> V {
        V(s == "r" ? -halfGrip : halfGrip, grip == .neutral ? -Self.handleOut : 0, barHeight)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(pose)
        let u = progress(pose)
        let rel = body.place(g, root: V(0, 0, 0))
        let thorax = g["thorax"] ?? .identity
        let z0 = barHeight, y0 = hold("r").y
        let shoulders = ["r", "l"].compactMap { rel["humerus.\($0)"] }
        let mid = shoulders.reduce(V(0, 0, 0), +) * (1 / Double(max(1, shoulders.count)))
        let neck = rel["neck"] ?? mid

        // The body's weight hangs under the hands (the arms are a tenth of it, halfway up).
        let weight = body.balance(g, rel)
        var y = y0 - (0.9 * weight.y + 0.05 * mid.y) / 0.95

        /// The height of the hips that leaves each elbow bent by `bend`.
        func hips(bend: Double, y: Double) -> Double {
            var sum = 0.0, n = 0.0
            for s in ["r", "l"] {
                guard let shoulder = rel["humerus.\(s)"], let grip = grips[s] else { continue }
                let reach = body.reach(s, grip, bend: bend)
                let dx = hold(s).x - shoulder.x, dy = y0 - (shoulder.y + y)
                sum += z0 - max(0, reach * reach - dx * dx - dy * dy).squareRoot() - shoulder.z
                n += 1
            }
            return n > 0 ? sum / n : 0
        }
        // At the top the chin is over the bar, as far as the arms can fold.
        let headTurn = g["head"] ?? thorax
        let chin = neck + headTurn * V(0, -0.114, 0.03)
        let want = z0 + Self.barRadius + 0.014 - chin.z
        let deepest = PullUpStaging.deepest
        let hang = hips(bend: 6, y: y)
        var z = hang + (min(want, hips(bend: deepest, y: y)) - hang) * u

        if grip != .neutral {
            // The face passes behind the bar on the way up.
            let clear = Self.barRadius + 0.012
            for (forward, up) in PullUpStaging.face {
                let p = neck + headTurn * V(0, -forward, up)
                let dz = p.z + z - z0
                guard abs(dz) < clear else { continue }
                y = max(y, -p.y + (clear * clear - dz * dz).squareRoot())
            }
            // Arms that cannot fold far enough let the body lean back a touch instead.
            var lean = 0.0
            while lean < 0.05, hips(bend: deepest, y: y + lean) < want { lean += 0.005 }
            y += lean * u * u
            z = hang + (min(want, hips(bend: deepest, y: y)) - hang) * u
        }

        let root = V(0, y, z)
        var h = body.place(g, root: root)
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let hand = grips[s] else { continue }
            // Which way the bar runs under the hand from thumb to little finger, and where the
            // elbow goes: out to the side for palms away, in front for palms toward the face.
            let across: V, pole: V
            switch grip {
            case .over: (across, pole) = (V(-m, 0, 0), thorax * V(-m * 0.5, -0.15, -1))
            case .under: (across, pole) = (V(m, 0, 0), thorax * V(-m * 0.12, -0.7, -1))
            case .neutral: (across, pole) = (V(0, -1, 0), thorax * V(-m * 0.2, -0.5, -1))
            }
            body.hold(s, hand, at: hold(s), across: across, pole: pole, &g, h)
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), loaded ? BodyweightStagings.beltPlate(g, h) : [])
    }
}

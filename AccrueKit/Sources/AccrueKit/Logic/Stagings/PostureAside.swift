import Foundation

/// An exercise whose plain picture stands the body through its bench or its ball, and which
/// nothing stages properly: the body keeps the family's pose and its hands keep what they
/// hold, and the bench or ball is taken out of the body. One the name asks for stands just
/// behind or beside; one that only the family's habit put there is left out.
struct PostureAsideStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    static let strays: [PropKind] = [.bench, .stabilityBall]

    let plan: PropPlan
    let kinds: [PropKind]
    let fixed: [PropPiece]
    /// The loop's own poses, to tell which moment of it a pose belongs to.
    let loop: [(t: Double, pose: JointPose)]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        let quick = PropPlan.kinds(for: guide)
        guard quick.contains(where: Self.strays.contains) else { return nil }
        let plan = PropPlan(guide: guide, body: body, plain: true)
        guard let hands = plan.hands, plan.lift == 0, plan.kinds.contains(where: Self.strays.contains) else { return nil }
        // The same moments the plain picture places its equipment from.
        let frames = (0...12).map { i -> BodyFrame in
            let t = Double(i) / 12
            return hands.frame(Figure.interpolate(guide.keyframes, at: t), at: t).frame
        }
        // Only a body that stands on the floor all loop long, with the bench or ball in it.
        let stands = frames.allSatisfy { f in
            guard f.floor != nil, let pelvis = f.heads["pelvis"] else { return false }
            let feet = ["foot.r", "foot.l"].compactMap { f.heads[$0]?[2] }.min() ?? 1
            return pelvis[2] > 0.7 && pelvis[2] < 1.15 && feet < 0.5
        }
        guard stands, Self.through(frames, plan.fixed) else { return nil }
        self.plan = plan
        let kept = plan.kinds.filter { !Self.strays.contains($0) }
        var builder = Builder(kinds: kept, guide: guide, samples: frames)
        builder.buildFixed()
        var pieces = builder.pieces
        var kinds = kept

        let heels = frames.flatMap { f in ["foot.r", "foot.l"].compactMap { f.heads[$0]?[1] } }.max() ?? 0
        if plan.kinds.contains(.stabilityBall) {
            let r = PostureStaging.ballRadius
            if has("wall") {
                // The ball rolls between the back and a wall.
                let back = frames.compactMap { $0.heads["lumbar"] }.map { V($0) }
                let mid = back.reduce(V(0, 0, 0), +) * (1 / Double(max(1, back.count)))
                let y = (back.map(\.y).max() ?? 0) + 0.115 + r
                pieces.append(Plan.ball(V(0, y, mid.z), r, .accent))
                pieces.append(Plan.box(V(0, y + r + 0.03, 1.1), (1.6, 0.06, 2.2), .metal))
            } else {
                pieces.append(Plan.ball(V(0.8, heels + 0.1, r), r, .accent))
            }
            kinds.append(.stabilityBall)
        } else if !kept.contains(.box), has("bench", "seated", "lying", "incline", "prone", "supine", "chair") {
            // A bench just behind, as if stood up from.
            let near = heels + 0.3
            pieces += PostureStaging.flatBench(from: near, to: near + 1.1, top: 0.43, posts: [near + 0.14, near + 0.96])
            kinds.append(.bench)
        }
        self.kinds = kinds
        fixed = pieces
        loop = (0...48).map { i in
            let t = Double(i) / 48
            return (t, Figure.interpolate(guide.keyframes, at: t))
        }
    }

    /// Whether a pad or a ball among `pieces` has part of the legs or the trunk inside it at
    /// any of the `frames`.
    static func through(_ frames: [BodyFrame], _ pieces: [PropPiece]) -> Bool {
        let pads = pieces.filter { $0.shape == .box && $0.finish == .pad || $0.shape == .sphere && $0.finish == .accent }
        guard !pads.isEmpty else { return false }
        for f in frames {
            func at(_ b: String) -> V? { f.heads[b].map { V($0) } }
            var points: [V] = []
            for s in ["r", "l"] {
                guard let hip = at("femur.\(s)"), let knee = at("shin.\(s)"), let ankle = at("foot.\(s)") else { continue }
                points += (1...4).map { mix(hip, knee, Double($0) / 5) } + (0...4).map { mix(knee, ankle, Double($0) / 5) }
            }
            if let p = at("pelvis"), let l = at("lumbar"), let t = at("thorax"), let n = at("neck") {
                points += [p, l, t, mix(t, n, 0.5)]
            }
            for piece in pads {
                let c = V(piece.center)
                for p in points {
                    if piece.shape == .box {
                        let d = M(piece.rotation).t * (p - c)
                        if abs(d.x) < piece.size[0] / 2, abs(d.y) < piece.size[1] / 2, abs(d.z) < piece.size[2] / 2 { return true }
                    } else if (p - c).length < piece.size[0] / 2 - 0.02 {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The moment of the loop whose pose is nearest to `pose`.
    func moment(_ pose: JointPose) -> Double {
        var best = 0.0, least = Double.infinity
        for step in loop {
            var d = 0.0
            for key in Set(pose.angles.keys).union(step.pose.angles.keys) {
                let gap = (pose.angles[key] ?? 0) - (step.pose.angles[key] ?? 0)
                d += gap * gap
            }
            if d < least {
                least = d
                best = step.t
            }
        }
        return best
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        guard let hands = plan.hands else { return (plan.frame(at: 0).body, []) }
        let (frame, held) = hands.frame(pose, at: moment(pose))
        return (frame, plan.moving(frame, held))
    }
}

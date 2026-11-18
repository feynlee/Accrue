import Foundation

extension CableKit {
    /// What the body rests on while it works a cable: its own two feet, or a bench, a ball or
    /// its knees. On a support the legs stay as it has them, and only the trunk and the arms
    /// do what the keyframes say.
    struct Footing: Sendable {
        let stance: Stance?
        let posture: PostureStaging?

        private init(stance: Stance?, posture: PostureStaging?) {
            self.stance = stance
            self.posture = posture
        }

        /// Standing on both feet, the left one `stagger` ahead of the right.
        init(_ body: Body3D, first pose: JointPose, stagger: Double = 0) {
            self.init(stance: Stance(body, first: pose, stagger: stagger), posture: nil)
        }

        /// Sitting, kneeling or lying as `support` says; standing when it says nothing.
        init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support?) {
            guard let first = guide.keyframes.first?.pose else { return nil }
            guard let support else {
                self.init(body, first: first)
                return
            }
            guard let posture = PostureStaging(guide, body, support) else { return nil }
            self.init(stance: nil, posture: posture)
        }

        var support: PostureStaging.Support? { posture?.support }

        /// Sitting with the thighs level in front of the hips.
        var sits: Bool {
            switch support {
            case .seat, .ball: return true
            default: return false
            }
        }

        /// Lying back on a bench.
        var lies: Bool {
            if case .supine = support { return true }
            return false
        }

        /// The bench or the ball, which never moves.
        var pieces: [PropPiece] { posture?.fixed ?? [] }

        /// What the picture holds: the cable, and whatever is sat on.
        var kinds: [PropKind] {
            var kinds: [PropKind] = [.cable]
            for kind in posture?.kinds ?? [] where !kinds.contains(kind) { kinds.append(kind) }
            return kinds
        }

        /// The posed body on its feet or its support, and where its pelvis is.
        func settle(_ body: Body3D, _ pose: JointPose) -> (g: [String: M], h: [String: V], root: V) {
            if let posture { return posture.settle(pose) }
            var g = body.rotations(pose)
            guard let stance else { return (g, body.place(g, root: V(0, 0, 0.9)), V(0, 0, 0.9)) }
            let (root, h) = stance.stand(body, &g)
            return (g, h, root)
        }
    }

    /// How high the skin of a body lying on its back reaches at `y` along it: the top of the
    /// thighs, the belly, the chest and the face. `front` turned on its back.
    static func top(_ h: [String: V], at y: Double) -> Double {
        let parts: [(String, String, Double)] = [
            ("femur.r", "shin.r", 0.1), ("femur.l", "shin.l", 0.1), ("pelvis", "lumbar", 0.13),
            ("lumbar", "thorax", 0.14), ("thorax", "neck", 0.17), ("neck", "head", 0.15),
        ]
        var top = -Double.infinity
        for (a, b, thick) in parts {
            guard let p = h[a], let q = h[b], abs(q.y - p.y) > 1e-6 else { continue }
            let t = (y - p.y) / (q.y - p.y)
            guard t >= -0.05, t <= 1.05 else { continue }
            top = max(top, p.z + (q.z - p.z) * min(1, max(0, t)) + thick)
        }
        if let head = h["head"], y > head.y, y < head.y + 0.22 { top = max(top, head.z + 0.15) }
        return top
    }

    /// The pose with the left arm taken out of the work, for an exercise done with the right
    /// arm alone: it hangs at the side, straight down however the trunk leans.
    static func oneArmed(_ pose: JointPose) -> JointPose {
        var pose = pose
        let lean = min(60, max(-20, pose.angles["trunk"] ?? 0))
        pose.angles["shoulderFlexL"] = lean
        pose.angles["shoulderAbdL"] = 7
        pose.angles["shoulderRotL"] = 0
        pose.angles["elbowFlexL"] = 10
        pose.angles["forearmL"] = 0
        pose.angles["wristExtL"] = 0
        return pose
    }
}

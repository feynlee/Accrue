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

        /// Standing on both feet.
        init(_ body: Body3D, first pose: JointPose) {
            self.init(stance: Stance(body, first: pose), posture: nil)
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
}

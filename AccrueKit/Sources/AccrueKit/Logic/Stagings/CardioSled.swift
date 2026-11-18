import Foundation

/// A weight sled, pushed by its posts or dragged by straps. The sled stays where it is and
/// the body walks on the spot against it, the floor implied: the hips stay over one place,
/// whichever foot is lowest is on the floor, and the hands stay closed on the posts or on the
/// strap handles.
struct CardioSledStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    enum Style: Sendable {
        /// Leaning in with straight arms on the two posts.
        case push
        /// Facing the sled and walking backward, a strap handle in each hand.
        case rearDrag
        /// Walking away from the sled, its straps clipped to a belt.
        case forwardDrag
    }

    static let postRadius = 0.021, handleRadius = 0.015

    let body: Body3D
    let style: Style
    let loop: CardioLoop
    let grips: [String: HandGrip]
    /// Where each hand holds: fixed on a post for a push, and for a drag where the keyframes'
    /// arms carry the handle.
    let holds: [String: V]
    /// Where the straps meet the sled.
    let eye: V
    let kinds: [PropKind] = [.sled]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard let style = Self.style(for: guide) else { return nil }
        let radius = style == .push ? Self.postRadius : Self.handleRadius
        guard let r = body.grip("r", radius: radius), let l = body.grip("l", radius: radius) else { return nil }
        self.body = body
        self.style = style
        grips = ["r": r, "l": l]
        let loop = CardioLoop(guide)
        self.loop = loop

        // Where the keyframes' arms hold the hands, on average through the loop.
        var mean = ["r": V(0, 0, 0), "l": V(0, 0, 0)]
        let count = 24
        for i in 0..<count {
            let g = body.rotations(Figure.smooth(loop.closed, at: Double(i) / Double(count)))
            let h = body.place(g, root: V(0, 0, body.cardioStand(g)))
            for s in ["r", "l"] {
                guard let wrist = h["hand.\(s)"], let hand = g["hand.\(s)"], let grip = grips[s] else { return nil }
                mean[s] = (mean[s] ?? V(0, 0, 0)) + (wrist + hand * grip.centre) * (1 / Double(count))
            }
        }
        guard let mr = mean["r"], let ml = mean["l"] else { return nil }
        let mid = (mr + ml) * 0.5
        let half = min(0.3, max(0.2, (ml.x - mr.x) / 2))
        holds = ["r": V(-half, mid.y, mid.z), "l": V(half, mid.y, mid.z)]
        // A dragged sled is drawn nearer than its straps would really hold it, so that it is
        // in the picture with the body.
        switch style {
        case .push:
            eye = V(0, mid.y - 0.45, 0.2)
            fixed = Self.sled(at: V(0, mid.y - 0.42, 0), half: 0.5, posts: (half, mid.y, mid.z))
        case .rearDrag:
            eye = V(0, mid.y - 0.8, 0.32)
            fixed = Self.sled(at: V(0, eye.y - 0.37, 0), half: 0.35, posts: nil, eye: eye)
        case .forwardDrag:
            eye = V(0, 1.1, 0.32)
            fixed = Self.sled(at: V(0, eye.y + 0.37, 0), half: 0.35, posts: nil, eye: eye)
        }
    }

    /// Which way of moving a sled the name describes, or nil for one this staging does not
    /// show honestly (a plate pushed along the floor, a rope hauled in hand over hand, a sled
    /// push mixed with another move).
    static func style(for guide: HowToGuide) -> Style? {
        guard guide.familyID == "sled-push-pull", guide.equipment == "machine" else { return nil }
        let words = CardioStagings.words(guide)
        let known: Set<String> = ["power", "sled", "push", "torque", "tank", "rear", "drag", "v", "2"]
        guard words.isSubset(of: known) else { return nil }
        switch guide.subtypeID {
        case nil: return words.contains("push") ? .push : nil
        case "rear-drag": return words.contains("drag") ? .rearDrag : nil
        case "forward-drag": return .forwardDrag
        default: return nil
        }
    }

    /// The sled, `half` its length each way from `c`: two runners, a deck, and plates on a peg.
    /// `posts` stands two posts at its near end, with a rubber grip at hand height.
    static func sled(at c: V, half: Double, posts: (half: Double, y: Double, z: Double)?, eye: V? = nil) -> [PropPiece] {
        var p: [PropPiece] = []
        for x in [-0.3, 0.3] {
            p.append(Plan.rod(V(x, c.y - half, 0.03), V(x, c.y + half, 0.03), 0.03, .metal))
            p.append(Plan.ball(V(x, c.y - half, 0.03), 0.03, .metal))
            p.append(Plan.ball(V(x, c.y + half, 0.03), 0.03, .metal))
        }
        if let eye {
            // The ring the straps are tied to, on a short post at the sled's near end.
            p.append(Plan.rod(V(0, eye.y, 0.06), eye, 0.02, .metal))
            p.append(Plan.ball(eye, 0.025, .metal))
        }
        p.append(Plan.box(V(0, c.y, 0.075), (0.66, 2 * half - 0.1, 0.03), .metal))
        p.append(Plan.rod(V(0, c.y, 0.09), V(0, c.y, 0.48), 0.025, .metal))
        for k in 0..<3 {
            p.append(Plan.disc(V(0, c.y, 0.115 + 0.05 * Double(k)), axis: V(0, 0, 1), radius: 0.225, thickness: 0.045, .plate))
        }
        if let posts {
            for x in [-posts.half, posts.half] {
                p.append(Plan.rod(V(x, posts.y, 0.06), V(x, posts.y, posts.z + 0.16), 0.019, .metal))
                p.append(Plan.rod(V(x, posts.y, posts.z - 0.09), V(x, posts.y, posts.z + 0.09), postRadius, .dark))
                // A brace from the post's foot to the deck.
                p.append(Plan.rod(V(x, posts.y, 0.06), V(x * 0.9, c.y + 0.3, 0.075), 0.019, .metal))
            }
        }
        return p
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var g = body.rotations(loop.clean(pose).pose)
        let root = V(0, 0, body.cardioStand(g))
        var h = body.place(g, root: root)
        let thorax = g["thorax"] ?? .identity
        var p: [PropPiece] = []
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let grip = grips[s], let at = holds[s] else { continue }
            switch style {
            case .push:
                body.hold(s, grip, at: at, across: V(0, 0, -1), pole: thorax * V(-m * 0.6, 0.4, -1), &g, h)
            case .rearDrag:
                // A handle across each fist, on a strap to the sled.
                body.hold(s, grip, at: at, across: V(-m, 0, 0), pole: thorax * V(-m * 0.4, 0.6, -1), &g, h)
                p.append(Plan.rod(at - V(0.065, 0, 0), at + V(0.065, 0, 0), Self.handleRadius, .dark))
                for end in [-0.065, 0.065] { p.append(Plan.rod(at + V(end, 0, 0), at + V(0, -0.14, -0.02), 0.005, .cable)) }
                p.append(Plan.rod(at + V(0, -0.14, -0.02), eye, 0.006, .cable))
            case .forwardDrag:
                // A strap from each side of the belt's clip, low on the back.
                guard let hips = h["pelvis"] else { continue }
                let clip = hips + (g["pelvis"] ?? .identity) * V(-m * 0.1, 0.125, 0.1)
                p.append(Plan.rod(clip, eye, 0.006, .cable))
                if s == "r" {
                    let back = hips + (g["pelvis"] ?? .identity) * V(0, 0.125, 0.1)
                    p.append(Plan.box(back, (0.26, 0.025, 0.06), x: (g["pelvis"] ?? .identity) * V(1, 0, 0),
                                      z: (g["pelvis"] ?? .identity) * V(0, 0, 1), .dark))
                }
            }
        }
        h = body.place(g, root: root)
        return (body.made(g, h, floor: 0), p)
    }
}

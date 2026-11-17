import Foundation

/// A stretch, yoga or pilates pose done on the floor with nothing but the body: the pose is
/// the keyframes' own, and the body is put down the way a body lies. Its lowest skin rests on
/// the floor (or the mat) through the whole loop, the part it rests on at the start does not
/// slide, and hands that belong on the floor lie flat on it, the body tipped a little if that
/// is what brings them down.
struct FloorRestStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    struct Setup: Sendable {
        /// The hands are part of what the body rests on.
        var onHands = false
        /// A mat under the body.
        var mat = false
    }

    /// How far the skin presses into what it rests on, how thick a mat is, how near the floor
    /// a wrist must be for its hand to be laid on it, and how far the body may be tipped
    /// (degrees) to bring the hands down.
    static let sink = 0.005, matTop = 0.008, near = 0.16, tip = 25.0
    /// What the body rests on: everything but the arms.
    static let rests = FloorSkin.trunk + FloorSkin.legs

    let body: Body3D
    let setup: Setup
    let hands: [String: HandPress]
    /// How high the floor is under the body.
    let level: Double
    /// The bone the body rests on at the start, and where its head stays.
    private(set) var anchor = "pelvis"
    private(set) var anchorAt = V(0, 0, 0)
    /// Where the wrist of a hand that is down through the whole loop stays.
    private(set) var spots: [String: V] = [:]
    let kinds: [PropKind]
    private(set) var fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D, _ setup: Setup) {
        guard let r = body.flatHand("r", spread: 1.3), let l = body.flatHand("l", spread: 1.3),
              let first = guide.keyframes.first?.pose else { return nil }
        self.body = body
        self.setup = setup
        hands = ["r": r, "l": l]
        level = setup.mat ? Self.matTop : 0
        kinds = setup.mat ? [.mat] : []

        let start = settled(first, pinned: false)
        guard let low = body.floorLowest(Self.rests, start.g, start.h), let at = start.h[low.bone] else { return nil }
        anchor = low.bone
        anchorAt = V(at.x, at.y, 0)
        if setup.onHands {
            // A hand that is down in every keyframe stays where it first lies.
            let frames = guide.keyframes.map { settled($0.pose, pinned: true) }
            for s in ["r", "l"] {
                let wrists = frames.compactMap { $0.h["hand.\(s)"] }
                if let first = wrists.first, wrists.allSatisfy({ $0.z - level < Self.near && ($0 - first).flat.length < 0.12 }) {
                    spots[s] = first
                }
            }
        }
        if setup.mat, let pelvis = start.h["pelvis"], let neck = start.h["neck"] {
            // The mat lies along the body, or across the way it faces when it is upright.
            let middle = ["pelvis", "neck", "toes.r", "toes.l"].compactMap { start.h[$0] }
            let c = middle.reduce(V(0, 0, 0), +) * (1 / Double(max(1, middle.count)))
            let along = (neck - pelvis).flat
            let x = along.length > 0.2 ? along.unit.cross(V(0, 0, 1)) : V(1, 0, 0)
            fixed = [Plan.box(V(c.x, c.y, Self.matTop / 2), (0.66, 1.85, Self.matTop), x: x, .accent)]
        }
    }

    /// The body for `pose` laid on the floor, before the arms are fitted.
    func settled(_ pose: JointPose, pinned: Bool) -> (g: [String: M], h: [String: V]) {
        let posed = body.rotations(pose)
        let heads = body.heads(posed)
        /// Tipped forward by `tip` degrees and lowered until the skin rests.
        func laid(_ tip: Double) -> (g: [String: M], h: [String: V]) {
            let turn = M.x(tip)
            let g = posed.mapValues { turn * $0 }
            var h = heads.mapValues { turn * $0 }
            let drop = V(0, 0, level - Self.sink - body.floorLow(Self.rests, g, h))
            for (k, v) in h { h[k] = v + drop }
            return (g, h)
        }
        var tip = 0.0
        if setup.onHands, let press = hands["r"] {
            // How far the wrists are from where they lie when the palms are flat.
            func gap(_ tip: Double) -> Double {
                let h = laid(tip).h
                let wrists = ["r", "l"].compactMap { h["hand.\($0)"]?.z }
                return (wrists.min() ?? 0) - level - press.wristLift
            }
            let now = gap(0)
            // Only hands that are already close are brought down, and only by a small tip.
            if abs(now) > 0.004, now < 0.3 {
                for side in [Self.tip, -Self.tip] where now * gap(side) < 0 {
                    var a = 0.0, b = side
                    for _ in 0..<14 {
                        let mid = (a + b) / 2
                        if now * gap(mid) > 0 { a = mid } else { b = mid }
                    }
                    tip = (a + b) / 2
                    break
                }
            }
        }
        var (g, h) = laid(tip)
        if pinned, let at = h[anchor] {
            let slide = V(anchorAt.x - at.x, anchorAt.y - at.y, 0)
            for (k, v) in h { h[k] = v + slide }
        }
        // Hands and arms the pose leaves below the floor come up out of it.
        if !setup.onHands { for s in ["r", "l"] { clear(s, &g, &h) } }
        return (g, h)
    }

    /// Swings the arm of side `s` up from the shoulder until none of it is under the floor.
    private func clear(_ s: String, _ g: inout [String: M], _ h: inout [String: V]) {
        let bones = ["humerus.\(s)", "ulna.\(s)", "hand.\(s)"]
        guard body.floorLow(bones, g, h) < level - 0.01, let shoulder = h["humerus.\(s)"], let wrist = h["hand.\(s)"],
              let root = h["pelvis"] else { return }
        let out = (wrist - shoulder).flat
        guard out.length > 0.05 else { return }
        // About the level line across the arm, the way that lifts the hand.
        let axis = V(0, 0, 1).cross(out.unit)
        let branch = body.floorBranch("humerus.\(s)")
        let start = g
        func lifted(_ degrees: Double) -> (g: [String: M], h: [String: V]) {
            var turned = start
            body.floorTurn(branch, by: M.axis(axis, -degrees), &turned)
            return (turned, body.place(turned, root: root))
        }
        let up = floorCross(0...80) { degrees in
            let (g, h) = lifted(degrees)
            return body.floorLow(bones, g, h) - level + 0.004
        }
        (g, h) = lifted(up)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        var (g, h) = settled(pose, pinned: true)
        let root = h["pelvis"] ?? V(0, 0, 0)
        if setup.onHands {
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                guard let press = hands[s], let wrist = spots[s] ?? h["hand.\(s)"], wrist.z - level < Self.near,
                      let turn = g["hand.\(s)"], let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"] else { continue }
                // Flat where the wrist is, the fingers the way the pose points them.
                var fingers = (turn * press.along).flat
                if fingers.length < 0.2 { fingers = Body3D.forward }
                let rest = body.pressWrist(press, at: V(0, 0, 0), fingers: fingers, normal: Body3D.up)
                let at = V(wrist.x - rest.x, wrist.y - rest.y, level)
                // The elbow stays on the side the pose has it.
                var pole = elbow - (shoulder + wrist) * 0.5
                if pole.length < 0.02 { pole = V(-m * 0.3, 1, 0.3) }
                body.press(s, press, at: at, fingers: fingers, pole: pole, &g, h)
            }
            h = body.place(g, root: root)
        }
        return (body.made(g, h, floor: 0), [])
    }
}

import Foundation

// MARK: - Pallof press

/// A Pallof press: side-on to a pulley at chest height, both fists one above the other on a
/// single upright handle, held at the breastbone and pressed straight out in front and back.
/// The cable pulls sideways the whole time and the body does not turn to it, so the stack hangs
/// lifted all loop long and only moves a little. Standing, or on one knee.
struct CablePallofStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M
    typealias Plan = PropPlan

    /// The station's height, and how far to the side of the body its wheel is.
    static let top = 2.2, aside = 1.15
    /// The handle's thickness and half its length, how far from it the stirrup's ring is, and
    /// how far above and below its middle the two fists close.
    static let gripRadius = 0.015, halfGrip = 0.12, ring = 0.16, apart = 0.046
    /// How near the chest the handle's middle line comes, and how high the stack hangs with
    /// the cable at its shortest.
    static let clear = 0.085, lifted = 0.28

    let body: Body3D
    let grips: [String: HandGrip]
    let footing: CableKit.Footing
    let kinds: [PropKind]
    /// Which side the pulley is on: 1 on the body's right, -1 on its left.
    let side: Double
    private(set) var fixed: [PropPiece] = []
    /// The middle of the wheel, how the station is turned and where it stands.
    private(set) var wheel = V(-1.15, -0.3, 1.3)
    private(set) var turn = M.identity
    private(set) var base = V(0, 0, 0)
    private(set) var column = 0.0
    /// The cable's shortest length out of the wheel through the loop.
    private(set) var slack = 0.0

    /// `stagger` puts the left foot that far ahead of the right when standing. On one knee the
    /// pulley is beside the knee that is down, or beside the raised one when `byRaisedKnee`.
    init?(_ guide: HowToGuide, _ body: Body3D, on support: PostureStaging.Support? = nil, stagger: Double = 0,
          byRaisedKnee: Bool = false) {
        guard let first = guide.keyframes.first?.pose,
              let footing = support == nil ? CableKit.Footing(body, first: first, stagger: stagger) : CableKit.Footing(guide, body, on: support),
              let r = body.grip("r", radius: Self.gripRadius), let l = body.grip("l", radius: Self.gripRadius) else { return nil }
        self.body = body
        self.footing = footing
        grips = ["r": r, "l": l]
        kinds = footing.kinds
        // On one knee, the raised knee is the higher one.
        let start = footing.settle(body, first).h
        if support != nil, let right = start["shin.r"], let left = start["shin.l"], abs(right.z - left.z) > 0.1 {
            let raised: Double = right.z > left.z ? 1 : -1
            side = byRaisedKnee ? raised : -raised
        } else {
            side = 1
        }

        // The wheel is level with the hands and beside the middle of their way out and back.
        let loop = (0...24).map { Figure.smooth(guide.keyframes, at: Double($0) / 24) }
        let centres = loop.map { reach($0).centre }
        guard let near = centres.map(\.y).max(), let far = centres.map(\.y).min(), near - far > 0.15 else { return nil }
        let height = centres.map(\.z).reduce(0, +) / Double(centres.count)
        turn = M.z(-side * 90)
        base = V(-side * Self.aside, (near + far) / 2, 0)
        wheel = base + V(0, 0, height + CableKit.wheel)
        let station = CableKit.mastStation(pulley: V(0, 0, wheel.z), top: Self.top)
        column = station.column
        fixed = CableKit.moved(station.pieces, turn: turn, by: base) + footing.pieces

        // The stack rests on the cable's shortest length, and the cable stays out of the body.
        var poses = loop
        let fault = Figure.smooth(guide.keyframes, at: guide.faultT)
        poses += guide.steps.flatMap(\.mistakes).compactMap { step in step.pose.map { Figure.applying($0, to: fault) } }
        var least = Double.infinity
        for (i, pose) in poses.enumerated() {
            let at = layout(pose)
            if i < loop.count { least = min(least, (at.ring - wheel).length) }
            let run = at.rim - at.ring
            guard run.length > 0.3 else { return nil }
            if Body3D.wayOut((at.ring + at.rim) * 0.5, axis: run.unit, half: run.length / 2, radius: 0.012,
                             of: at.bulk, front: Body3D.forward) != nil { return nil }
        }
        slack = least
    }

    /// The posed body on its feet or its knee, and the middle of the handle: midway between
    /// where the keyframes' two forearms end, on the body's middle line, short of the chest
    /// and within reach of both arms.
    func reach(_ pose: JointPose) -> (g: [String: M], h: [String: V], root: V, centre: V) {
        let (g, h, root) = footing.settle(body, pose)
        var centre = V(0, 0, 0), between = V(0, 0, 0), n = 0.0
        for s in ["r", "l"] {
            guard let elbow = h["ulna.\(s)"], let wrist = h["hand.\(s)"], let shoulder = h["humerus.\(s)"], let grip = grips[s] else { continue }
            let c = grip.centre
            centre = centre + wrist + (wrist - elbow).unit * (c - grip.across * c.dot(grip.across)).length
            between = between + shoulder
            n += 1
        }
        guard n == 2 else { return (g, h, root, V(0, -0.3, 1.3)) }
        centre = centre * 0.5
        between = between * 0.5
        centre.x = between.x
        centre.y = min(centre.y, CableKit.front(h, at: centre.z) - Self.clear)
        // Arms pressed straight out side by side come a little short of meeting in the middle.
        for _ in 0..<40 {
            var short = false
            for (s, up) in [("r", 1.0), ("l", -1.0)] {
                guard let shoulder = h["humerus.\(s)"], let grip = grips[s] else { continue }
                if (centre + V(0, 0, up * Self.apart) - shoulder).length > body.reach(s, grip, bend: 8) { short = true }
            }
            guard short else { break }
            var back = between - centre
            back.x = 0
            centre = centre + back.unit * 0.006
        }
        return (g, h, root, centre)
    }

    struct Layout {
        var frame: BodyFrame
        /// The handle's middle line under each palm, its direction from thumb to little finger,
        /// the handle's middle, the stirrup's ring and where the cable leaves the wheel.
        var hands: [String: V]
        var across: [String: V]
        var centre, ring, rim: V
        /// The trunk, head and legs, which the cable stays out of.
        var bulk: [BulkRod]
    }

    func layout(_ pose: JointPose) -> Layout {
        var (g, h, root, centre) = reach(pose)
        // The cable comes round under the wheel, on the body's side of it.
        let under = V(side * 0.2, 0, -1)
        let c = (CableKit.rim(wheel, axis: V(0, 1, 0), from: centre, side: under) - centre).unit
        let ring = centre + c * Self.ring
        // The handle stands upright, square to its cable, with both thumbs on top.
        var line = V(0, 0, -1)
        line = (line - c * line.dot(c)).unit
        var hands: [String: V] = [:], across: [String: V] = [:]
        for (s, m, up) in [("r", 1.0, 1.0), ("l", -1.0, -1.0)] {
            guard let grip = grips[s], let shoulder = h["humerus.\(s)"], let elbow = h["ulna.\(s)"] else { continue }
            let at = centre - line * (up * Self.apart)
            // The elbows stay low and a little out, as the keyframes carry them.
            let pole = (elbow - (shoulder + at) * 0.5) + V(-m * 0.08, 0, -0.08)
            body.hold(s, grip, at: at, across: line, pole: pole, &g, h)
            hands[s] = at
            across[s] = line
        }
        h = body.place(g, root: root)
        return Layout(frame: body.made(g, h, floor: 0), hands: hands, across: across, centre: centre, ring: ring,
                      rim: CableKit.rim(wheel, axis: V(0, 1, 0), from: ring, side: under), bulk: body.bulk(g, h, walls: false))
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let at = layout(pose)
        guard let line = at.across["r"] else { return (at.frame, []) }
        var p: [PropPiece] = []
        // The stirrup: a long grip, and a strap from each of its ends to the ring.
        let a = at.centre - line * Self.halfGrip, b = at.centre + line * Self.halfGrip
        p.append(Plan.rod(a, b, Self.gripRadius, .dark))
        for end in [a, b] {
            p.append(Plan.rod(end, at.ring, 0.006, .metal))
            p.append(Plan.ball(end, 0.008, .metal))
        }
        p.append(Plan.ball(at.ring, 0.014, .metal))
        p.append(Plan.rod(at.ring, at.rim, CableKit.cable, .cable))
        let travel = Self.lifted + max(0, (at.ring - wheel).length - slack)
        p += CableKit.moved(liftedPlates(y: column, height: Self.top, travel: travel), turn: turn, by: base)
        return (at.frame, p)
    }
}

import Foundation

/// A plank jack: the body held in a line on its hands and toes, the feet jumping out wide and
/// in again. The hands lie flat on the floor under the shoulders and do not move; the feet
/// leave the floor a little to change their spread, and stay where they land.
struct CardioPlankJackStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How high the toes come off the floor in a hop, and how long each hop is, as a share of the loop.
    static let height = 0.035, flight = 0.3
    /// How long the arms are from shoulder to wrist, as a share of their full length.
    static let long = 0.97

    let body: Body3D
    let loop: CardioLoop
    let presses: [String: HandPress]
    /// How high the shoulders are held, and how far in front of the toes.
    let shoulders: Double
    private(set) var ahead = 0.0
    /// The middle of the hop out and of the hop back in, and how wide the legs stand between.
    let out: Double, back: Double, spread: Double
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        guard guide.familyID == "jumping-jack", guide.subtypeID == "plank-jack",
              guide.equipment == nil || guide.equipment == "none",
              // On the hands, on the floor: not on the elbows, a bench, a ball or a towel.
              [["jack", "plank"], ["plank", "jack"], ["push", "up", "jack"]].contains(CardioStagings.words(guide)),
              let r = body.flatHand("r"), let l = body.flatHand("l") else { return nil }
        let frames = guide.keyframes
        guard let wide = frames.max(by: { CardioStagings.angle($0.pose, "hipAbd") < CardioStagings.angle($1.pose, "hipAbd") }),
              wide.t - Self.flight > 0, wide.t + Self.flight < 1, let first = frames.first else { return nil }
        self.body = body
        loop = CardioLoop(guide, steps: 384)
        presses = ["r": r, "l": l]
        out = wide.t / 2
        back = (1 + wide.t) / 2
        spread = CardioStagings.angle(wide.pose, "hipAbd")
        shoulders = Self.long * body.armSpan("r", bend: 5) + r.wristLift
        // With the feet together the shoulders are this far ahead of the toes, and there they stay.
        let h = ProneLine(body: body, onKnees: false).place(first.pose, shoulders: shoulders).h
        guard let right = h["humerus.r"], let left = h["humerus.l"] else { return nil }
        ahead = (right.y + left.y) / 2
    }

    /// How high the toes are at `t`, and how far into the air.
    func hop(at t: Double) -> (height: Double, air: Double) {
        for middle in [out, back] {
            let u = (t - middle) / Self.flight + 0.5
            if u > 0, u < 1 { return (4 * Self.height * u * (1 - u), CardioStagings.ease(min(u, 1 - u), from: 0, to: 0.25)) }
        }
        return (0, 0)
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let found = loop.find(pose)
        let clean = Figure.smooth(loop.closed, at: found.t)
        var pose = found.fault.map { CardioStagings.applying($0, to: clean) } ?? clean
        let (height, air) = hop(at: found.t)
        // The legs open and close only while the toes are off the floor.
        let landed = found.t > out && found.t < back ? spread : 0
        for key in ["hipAbd", "hipAbdL"] {
            let own = CardioStagings.angle(clean, key)
            pose.angles[key] = CardioStagings.angle(pose, key) - own + own * air + landed * (1 - air)
        }
        let line = ProneLine(body: body, onKnees: false, feetHeight: height)
        var (g, h) = line.place(pose, shoulders: shoulders)
        // Legs that are spread are shorter from toe to shoulder: the feet come that much
        // nearer, and the shoulders stay over the hands.
        var slide = 0.0
        if let right = h["humerus.r"], let left = h["humerus.l"] { slide = ahead - (right.y + left.y) / 2 }
        h = h.mapValues { $0 + V(0, slide, 0) }
        for (s, m) in [("r", 1.0), ("l", -1.0)] {
            guard let press = presses[s], let shoulder = h["humerus.\(s)"] else { continue }
            let rest = body.pressWrist(press, at: V(0, 0, 0), fingers: Body3D.forward, normal: Body3D.up)
            body.press(s, press, at: V(shoulder.x - rest.x, shoulder.y - rest.y, 0), fingers: Body3D.forward, pole: V(-m * 0.5, 1, 0.3), &g, h)
        }
        h = line.settle(g).mapValues { $0 + V(0, slide, 0) }
        return (body.made(g, h, floor: 0), [])
    }
}

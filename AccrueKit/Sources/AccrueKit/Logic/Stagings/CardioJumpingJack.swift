import Foundation

/// Jumping jacks. The body hops on the spot: the feet leave the floor, land wide, leave it
/// again and land together, and while they are down they stay where they landed.
struct CardioJumpingJackStaging: BodyStaging {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// How high the feet come off the floor, and how long each hop is, as a share of the loop.
    static let height = 0.06, flight = 0.3

    let body: Body3D
    let loop: CardioLoop
    /// The middle of the hop out, the landing wide, and the middle of the hop back in.
    let out: Double, wide: Double, back: Double
    /// How far the legs are spread while the feet stand wide, in degrees.
    let spread: Double
    /// Where the balls of the feet, taken together, stay.
    let spot: V
    let kinds: [PropKind] = []
    let fixed: [PropPiece] = []

    init?(_ guide: HowToGuide, _ body: Body3D) {
        // The plain jack only: jacks that squat, cross, step or star are other movements.
        guard guide.familyID == "jumping-jack", guide.subtypeID == nil,
              guide.equipment == nil || guide.equipment == "none",
              [["jumping", "jack"], ["astride", "jumps", "male"]].contains(CardioStagings.words(guide)),
              let out = guide.keyframes.first(where: { $0.phase == "Out" })?.t,
              let wide = guide.keyframes.first(where: { $0.phase == "Wide" }),
              let back = guide.keyframes.first(where: { $0.phase == "In" })?.t,
              out - Self.flight / 2 > 0, out + Self.flight / 2 < wide.t, back - Self.flight / 2 > wide.t, back + Self.flight / 2 < 1,
              let ball = body.head["toes.r"], let pelvis = body.head["pelvis"] else { return nil }
        self.body = body
        self.out = out
        self.wide = wide.t
        self.back = back
        spread = CardioStagings.angle(wide.pose, "hipAbd")
        loop = CardioLoop(guide, steps: 384)
        spot = V(0, ball.y - pelvis.y, 0)
    }

    /// How high the feet are at `t`, and how far into the air (0 on the floor, 1 well off it).
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
        // Feet on the floor do not slide: the legs keep the spread they landed with, and
        // open or close only in the air.
        let landed = found.t > out && found.t < back ? spread : 0
        for key in ["hipAbd", "hipAbdL"] {
            let own = CardioStagings.angle(clean, key)
            pose.angles[key] = CardioStagings.angle(pose, key) - own + own * air + landed * (1 - air)
        }
        let g = CardioFooting.settle(body.rotations(pose), air: ["r": air, "l": air])
        let root = CardioFooting.root(body, g, ball: spot, floor: height)
        return (body.made(g, body.place(g, root: root), floor: 0), [])
    }
}

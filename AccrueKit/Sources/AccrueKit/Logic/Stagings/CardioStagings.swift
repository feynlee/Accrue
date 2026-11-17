import Foundation

/// Cardio and conditioning equipment: treadmill, bike, rower, elliptical, ski erg, stairs, sled, ropes.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum CardioStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        switch guide.familyID {
        case "row-erg": return CardioRowerStaging(guide, body)
        case "stationary-bike": return CardioBikeStaging(guide, body)
        case "elliptical": return CardioEllipticalStaging(guide, body)
        case "sled-push-pull": return CardioSledStaging(guide, body)
        case "ski-erg": return CardioSkiErgStaging(guide, body)
        case "stair-climb": return CardioStairsStaging(guide, body)
        case "treadmill-run", "run", "walk": return CardioGaitStaging(guide, body, treadmills: true)
        default: return nil
        }
    }

    /// The words of an exercise's name. A staging claims an exercise only when it knows the
    /// meaning of every one of them, so a variation it cannot show keeps the plain fallback.
    static func words(_ guide: HowToGuide) -> Set<String> {
        Set(guide.exerciseName.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// A pose's angle for `key`. A left-side key ("kneeFlexL") that the pose leaves out is the
    /// same as the right side's, as Body3D reads it.
    static func angle(_ pose: JointPose, _ key: String) -> Double {
        if let v = pose.angles[key] { return v }
        if key.hasSuffix("L"), let v = pose.angles[String(key.dropLast())] { return v }
        return 0
    }

    /// 0 below `from`, 1 above `to`, and an eased rise between.
    static func ease(_ x: Double, from: Double, to: Double) -> Double {
        let s = min(1, max(0, (x - from) / (to - from)))
        return s * s * (3 - 2 * s)
    }
}

/// Where in its loop a pose is. A staging is handed only the pose, never the time, and a crank
/// or a belt has to know how far round the loop has gone: so the loop is sampled once, as the
/// plan samples it, and a pose is found on it by the angles in `keys`. A pose with one of the
/// how-to's mistakes added is found as the pose it was before the mistake.
///
/// A loop whose last keyframe is not its first again (running, walking, stairs) is handed to a
/// staging with its last stretch run off the end of the curve. `clean` gives the pose the loop
/// should have there: the same moment on the keyframes closed into a ring.
struct CardioLoop: Sendable {
    let given: [Keyframe]
    let closed: [Keyframe]
    let keys: [String]
    let faults: [JointPose]
    let samples: [[Double]]

    init(_ guide: HowToGuide, keys: [String]? = nil, steps: Int = 96) {
        let given = guide.keyframes
        self.given = given
        var closed = given
        if let first = given.first, let last = given.last, last.t < 1, first.pose != last.pose {
            var again = first
            again.t = 1
            closed.append(again)
        }
        self.closed = closed
        let keys = keys ?? Set(given.flatMap { $0.pose.angles.keys }).sorted()
        self.keys = keys
        faults = guide.steps.flatMap(\.mistakes).compactMap(\.pose).filter { !$0.angles.isEmpty }
        samples = (0...steps).map { i in
            let pose = Figure.smooth(given, at: Double(i) / Double(steps))
            return keys.map { CardioStagings.angle(pose, $0) }
        }
    }

    /// The moment of the loop (0 to 1) whose pose is nearest to `pose`.
    func callAsFunction(_ pose: JointPose) -> Double { find(pose).t }

    /// That moment, and the mistake the pose carries, if it is one of the how-to's.
    func find(_ pose: JointPose) -> (t: Double, fault: JointPose?) {
        var best = nearest(pose)
        var carried: JointPose?
        for fault in faults where best.gap > 1e-6 {
            var p = pose
            for (key, value) in fault.angles { p.angles[key] = (p.angles[key] ?? 0) - value }
            let found = nearest(p)
            if found.gap < best.gap { (best, carried) = (found, fault) }
        }
        return (best.t, carried)
    }

    /// The moment of the loop the pose belongs to, and the pose the closed loop has there, with
    /// the pose's mistake still on it.
    func clean(_ pose: JointPose) -> (t: Double, pose: JointPose) {
        let found = find(pose)
        let good = Figure.smooth(closed, at: found.t)
        return (found.t, found.fault.map { Figure.applying($0, to: good) } ?? good)
    }

    /// The nearest moment of the loop, and how far from the loop the pose is there.
    func nearest(_ pose: JointPose) -> (t: Double, gap: Double) {
        let n = samples.count - 1
        guard n > 0 else { return (0, 0) }
        let p = keys.map { CardioStagings.angle(pose, $0) }
        func gap(_ a: [Double]) -> Double { zip(a, p).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
        var best = 0, least = Double.infinity
        for (i, s) in samples.enumerated() {
            let d = gap(s)
            if d < least { (best, least) = (i, d) }
        }
        // Between that sample and its neighbours: the nearest point of the loop's own line.
        var t = Double(best)
        for j in [best - 1, best] where j >= 0 && j < n {
            let a = samples[j], b = samples[j + 1]
            var along = 0.0, length = 0.0
            for k in 0..<p.count {
                along += (p[k] - a[k]) * (b[k] - a[k])
                length += (b[k] - a[k]) * (b[k] - a[k])
            }
            let s = length > 1e-12 ? min(1, max(0, along / length)) : 0
            let d = gap((0..<p.count).map { a[$0] + (b[$0] - a[$0]) * s })
            if d < least { (t, least) = (Double(j) + s, d) }
        }
        return (t / Double(n), least)
    }

    /// How far the pose's `key` is from where the loop has it at moment `t`, in degrees: what a
    /// mistake added.
    func off(_ key: String, _ pose: JointPose, at t: Double) -> Double {
        CardioStagings.angle(pose, key) - CardioStagings.angle(Figure.smooth(given, at: t), key)
    }
}

/// The measures of the model's foot that equipment under it is built to.
struct CardioFoot: Sendable {
    typealias V = Body3D.V
    typealias M = Body3D.M

    /// From the ball of the foot (the joint at the base of the toes) to the ankle, at rest.
    let toAnkle: V
    /// From the ball of the foot to the heel's underside, at rest.
    let toHeel: V
    /// How high the ball joint and the ankle joint are above the sole.
    let ballHeight, ankleHeight: Double
    /// The ball joint and the ankle joint at rest.
    let ball, ankle: V

    init?(_ body: Body3D, _ s: String) {
        guard let ankle = body.head["foot.\(s)"], let ball = body.head["toes.\(s)"], let tip = body.tail["toes.\(s)"]
        else { return nil }
        self.ankle = ankle
        self.ball = ball
        toAnkle = ankle - ball
        let floor = tip.z - 0.01
        ballHeight = ball.z - floor
        ankleHeight = ankle.z - floor
        toHeel = V(ankle.x, ankle.y + 0.045, floor) - ball
    }
}

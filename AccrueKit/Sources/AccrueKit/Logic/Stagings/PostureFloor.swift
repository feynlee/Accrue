import Foundation

/// A stretch whose keyframes hang in the air over legs that reach lower than what the body
/// should rest on. Sitting with the legs out in front, the legs come up at the hips until they
/// lie as low as the seat and no lower, and the arms until the hands are off the floor. Half
/// kneeling with one leg out straight, the back shin is laid along the floor and the front leg
/// comes up until its heel is as low as the back knee. The pose is then laid down as every
/// floor pose is.
struct PostureFloorSitStaging: BodyStaging {
    enum Pose: Sendable { case sitting, halfKneeling }

    static let legs = ["r": ["femur.r", "shin.r", "foot.r", "toes.r"], "l": ["femur.l", "shin.l", "foot.l", "toes.l"]]
    static let arms = ["r": ["humerus.r", "ulna.r", "hand.r"], "l": ["humerus.l", "ulna.l", "hand.l"]]
    /// The most a leg or an arm is brought up (degrees), and how far above the seat the lowest
    /// of a hand stays.
    static let most = 75.0, handClear = 0.015
    /// How far the foot of a shin that lies on the floor is pointed (degrees).
    static let pointed = -55.0

    let body: Body3D
    let pose: Pose
    let rest: FloorRestStaging
    var kinds: [PropKind] { rest.kinds }
    var fixed: [PropPiece] { rest.fixed }

    init?(_ guide: HowToGuide, _ body: Body3D, _ pose: Pose = .sitting) {
        self.body = body
        self.pose = pose
        var down = guide
        for i in down.keyframes.indices { down.keyframes[i].pose = Self.put(down.keyframes[i].pose, pose, body) }
        guard let rest = FloorRestStaging(down, body, .init()) else { return nil }
        self.rest = rest
    }

    static func put(_ pose: JointPose, _ how: Pose, _ body: Body3D) -> JointPose {
        switch how {
        case .sitting: sat(pose, body)
        case .halfKneeling: knelt(pose, body)
        }
    }

    /// `pose` with the shin of the bent leg laid along the floor behind its knee, and the
    /// straight leg brought up at the hip until it reaches no lower than that knee.
    static func knelt(_ pose: JointPose, _ body: Body3D) -> JointPose {
        var pose = pose
        for key in ["hipFlex", "kneeFlex", "ankleDorsi"] { pose.angles[key + "L"] = pose.angles[key + "L"] ?? pose.angles[key] ?? 0 }
        // The leg knelt on is the one whose knee is bent.
        let left = (pose.angles["kneeFlexL"] ?? 0) > (pose.angles["kneeFlex"] ?? 0)
        let back = left ? "l" : "r", front = left ? "r" : "l"
        func key(_ name: String, _ s: String) -> String { s == "l" ? name + "L" : name }
        let bent = pose.angles[key("kneeFlex", back)] ?? 0
        let straighter = floorCross(0...70) { less in
            var tried = pose
            tried.angles[key("kneeFlex", back)] = bent - less
            let h = body.heads(body.rotations(tried))
            return (h["shin.\(back)"]?.z ?? 0) - (h["foot.\(back)"]?.z ?? 0)
        }
        pose.angles[key("kneeFlex", back)] = bent - straighter
        pose.angles[key("ankleDorsi", back)] = pointed
        let flexed = pose.angles[key("hipFlex", front)] ?? 0
        let up = floorCross(0...most) { more in
            var tried = pose
            tried.angles[key("hipFlex", front)] = flexed + more
            let g = body.rotations(tried), h = body.heads(g)
            return body.floorLow(legs[front] ?? [], g, h) - body.floorLow(legs[back] ?? [], g, h)
        }
        pose.angles[key("hipFlex", front)] = flexed + up
        return pose
    }

    /// `pose` with the legs and the arms brought up level with the seat.
    static func sat(_ pose: JointPose, _ body: Body3D) -> JointPose {
        var pose = pose
        func low(_ bones: [String], _ pose: JointPose) -> Double {
            let g = body.rotations(pose)
            return body.floorLow(bones, g, body.heads(g))
        }
        let seat = low(["pelvis"], pose)
        /// Raises `key` on each side by itself until `bones` are `clear` above the seat.
        func raise(_ key: String, _ bones: [String: [String]], clear: Double) {
            let right = pose.angles[key] ?? 0, left = pose.angles[key + "L"] ?? right
            pose.angles[key + "L"] = left
            for (s, name, from) in [("r", key, right), ("l", key + "L", left)] {
                guard let bones = bones[s] else { continue }
                let up = floorCross(0...Self.most) { more in
                    var tried = pose
                    tried.angles[name] = from + more
                    return low(bones, tried) - seat - clear
                }
                pose.angles[name] = from + up
            }
        }
        raise("hipFlex", legs, clear: 0)
        raise("shoulderFlex", arms, clear: handClear)
        return pose
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        rest.frame(Self.put(pose, self.pose, body))
    }
}

/// A stretch lying back with one leg hanging to the floor: the keyframes lie in the air at the
/// height the hanging leg gives them, which is the height of a bench. The bench goes under the
/// back, from the hips to past the head, and the body is drawn as the keyframes pose it.
struct PostureTableStaging: BodyStaging {
    typealias V = Body3D.V

    static let sink = 0.005

    let body: Body3D
    let contacts: [String]
    let kinds: [PropKind] = [.bench]
    let fixed: [PropPiece]

    init?(_ guide: HowToGuide, _ body: Body3D) {
        self.body = body
        contacts = guide.contacts
        let frames = guide.keyframes.map { body.posed($0.pose, contacts: guide.contacts) }
        guard !frames.isEmpty, frames.allSatisfy({ $0.floor != nil }) else { return nil }
        // The back's lowest skin through the loop is where the top of the bench is.
        let top = (frames.map { body.floorLow(FloorSkin.trunk, $0.g, $0.h) - ($0.floor ?? 0) }.min() ?? 0) + Self.sink
        guard top > 0.35, top < 0.65, let first = frames.first, let pelvis = first.h["pelvis"], let head = first.h["head"],
              let hip = first.h["femur.r"] else { return nil }
        // Lying along the bench, the head away from the hanging leg.
        guard head.y - hip.y > 0.4, abs(head.z - pelvis.z) < 0.25 else { return nil }
        let near = hip.y - 0.03, far = head.y + 0.3
        var pieces = PostureStaging.flatBench(from: near, to: far, top: top, posts: [near + 0.2, far - 0.2])
        for i in pieces.indices { pieces[i].center[0] += pelvis.x }
        fixed = pieces
    }

    func frame(_ pose: JointPose) -> (body: BodyFrame, props: [PropPiece]) {
        let p = body.posed(pose, contacts: contacts)
        return (body.made(p.g, p.h, floor: p.floor), [])
    }
}

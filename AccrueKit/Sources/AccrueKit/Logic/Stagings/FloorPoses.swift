import Foundation

/// Poses held on the floor that a subtype's keyframes do not show: one set of keyframes
/// serves a whole subtype, and some of its names are a different pose (a hero pose among the
/// cross-legged seats, a lizard among the pigeons). Joint angles as the keyframes give them.
enum FloorPoses {
    typealias Angles = [String: Double]

    /// Sitting cross-legged, the right heel in close and the left shin in front of it.
    static let crossLegs: Angles = ["hipFlex": 82, "hipAbd": 50, "hipRot": 88, "kneeFlex": 150, "ankleDorsi": -25,
                                    "hipFlexL": 82, "hipAbdL": 50, "hipRotL": 88, "kneeFlexL": 128, "ankleDorsiL": -25]
    /// Kneeling, sitting back on the heels with the tops of the feet down.
    static let heelLegs: Angles = ["hipFlex": 70, "hipAbd": 0, "hipRot": 0, "kneeFlex": 160, "ankleDorsi": -55]
    /// Sitting with the soles together and the knees out.
    static let butterflyLegs: Angles = ["hipFlex": 80, "hipAbd": 55, "hipRot": 88, "kneeFlex": 132, "ankleDorsi": -15]
    /// Sitting tall, the hands on the knees.
    static let tall: Angles = ["trunk": 0, "lumbar": 5, "shoulderFlex": 5, "shoulderAbd": 22, "elbowFlex": 45, "neck": 0]
    /// On the forearms and the knees, the knees wide apart.
    static let frog: Angles = ["trunk": 90, "hipFlex": 90, "hipAbd": 60, "kneeFlex": 90, "ankleDorsi": 0,
                               "shoulderFlex": 90, "elbowFlex": 90]
    /// Face down on the forearms with the chest up, the right knee bent and its foot drawn in.
    static let halfFrog: Angles = ["trunk": 62, "lumbar": -30, "hipFlex": -15, "kneeFlex": 125, "kneeFlexL": 5, "ankleDorsi": -40,
                                   "shoulderFlex": 25, "elbowFlex": 85, "neck": -20]
    /// Standing on the left leg and sitting back, the right ankle across the left knee, palms together.
    static let figureFour: Angles = ["trunk": 35, "lumbar": 0, "hipFlex": 95, "hipAbd": 35, "hipRot": 75, "kneeFlex": 95,
                                     "hipFlexL": 75, "hipAbdL": 0, "hipRotL": 0, "kneeFlexL": 75, "ankleDorsiL": 22,
                                     "shoulderFlex": 55, "shoulderAbd": 10, "elbowFlex": 110, "neck": -10]
    /// Standing tall with both arms reaching straight up.
    static let reachUp: Angles = ["trunk": 0, "lumbar": 0, "shoulderFlex": 175, "elbowFlex": 0, "neck": -5]
    /// Standing and leaning back, the hands on the hips.
    static let leanBack: Angles = ["trunk": -12, "lumbar": -25, "hipFlex": -8, "kneeFlex": 0, "ankleDorsi": 5,
                                   "shoulderFlex": -25, "shoulderAbd": 20, "elbowFlex": 75, "neck": -15]
    /// The same lean back, up on the knees.
    static let kneelBack: Angles = ["trunk": -15, "lumbar": -25, "hipFlex": -5, "kneeFlex": 90, "ankleDorsi": -45,
                                    "shoulderFlex": -25, "shoulderAbd": 20, "elbowFlex": 75, "neck": -15]
    /// Lying on the back, reaching long through the arms and the toes.
    static let lyingLong: Angles = ["trunk": -90, "shoulderFlex": 170, "ankleDorsi": -30]

    /// `angles` held in place of the keyframes' own pose `base`: what a mistake adds to the
    /// keyframes is added to the pose held.
    static func held(_ angles: Angles, over base: JointPose) -> @Sendable (JointPose) -> JointPose {
        { pose in
            var out = JointPose(angles: angles, scapula: pose.scapula)
            for key in Set(pose.angles.keys).union(base.angles.keys) {
                let more = (pose.angles[key] ?? 0) - (base.angles[key] ?? 0)
                guard more != 0 else { continue }
                out.angles[key] = (out.angles[key] ?? 0) + more
                // A mistake given for the right side is the left side's too, unless the keyframes part them.
                if !key.hasSuffix("L"), pose.angles[key + "L"] == nil, let left = out.angles[key + "L"] {
                    out.angles[key + "L"] = left + more
                }
            }
            return out
        }
    }

    /// `legs` under whatever the keyframes do above the hips.
    static func seated(on legs: Angles) -> @Sendable (JointPose) -> JointPose {
        { pose in
            var out = pose
            for key in ["hipFlex", "hipAbd", "hipRot", "kneeFlex", "ankleDorsi"] {
                out.angles[key] = legs[key] ?? 0
                out.angles[key + "L"] = legs[key + "L"] ?? legs[key] ?? 0
            }
            return out
        }
    }

    /// The neck stretch a name asks for. The keyframes tilt the head to the side; a name that
    /// stretches the back of the neck nods it down instead, one that stretches the front
    /// looks up, one that rotates turns it. `tilt` is how far the keyframes tilt (degrees).
    static func neck(_ said: Set<String>, tilt: Double) -> @Sendable (JointPose) -> JointPose {
        func has(_ words: String...) -> Bool { !said.isDisjoint(with: words) }
        let down = has("flexion", "extensor", "forward", "front", "chin")
        let up = !down && has("extension", "flexor")
        let turn = has("rotating", "rotational", "rotation", "diagonal")
        let side = has("side", "inclination", "trap", "circle") || !(down || up || turn)
        return { pose in
            var out = pose
            let share = tilt == 0 ? 0 : (pose.angles["neckSide"] ?? 0) / tilt
            out.angles["neckSide"] = side ? 30 * share : 0
            out.angles["neck"] = (pose.angles["neck"] ?? 0) + (down ? 40 : up ? -35 : 0) * share
            out.angles["neckRot"] = turn ? 50 * share : 0
            return out
        }
    }
}

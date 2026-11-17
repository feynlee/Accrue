import Foundation

/// On the floor or a mat: crunch, leg raise, bridge, stretch, yoga and pilates.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum FloorStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        // Nothing but the body and the floor.
        guard guide.equipment == nil else { return nil }
        let said = words(guide.exerciseName)
        /// The name says nothing but these words: every other word is a different picture.
        func only(_ known: String...) -> Bool {
            said.isSubset(of: Set(known.flatMap { $0.split(separator: " ").map(String.init) }))
        }
        typealias Setup = FloorLyingStaging.Setup

        switch (guide.familyID, guide.subtypeID) {
        case ("crunch-sit-up", nil):
            // Knees bent, feet flat, the shoulders curling off the floor.
            if said.contains("chest") {
                guard only("crunch arms on chest") else { return nil }
                return FloorLyingStaging(guide, body, Setup(feet: .planted, arms: .onChest))
            }
            guard only("crunch floor v 2 negative hold back form check") else { return nil }
            return FloorLyingStaging(guide, body, Setup(feet: .planted, arms: .byHead))
        case ("crunch-sit-up", "sit-up"):
            if said.contains("chest") {
                guard only("sit up with arms on chest") else { return nil }
                return FloorLyingStaging(guide, body, Setup(sitsUp: true, feet: .planted, arms: .onChest))
            }
            guard only("sit up v 2 3 4 quarter half full male prisoner") else { return nil }
            return FloorLyingStaging(guide, body, Setup(sitsUp: true, feet: .planted, arms: .byHead))
        case ("lying-leg-raise", nil):
            // Both legs straight, lifted together.
            guard only("lying leg raise v 2 3 straight and hold full") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: .onFloor))
        case ("lying-leg-raise", "reverse-crunch"):
            guard only("reverse crunch v 2 3 tuck lying hip raise bent knee leg on floor flat lift with head up") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: .onFloor, headUp: said.contains("head")))
        case ("lying-leg-raise", "flutter"):
            // Straight legs beating up and down in turn; legs that cross are another picture.
            guard only("flutter kicks kick v 2 3 lying scissor scissors simultaneous alternating alternate leg raise",
                       "straight floor beginner advanced marches hands under hips with head up") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: said.contains("hips") ? .underHips : .onFloor,
                                                        headUp: said.contains("head")))
        case ("lying-leg-raise", "v-up"):
            guard only("v up jackknife sit hold") else { return nil }
            return FloorLyingStaging(guide, body, Setup(sitsUp: true))
        case ("hip-thrust-bridge", "glute-bridge"):
            // Shoulders on the floor, both feet flat, hips rising.
            if said.contains("march") {
                guard only("glute bridge march") else { return nil }
                return FloorLyingStaging(guide, body, Setup(anchor: .chest, feet: .underKnees, arms: .onFloor, marches: true))
            }
            guard only("butt bridge hip raise v 2 glute two legs on floor low") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, feet: .underKnees, arms: .onFloor))
        case ("hip-thrust-bridge", "single-leg"):
            // The right foot planted, the left leg held up: knee bent, or straight in line with the other thigh.
            var setup = Setup(anchor: .chest, feet: .underKnees, arms: .onFloor, plantedOnly: "r")
            if said.contains("straight") || said.contains("outstretched") {
                guard only("single leg glute hip bridge one on floor straight with outstretched hold") else { return nil }
                setup.straightLeg = true
            } else if said.contains("chest") {
                guard only("single leg glute bridge arms on chest") else { return nil }
                setup.arms = .onChest
            } else {
                guard only("single leg glute bridge one on floor bent knee") else { return nil }
            }
            return FloorLyingStaging(guide, body, setup)
        case ("hip-thrust-bridge", "hamstring-bridge"):
            guard only("hamstring bridge v 2 straight leg hip glute heel") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, feet: .planted, arms: .onFloor))
        case ("dead-bug-bird-dog", nil):
            guard only("dead bug v 2 3") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest))
        case ("dead-bug-bird-dog", "bird-dog"):
            guard only("bird dog v 2") else { return nil }
            return FloorProneStaging(guide, body, .birdDog)
        case ("plank", nil):
            // The forearm plank held still is the bodyweight group's; these names show what its hips do wrong.
            guard said.contains("butt"), only("front plank butt form check") else { return nil }
            return PlankStaging(guide, body)
        case ("plank", "high-plank"):
            // On straight arms, held still or with a hand tapping the other shoulder.
            if only("plank on hands") { return FloorProneStaging(guide, body, .plank(onKnees: false, taps: false)) }
            if only("shoulder tap") { return FloorProneStaging(guide, body, .plank(onKnees: false, taps: true)) }
            guard said.contains("kneeling"), only("kneeling plank shoulder tap male") else { return nil }
            return FloorProneStaging(guide, body, .plank(onKnees: true, taps: true))
        case ("plank", "bear"):
            guard only("bear plank") else { return nil }
            return FloorProneStaging(guide, body, .bear)
        case ("plank", "reverse"):
            guard only("reverse plank v 2") else { return nil }
            return FloorReversePlankStaging(guide, body)
        case ("mountain-climber", "standard"):
            // Feet that slide on a towel run the same way.
            guard only("mountain climber v 2 slide with towel") else { return nil }
            return FloorProneStaging(guide, body, .climber)
        case ("plank", "hollow"):
            // Low back pressed down, shoulders and legs just off the floor.
            guard only("hollow dish hold") else { return nil }
            return FloorLyingStaging(guide, body, Setup())
        case ("side-plank", nil):
            guard only("side plank bridge v 2 3 lateral with straight legs butt form check") else { return nil }
            return FloorSidePlankStaging(guide, body)
        case ("side-plank", "bent-knee"):
            guard only("bent knee side plank bridge beginner lateral leg with") else { return nil }
            return FloorSidePlankStaging(guide, body)
        case ("side-plank", "star"):
            // The upper leg lifting and lowering.
            guard only("side bridge plank hip abduction star leg raise lift with raised v 2") else { return nil }
            return FloorSidePlankStaging(guide, body)
        default:
            return rest(guide, body, said)
        }
    }

    /// Words that put something else in the picture (a wall to lean on, a chair, a strap), or
    /// say the pose is not done down on the floor at all.
    static let things: Set<String> = ["wall", "chair", "bench", "box", "ball", "roller", "stick", "bar", "band", "strap", "towel",
                                      "partner", "door", "step", "table", "couch", "pole", "rope", "ring", "rings", "block", "pvc",
                                      "assisted", "suspension", "machine", "smith", "cable", "dumbbell", "kettlebell", "barbell",
                                      "standing", "stand"]

    /// The poses that only need laying on the floor, by family and subtype ("" for the
    /// family's own keyframes). `true`: the hands are down too. Only what the keyframes
    /// already pose as a body that lies, sits or kneels there; the rest keep the fallback.
    static let resting: [String: [String: Bool]] = [
        "pilates-mat": ["": false, "criss-cross": false, "double-leg-stretch": false, "hundred": false, "leg-circle": false,
                        "overhead": false, "rolling": false, "single-leg-stretch": false, "spine-stretch": false,
                        "teaser": false, "leg-pull": true, "swan": true],
        "yoga-pose": ["boat": false, "prone-backbend": false, "supine-rest": false, "cobra": true, "down-dog": true,
                      "seated-fold": true, "child": true, "fish": false, "camel": false],
        "stretch-spine": ["knees-chest": false, "lying-twist": false],
        "stretch-chest-shoulder": ["lying": false],
        "stretch-wrist-forearm": ["kneeling": true],
        "stretch-glute-hip": ["": false, "knee-chest": false, "lying": false, "pigeon": true, "ninety": true, "frog": false],
        "stretch-hamstring": ["": false, "lying": false],
        "stretch-quad-hip-flexor": ["lying": false],
        "stretch-calf": ["seated": false],
        "mobility-flow": ["inchworm": true, "pelvic-tilt": false],
    ]

    static func rest(_ guide: HowToGuide, _ body: Body3D, _ said: Set<String>) -> (any BodyStaging)? {
        func has(_ words: String...) -> Bool { !said.isDisjoint(with: words) }
        guard let base = guide.keyframes.first?.pose else { return nil }
        let mat = ["yoga-pose", "pilates-mat"].contains(guide.familyID)
        /// A pose held on the floor in place of the keyframes' own.
        func held(_ angles: FloorPoses.Angles, onHands: Bool = false) -> (any BodyStaging)? {
            FloorRestStaging(guide, body, .init(onHands: onHands, mat: mat, posed: FloorPoses.held(angles, over: base)))
        }
        func merged(_ a: FloorPoses.Angles, _ b: FloorPoses.Angles) -> FloorPoses.Angles { a.merging(b) { $1 } }

        // The one pose among these that is done standing.
        if guide.familyID == "yoga-pose", guide.subtypeID == "pigeon", has("standing") {
            return said.isSubset(of: ["standing", "figure", "four", "pose"]) ? held(FloorPoses.figureFour) : nil
        }
        if guide.familyID == "stretch-spine", guide.subtypeID == "extension", has("standing") {
            return said.isSubset(of: ["standing", "lean", "back", "stomach", "stretch"]) ? held(FloorPoses.leanBack) : nil
        }
        if guide.familyID == "mobility-flow", guide.subtypeID == "pelvic-tilt", has("standing") {
            // The same tilt of the hips done on the feet: the legs stay upright under them, hands on the hips.
            guard said.isSubset(of: ["standing", "pelvic", "tilt"]) else { return nil }
            return FloorRestStaging(guide, body, .init(posed: { pose in
                let lumbar = pose.angles["lumbar"] ?? 0
                return JointPose(angles: ["trunk": 0, "lumbar": lumbar, "hipFlex": -lumbar / 2, "kneeFlex": 4,
                                          "shoulderFlex": -20, "shoulderAbd": 20, "elbowFlex": 80], scapula: pose.scapula)
            }))
        }
        guard said.isDisjoint(with: things) else { return nil }
        switch (guide.familyID, guide.subtypeID) {
        case ("stretch-spine", "extension"):
            // The keyframes lie face down and press the chest up; the same bend is also done up on the knees or standing.
            if has("bridge") { return nil }
            if has("kneeling") { return held(FloorPoses.kneelBack) }
            if has("backward", "backbend") { return held(FloorPoses.leanBack) }
            return FloorRestStaging(guide, body, .init(onHands: true))
        case ("stretch-spine", "cat"), ("stretch-spine", "cow"), ("yoga-pose", "cat-cow"):
            // On hands and knees, the back rounding and hollowing. A leg sent back is another pose.
            guard said.isSubset(of: ["cat", "cow", "stretch", "pose", "yoga", "bitilasana", "marjaryasana", "v", "2"]) else { return nil }
            return FloorProneStaging(guide, body, .allFours, mat: guide.familyID == "yoga-pose")
        case ("yoga-pose", "seat"):
            // The keyframes sit cross-legged; the hero and the thunderbolt kneel, the butterfly puts the soles together.
            if has("hero", "virasana", "vajrasana", "thunderbolt") { return held(merged(FloorPoses.tall, FloorPoses.heelLegs)) }
            if has("butterfly") { return held(merged(FloorPoses.tall, FloorPoses.butterflyLegs)) }
            return FloorRestStaging(guide, body, .init(mat: mat))
        case ("yoga-pose", "pigeon"):
            // The keyframes are the pigeon. The frogs are face down, the cow face and the double pigeon sit.
            if has("frog") { return held(has("half") ? FloorPoses.halfFrog : FloorPoses.frog) }
            if has("cow", "double") { return held(merged(FloorPoses.tall, FloorPoses.crossLegs)) }
            guard has("pigeon") else { return nil }
            return FloorRestStaging(guide, body, .init(onHands: true, mat: mat))
        case ("yoga-pose", "bridge-wheel"), ("pilates-mat", "bridge"):
            // The bridge: shoulders and feet down, hips up. The wheel, the upward bow and the crab
            // are shown as the bridge they start from.
            var lying = guide
            if lying.keyframes.count == 1, var down = lying.keyframes.first {
                // Held at the top: the feet are planted where they stand with the hips down.
                var top = down
                down.pose.angles.merge(["trunk": -90, "hipFlex": 45, "kneeFlex": 100, "ankleDorsi": 5, "neck": 0]) { $1 }
                top.t = 0.5
                var end = down
                end.t = 1
                lying.keyframes = [down, top, end]
            }
            return FloorLyingStaging(lying, body, .init(anchor: .chest, feet: .underKnees, arms: .onFloor))
        case ("stretch-chest-shoulder", "overhead"):
            // The keyframes kneel and reach forward along the floor. Reaching up is done upright.
            if has("above", "reaching") || (has("over") && has("head")) {
                return held(has("seated", "sitting") ? merged(FloorPoses.reachUp, FloorPoses.crossLegs) : FloorPoses.reachUp)
            }
            guard !has("seated", "sitting") else { return nil }
            return FloorRestStaging(guide, body, .init(onHands: true))
        case ("stretch-general", nil):
            if has("whole", "boat") { return held(FloorPoses.lyingLong) }
            // The neck stretches: upright, the head going the way the name says.
            guard has("neck") else { return nil }
            let tilt = guide.keyframes.map { $0.pose.angles["neckSide"] ?? 0 }.max() ?? 0
            let neck = FloorPoses.neck(said, tilt: tilt)
            let legs: FloorPoses.Angles? = has("seated", "sitting") ? FloorPoses.crossLegs : has("kneeling") ? FloorPoses.heelLegs : nil
            let lies = has("lying")
            return FloorRestStaging(guide, body, .init(posed: { pose in
                var out = neck(pose)
                if let legs { out = FloorPoses.seated(on: legs)(out) }
                if lies { out.angles["trunk"] = -90 }
                return out
            }))
        default:
            guard let onHands = resting[guide.familyID]?[guide.subtypeID ?? ""] else { return nil }
            if guide.familyID.hasPrefix("stretch-") {
                // A stretch whose name says it is done sitting or kneeling is not the one keyframes
                // that lie down draw, and the other way round.
                let other: Set<String> = switch guide.subtypeID {
                case "seated", "ninety": ["lying", "recumbent"]
                case "kneeling", "frog", "pigeon": ["lying", "recumbent", "seated", "sitting"]
                default: ["seated", "sitting", "kneeling", "fours"]
                }
                guard said.isDisjoint(with: other) else { return nil }
            }
            var setup = FloorRestStaging.Setup(onHands: onHands, mat: mat)
            // A knee drawn to the chest is held there with both hands, unless the name sends them elsewhere.
            if guide.familyID == "stretch-glute-hip", guide.subtypeID == "knee-chest" {
                if said.isDisjoint(with: ["overhead", "cross", "crossover", "twist", "back"]) {
                    setup.holds = "r"
                } else {
                    // The arms lie on the floor, overhead or out to the sides, and a knee that crosses over goes across the body.
                    let overhead = has("overhead"), across = has("cross", "crossover", "twist")
                    setup.posed = { pose in
                        var out = pose
                        out.angles.merge(overhead ? ["shoulderFlex": 172, "shoulderAbd": 0, "elbowFlex": 5]
                                                  : ["shoulderFlex": 0, "shoulderAbd": 80, "elbowFlex": 5]) { $1 }
                        if across {
                            out.angles["hipAbd"] = (pose.angles["hipAbd"] ?? 0) - 25
                            out.angles["hipAbdL"] = pose.angles["hipAbdL"] ?? 0
                        }
                        return out
                    }
                }
            }
            return FloorRestStaging(guide, body, setup)
        }
    }

    /// The words of an exercise name: "sit-up (arms on chest)" is sit, up, arms, on, chest.
    static func words(_ name: String) -> Set<String> {
        Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

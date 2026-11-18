import Foundation

/// The body on fixed bars or the floor: dip, push-up, plank, hanging leg raise, and the rest of the pull-up family.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum BodyweightStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        /// Nothing but the body, or the body with a weight hung on it.
        let plain = guide.equipment == nil || guide.equipment == "weighted"

        switch guide.familyID {
        case "dip":
            guard plain || guide.equipment == "dumbbell" && guide.subtypeID == "bench" else { return nil }
            switch guide.subtypeID {
            case nil, "hold", "scapula":
                // Two hands on two parallel bars, the right way up.
                if has("one arm", "straight bar", "ring", "elbow", "impossible", "korean", "planche", "push up",
                       "inverted", "assisted", "ball") { return nil }
                return DipStaging(guide, body)
            case "bench":
                // Hands on one bench behind the hips; off the floor or between chairs is another picture.
                if !has("bench") || has("floor", "chair", "ball") { return nil }
                let raised = has("between", "legs on bench", "bench leg", "legs elevated", "three bench")
                return BenchDipStaging(guide, body, feet: raised ? .raised : has("knees bent") ? .flat : .heels)
            default:
                return nil
            }
        case "push-up":
            // Only the names that say nothing more than how the hands and feet are set: every
            // other word (a ball, a clap, one arm, a twist) is a different picture.
            guard plain else { return nil }
            let said = words(name)
            var setup = PushUpStaging.Setup()
            var known: Set<String> = ["push", "up", "close", "grip", "narrow", "diamond", "wide", "hand", "male"]
            switch guide.subtypeID {
            case nil:
                known.formUnion(["decline", "start", "end", "position", "form", "check", "plus", "negative", "isometric",
                                 "hold", "weighted", "with", "vest", "plate"])
            case "knee":
                known.formUnion(["on", "knees", "kneeling"])
                setup.onKnees = true
            case "incline":
                known.formUnion(["incline", "on", "box", "bench"])
                setup.handsOnBench = true
                setup.handsOnBox = said.contains("box")
            default:
                return nil
            }
            guard said.isSubset(of: known) else { return nil }
            setup.feetOnBench = said.contains("decline")
            setup.plate = said.contains("plate")
            if said.contains("close") || said.contains("narrow") { (setup.halfHands, setup.flare) = (0.13, 0.35) }
            if said.contains("wide") { (setup.halfHands, setup.flare) = (0.4, 1.3) }
            if said.contains("diamond") { (setup.halfHands, setup.turnedIn, setup.flare) = (0.075, 40, 0.9) }
            return PushUpStaging(guide, body, setup)
        case "plank":
            // The forearm plank held still; the moving and one-limb planks are other pictures.
            guard plain, guide.subtypeID == nil else { return nil }
            let said = words(name)
            guard said.isSubset(of: ["front", "plank", "weighted", "kneeling"]) else { return nil }
            return PlankStaging(guide, body, onKnees: said.contains("kneeling"), plate: said.contains("weighted"))
        case "pull-up":
            // Both hands on one fixed bar, pulling straight up: the grips a name can ask for,
            // and nothing else (no ropes, rings, machines, one arm or swinging).
            guard plain else { return nil }
            let said = words(name)
            var known: Set<String> = []
            switch guide.subtypeID {
            case nil, "negative":
                known = ["pull", "up", "ups", "chin", "grip", "wide", "close", "narrow", "reverse", "supinated", "biceps",
                         "weighted", "negative", "isometric", "and", "hold", "top", "shoulder", "width", "on", "dip", "cage",
                         "neutral", "parallel", "hammer"]
            case "hang":
                known = ["hanging", "scapular", "shrug", "dead", "hang"]
            default:
                return nil
            }
            guard said.isSubset(of: known) else { return nil }
            let under = !said.isDisjoint(with: ["chin", "reverse", "supinated", "biceps"])
            let neutral = !said.isDisjoint(with: ["neutral", "parallel", "hammer"])
            let narrow = !said.isDisjoint(with: ["close", "narrow"])
            let half = neutral ? (narrow ? 0.12 : 0.26) : said.contains("wide") ? 0.45 : narrow ? 0.1 : under || said.contains("shoulder") ? 0.2 : 0.3
            return BarHangStaging(guide, body, grip: neutral ? .neutral : under ? .under : .over, halfGrip: half)
        case "hanging-leg-raise":
            // Hanging from the bar by both hands and lifting both legs together.
            guard guide.equipment == nil, guide.subtypeID == nil,
                  words(name).isSubset(of: ["hanging", "leg", "hip", "raise", "knee", "straight"]) else { return nil }
            return BarHangStaging(guide, body, grip: .over, halfGrip: 0.28)
        default:
            return nil
        }
    }

    /// A plate hung from the hips for the weighted dips and pull-ups: a belt's straps from the
    /// hips to a ring in front, and the plate on its chain straight under the ring.
    static func beltPlate(_ g: [String: Body3D.M], _ h: [String: Body3D.V]) -> [PropPiece] {
        typealias V = Body3D.V
        guard let pelvis = h["pelvis"] else { return [] }
        let turn = g["pelvis"] ?? .identity
        let ring = pelvis + turn * V(0, -0.125, 0.0)
        let plate = V(0, ring.y - 0.015, ring.z - 0.3)
        var p = [-0.165, 0.165].map { PropPlan.rod(pelvis + turn * V($0, -0.02, 0.05), ring, 0.012, .dark) }
        p.append(PropPlan.rod(ring, plate, 0.005, .metal))
        p.append(PropPlan.disc(plate, axis: V(0, 1, 0), radius: 0.15, thickness: 0.04, .plate))
        return p
    }

    /// The words of an exercise name: "push-up (on knees)" is push, up, on, knees.
    static func words(_ name: String) -> Set<String> {
        Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

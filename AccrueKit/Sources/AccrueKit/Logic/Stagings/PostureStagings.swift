import Foundation

/// A standing family's exercise done seated, kneeling, lying or leaning on a bench, a ball or
/// the floor: the family's poses stand, so the body has to be sat or laid on its support before
/// the arms do their work. Also poses that sit or lie on nothing, which are put down on the
/// floor or given a bench. Asked last, after every group that stages an exercise as a whole.
enum PostureStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        if let support = support(for: guide, body), let staging = PostureStaging(guide, body, support) { return staging }
        if onSide(guide), let staging = PostureSideStaging(guide, body) { return staging }
        if let staging = down(guide, body) { return staging }
        return PostureAsideStaging(guide, body)
    }

    /// Done lying on one side on the floor, by keyframes that stand: the family and subtype
    /// say so, or the name does.
    static func onSide(_ guide: HowToGuide) -> Bool {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        // Kneeling or standing versions, and anything lain on that is not the floor.
        guard !has("kneeling", "standing", "seated", "squat", "bench", "ball", "wall", "cable", "band", "machine", "lever", "smith") else { return false }
        switch (guide.familyID, guide.subtypeID) {
        case ("hip-abduction", nil), ("hip-abduction", "clam"):
            return guide.equipment == nil || guide.equipment == "weighted"
        case ("pilates-mat", "side-kick"):
            return guide.equipment == nil && has("lying")
        case ("shoulder-rotation", "side-lying"), ("lateral-raise", "side-lying"):
            return guide.equipment == nil || guide.equipment == "dumbbell"
        default:
            return false
        }
    }

    /// Stretches whose keyframes sit on nothing with the legs out, by family and subtype.
    static let floorSits: [String: Set<String>] = ["stretch-glute-hip": ["butterfly", "straddle", "seated"]]

    /// A pose that hangs in the air put down: sat or knelt on the floor, or given a bench to
    /// lie on.
    static func down(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        guard guide.equipment == nil else { return nil }
        // Nothing else in the picture: no wall to lean on, no chair, no strap.
        let said = FloorStagings.words(guide.exerciseName)
        guard said.isDisjoint(with: FloorStagings.things) else { return nil }
        switch (guide.familyID, guide.subtypeID) {
        case ("stretch-quad-hip-flexor", "thomas"):
            return PostureTableStaging(guide, body)
        case ("stretch-hamstring", "kneeling"):
            return PostureFloorSitStaging(guide, body, .halfKneeling)
        case (let family, let subtype?) where floorSits[family]?.contains(subtype) == true:
            return said.isDisjoint(with: ["lying", "split", "kneeling"]) ? PostureFloorSitStaging(guide, body) : nil
        default:
            return nil
        }
    }

    /// Families whose own keyframes stand upright and move only the arms, and those that stand
    /// bent over at the hips with the arms hanging.
    static let upright: Set<String> = ["biceps-curl", "front-raise", "lateral-raise", "overhead-press", "triceps-extension",
                                       "shrug", "upright-row"]
    static let bentOver: Set<String> = ["row", "rear-delt-fly", "front-raise", "triceps-extension"]
    /// What the hands may hold: things the plain picture closes them on, with nothing fixed to
    /// the room (a cable's tower would have to move with the body).
    static let loads: Set<String> = ["dumbbell", "barbell", "ez-bar", "kettlebell", "band"]

    /// Families done sitting with nothing drawn to sit on: small movements of the wrists, the
    /// neck and the shoulders, punches, and stretches of the arms and the trunk.
    static let sitters: Set<String> = ["wrist-forearm", "stretch-wrist-forearm", "neck", "shoulder-rotation",
                                       "stretch-chest-shoulder", "stretch-spine", "punch"]
    /// What those hold, if anything.
    static let sitterLoads: Set<String> = ["dumbbell", "barbell", "ez-bar", "weighted"]
    /// What the plain picture may draw for an exercise that is sat or knelt here: things held
    /// in the hands. A bench it already draws is sat on already, and a cable has its tower.
    static let handHeld: Set<PropKind> = [.dumbbell, .barbell, .ezBar, .kettlebell]

    /// A seat for a movement whose name says it is done sitting and whose keyframes stand
    /// upright, or sit on nothing with the feet under the knees.
    static func seat(for guide: HowToGuide, _ body: Body3D) -> PostureStaging.Support? {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard sitters.contains(guide.familyID), has("seated", "sitting"), let first = guide.keyframes.first?.pose else { return nil }
        guard guide.equipment.map(sitterLoads.contains) ?? true, handHeld.isSuperset(of: PropPlan.kinds(for: guide)) else { return nil }
        // Sitting on the floor, or with someone or something else in the picture.
        guard !has("floor", "cross legged", "bent knee", "assisted", "wall", "lying", "kneeling", "ball", "roll") else { return nil }
        let lean = first.angles["trunk"] ?? 0
        if lean <= 12, stands(guide, body) { return .seat(back: false) }
        guard sits(guide), lean >= 0, lean <= 65 else { return nil }
        // Keyframes that sit level through the whole loop are given a seat by the plain picture.
        return PropPlan.sits((0...12).map { body.frame(guide, at: Double($0) / 12) }) ? nil : .seat(back: false)
    }

    /// The keyframes sit on nothing: hips bent, knees at about a right angle.
    static func sits(_ guide: HowToGuide) -> Bool {
        guide.keyframes.allSatisfy { key in
            let hip = key.pose.angles["hipFlex"] ?? 0, knee = key.pose.angles["kneeFlex"] ?? 0
            return hip >= 80 && knee >= 70 && knee <= 110
        }
    }

    /// Kneeling on the floor, for a family that stands upright and moves only the arms.
    static func kneel(for guide: HowToGuide, _ body: Body3D) -> PostureStaging.Support? {
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard has("kneeling"), upright.contains(guide.familyID), let first = guide.keyframes.first?.pose else { return nil }
        guard guide.equipment.map({ loads.contains($0) && $0 != "band" }) ?? true, handHeld.isSuperset(of: PropPlan.kinds(for: guide)) else { return nil }
        // Getting up from the knees, or kneeling on or against something, is another picture.
        guard !has("stand", "get up", "squat", "jump", "lunge", "bench", "ball", "wall", "seated", "lying", "one leg", "single leg") else { return nil }
        guard (first.angles["trunk"] ?? 0) <= 12, stands(guide, body) else { return nil }
        return .kneel(half: has("half kneeling"))
    }

    /// What the name says the body rests on, for an exercise whose keyframes stand.
    static func support(for guide: HowToGuide, _ body: Body3D) -> PostureStaging.Support? {
        if let seat = seat(for: guide, body) { return seat }
        if let kneel = kneel(for: guide, body) { return kneel }
        let name = guide.exerciseName
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        guard let load = guide.equipment, loads.contains(load), let first = guide.keyframes.first?.pose else { return nil }
        // Other pictures: on the side, on the knees, a leg in the air, against a wall, a bench
        // that is only leaned on or stepped onto.
        guard !has("side lying", "kneeling", "leg raised", "one leg", "single leg", "wall", "towel", "between", "decline",
                   "floor", "head below", "head supported", "over the bench", "bench supported", "step", "deadlift", "lunge",
                   "powell") else { return nil }
        guard !has("squat") || has("squat cage") else { return nil }
        // A band runs to the feet, which only a curl's hands stay over; and a shrug's arms hang
        // long, where the thighs of someone sitting leave no room for a bar.
        if load == "band", guide.familyID != "biceps-curl" { return nil }
        if guide.familyID == "shrug", load != "dumbbell" { return nil }
        // A rear raise lying down with one arm is done lying on the side.
        if guide.familyID == "rear-delt-fly", has("lying"), has("one arm") { return nil }
        guard stands(guide, body) else { return nil }
        let lean = first.angles["trunk"] ?? 0
        let bent = lean >= 40
        guard bent ? bentOver.contains(guide.familyID) : lean <= 12 && upright.contains(guide.familyID) else { return nil }

        let faceDown = has("prone", "face down", "chest support")
        if has("seated", "sitting", "chair") && !faceDown && !has("incline") {
            if has("ball") { return bent ? nil : .ball }
            return .seat(back: guide.familyID == "overhead-press")
        }
        if has("ball") { return nil }
        if bent {
            // Bent over with the arms hanging becomes lying face down: flat for "lying", on an
            // incline bench at the keyframes' own lean otherwise.
            if has("lying") && !has("incline") { return .prone(lean: 90) }
            if has("incline") || faceDown { return .prone(lean: min(60, max(45, lean))) }
            return nil
        }
        if faceDown { return guide.familyID == "lateral-raise" ? .prone(lean: 55) : nil }
        if has("lying", "supine") && !has("incline") {
            return ["front-raise", "biceps-curl"].contains(guide.familyID) ? .supine(tilt: 0) : nil
        }
        return nil
    }

    /// The keyframes stand on the feet all loop long, with the hips at standing height.
    static func stands(_ guide: HowToGuide, _ body: Body3D) -> Bool {
        guide.keyframes.allSatisfy { key in
            let p = body.posed(key.pose, contacts: guide.contacts)
            guard p.floor != nil, let pelvis = p.h["pelvis"] else { return false }
            return pelvis.z > 0.8
        }
    }
}

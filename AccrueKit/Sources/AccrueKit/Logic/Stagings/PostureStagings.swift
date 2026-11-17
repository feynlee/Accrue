import Foundation

/// A standing family's exercise done seated, lying or leaning on a bench or a ball: the family's
/// poses stand, so the body has to be sat or laid on its support before the arms do their work.
/// Asked last, after every group that stages an exercise as a whole.
enum PostureStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        if let support = support(for: guide, body), let staging = PostureStaging(guide, body, support) { return staging }
        return PostureAsideStaging(guide, body)
    }

    /// Families whose own keyframes stand upright and move only the arms, and those that stand
    /// bent over at the hips with the arms hanging.
    static let upright: Set<String> = ["biceps-curl", "front-raise", "lateral-raise", "overhead-press", "triceps-extension",
                                       "shrug", "upright-row"]
    static let bentOver: Set<String> = ["row", "rear-delt-fly", "front-raise", "triceps-extension"]
    /// What the hands may hold: things the plain picture closes them on, with nothing fixed to
    /// the room (a cable's tower would have to move with the body).
    static let loads: Set<String> = ["dumbbell", "barbell", "ez-bar", "kettlebell", "band"]

    /// What the name says the body rests on, for an exercise whose keyframes stand.
    static func support(for guide: HowToGuide, _ body: Body3D) -> PostureStaging.Support? {
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

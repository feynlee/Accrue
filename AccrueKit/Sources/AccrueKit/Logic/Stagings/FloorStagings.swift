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
            guard only("crunch floor v 2 negative hold back form check") else { return nil }
            return FloorLyingStaging(guide, body, Setup(feet: .planted, arms: .byHead))
        case ("crunch-sit-up", "sit-up"):
            guard only("sit up v 2 3 4 quarter half full male prisoner") else { return nil }
            return FloorLyingStaging(guide, body, Setup(sitsUp: true, feet: .planted, arms: .byHead))
        case ("lying-leg-raise", nil):
            // Both legs straight, lifted together.
            guard only("lying leg raise v 2 3 straight and hold full") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: .onFloor))
        case ("lying-leg-raise", "reverse-crunch"):
            guard only("reverse crunch v 2 3 tuck lying hip raise bent knee leg on floor flat") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: .onFloor))
        case ("lying-leg-raise", "flutter"):
            // Straight legs beating up and down in turn; legs that cross are another picture.
            guard only("flutter kicks kick v 2 3 lying scissor scissors simultaneous alternating alternate leg raise",
                       "straight floor beginner advanced marches") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, arms: .onFloor))
        case ("lying-leg-raise", "v-up"):
            guard only("v up jackknife sit hold") else { return nil }
            return FloorLyingStaging(guide, body, Setup(sitsUp: true))
        case ("hip-thrust-bridge", "glute-bridge"):
            // Shoulders on the floor, both feet flat, hips rising.
            guard only("butt bridge hip raise v 2 glute two legs on floor low") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, feet: .underKnees, arms: .onFloor))
        case ("hip-thrust-bridge", "hamstring-bridge"):
            guard only("hamstring bridge v 2 straight leg hip glute heel") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest, feet: .planted, arms: .onFloor))
        case ("dead-bug-bird-dog", nil):
            guard only("dead bug v 2 3") else { return nil }
            return FloorLyingStaging(guide, body, Setup(anchor: .chest))
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
            return nil
        }
    }

    /// The words of an exercise name: "sit-up (arms on chest)" is sit, up, arms, on, chest.
    static func words(_ name: String) -> Set<String> {
        Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

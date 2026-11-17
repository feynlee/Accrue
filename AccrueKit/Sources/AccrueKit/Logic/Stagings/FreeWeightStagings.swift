import Foundation

/// Standing with a bar, dumbbells or kettlebells: deadlift, row, curl, raise, overhead press, clean, snatch, carry.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum FreeWeightStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

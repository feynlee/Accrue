import Foundation

/// Cardio and conditioning equipment: treadmill, bike, rower, elliptical, ski erg, stairs, sled, ropes.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum CardioStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

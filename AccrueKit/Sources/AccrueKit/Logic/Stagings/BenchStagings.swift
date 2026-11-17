import Foundation

/// Lying or sitting on a bench with a bar or dumbbells: bench press, fly, pullover, lying triceps extension, hip thrust.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum BenchStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

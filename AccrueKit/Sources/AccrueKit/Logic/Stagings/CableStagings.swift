import Foundation

/// Standing or kneeling at a cable stack: pushdown, face pull, cable curl, cable fly, woodchop, and the rest of the pulldown and seated row families.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum CableStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

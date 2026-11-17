import Foundation

/// A standing family's exercise done seated, lying or leaning on a bench or a ball: the family's
/// poses stand, so the body has to be sat or laid on its support before the arms do their work.
/// Asked last, after every group that stages an exercise as a whole.
enum PostureStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

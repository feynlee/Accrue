import Foundation

/// Sitting or lying in a machine: leg press, leg curl, leg extension, pec deck, machine press, seated calf raise.
/// Each exercise is staged as BodyStaging describes: the equipment first, the body fitted to it.
enum MachineStagings {
    static func make(_ guide: HowToGuide, _ body: Body3D) -> (any BodyStaging)? {
        nil
    }
}

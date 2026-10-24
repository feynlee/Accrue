import AccrueKit
import SwiftUI

/// A small front or back body map with the working muscles lit: lime for the main ones,
/// dark lime for the helpers. It picks the side that shows more of the main muscles.
struct MuscleMap: View {
    @Environment(\.palette) private var palette
    let muscles: MuscleSet

    private struct Region {
        let ids: [String]
        let points: [CGPoint]
    }

    // Right half of a 100 × 160 body (the viewer's right), mirrored for the other side.
    private static func r(_ ids: [String], _ xy: [(CGFloat, CGFloat)]) -> Region {
        Region(ids: ids, points: xy.map { CGPoint(x: $0.0, y: $0.1) })
    }

    private static let front: [Region] = [
        r(["upper-traps", "levator-scapulae", "neck-flexors"], [(51, 19), (55, 18), (62, 24), (51, 25)]),
        r(["front-delts", "side-delts", "rotator-cuff"], [(62, 24), (70, 25), (73, 36), (64, 36)]),
        r(["chest", "pec-minor"], [(51, 26), (62, 25), (64, 36), (60, 42), (51, 42)]),
        r(["upper-chest"], [(51, 26), (62, 25), (63, 30), (51, 31)]),
        r(["serratus-anterior"], [(60, 43), (65, 38), (66, 48), (61, 50)]),
        r(["biceps", "brachialis"], [(66, 38), (73, 37), (74, 56), (67, 57)]),
        r(["brachioradialis", "wrist-flexors", "wrist-extensors"], [(67, 59), (74, 58), (76, 80), (70, 81)]),
        r(["abs", "deep-core", "breathing"], [(51, 44), (59, 44), (58, 74), (51, 74)]),
        r(["obliques"], [(60, 51), (66, 49), (65, 70), (59, 74)]),
        r(["hip-flexors"], [(52, 76), (60, 75), (57, 82), (52, 82)]),
        r(["adductors"], [(51, 84), (56, 82), (55, 104), (51, 100)]),
        r(["quads"], [(57, 82), (66, 76), (67, 110), (57, 112)]),
        r(["shins", "peroneals"], [(57, 118), (64, 118), (63, 146), (58, 146)]),
        r(["foot"], [(57, 148), (64, 148), (66, 154), (57, 154)]),
    ]

    private static let back: [Region] = [
        r(["upper-traps", "levator-scapulae", "neck-extensors"], [(51, 18), (56, 18), (64, 24), (51, 26)]),
        r(["mid-traps"], [(51, 26), (64, 25), (58, 30), (51, 30)]),
        r(["rear-delts", "side-delts", "rotator-cuff"], [(64, 24), (71, 26), (73, 36), (65, 35)]),
        r(["rhomboids"], [(51, 30), (58, 30), (58, 40), (51, 42)]),
        r(["lower-traps"], [(51, 42), (58, 40), (54, 52), (51, 54)]),
        r(["lats"], [(58, 32), (66, 36), (65, 58), (56, 66), (55, 48)]),
        r(["triceps"], [(66, 38), (73, 37), (74, 56), (67, 57)]),
        r(["brachioradialis", "wrist-extensors", "wrist-flexors"], [(67, 59), (74, 58), (76, 80), (70, 81)]),
        r(["lower-back"], [(51, 56), (55, 54), (56, 72), (51, 74)]),
        r(["glutes", "glute-med", "hip-rotators"], [(51, 76), (64, 74), (66, 92), (52, 94)]),
        r(["hamstrings", "adductors"], [(52, 96), (66, 94), (65, 118), (56, 118)]),
        r(["calves", "soleus"], [(56, 120), (64, 120), (63, 142), (57, 144)]),
        r(["foot"], [(57, 148), (64, 148), (66, 154), (57, 154)]),
    ]

    private static func score(_ regions: [Region], _ ids: [String]) -> Int {
        ids.filter { id in regions.contains { $0.ids.contains(id) } }.count
    }

    var showsBack: Bool {
        Self.score(Self.back, muscles.primary) > Self.score(Self.front, muscles.primary)
    }

    var body: some View {
        let regions = showsBack ? Self.back : Self.front
        let main = Color(hex: 0xC6F432), helper = Color(hex: 0x6E8A1E), idle = Color(hex: 0x3A3E46)
        VStack(spacing: 2) {
            Canvas { context, size in
                let s = min(size.width / 100, size.height / 160)
                let dx = (size.width - 100 * s) / 2
                func pt(_ p: CGPoint, mirrored: Bool) -> CGPoint {
                    CGPoint(x: dx + (mirrored ? 100 - p.x : p.x) * s, y: p.y * s)
                }
                let head = Path(ellipseIn: CGRect(x: dx + 43 * s, y: 2 * s, width: 14 * s, height: 15 * s))
                context.fill(head, with: .color(idle))
                for region in regions {
                    let fill: Color = region.ids.contains(where: muscles.primary.contains) ? main
                        : region.ids.contains(where: muscles.secondary.contains) ? helper : idle
                    for mirrored in [false, true] {
                        var path = Path()
                        path.addLines(region.points.map { pt($0, mirrored: mirrored) })
                        path.closeSubpath()
                        context.fill(path, with: .color(fill))
                    }
                }
            }
            Text(showsBack ? "back view" : "front view")
                .font(.inter(9))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(showsBack ? "Back" : "Front") view of the body with the working muscles lit")
    }
}

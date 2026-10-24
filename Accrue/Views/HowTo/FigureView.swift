import AccrueKit
import SwiftUI

/// Inks for the figure, drawn on the light demo panel in both themes.
enum FigureInk {
    static let body = Color(hex: 0x2A2D33)
    static let far = Color(hex: 0x9AA0AA)
    static let ground = Color(hex: 0xC9CDD4)
    static let working = Color(hex: 0x5E8A00)
    static let fault = Color(hex: 0xE5484D)
}

/// The figure's limbs, so working muscles can colour the right ones.
enum FigureSegment: Hashable {
    case trunk, upperArm, forearm, thigh, shank

    /// Which segments a muscle group mostly moves or braces.
    static func segments(for muscle: String) -> [FigureSegment] {
        switch muscle {
        case "chest", "upper-chest", "pec-minor", "front-delts", "side-delts", "rear-delts", "rotator-cuff",
             "triceps", "biceps", "brachialis":
            [.upperArm]
        case "brachioradialis", "wrist-flexors", "wrist-extensors":
            [.forearm]
        case "lats", "upper-traps", "mid-traps", "lower-traps", "rhomboids", "serratus-anterior", "levator-scapulae",
             "abs", "obliques", "deep-core", "lower-back", "neck-flexors", "neck-extensors":
            [.trunk]
        case "glutes", "glute-med", "hip-rotators", "hip-flexors", "adductors", "quads", "hamstrings":
            [.thigh]
        case "calves", "soleus", "shins", "peroneals", "foot":
            [.shank]
        default:
            []
        }
    }
}

/// Draws one frame of a how-to guide's figure, scaled so the whole loop fits the box.
struct FigureCanvas: View {
    let guide: HowToGuide
    let t: Double
    /// A mistake to draw in red over the faded good pose.
    var fault: Mistake?
    var showMuscles = true

    var body: some View {
        let bounds = FigureBounds.of(guide)
        let working: Set<FigureSegment> = showMuscles && guide.bodyModel == "anatomy"
            ? Set(guide.muscles.primary.flatMap(FigureSegment.segments(for:))) : []
        Canvas { context, size in
            let pose = Figure.interpolate(guide.keyframes, at: t)
            let fit = bounds.fit(in: size)
            if let ground = Figure.pose(pose, contacts: guide.contacts).groundY {
                let y = fit.map(FigurePoint(0, ground)).y
                var line = Path()
                line.move(to: CGPoint(x: 8, y: y + fit.scale * 0.012))
                line.addLine(to: CGPoint(x: size.width - 8, y: y + fit.scale * 0.012))
                context.stroke(line, with: .color(FigureInk.ground), lineWidth: max(2, fit.scale * 0.012))
            }
            if let fault, let change = fault.pose {
                draw(Figure.pose(pose, contacts: guide.contacts), in: &context, fit: fit, working: [], faded: true)
                let bad = Figure.pose(Figure.applying(change, to: pose), contacts: guide.contacts)
                draw(bad, in: &context, fit: fit, working: [], tint: FigureInk.fault)
            } else {
                draw(Figure.pose(pose, contacts: guide.contacts), in: &context, fit: fit, working: working)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ p: FigurePose, in context: inout GraphicsContext, fit: FigureFit, working: Set<FigureSegment>,
                      faded: Bool = false, tint: Color? = nil) {
        let s = fit.scale
        let ink = tint ?? (faded ? FigureInk.far.opacity(0.55) : FigureInk.body)
        let farInk = tint.map { $0.opacity(0.45) } ?? (faded ? FigureInk.far.opacity(0.35) : FigureInk.far)
        let hot = tint ?? FigureInk.working

        func line(_ a: FigureJoint, _ b: FigureJoint, _ width: Double, _ color: Color) {
            var path = Path()
            path.move(to: fit.map(p[a]))
            path.addLine(to: fit.map(p[b]))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
        }
        func color(_ seg: FigureSegment) -> Color { working.contains(seg) ? hot : ink }

        // Far side first, then the trunk and head, then the near side on top.
        line(.hip, .kneeL, 0.042, farInk); line(.kneeL, .ankleL, 0.036, farInk)
        line(.heelL, .toeL, 0.026, farInk); line(.ankleL, .heelL, 0.026, farInk)
        line(.shoulder, .elbowL, 0.034, farInk); line(.elbowL, .wristL, 0.03, farInk); line(.wristL, .handL, 0.026, farInk)

        line(.hip, .midBack, 0.06, color(.trunk)); line(.midBack, .shoulder, 0.064, color(.trunk))
        line(.shoulder, .neck, 0.034, ink)
        let head = fit.map(p[.head])
        let r = Figure.headSize * s
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: .color(ink))

        line(.hip, .knee, 0.046, color(.thigh)); line(.knee, .ankle, 0.038, color(.shank))
        line(.heel, .toe, 0.028, ink); line(.ankle, .heel, 0.028, ink)
        line(.shoulder, .elbow, 0.038, color(.upperArm)); line(.elbow, .wrist, 0.032, color(.forearm))
        line(.wrist, .hand, 0.028, ink)
    }
}

/// How body-height units map to points in a box.
struct FigureFit {
    var scale: Double
    var origin: CGPoint

    func map(_ p: FigurePoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y - p.y * scale)
    }
}

/// The box every frame of a guide's loop (and its mistakes) fits in, so the figure does not
/// jump in size as it moves.
struct FigureBounds {
    var minX, maxX, minY, maxY: Double

    @MainActor private static var cache: [String: FigureBounds] = [:]

    @MainActor static func of(_ guide: HowToGuide) -> FigureBounds {
        let key = guide.name
        if let hit = cache[key] { return hit }
        var b = FigureBounds(minX: .infinity, maxX: -.infinity, minY: .infinity, maxY: -.infinity)
        var poses = (0...20).map { Figure.interpolate(guide.keyframes, at: Double($0) / 20) }
        for step in guide.steps {
            for m in step.mistakes {
                if let change = m.pose { poses.append(Figure.applying(change, to: Figure.interpolate(guide.keyframes, at: guide.faultT))) }
            }
        }
        for pose in poses {
            let p = Figure.pose(pose, contacts: guide.contacts)
            for point in p.joints.values {
                b.minX = min(b.minX, point.x); b.maxX = max(b.maxX, point.x)
                b.minY = min(b.minY, point.y); b.maxY = max(b.maxY, point.y)
            }
            if let g = p.groundY { b.minY = min(b.minY, g) }
        }
        // Room for the head and line caps.
        b.minX -= 0.09; b.maxX += 0.09; b.minY -= 0.03; b.maxY += 0.09
        cache[key] = b
        return b
    }

    func fit(in size: CGSize, padding: CGFloat = 14) -> FigureFit {
        let w = max(0.1, maxX - minX), h = max(0.1, maxY - minY)
        let scale = min((size.width - 2 * padding) / w, (size.height - 2 * padding) / h)
        let left = (size.width - w * scale) / 2
        let bottom = size.height - (size.height - h * scale) / 2
        return FigureFit(scale: scale, origin: CGPoint(x: left - minX * scale, y: bottom + minY * scale))
    }
}

/// The figure playing a part of its loop: the whole rep, or one step's phase, at a speed.
struct AnimatedFigure: View {
    let guide: HowToGuide
    var window: ClosedRange<Double> = 0...1
    var speed: Double = 1
    var playing = true
    var fault: Mistake?
    var showMuscles = true
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(paused: !playing || window.lowerBound == window.upperBound)) { context in
            FigureCanvas(guide: guide, t: t(at: context.date), fault: fault, showMuscles: showMuscles)
        }
        .onChange(of: window) { started = Date() }
    }

    /// Plays the window, then holds its last pose a moment before starting again.
    private func t(at date: Date) -> Double {
        let span = window.upperBound - window.lowerBound
        guard span > 0, guide.seconds > 0 else { return window.upperBound }
        let run = span * guide.seconds / max(0.1, speed)
        let hold = span < 1 ? 0.6 / max(0.1, speed) : 0
        let elapsed = date.timeIntervalSince(started).truncatingRemainder(dividingBy: run + hold)
        return window.lowerBound + span * min(1, elapsed / run)
    }
}

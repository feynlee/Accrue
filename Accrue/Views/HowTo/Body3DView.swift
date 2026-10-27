import AccrueKit
import RealityKit
import SwiftUI
import UIKit
import os

/// The exercise on the 3D body (Z-Anatomy, CC BY-SA 4.0): gray muscles with the working ones in
/// lime, Glass to see the bones through them, or the dressed skin for cardio. Falls back to the
/// 2D figure while the model loads or if it cannot.
struct ExerciseDemo: View {
    let guide: HowToGuide
    var window: ClosedRange<Double> = 0...1
    var speed: Double = 1
    var playing = true
    var fault: Mistake?
    var showMuscles = true
    /// Drag to turn, pinch to zoom, two fingers to move, double tap to reset.
    var interactive = false
    var glass = false

    @State private var loaded = BodyAsset.shared.isReady

    var body: some View {
        Group {
            if loaded, BodyAsset.shared.body3D != nil {
                Body3DView(guide: guide, window: window, speed: speed, playing: playing, fault: fault,
                           showMuscles: showMuscles, interactive: interactive, glass: glass)
            } else {
                AnimatedFigure(guide: guide, window: window, speed: speed, playing: playing, fault: fault,
                               showMuscles: showMuscles)
            }
        }
        .task {
            guard !loaded else { return }
            loaded = await BodyAsset.shared.prepare()
        }
    }
}

/// Loads the body once; every demo gets its own copy that shares the meshes.
@MainActor
final class BodyAsset {
    static let shared = BodyAsset()
    let rig: BodyRig? = try? BodyRig.bundled()
    lazy var body3D: Body3D? = rig.map(Body3D.init(rig:))
    /// Part names by roughness tag: material roughness (i + 1) / 100 is part i (pack_usdz.py).
    let partNames: [String] = Bundle.main.url(forResource: "body-parts", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    private var template: Entity?
    private var loading: Task<Entity?, Never>?

    var isReady: Bool { template != nil }

    func prepare() async -> Bool {
        if template != nil { return true }
        if loading == nil {
            loading = Task { try? await Entity(named: "Body", in: .main) }
        }
        template = await loading?.value
        return template != nil
    }

    func copy() -> Entity? { template?.clone(recursive: true) }
}

/// Colours on the light demo panel.
private enum BodyInk {
    static let muscle = UIColor(rgb: 0xA4A9B2)
    static let main = UIColor(rgb: 0xC6F432)
    static let helps = UIColor(rgb: 0x8DB51E)
    static let bone = UIColor(rgb: 0xEAE4D3)
    static let skin = UIColor(rgb: 0xD9D6D0)
    static let top = UIColor(rgb: 0xC6F432)
    static let shorts = UIColor(rgb: 0x292E36)
    static let shoes = UIColor(rgb: 0x30333B)
    static let floor = UIColor(rgb: 0xC9CDD4)
    static let bar = UIColor(rgb: 0x4A4F58)
    static let fault = UIColor(rgb: 0xE5484D)
}

struct Body3DView: View {
    let guide: HowToGuide
    var window: ClosedRange<Double>
    var speed: Double
    var playing: Bool
    var fault: Mistake?
    var showMuscles: Bool
    var interactive: Bool
    var glass: Bool

    @State private var scene = BodyScene()

    var body: some View {
        GeometryReader { geo in
            RealityView { content in
                content.camera = .virtual
                content.add(scene.root)
                scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [scene] _ in
                    MainActor.assumeIsolated { scene.tick() }
                }
            } update: { _ in
                scene.configure(guide: guide, window: window, speed: speed, playing: playing, fault: fault?.pose,
                                showMuscles: showMuscles, glass: glass, size: geo.size)
            }
            .modifier(Controls(on: interactive, scene: scene, size: geo.size))
        }
        .accessibilityHidden(true)
    }

}

/// Drag to turn, pinch to zoom, two fingers to move, double tap to reset.
private struct Controls: ViewModifier {
    let on: Bool
    let scene: BodyScene
    let size: CGSize
    @State private var dragStart: SIMD2<Float>?
    @State private var zoomStart: Float?

    func body(content: Content) -> some View {
        if on {
            content
                .gesture(turnAndZoom)
                .gesture(TwoFingerPan { scene.move($0, in: size) })
                .onTapGesture(count: 2) { scene.resetView() }
        } else {
            content
        }
    }

    private var turnAndZoom: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStart ?? scene.angles
                    if dragStart == nil { dragStart = start }
                    scene.angles = SIMD2(start.x - Float(value.translation.width) * 0.008,
                                         min(1.2, max(-0.6, start.y + Float(value.translation.height) * 0.006)))
                    scene.updateCamera()
                }
                .onEnded { _ in dragStart = nil },
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? scene.zoom
                    if zoomStart == nil { zoomStart = start }
                    scene.zoom = min(4, max(0.6, start * Float(value.magnification)))
                    scene.updateCamera()
                }
                .onEnded { _ in zoomStart = nil })
    }
}

/// Two-finger drag, for moving the view while one finger turns it.
private struct TwoFingerPan: UIGestureRecognizerRepresentable {
    var moved: (CGSize) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let t = recognizer.translation(in: recognizer.view)
        moved(CGSize(width: t.x, height: t.y))
        recognizer.setTranslation(.zero, in: recognizer.view)
    }
}

/// The scene behind one demo: the posed body, a floor or bar, lights and an orbiting camera.
@MainActor
final class BodyScene {
    let root = Entity()
    var subscription: EventSubscription?
    var angles = SIMD2<Float>(-1.2, 0.12)  // yaw, pitch: the right side, a little from the front
    var zoom: Float = 1

    private let body3D = BodyAsset.shared.body3D
    private let log = Logger(subsystem: "com.feynlee.Accrue", category: "Body3D")
    private var model: Entity?
    private let camera = PerspectiveCamera()
    private let floor = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.8),
                                    materials: [SimpleMaterial(color: BodyInk.floor, roughness: 1, isMetallic: false)])
    private let bar = ModelEntity(mesh: .generateCylinder(height: 1.3, radius: 0.016),
                                  materials: [SimpleMaterial(color: BodyInk.bar, roughness: 0.4, isMetallic: true)])
    private var skinned: [(entity: ModelEntity, rest: [Transform], bones: [String])] = []
    /// Every material slot of every mesh, with the body part it draws ("m_chest", "bones").
    private var slots: [(entity: ModelEntity, index: Int, part: String)] = []
    /// Blender's Z-up axes to the model's, and the pelvis joint at rest.
    private var toModel = simd_quatf(angle: 0, axis: [1, 0, 0])
    private var restPelvis = SIMD3<Float>.zero

    private var guide: HowToGuide?
    private var window: ClosedRange<Double> = 0...1
    private var speed = 1.0
    private var playing = true
    private var fault: JointPose?
    private var look: String = ""
    private var started = Date()
    private var center = SIMD3<Float>(0, 0.9, 0)
    private var radius: Float = 1.1
    private var offset = SIMD2<Float>.zero
    private var aspect: Float = 1

    init() {
        camera.camera.fieldOfViewInDegrees = 30
        root.addChild(camera)
        bar.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        root.addChild(floor)
        root.addChild(bar)
        let key = DirectionalLight()
        key.light.intensity = 2600
        key.look(at: .zero, from: [-1.5, 3, 2], relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 1100
        fill.look(at: .zero, from: [2, 1, -1.5], relativeTo: nil)
        let under = DirectionalLight()
        under.light.intensity = 500
        under.look(at: .zero, from: [0.5, -2, 1], relativeTo: nil)
        root.addChild(key)
        root.addChild(fill)
        root.addChild(under)
        if let body = BodyAsset.shared.copy() {
            attach(body)
        }
    }

    private func attach(_ body: Entity) {
        // The file is Z-up: stand it up unless the loader already did.
        let bounds = body.visualBounds(relativeTo: nil).extents
        let holder = Entity()
        if bounds.z > bounds.y {
            holder.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        }
        holder.addChild(body)
        root.addChild(holder)
        model = holder

        var all: [Entity] = [body]
        while let e = all.popLast() {
            all.append(contentsOf: e.children)
            guard let m = e as? ModelEntity else { continue }
            // RealityKit can merge meshes and drop names, so each material carries its part as a
            // roughness tag; the mesh's own name is the fallback.
            let names = BodyAsset.shared.partNames
            for (i, material) in (m.model?.materials ?? []).enumerated() {
                var part = [m.name, m.parent?.name ?? ""].first { names.contains($0) } ?? ""
                if let pbr = material as? PhysicallyBasedMaterial {
                    let tag = Int((pbr.roughness.scale * 100).rounded()) - 1
                    if names.indices.contains(tag) { part = names[tag] }
                }
                slots.append((m, i, part))
            }
            log.debug("mesh \(m.name, privacy: .public) under \(m.parent?.name ?? "-", privacy: .public): \(m.model?.materials.count ?? 0) materials, \(m.jointNames.count) joints")
            if !m.jointNames.isEmpty {
                let bones = m.jointNames.map { ($0.split(separator: "/").last.map(String.init) ?? $0).replacingOccurrences(of: "_", with: ".") }
                skinned.append((m, m.jointTransforms, bones))
            }
        }
        // The pelvis joint at rest tells how the file's skeleton sits against Blender's axes.
        if let first = skinned.first, let i = first.bones.firstIndex(of: "pelvis"),
           let rig = BodyAsset.shared.rig?.bones.first(where: { $0.name == "pelvis" }), let r = rig.rest, r.count == 9 {
            let f = r.map { Float($0) }
            let row0 = SIMD3<Float>(f[0], f[1], f[2])
            let row1 = SIMD3<Float>(f[3], f[4], f[5])
            let row2 = SIMD3<Float>(f[6], f[7], f[8])
            toModel = first.rest[i].rotation * simd_quatf(simd_float3x3(rows: [row0, row1, row2])).inverse
            let head = SIMD3<Float>(Float(rig.head[0]), Float(rig.head[1]), Float(rig.head[2]))
            restPelvis = first.rest[i].translation - toModel.act(head)
        }
        let found = Set(slots.map(\.part))
        log.notice("body: \(self.slots.count) material slots, \(found.count) parts known, \(self.skinned.count) skinned meshes")
    }

    func configure(guide: HowToGuide, window: ClosedRange<Double>, speed: Double, playing: Bool, fault: JointPose?,
                   showMuscles: Bool, glass: Bool, size: CGSize) {
        if self.guide?.name != guide.name || self.guide?.keyframes != guide.keyframes {
            self.guide = guide
            frameCamera(guide)
            look = ""
        }
        if self.window != window { started = Date() }
        self.window = window
        self.speed = speed
        self.playing = playing
        self.fault = fault
        aspect = size.height > 0 ? Float(size.width / size.height) : 1
        let want = "\(guide.bodyModel)|\(showMuscles)|\(glass)|\(fault != nil)|\(guide.muscles.primary)|\(guide.muscles.secondary)"
        if want != look {
            look = want
            paint(guide, showMuscles: showMuscles, glass: glass, fault: fault != nil)
        }
        updateCamera()
        tick()
    }

    // MARK: Look

    private func material(_ color: UIColor, roughness: Float = 0.65, opacity: Float = 1) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    private func paint(_ guide: HowToGuide, showMuscles: Bool, glass: Bool, fault: Bool) {
        let skinOnly = guide.bodyModel != "anatomy"
        let main = Set(guide.muscles.primary.map { "m_" + $0.replacingOccurrences(of: "-", with: "_") })
        let helps = Set(guide.muscles.secondary.map { "m_" + $0.replacingOccurrences(of: "-", with: "_") })
        // Unlit, so no highlight shows the hidden part's edges.
        var hidden = UnlitMaterial(color: .clear)
        hidden.blending = .transparent(opacity: .init(floatLiteral: 0))
        var cache: [String: RealityKit.Material] = [:]

        func look(_ part: String) -> RealityKit.Material? {
            switch part {
            case "skin_body": return skinOnly ? material(BodyInk.skin, roughness: 0.6) : nil
            case "skin_top": return skinOnly ? material(BodyInk.top, roughness: 0.8) : nil
            case "skin_shorts": return skinOnly ? material(BodyInk.shorts, roughness: 0.7) : nil
            case "skin_shoes": return skinOnly ? material(BodyInk.shoes, roughness: 0.5) : nil
            case "head": return skinOnly ? nil : material(BodyInk.skin, opacity: glass ? 0.25 : 1)
            case "bones": return !skinOnly && glass ? material(BodyInk.bone, roughness: 0.5) : nil
            default:
                guard !skinOnly, part.hasPrefix("m_") else { return nil }
                let isMain = showMuscles && main.contains(part), isHelp = showMuscles && helps.contains(part)
                let hot = fault ? BodyInk.fault : isMain ? BodyInk.main : BodyInk.helps
                let color = isMain || isHelp ? hot : BodyInk.muscle
                let opacity: Float = glass ? (isMain || isHelp ? 0.7 : 0.3) : 1
                return material(color, roughness: 0.55, opacity: opacity)
            }
        }

        var byEntity: [ObjectIdentifier: (ModelEntity, [RealityKit.Material], Bool)] = [:]
        for slot in slots {
            let key = ObjectIdentifier(slot.entity)
            var entry = byEntity[key] ?? (slot.entity, slot.entity.model?.materials ?? [], false)
            if cache[slot.part] == nil { cache[slot.part] = look(slot.part) ?? hidden }

            let m = cache[slot.part]!
            if entry.1.indices.contains(slot.index) { entry.1[slot.index] = m }
            if look(slot.part) != nil { entry.2 = true }
            byEntity[key] = entry
        }
        for (entity, materials, anyVisible) in byEntity.values {
            entity.model?.materials = materials
            entity.isEnabled = anyVisible
        }
    }

    // MARK: Motion

    func tick() {
        guard let guide, let body3D, !skinned.isEmpty else { return }
        let frame = body3D.frame(guide, at: t(at: Date(), guide), fault: fault)
        let root = SIMD3(Float(frame.root[0]), Float(frame.root[1]), Float(frame.root[2]))
        for (entity, rest, bones) in skinned {
            var joints = rest
            for (i, bone) in bones.enumerated() {
                guard let q = frame.local[bone] else { continue }
                joints[i].rotation = rest[i].rotation * simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
                if bone == "pelvis" { joints[i].translation = restPelvis + toModel.act(root) }
            }
            entity.jointTransforms = joints
        }
        floor.isEnabled = frame.floor != nil
        bar.isEnabled = frame.floor == nil && guide.contacts.contains { $0.lowercased() == "bar" }
        if bar.isEnabled, let hand = frame.heads["f3a.r"] {
            bar.position = [0, Float(hand[2]) + 0.01, -Float(hand[1])]
        }
    }

    /// Plays the window, then holds its last pose a moment before starting again (as the 2D figure).
    private func t(at date: Date, _ guide: HowToGuide) -> Double {
        let span = window.upperBound - window.lowerBound
        guard span > 0, guide.seconds > 0 else { return window.upperBound }
        guard playing else { return pausedT ?? window.lowerBound }
        let run = span * guide.seconds / max(0.1, speed)
        let hold = span < 1 ? 0.6 / max(0.1, speed) : 0
        let elapsed = date.timeIntervalSince(started).truncatingRemainder(dividingBy: run + hold)
        let t = window.lowerBound + span * min(1, elapsed / run)
        pausedT = t
        return t
    }

    private var pausedT: Double?

    // MARK: Camera

    /// Fits the whole loop: the body's joints over the rep, plus room for the flesh around them.
    private func frameCamera(_ guide: HowToGuide) {
        guard let body3D else { return }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for i in 0...12 {
            let f = body3D.frame(guide, at: Double(i) / 12)
            for h in f.heads.values {
                let p = SIMD3(Float(h[0]), Float(h[2]), -Float(h[1]))
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
        }
        lo -= 0.14
        hi += 0.14
        lo.y = max(lo.y, -0.02)
        center = (lo + hi) / 2
        // A floor disc just under the body, so it stays in the picture.
        let reach = max(0.35, max(hi.x - lo.x, hi.z - lo.z) / 2 + 0.1)
        floor.position = [center.x, 0, center.z]
        floor.scale = [reach / 0.8, 1, reach / 0.8]
        radius = max(0.45, simd_length(hi - lo) * 0.42)
        offset = .zero
    }

    func resetView() {
        angles = SIMD2(-1.2, 0.12)
        zoom = 1
        offset = .zero
        updateCamera()
    }

    func move(_ delta: CGSize, in size: CGSize) {
        let scale = 2 * radius / zoom / Float(max(1, min(size.width, size.height)))
        offset += SIMD2(Float(-delta.width), Float(delta.height)) * scale
        updateCamera()
    }

    func updateCamera() {
        let fovY: Float = 30 * .pi / 180
        let fov = min(fovY, 2 * atan(tan(fovY / 2) * aspect))
        let distance = radius / sin(fov / 2) / zoom
        let (yaw, pitch) = (angles.x, angles.y)
        let dir = SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), dir))
        let up = simd_cross(dir, right)
        let target = center + right * offset.x + up * offset.y
        camera.look(at: target, from: target + dir * distance, relativeTo: nil)
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

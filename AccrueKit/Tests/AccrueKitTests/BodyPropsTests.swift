import Foundation
import Testing
@testable import AccrueKit

struct BodyPropsTests {
    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    func guide(_ name: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
        return try #require(catalog.howTo(for: ex))
    }

    @Test func readsTheEquipment() throws {
        #expect(PropPlan(guide: try guide("barbell bench press"), body: body).kinds == [.barbell, .bench])
        #expect(PropPlan(guide: try guide("cable bar lateral pulldown"), body: body).kinds.contains(.pulldown))
        #expect(PropPlan(guide: try guide("run on treadmill"), body: body).kinds == [.treadmill])
        #expect(PropPlan(guide: try guide("dumbbell lateral raise"), body: body).kinds == [.dumbbell])
    }

    @Test func benchPressLiesOnABench() throws {
        let plan = PropPlan(guide: try guide("barbell bench press"), body: body)
        let (f, props) = plan.frame(at: 0)
        let pad = try #require(props.first { $0.finish == .pad })
        // The pad's top is just under the back.
        let top = pad.center[2] + pad.size[2] / 2
        #expect(abs(top - (f.heads["thorax"]![2] - 0.1)) < 0.08, "pad top \(top)")
        // The bar is in the hands, across the body.
        let bar = try #require(props.first { $0.shape == .cylinder && $0.size[2] > 1.9 })
        let hand = f.heads["f3a.r"]!
        #expect(abs(bar.center[2] - hand[2]) < 0.1)
    }

    @Test func treadmillRaisesTheRunner() throws {
        let plan = PropPlan(guide: try guide("run on treadmill"), body: body)
        #expect(plan.lift > 0.1)
        #expect(plan.frame(at: 0).props.count >= 4)
    }

    @Test func everyFamilyGetsFiniteProps() throws {
        var seen = Set<String>()
        for ex in catalog.exercises {
            guard let fam = ex.familyID, seen.insert(fam).inserted, let g = catalog.howTo(for: ex) else { continue }
            let plan = PropPlan(guide: g, body: body)
            for t in [0.0, 0.5] {
                let (_, props) = plan.frame(at: t)
                #expect(props.allSatisfy { ($0.center + $0.size).allSatisfy(\.isFinite) }, "\(fam)")
            }
            #expect(plan.framing.radius.isFinite && plan.framing.yaw.isFinite)
        }
    }

    /// BODY_DUMP=/path writes frames, props and framing for a sample of exercises, for the
    /// offline renderer in Body/anatomy/render_app.py.
    @Test func dumpForRenderer() throws {
        guard let path = ProcessInfo.processInfo.environment["BODY_DUMP"] else { return }
        let only = ProcessInfo.processInfo.environment["BODY_DUMP_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var perFamily: [String: [String: Int]] = [:]
        var out: [[String: Any]] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let fam = ex.familyID else { continue }
            if let only, !only.contains(fam), !only.contains(ex.id) { continue }
            let key = ex.equipment ?? "-"
            var seen = perFamily[fam, default: [:]]
            if seen[key] != nil || seen.count >= (only == nil ? 2 : 6) { continue }
            seen[key] = 1
            perFamily[fam] = seen
            guard let g = catalog.howTo(for: ex) else { continue }
            let plan = PropPlan(guide: g, body: body)
            var frames: [[String: Any]] = []
            for t in [0.0, 0.5] {
                let (f, props) = plan.frame(at: t)
                frames.append([
                    "t": t,
                    "root": f.root,
                    "local": f.local.mapValues { [$0.w, $0.x, $0.y, $0.z] },
                    "props": props.map { ["shape": $0.shape.rawValue, "finish": $0.finish.rawValue, "center": $0.center,
                                          "size": $0.size, "q": [$0.rotation.w, $0.rotation.x, $0.rotation.y, $0.rotation.z]] },
                ])
            }
            out.append(["id": ex.id, "name": ex.name, "family": fam, "model": g.bodyModel,
                        "kinds": plan.kinds.map(\.rawValue), "lift": plan.lift,
                        "framing": ["center": plan.framing.center, "radius": plan.framing.radius,
                                    "yaw": plan.framing.yaw, "pitch": plan.framing.pitch, "view": plan.framing.view],
                        "primary": g.muscles.primary, "frames": frames])
        }
        let data = try JSONSerialization.data(withJSONObject: out)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

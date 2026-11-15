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

    private func staged(_ id: String) throws -> PropPlan {
        let ex = try #require(catalog.exercises.first { $0.id == id })
        let guide = try #require(catalog.howTo(for: ex))
        let plan = PropPlan(guide: guide, body: body)
        #expect(plan.staging != nil)
        return plan
    }

    /// How far the middle knuckle of each hand is from a bar through `point` along `axis`.
    private func knuckles(_ frame: BodyFrame, from point: (String) -> [Double], along axis: Int?) throws -> [Double] {
        try ["r", "l"].map { s in
            let k = try #require(frame.heads["f3a.\(s)"])
            let p = point(s)
            return (0..<3).filter { $0 != axis }.reduce(0.0) { $0 + (k[$1] - p[$1]) * (k[$1] - p[$1]) }.squareRoot()
        }
    }

    @Test func pullUpHangsFromTheBar() throws {
        let plan = try staged(StarterIDs.pullUp)
        #expect(plan.kinds == [.pullUpBar])
        let bar = PullUpStaging.barHeight
        var top = -Double.infinity, low = Double.infinity
        for i in 0...24 {
            let f = plan.frame(at: Double(i) / 24).body
            // Both hands stay closed on the bar, at the grip's width, the whole way.
            for d in try knuckles(f, from: { _ in [0, 0, bar] }, along: 0) { #expect(d < 0.06) }
            for s in ["r", "l"] {
                let k = try #require(f.heads["f3a.\(s)"])
                #expect(abs(abs(k[0]) - PullUpStaging.halfGrip) < 0.06)
            }
            let toes = try #require(f.heads["toes.r"])
            #expect(toes[2] > 0.1)
            let neck = try #require(f.heads["neck"])
            top = max(top, neck[2])
            low = min(low, neck[2])
        }
        // The chin clears the bar at the top, and the arms hang long at the bottom.
        #expect(top > bar - 0.06)
        #expect(low < bar - 0.5)
    }

    @Test func pulldownBringsTheBarToTheChest() throws {
        let plan = try staged(StarterIDs.pulldown)
        let first = plan.frame(at: 0), squeeze = plan.frame(at: 0.5)
        let ankle = try #require(first.body.heads["foot.r"])
        var bars: [[Double]] = []
        for i in 0...24 {
            let (f, props) = plan.frame(at: Double(i) / 24)
            let bar = props[plan.fixed.count].center
            bars.append(bar)
            for d in try knuckles(f, from: { _ in bar }, along: 0) { #expect(d < 0.06) }
            // Seated: the hips and the feet never move.
            #expect(f.heads["pelvis"] == first.body.heads["pelvis"])
            let foot = try #require(f.heads["foot.r"])
            #expect(abs(foot[2] - ankle[2]) < 0.005)
        }
        // The bar comes down by more than half a metre, to below the chin and in front of the chest.
        let neck = try #require(squeeze.body.heads["neck"])
        let bottom = squeeze.props[plan.fixed.count].center
        #expect(bars[0][2] - bottom[2] > 0.5)
        #expect(bottom[2] < neck[2])
        #expect(bottom[1] < neck[1])
        // The weight stack rises as the bar comes down.
        let plates = { (props: [PropPiece]) in props.last { $0.finish == .plate }?.center[2] ?? 0 }
        #expect(plates(squeeze.props) > plates(first.props) + 0.4)
    }

    @Test func seatedRowPullsTheHandleToTheBelly() throws {
        let plan = try staged(StarterIDs.seatedRow)
        let first = plan.frame(at: 0), squeeze = plan.frame(at: 0.5)
        for i in 0...24 {
            let (f, props) = plan.frame(at: Double(i) / 24)
            // The first two moving pieces are the handle's grips, right then left.
            let grips = ["r": props[plan.fixed.count].center, "l": props[plan.fixed.count + 5].center]
            for d in try knuckles(f, from: { grips[$0] ?? [0, 0, 0] }, along: nil) { #expect(d < 0.07) }
            // Feet stay on the plates.
            for s in ["r", "l"] { #expect(f.heads["foot.\(s)"] == first.body.heads["foot.\(s)"]) }
        }
        let start = first.props[plan.fixed.count].center, end = squeeze.props[plan.fixed.count].center
        #expect(end[1] - start[1] > 0.35)
        // At the squeeze the elbows are behind the shoulders.
        let elbow = try #require(squeeze.body.heads["ulna.r"]), shoulder = try #require(squeeze.body.heads["humerus.r"])
        #expect(elbow[1] > shoulder[1])
    }

    /// BODY_DUMP=/path writes frames, props and framing for a sample of exercises, for the
    /// offline renderer in Body/anatomy/render_app.py.
    @Test func dumpForRenderer() throws {
        guard let path = ProcessInfo.processInfo.environment["BODY_DUMP"] else { return }
        let only = ProcessInfo.processInfo.environment["BODY_DUMP_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        // BODY_DUMP_IDS=0198,0652 dumps just those exercises; BODY_DUMP_FRAMES=9 samples the loop.
        let ids = ProcessInfo.processInfo.environment["BODY_DUMP_IDS"].map { Set($0.split(separator: ",").map(String.init)) }
        let count = ProcessInfo.processInfo.environment["BODY_DUMP_FRAMES"].flatMap(Int.init) ?? 2
        let times = count <= 2 ? [0.0, 0.5] : (0..<count).map { Double($0) / Double(count) }
        var perFamily: [String: [String: Int]] = [:]
        var out: [[String: Any]] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let fam = ex.familyID else { continue }
            if let ids {
                guard ids.contains(ex.id) else { continue }
            } else {
                if let only, !only.contains(fam), !only.contains(ex.id) { continue }
                let key = ex.equipment ?? "-"
                var seen = perFamily[fam, default: [:]]
                if seen[key] != nil || seen.count >= (only == nil ? 2 : 6) { continue }
                seen[key] = 1
                perFamily[fam] = seen
            }
            guard let g = catalog.howTo(for: ex) else { continue }
            let plan = PropPlan(guide: g, body: body)
            var frames: [[String: Any]] = []
            // BODY_DUMP_FAULTS=1 adds one frame per common mistake after the loop's frames.
            var shots: [(Double, JointPose?)] = times.map { ($0, nil) }
            if ProcessInfo.processInfo.environment["BODY_DUMP_FAULTS"] != nil {
                let mistakes = g.steps.flatMap(\.mistakes)
                shots += mistakes.compactMap { m in m.pose.map { (g.faultT, $0) } }
            }
            for (t, fault) in shots {
                let (f, props) = plan.frame(at: t, fault: fault)
                frames.append([
                    "t": t,
                    "root": f.root,
                    "heads": f.heads,
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

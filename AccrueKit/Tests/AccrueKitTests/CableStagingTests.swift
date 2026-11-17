import Foundation
import Testing
@testable import AccrueKit

struct CableStagingTests {
    typealias V = Body3D.V

    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func staging<S: BodyStaging>(_ id: String, as type: S.Type = S.self) throws -> (HowToGuide, S) {
        let g = try guide(id)
        return (g, try #require(Stagings.make(g, body) as? S, "\(id) is not staged as \(S.self)"))
    }

    /// Every pose of the loop, then the common mistakes at the moment they show.
    private func poses(_ g: HowToGuide, mistakes: Bool = true) -> [JointPose] {
        var out = (0...24).map { Figure.smooth(g.keyframes, at: Double($0) / 24) }
        if mistakes {
            let at = Figure.smooth(g.keyframes, at: g.faultT)
            out += g.steps.flatMap(\.mistakes).compactMap { m in m.pose.map { Figure.applying($0, to: at) } }
        }
        return out
    }

    private func point(_ f: BodyFrame, _ bone: String) throws -> V { V(try #require(f.heads[bone], "\(bone)")) }

    /// How far the middle knuckle of each hand is from the line of the handle it holds.
    private func knuckles(_ f: BodyFrame, hands: [String: V], across: [String: V]) throws -> [Double] {
        try ["r", "l"].map { s in
            let k = try point(f, "f3a.\(s)")
            let at = try #require(hands[s]), line = try #require(across[s]).unit
            let d = k - at
            return (d - line * d.dot(line)).length
        }
    }

    /// The feet are flat on the floor where they were in `first`.
    private func planted(_ f: BodyFrame, as first: BodyFrame) throws {
        for s in ["r", "l"] {
            let ankle = try point(f, "foot.\(s)"), was = try point(first, "foot.\(s)")
            #expect((ankle - was).length < 0.003)
            #expect(abs(ankle.z - body.ankleHeight) < 0.003)
            let toes = try point(f, "toes.\(s)")
            #expect(toes.z < ankle.z && toes.z > 0)
        }
    }

    /// The cable runs straight from the handle's swivel to the wheel and leaves it along a tangent.
    private func tangent(eye: V, rim: V, wheel: V, axis: V = V(1, 0, 0)) {
        var spoke = rim - wheel
        spoke = spoke - axis * spoke.dot(axis)
        var cable = eye - rim
        cable = cable - axis * cable.dot(axis)
        #expect(abs(spoke.length - CableKit.wheel) < 1e-6)
        #expect(abs(spoke.unit.dot(cable.unit)) < 1e-6)
    }

    private func plates(_ props: [PropPiece]) -> Double { props.last { $0.finish == .plate }?.center[2] ?? 0 }

    // MARK: Which exercises

    @Test func stagesOnlyWhatFits() throws {
        func kind(_ name: String) throws -> (any BodyStaging)? {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            return Stagings.make(try #require(catalog.howTo(for: ex)), body)
        }
        #expect(try (kind("cable triceps pushdown (v-bar)") as? StandingCableStaging)?.handle == .vBar)
        #expect(try (kind("cable pushdown") as? StandingCableStaging)?.handle == .bar)
        #expect(try (kind("cable pushdown (with rope attachment)") as? StandingCableStaging)?.handle == .rope)
        #expect(try (kind("cable triceps pushdown (sz bar)") as? StandingCableStaging)?.handle == .ezBar)
        #expect(try (kind("cable reverse-grip pushdown") as? StandingCableStaging)?.underhand == true)
        #expect(try (kind("cable curl") as? StandingCableStaging)?.move == .curl)
        #expect(try (kind("cable hammer curl (with rope)") as? StandingCableStaging)?.handle == .rope)
        #expect(try (kind("cable reverse curl") as? StandingCableStaging)?.underhand == false)
        #expect(try kind("cable standing face pull") is FacePullStaging)
        #expect(try kind("cable standing fly") is CableFlyStaging)
        #expect(try (kind("cable wide grip lat pulldown") as? PulldownGripStaging)?.grip == .over)
        #expect(try (kind("cable underhand pulldown") as? PulldownGripStaging)?.grip == .under)
        #expect(try (kind("cable lateral pulldown with v-bar") as? PulldownGripStaging)?.handle == .vHandle)
        #expect(try (kind("cable wide neutral grip pulldown") as? PulldownGripStaging)?.handle == .parallelBar)
        #expect(try (kind("cable seated wide-grip row") as? SeatedRowGripStaging)?.handle == .barOver)
        #expect(try (kind("cable rope seated row") as? SeatedRowGripStaging)?.handle == .rope)
        #expect(try kind("cable low seated row") is SeatedRowStaging)
        // The starters keep their own stagings.
        #expect(try kind("cable pulldown") is PulldownStaging)
        #expect(try kind("cable seated row") is SeatedRowStaging)
        // One arm, lying, kneeling, behind the neck, other pulleys and other equipment are other pictures.
        for name in ["cable one arm tricep pushdown", "cable incline pushdown", "cable kneeling triceps extension",
                     "cable overhead triceps extension (rope attachment)", "cable kickback", "cable one arm curl",
                     "cable preacher curl", "cable drag curl", "cable seated curl", "cable lying face pull",
                     "cable standing one arm face pull", "band face pull", "cable rear pulldown", "cable one arm lat pulldown",
                     "cable lateral pulldown (with rope attachment)", "band kneeling pulldown", "cable seated high row (v-bar)",
                     "cable standing row (v-bar)", "cable seated one arm alternate row", "cable floor seated wide-grip row",
                     "cable low fly", "cable standing single arm fly", "cable upper chest crossovers", "cable lying fly",
                     "dumbbell fly", "barbell curl"] {
            // Asked of the cable maker alone: another group may stage a dumbbell fly or a barbell curl.
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            #expect(CableStagings.make(try #require(catalog.howTo(for: ex)), body) == nil, "\(name)")
        }
        // How many of the catalog each family's staging covers.
        var count: [String: Int] = [:]
        for ex in catalog.exercises where !ex.hidden {
            guard let fam = ex.familyID, let g = catalog.howTo(for: ex), CableStagings.make(g, body) != nil else { continue }
            count[fam, default: 0] += 1
        }
        #expect(count["triceps-extension", default: 0] >= 9)
        #expect(count["face-pull", default: 0] >= 3)
        #expect(count["lat-pulldown", default: 0] >= 10)
        #expect(count["row", default: 0] >= 8)
        #expect(count["biceps-curl", default: 0] >= 8)
        #expect(count["chest-fly", default: 0] >= 4)
        #expect(Set(count.keys) == ["triceps-extension", "face-pull", "lat-pulldown", "row", "biceps-curl", "chest-fly"])
    }

    // MARK: Pushdown and curl

    /// 0241 V-bar, 0201 bar, 0200 rope, 1605 cambered bar, 0207 and 1606 palms up.
    @Test(arguments: ["0241", "0201", "0200", "1605", "0207", "1606"])
    func pushdownKeepsTheHandsOnTheHandle(_ id: String) throws {
        let (g, staging): (HowToGuide, StandingCableStaging) = try staging(id)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var heights: [Double] = [], elbows: [V] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "\(id) frame \(i): \(d)") }
            // Both hands on one level handle, the same distance either side of the middle.
            let r = try #require(at.hands["r"]), l = try #require(at.hands["l"])
            #expect(abs(r.z - l.z) < 1e-6 && abs(r.x + l.x) < 1e-6)
            try planted(at.frame, as: first.frame)
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            // The handle stays in front of the body, and the cable in front of the face.
            #expect(at.centre.y < CableKit.front(at.frame.heads.mapValues { V($0) }, at: at.centre.z) - 0.04)
            let neck = try point(at.frame, "neck")
            let t = (neck.z + 0.1 - at.eye.z) / (at.rim.z - at.eye.z)
            #expect(at.eye.y + (at.rim.y - at.eye.y) * t < neck.y - 0.19, "\(id) frame \(i)")
            if i <= 24 {
                heights.append(at.centre.z)
                elbows.append(try point(at.frame, "ulna.r"))
                // The elbows bend the natural way: behind the line from shoulder to wrist.
                let shoulder = try point(at.frame, "humerus.r"), wrist = try point(at.frame, "hand.r")
                let k = (elbows[i].z - shoulder.z) / (wrist.z - shoulder.z)
                #expect(elbows[i].y > shoulder.y + (wrist.y - shoulder.y) * k - 0.005, "\(id) frame \(i)")
            }
        }
        // From chest height to straight arms, with the elbows staying at the sides.
        let chest = try point(first.frame, "neck").z - 0.3
        #expect(heights[0] > chest && heights[0] - (heights.min() ?? 0) > 0.35)
        for e in elbows { #expect((e - elbows[0]).length < 0.09 && abs(e.x) < 0.33) }
        // The stack rises as the handle goes down, and rests again at the top.
        let plan = PropPlan(guide: g, body: body)
        let low = Double(heights.firstIndex(of: heights.min() ?? 0) ?? 8) / 24
        #expect(plates(plan.frame(at: low).props) > plates(plan.frame(at: 0).props) + 0.3)
        #expect(plan.frame(at: 0).props.allSatisfy { ($0.center + $0.size).allSatisfy(\.isFinite) })
    }

    /// 0868 bar, 1630 close grip, 1607 cambered bar, 3068 rope, 0206 palms down.
    @Test(arguments: ["0868", "1630", "1607", "3068", "0206"])
    func curlBringsTheHandleToTheShoulders(_ id: String) throws {
        let (g, staging): (HowToGuide, StandingCableStaging) = try staging(id)
        #expect(staging.move == .curl)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var heights: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "\(id) frame \(i): \(d)") }
            try planted(at.frame, as: first.frame)
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            #expect(at.centre.y < CableKit.front(at.frame.heads.mapValues { V($0) }, at: at.centre.z) - 0.04, "\(id) frame \(i)")
            if i <= 24 { heights.append(at.centre.z) }
        }
        // From the thighs to the shoulders, with the pulley near the floor in front.
        let hips = try point(first.frame, "pelvis").z, shoulders = try point(first.frame, "humerus.r").z
        #expect(heights[0] < hips - 0.02 && (heights.max() ?? 0) > shoulders - 0.12)
        #expect(staging.pulley.z < 0.3 && staging.pulley.y < first.centre.y - 0.3)
        let plan = PropPlan(guide: g, body: body)
        let high = Double(heights.firstIndex(of: heights.max() ?? 0) ?? 8) / 24
        #expect(plates(plan.frame(at: high).props) > plates(plan.frame(at: 0).props) + 0.3)
    }

    // MARK: Face pull

    @Test func facePullComesToTheFaceWithTheElbowsHigh() throws {
        let (g, staging): (HowToGuide, FacePullStaging) = try staging("5609")
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "frame \(i): \(d)") }
            try planted(at.frame, as: first.frame)
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            // The rope's swivel never reaches the face or the chest, and each half of the rope
            // is as long as the other.
            let heads = at.frame.heads.mapValues { V($0) }
            #expect(at.eye.y < CableKit.front(heads, at: at.eye.z) - 0.03, "frame \(i)")
            for s in ["r", "l"] {
                let hand = try #require(at.hands[s]), run = try #require(at.run[s])
                let edge = hand - run * CableKit.fist
                #expect(abs((edge - at.eye).length - CableKit.strand) < 1e-4)
            }
        }
        // At arm's length the hands are together on the pulley's line.
        let r0 = try #require(first.hands["r"]), l0 = try #require(first.hands["l"])
        #expect((r0 - l0).length < 0.2)
        let head = try point(first.frame, "head")
        #expect(abs(staging.pulley.z - head.z) < 0.2)
        // At the face they are apart beside the head, level with it, the elbows out and high.
        let squeeze = staging.layout(Figure.smooth(g.keyframes, at: 0.4))
        let r = try #require(squeeze.hands["r"]), l = try #require(squeeze.hands["l"])
        let neck = try point(squeeze.frame, "neck"), shoulder = try point(squeeze.frame, "humerus.r")
        let elbow = try point(squeeze.frame, "ulna.r")
        #expect((r - l).length > 0.4 && r.z > neck.z && r.z < neck.z + 0.3)
        #expect(r.y > r0.y + 0.4)
        #expect(elbow.z > shoulder.z - 0.08 && abs(elbow.x) > abs(shoulder.x) + 0.15)
        let plan = PropPlan(guide: g, body: body)
        #expect(plates(plan.frame(at: 0.4).props) > plates(plan.frame(at: 0).props) + 0.4)
    }

    // MARK: Pulldown and seated row, the other grips

    /// 2291 wide, 1047 close, 0245 palms up, 10503 palms up and narrow, 7583 and 4217 palms
    /// facing on the parallel bar, 2616 the close V handle.
    @Test(arguments: ["2291", "1047", "0245", "10503", "7583", "4217", "2616"])
    func pulldownGripsBringTheHandleToTheChest(_ id: String) throws {
        let (g, staging): (HowToGuide, PulldownGripStaging) = try staging(id)
        let first = staging.solve(Figure.smooth(g.keyframes, at: 0))
        var bars: [V] = []
        for (i, pose) in poses(g).enumerated() {
            let (f, bar) = staging.solve(pose)
            var hands: [String: V] = [:], across: [String: V] = [:]
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                hands[s] = bar + V(-m * staging.halfGrip, 0, 0)
                across[s] = staging.line(m, thorax: .identity).across
            }
            for d in try knuckles(f, hands: hands, across: across) { #expect(d < 0.06, "\(id) frame \(i): \(d)") }
            // Seated: the hips and the feet never move.
            #expect(f.heads["pelvis"] == first.frame.heads["pelvis"])
            let ankle = try point(f, "foot.r"), was = try point(first.frame, "foot.r")
            #expect(abs(ankle.z - was.z) < 0.005)
            if i <= 24 { bars.append(bar) }
        }
        // Down by more than half a metre, to below the chin and in front of the chest.
        let squeeze = staging.solve(Figure.smooth(g.keyframes, at: 0.5))
        let neck = try point(squeeze.frame, "neck")
        #expect(bars[0].z - squeeze.bar.z > 0.5)
        #expect(squeeze.bar.z < neck.z && squeeze.bar.y < neck.y)
        let plan = PropPlan(guide: g, body: body)
        #expect(plates(plan.frame(at: 0.5).props) > plates(plan.frame(at: 0).props) + 0.4)
    }

    /// 0218 wide bar, 3233 palms up, 1323 rope.
    @Test(arguments: ["0218", "3233", "1323"])
    func seatedRowGripsPullTheHandleToTheBelly(_ id: String) throws {
        let (g, staging): (HowToGuide, SeatedRowGripStaging) = try staging(id)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            // Hips on the bench, feet on the plates.
            #expect(at.frame.heads["pelvis"] == first.frame.heads["pelvis"])
            for s in ["r", "l"] { #expect(at.frame.heads["foot.\(s)"] == first.frame.heads["foot.\(s)"]) }
            tangent(eye: at.eye, rim: at.rim, wheel: staging.wheel)
        }
        let squeeze = staging.layout(Figure.smooth(g.keyframes, at: 0.5))
        #expect(squeeze.centre.y - first.centre.y > 0.3)
        // At the squeeze the elbows are behind the shoulders and the handle short of the belly.
        let elbow = try point(squeeze.frame, "ulna.r"), shoulder = try point(squeeze.frame, "humerus.r")
        #expect(elbow.y > shoulder.y)
        if staging.handle != .rope {
            #expect(squeeze.centre.y < CableKit.front(squeeze.frame.heads.mapValues { V($0) }, at: squeeze.centre.z) - 0.02)
        }
        let plan = PropPlan(guide: g, body: body)
        #expect(plates(plan.frame(at: 0.5).props) > plates(plan.frame(at: 0).props) + 0.3)
    }

    // MARK: Cable fly

    @Test func flyHugsTheHandlesTogether() throws {
        let (g, staging): (HowToGuide, CableFlyStaging) = try staging("0227")
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "frame \(i): \(d)") }
            for s in ["r", "l"] {
                // Each cable runs from its own wheel, and the stirrup hangs in line with it.
                let hand = try #require(at.hands[s]), ring = try #require(at.rings[s]), rim = try #require(at.rims[s])
                let wheel = try #require(staging.wheels[s])
                tangent(eye: hand, rim: rim, wheel: wheel, axis: V(0, 1, 0))
                #expect(((ring - hand).unit - (rim - hand).unit).length < 1e-6)
                let line = try #require(at.across[s])
                #expect(abs(line.dot((rim - hand).unit)) < 1e-6)
                // The feet never move: the front one flat, the back one on its ball.
                let ankle = try point(at.frame, "foot.\(s)"), was = try point(first.frame, "foot.\(s)")
                let ball = try point(at.frame, "toes.\(s)")
                #expect((ankle - was).length < 0.003)
                #expect(ball.z < 0.03)
            }
        }
        let front = staging.stance.front, back = front == "r" ? "l" : "r"
        let lead = try point(first.frame, "foot.\(front)"), rear = try point(first.frame, "foot.\(back)")
        #expect(abs(lead.z - body.ankleHeight) < 0.003)
        #expect(rear.z > body.ankleHeight + 0.02)
        #expect(rear.y > lead.y + 0.3)
        // Open, the hands are wide and the cables short; hugged, the fists meet in front.
        let hug = staging.layout(Figure.smooth(g.keyframes, at: 0.5))
        let wide = try #require(first.hands["r"]), near = try #require(hug.hands["r"])
        #expect(abs(wide.x) > 0.55 && abs(near.x) < 0.08)
        let waist = try point(hug.frame, "thorax")
        #expect(near.y < waist.y - 0.3)
        let plan = PropPlan(guide: g, body: body)
        let rest = plan.frame(at: 0).props.filter { $0.finish == .plate }.map { $0.center[2] }.max() ?? 0
        let lifted = plan.frame(at: 0.5).props.filter { $0.finish == .plate }.map { $0.center[2] }.max() ?? 0
        #expect(lifted > rest + 0.3)
    }
}

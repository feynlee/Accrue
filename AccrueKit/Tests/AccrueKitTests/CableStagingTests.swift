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
        // A handle in each hand between two pulleys, on a bench or the knees.
        #expect(try (kind("cable seated chest press") as? CableHandlesStaging)?.pulleys == .chest)
        #expect(try (kind("cable seated chest fly") as? CableHandlesStaging)?.posture.support == .seat(back: true))
        #expect(try (kind("cable bench press") as? CableHandlesStaging)?.posture.support == .supine(tilt: 0))
        #expect(try (kind("cable incline fly") as? CableHandlesStaging)?.posture.support == .supine(tilt: 30))
        #expect(try (kind("cable kneeling shoulder press") as? CableHandlesStaging)?.pulleys == .low)
        #expect(try (kind("cable kneeling crunch") as? CableCrunchStaging)?.footing.support == .kneel(half: false))
        #expect(try (kind("cable lying triceps extension") as? StandingCableStaging)?.move == .lyingExtension)
        #expect(try (kind("cable lying triceps extension (with rope)") as? StandingCableStaging)?.handle == .rope)
        // The row's other seats and pulleys.
        #expect(try (kind("cable seated high row (v-bar)") as? SeatedRowGripStaging)?.from == .high)
        #expect(try (kind("cable high row (kneeling)") as? SeatedRowGripStaging)?.seat == .knees)
        #expect(try (kind("cable floor seated wide-grip row") as? SeatedRowGripStaging)?.seat == .floor)
        #expect(try (kind("cable seated row (bent bar)") as? SeatedRowGripStaging)?.bent == true)
        // One arm alone on a stirrup.
        #expect(try (kind("cable one arm tricep pushdown") as? StandingCableStaging)?.oneArm == true)
        #expect(try (kind("cable one arm curl") as? StandingCableStaging)?.handle == .stirrup)
        #expect(try (kind("cable reverse one arm curl") as? StandingCableStaging)?.underhand == false)
        #expect(try (kind("cable kneeling one arm row") as? SeatedRowGripStaging)?.handle == .single)
        #expect(try (kind("cable kneeling one arm lat pulldown") as? SeatedRowGripStaging)?.from == .overhead)
        #expect(try (kind("cable standing single arm fly") as? CableFlyStaging)?.oneArm == true)
        // Lying and incline curls.
        #expect(try (kind("cable lying bicep curl") as? StandingCableStaging)?.footing.lies == true)
        #expect(try (kind("cable incline biceps curl") as? CableHandlesStaging)?.posture.support == .supine(tilt: 50))
        // Lying with a bar over the thighs to raise or row, and the row's seat for a shrug.
        #expect(try (kind("cable lying front raise") as? StandingCableStaging)?.footing.lies == true)
        #expect(try (kind("cable lying upright row (sz bar)") as? StandingCableStaging)?.handle == .ezBar)
        #expect(try (kind("cable seated scapular retraction") as? SeatedRowGripStaging)?.handle == .close)
        // Side-on to the pulley with both hands on one handle.
        #expect(try (kind("cable horizontal pallof press") as? CablePallofStaging)?.footing.support == nil)
        #expect(try (kind("cable half kneeling pallof press") as? CablePallofStaging)?.footing.support == .kneel(half: true))
        // Seated and kneeling versions keep the staging and change what the body rests on.
        #expect(try (kind("cable seated curl") as? StandingCableStaging)?.footing.support == .seat(back: false))
        #expect(try (kind("cable seated face pull (with rope)") as? FacePullStaging)?.footing.support == .seat(back: false))
        #expect(try (kind("cable half kneeling face pull") as? FacePullStaging)?.footing.support == .kneel(half: true))
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
        for name in ["cable one arm side triceps pushdown", "cable incline pushdown", "cable kneeling triceps extension",
                     "cable overhead triceps extension (rope attachment)", "cable kickback", "cable one arm inner biceps curl",
                     "cable preacher curl", "cable drag curl", "cable seated unilateral bicep curl", "cable lying face pull",
                     "cable standing one arm face pull", "band face pull", "cable rear pulldown", "cable one arm lat pulldown",
                     "cable lateral pulldown (with rope attachment)", "band kneeling pulldown", "cable front seated row", "cable decline seated wide-grip row", "cable rope crossover seated row",
                     "cable standing row (v-bar)", "cable seated one arm alternate row", "cable kneeling leaning forward one arm row",
                     "cable low fly", "cable upper chest crossovers", "cable decline fly", "cable single arm bear fly", "cable one arm incline press",
                     "cable press on exercise ball", "cable shoulder press", "cable seated crunch", "cable incline close grip curl", "cable seated overhead curl", "cable incline skull crusher",
                     "cable rope lying on floor tricep extension", "cable front raise", "cable upright row", "cable shrug",
                     "cable lying shrug", "cable lying floor front raise", "cable vertical pallof press", "cable lying pallof press",
                     "cable kneeling high low anti rotation chop", "cable kneeling twist", "cable seated twist",
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
        #expect(Set(count.keys) == ["triceps-extension", "face-pull", "lat-pulldown", "row", "biceps-curl", "chest-fly",
                                    "bench-press", "overhead-press", "crunch-sit-up", "front-raise", "upright-row", "shrug",
                                    "pallof-anti-rotation"])
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

    // MARK: Seated and kneeling

    /// 1641 curls sitting on a bench, 5658 pulls to the face sitting, 7743 on one knee.
    @Test(arguments: ["1641", "5658", "7743"])
    func seatedAndKneelingStayOnTheirSupport(_ id: String) throws {
        let g = try guide(id)
        let made = try #require(Stagings.make(g, body))
        func at(_ pose: JointPose) throws -> (frame: BodyFrame, hands: [String: V], across: [String: V], eye: V, rim: V, wheel: V) {
            if let curl = made as? StandingCableStaging {
                let l = curl.layout(pose)
                return (l.frame, l.hands, l.across, l.eye, l.rim, curl.pulley)
            }
            let pull = try #require(made as? FacePullStaging)
            let l = pull.layout(pose)
            return (l.frame, l.hands, l.across, l.eye, l.rim, pull.pulley)
        }
        let first = try at(Figure.smooth(g.keyframes, at: 0))
        for (i, pose) in poses(g).enumerated() {
            let now = try at(pose)
            for d in try knuckles(now.frame, hands: now.hands, across: now.across) { #expect(d < 0.06, "\(id) frame \(i): \(d)") }
            // Hips on the seat or over the knees, and feet that never move.
            for bone in ["pelvis", "foot.r", "foot.l"] {
                #expect((try point(now.frame, bone) - point(first.frame, bone)).length < 0.003, "\(id) frame \(i) \(bone)")
            }
            tangent(eye: now.eye, rim: now.rim, wheel: now.wheel)
            if made is StandingCableStaging {
                // The bar never sinks into the thighs.
                let knee = try point(now.frame, "shin.r"), bar = try #require(now.hands["r"])
                #expect(bar.z > knee.z + 0.1 || bar.y < knee.y - 0.08, "\(id) frame \(i)")
            }
        }
        // Sitting, the hips are as high as the knees and a bench is under them; kneeling, a knee is on the floor.
        let hip = try point(first.frame, "femur.r"), knee = try point(first.frame, "shin.r")
        if id == "7743" {
            #expect(knee.z < 0.08 && hip.z > 0.4)
            #expect(!made.kinds.contains(.bench))
        } else {
            #expect(abs(hip.z - knee.z) < 0.03)
            #expect(made.kinds.contains(.bench))
            #expect(made.fixed.contains { $0.finish == .pad })
        }
        let plan = PropPlan(guide: g, body: body)
        let peak = (0...24).map { plates(plan.frame(at: Double($0) / 24).props) }.max() ?? 0
        #expect(peak > plates(plan.frame(at: 0).props) + 0.2)
    }

    // MARK: A handle in each hand

    /// Presses and flies sitting (2144, 3869), kneeling (4010) and lying flat or on an incline.
    /// Then the incline curls 5703, 11763 and 1645.
    @Test(arguments: ["2144", "3869", "4010", "0151", "3362", "0169", "0185", "0171", "5703", "11763", "1645"])
    func handlesStayInTheHandsBetweenTwoPulleys(_ id: String) throws {
        let (g, staging): (HowToGuide, CableHandlesStaging) = try staging(id)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var lengths: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "\(id) frame \(i): \(d)") }
            // The hips stay on the bench or over the knees.
            // (a mistake that arches the back may shift them in the seat).
            #expect((try point(at.frame, "pelvis") - point(first.frame, "pelvis")).length < (i <= 24 ? 0.02 : 0.08), "\(id) frame \(i)")
            for s in ["r", "l"] {
                let ring = try #require(at.rings[s]), rim = try #require(at.rims[s]), wheel = try #require(staging.wheels[s])
                let hand = try #require(at.hands[s]), line = try #require(at.across[s])
                tangent(eye: ring, rim: rim, wheel: wheel, axis: V(0, 1, 0))
                // The grip lies square across its cable, and the wheel is on the hand's own side.
                #expect(abs(line.dot((ring - hand).unit)) < 1e-6)
                #expect(wheel.x * hand.x > 0 && abs(hand.x) > 0.04 && abs(wheel.x) > abs(hand.x) + 0.15, "\(id) frame \(i)")
                // The cable stays out of the trunk, the head and the legs.
                let run = rim - ring
                #expect(Body3D.wayOut((ring + rim) * 0.5, axis: run.unit, half: run.length / 2, radius: 0.01, of: at.bulk,
                                      front: Body3D.forward) == nil, "\(id) frame \(i)")
                if s == "r", i <= 24 { lengths.append((ring - wheel).length) }
            }
        }
        // The stacks rest where the cable is shortest and rise as it is drawn out.
        let low = try #require(lengths.min()), high = try #require(lengths.max())
        #expect(high - low > 0.12)
        #expect(abs(low - (staging.slack["r"] ?? 0)) < 1e-9)
        let plan = PropPlan(guide: g, body: body)
        let tops = (0...24).map { plates(plan.frame(at: Double($0) / 24).props) }
        #expect(abs((tops.max() ?? 0) - (tops.min() ?? 0) - (high - low)) < 0.02)
        let sits = staging.posture.support == .seat(back: true), kneels = staging.posture.support == .kneel(half: false)
        #expect(staging.kinds.contains(.bench) == !kneels)
        // Sitting, the wheels are level with the shoulders; lying or kneeling, near the floor.
        let wheel = try #require(staging.wheels["r"]), shoulder = try point(first.frame, "humerus.r")
        #expect(sits ? abs(wheel.z - shoulder.z) < 0.1 : wheel.z < 0.3)
    }

    // MARK: Lying triceps extension

    /// 0187 with a bar, 4353 with the rope.
    @Test(arguments: ["0187", "4353"])
    func lyingExtensionStraightensTheArmsOverTheFace(_ id: String) throws {
        let (g, staging): (HowToGuide, StandingCableStaging) = try staging(id)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var lengths: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            // The back stays on the bench and the feet on the floor.
            for bone in ["pelvis", "foot.r", "foot.l"] {
                #expect((try point(at.frame, bone) - point(first.frame, bone)).length < 0.01, "\(id) frame \(i) \(bone)")
            }
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            // Neither the handle nor the cable touches the head.
            let skull = at.frame.bulkHead(body)
            var off = at.centre - skull
            off.x = 0
            #expect(off.length > 0.16, "\(id) frame \(i)")
            let run = at.rim - at.eye
            let t = min(1, max(0, (skull - at.eye).dot(run) / run.dot(run)))
            #expect((at.eye + run * t - skull).length > 0.125, "\(id) frame \(i)")
            if i <= 24 { lengths.append((at.eye - staging.pulley).length) }
        }
        // Lying level, the wheel near the floor beyond the head.
        let head = try point(first.frame, "head"), hips = try point(first.frame, "pelvis")
        #expect(abs(head.z - hips.z) < 0.15 && head.y > hips.y + 0.4)
        #expect(staging.pulley.y > head.y + 0.3 && staging.pulley.z < 0.3)
        #expect(staging.kinds.contains(.bench))
        // The arms are straight at the start, where the cable is longest and the stack highest.
        #expect(lengths[0] > (lengths.min() ?? 0) + 0.2)
        let plan = PropPlan(guide: g, body: body)
        let tops = (0...24).map { plates(plan.frame(at: Double($0) / 24).props) }
        #expect(tops[0] > (tops.min() ?? 0) + 0.2)
    }

    // MARK: Kneeling fly

    @Test func kneelingFlyHugsDownFromTheHighPulleys() throws {
        let (g, staging): (HowToGuide, CableFlyStaging) = try staging("6542")
        #expect(staging.posture?.support == .kneel(half: false))
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.06, "frame \(i): \(d)") }
            // Both knees and insteps stay on the floor, the hips over the knees.
            for bone in ["pelvis", "shin.r", "shin.l", "foot.r", "foot.l"] {
                #expect((try point(at.frame, bone) - point(first.frame, bone)).length < 0.003, "frame \(i) \(bone)")
            }
            for s in ["r", "l"] {
                let ring = try #require(at.rings[s]), rim = try #require(at.rims[s]), wheel = try #require(staging.wheels[s])
                tangent(eye: ring, rim: rim, wheel: wheel, axis: V(0, 1, 0))
                // The wheels are well above the hands.
                #expect(wheel.z > (try #require(at.hands[s])).z + 0.5)
            }
        }
        #expect(try point(first.frame, "shin.r").z < 0.08 && point(first.frame, "shin.l").z < 0.08)
        let plan = PropPlan(guide: g, body: body)
        let tops = (0...24).map { plates(plan.frame(at: Double($0) / 24).props) }
        #expect((tops.max() ?? 0) > tops[0] + 0.2)
    }

    // MARK: One arm

    /// Pushdowns 1723 and 1227, curls 0190, 4838 and 1413, seated rows 10112, 1205 and 9875, kneeling rows 5369,
    /// 10667 and 0193, kneeling pulldowns 4948 and 5581.
    @Test(arguments: ["1723", "1227", "0190", "4838", "1413", "10112", "1205", "9875", "5369", "10667", "0193", "4948", "5581"])
    func oneArmWorksWhileTheOtherHangs(_ id: String) throws {
        let g = try guide(id)
        let made = try #require(Stagings.make(g, body))
        func at(_ pose: JointPose) throws -> (frame: BodyFrame, hands: [String: V], across: [String: V], eye: V, rim: V, wheel: V) {
            if let standing = made as? StandingCableStaging {
                let l = standing.layout(pose)
                return (l.frame, l.hands, l.across, l.eye, l.rim, standing.pulley)
            }
            let row = try #require(made as? SeatedRowGripStaging)
            let l = row.layout(pose)
            return (l.frame, l.hands, l.across, l.eye, l.rim, row.wheel)
        }
        let first = try at(Figure.smooth(g.keyframes, at: 0))
        var lengths: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let now = try at(pose)
            // Only the right hand holds, closed on its grip.
            #expect(now.hands.count == 1)
            let hand = try #require(now.hands["r"]), line = try #require(now.across["r"]).unit
            let d = try point(now.frame, "f3a.r") - hand
            #expect((d - line * d.dot(line)).length < 0.06, "\(id) frame \(i)")
            tangent(eye: now.eye, rim: now.rim, wheel: now.wheel)
            // The body stays where it stands, sits or kneels.
            for bone in ["foot.r", "foot.l"] {
                #expect((try point(now.frame, bone) - point(first.frame, bone)).length < 0.003, "\(id) frame \(i) \(bone)")
            }
            if i <= 24 {
                lengths.append((now.eye - now.wheel).length)
                // The left arm hangs from its shoulder, nearly straight down.
                let shoulder = try point(now.frame, "humerus.l"), wrist = try point(now.frame, "hand.l")
                #expect(shoulder.z - wrist.z > 0.42, "\(id) frame \(i)")
                #expect(abs(wrist.x - shoulder.x) < 0.14 && abs(wrist.y - shoulder.y) < 0.14, "\(id) frame \(i) \(wrist - shoulder)")
            }
        }
        // A standing arm works in line with its own wheel.
        if let standing = made as? StandingCableStaging {
            #expect(abs(standing.pulley.x - (try #require(first.hands["r"])).x) < 0.01)
            #expect(standing.pulley.x < -0.1)
        }
        let drawn: Double = (lengths.max() ?? 0) - (lengths.min() ?? 0)
        #expect(drawn > 0.25)
        let plan = PropPlan(guide: g, body: body)
        let tops: [Double] = (0...24).map { plates(plan.frame(at: Double($0) / 24).props) }
        let risen: Double = (tops.max() ?? 0) - (tops.min() ?? 0)
        #expect(abs(risen - drawn) < 0.02)
    }

    // MARK: Lying curl

    /// 1634 and 4350 at shoulder width, 0181 and 0182 with the hands close.
    @Test(arguments: ["1634", "4350", "0181", "0182"])
    func lyingCurlDrawsTheBarFromTheThighsToTheShoulders(_ id: String) throws {
        let (g, staging): (HowToGuide, StandingCableStaging) = try staging(id)
        #expect(staging.move == .curl && staging.footing.lies)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var lengths: [Double] = [], along: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            for bone in ["pelvis", "foot.r", "foot.l"] {
                #expect((try point(at.frame, bone) - point(first.frame, bone)).length < 0.01, "\(id) frame \(i) \(bone)")
            }
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            // The bar passes over the body, never through it, and so does its cable.
            #expect(at.centre.z > CableKit.top(at.frame.heads.mapValues { V($0) }, at: at.centre.y) + 0.04, "\(id) frame \(i)")
            try cableOverTheBody(at.frame, eye: at.eye, rim: at.rim, "\(id) frame \(i)")
            if i <= 24 {
                lengths.append((at.eye - staging.pulley).length)
                along.append(at.centre.y)
            }
        }
        // Lying level with the feet toward the low wheel; the bar travels from over the hips
        // toward the shoulders, and the cable is shortest at the start.
        let head = try point(first.frame, "head"), hips = try point(first.frame, "pelvis"), toes = try point(first.frame, "toes.r")
        #expect(abs(head.z - hips.z) < 0.15 && head.y > hips.y + 0.4)
        #expect(staging.pulley.y < toes.y - 0.3 && staging.pulley.z < hips.z + 0.35)
        let shoulder = try point(first.frame, "humerus.r")
        #expect(abs(along[0] - hips.y) < 0.25 && (along.max() ?? 0) > shoulder.y - 0.2)
        #expect(lengths[0] < (lengths.min() ?? 0) + 0.02 && (lengths.max() ?? 0) > lengths[0] + 0.25)
        #expect(staging.halves.straight == (id == "0181" || id == "0182" ? 0.08 : 0.17))
    }

    /// 4227 front raise, 4225 upright row, 9492 upright row with the cambered bar: palms down.
    @Test(arguments: ["4227", "4225", "9492"])
    func lyingRaiseAndUprightRowLiftTheBarOffTheThighs(_ id: String) throws {
        let (g, staging): (HowToGuide, StandingCableStaging) = try staging(id)
        #expect(staging.move == .curl && staging.footing.lies && !staging.underhand)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var lengths: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            for bone in ["pelvis", "foot.r", "foot.l"] {
                #expect((try point(at.frame, bone) - point(first.frame, bone)).length < 0.01, "\(id) frame \(i) \(bone)")
            }
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            #expect(at.centre.z > CableKit.top(at.frame.heads.mapValues { V($0) }, at: at.centre.y) + 0.04, "\(id) frame \(i)")
            try cableOverTheBody(at.frame, eye: at.eye, rim: at.rim, "\(id) frame \(i)")
            if i <= 24 { lengths.append((at.eye - staging.pulley).length) }
        }
        // The feet are toward the wheel, and the bar is drawn well away from it and let back.
        let toes = try point(first.frame, "toes.r"), head = try point(first.frame, "head")
        #expect(staging.pulley.y < toes.y - 0.3 && head.y > toes.y + 1)
        let most: Double = lengths.max() ?? 0, least: Double = lengths.min() ?? 0
        #expect(most > least + 0.25 && lengths[0] < least + 0.05)
    }

    /// The cable from the handle's swivel to the wheel passes clear of the legs, hips, trunk and head.
    private func cableOverTheBody(_ f: BodyFrame, eye: V, rim: V, _ note: String) throws {
        let h = f.heads.mapValues { V($0) }
        for i in 0...40 {
            let p = eye + (rim - eye) * (Double(i) / 40)
            #expect(p.z > CableKit.top(h, at: p.y) + 0.02, "\(note): the cable at \(p.y)")
        }
    }

    // MARK: Crunch

    @Test func kneelingCrunchCurlsDownUnderTheRope() throws {
        let (g, staging): (HowToGuide, CableCrunchStaging) = try staging("0175")
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var heights: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            // (The wrists are bent as far as they go with the fists this close to the shoulders.)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.07, "frame \(i): \(d)") }
            // Hips over the knees, knees and insteps on the floor.
            for bone in ["pelvis", "shin.r", "foot.r", "foot.l"] {
                #expect((try point(at.frame, bone) - point(first.frame, bone)).length < 0.003, "frame \(i) \(bone)")
            }
            tangent(eye: at.eye, rim: at.rim, wheel: staging.pulley)
            // The swivel is clear of the skull, toward the pulley.
            let skull = at.frame.bulkHead(body)
            #expect((at.eye - skull).length > 0.15, "frame \(i)")
            if i <= 24 {
                heights.append(try point(at.frame, "head").z)
                // Through the loop a fist rests against each side of the head.
                for s in ["r", "l"] { #expect((try #require(at.hands[s]) - skull).length < 0.2, "frame \(i)") }
            }
        }
        #expect(try point(first.frame, "shin.r").z < 0.08)
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.3)
        let plan = PropPlan(guide: g, body: body)
        let low = Double(heights.firstIndex(of: heights.min() ?? 0) ?? 12) / 24
        #expect(plates(plan.frame(at: low).props) > plates(plan.frame(at: 0).props) + 0.2)
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
    /// Then the high rows 0213, 0208, 1321 and on the knees 0167, the floor rows 0160, 3357, the bent bar 1238.
    @Test(arguments: ["0218", "3233", "1323", "0213", "0208", "1321", "0167", "0160", "3357", "1238"])
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

    /// 11057 scapular retraction, 4111 horizontal shrug: the arms stay long on the row's handle.
    @Test(arguments: ["11057", "4111"])
    func seatedShrugDrawsTheHandleBackWithLongArms(_ id: String) throws {
        let (g, staging): (HowToGuide, SeatedRowGripStaging) = try staging(id)
        #expect(staging.handle == .close && staging.seat == .bench && staging.from == .low)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var back: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            #expect(at.frame.heads["pelvis"] == first.frame.heads["pelvis"])
            tangent(eye: at.eye, rim: at.rim, wheel: staging.wheel)
            guard i <= 24 else { continue }
            back.append(at.centre.y - first.centre.y)
            // The elbows stay nearly straight: the hands are an arm's length from the shoulders.
            let reach = (try point(at.frame, "hand.r") - point(at.frame, "humerus.r")).length
            let arm = (try point(first.frame, "hand.r") - point(first.frame, "ulna.r")).length
                + (try point(first.frame, "ulna.r") - point(first.frame, "humerus.r")).length
            #expect(reach > arm * 0.93, "\(id) frame \(i)")
        }
        // A short pull, a few centimetres, and the plates follow it.
        let most: Double = back.max() ?? 0
        #expect(most > 0.03 && most < 0.12)
        let plan = PropPlan(guide: g, body: body)
        #expect(plates(plan.frame(at: 0.5).props) > plates(plan.frame(at: 0).props) + 0.03)
    }

    // MARK: Pallof press

    /// 1202 standing, 4106 with one foot ahead, 4193 on one knee with the pulley beside it,
    /// 4196 with the pulley beside the raised knee.
    @Test(arguments: ["1202", "4106", "4193", "4196"])
    func pallofPressGoesStraightOutAcrossTheCable(_ id: String) throws {
        let (g, staging): (HowToGuide, CablePallofStaging) = try staging(id)
        let first = staging.layout(Figure.smooth(g.keyframes, at: 0))
        var out: [Double] = [], lengths: [Double] = []
        for (i, pose) in poses(g).enumerated() {
            let at = staging.layout(pose)
            for d in try knuckles(at.frame, hands: at.hands, across: at.across) { #expect(d < 0.065, "\(id) frame \(i): \(d)") }
            tangent(eye: at.ring, rim: at.rim, wheel: staging.wheel, axis: V(0, 1, 0))
            // The handle stands upright on the body's middle line, off the chest, one fist
            // above the other, and the cable runs level to the side.
            let shoulders = (try point(at.frame, "humerus.r") + point(at.frame, "humerus.l")) * 0.5
            #expect(abs(at.centre.x - shoulders.x) < 0.01, "\(id) frame \(i)")
            #expect(at.centre.y < CableKit.front(at.frame.heads.mapValues { V($0) }, at: at.centre.z) - 0.07, "\(id) frame \(i)")
            let line = try #require(at.across["r"]), upper = try #require(at.hands["r"]), lower = try #require(at.hands["l"])
            #expect(abs(line.z) > 0.95 && upper.z - lower.z > 0.08)
            let run = (at.rim - at.ring).unit
            #expect(abs(run.x) > 0.9 && abs(run.z) < 0.15, "\(id) frame \(i)")
            guard i <= 24 else { continue }
            for s in ["r", "l"] {
                #expect((try point(at.frame, "foot.\(s)") - point(first.frame, "foot.\(s)")).length < 0.01, "\(id) frame \(i)")
            }
            out.append(at.centre.y)
            lengths.append((at.ring - staging.wheel).length)
        }
        // Pressed out a forearm's length and back, while the cable's length hardly changes:
        // the stack hangs lifted all the time.
        let furthest: Double = out.min() ?? 0, longest: Double = lengths.max() ?? 0, shortest: Double = lengths.min() ?? 0
        #expect(out[0] - furthest > 0.25)
        #expect(longest - shortest < 0.1)
        let rest: Double = plates(liftedPlates(y: 0, height: CablePallofStaging.top, travel: 0))
        for t in [0.0, 0.25, 0.5] {
            let hung: Double = plates(staging.frame(Figure.smooth(g.keyframes, at: t)).props)
            #expect(hung > rest + 0.2, "\(id) at \(t)")
        }
        // The pulley is a long step to one side, at the height of the hands.
        #expect(staging.wheel.x * staging.side < -1 && abs(staging.wheel.z - first.centre.z) < 0.2)
        let right = try point(first.frame, "shin.r"), left = try point(first.frame, "shin.l")
        switch id {
        case "4193": #expect((staging.side > 0) == (right.z < left.z) && abs(right.z - left.z) > 0.2)
        case "4196": #expect((staging.side > 0) == (right.z > left.z) && abs(right.z - left.z) > 0.2)
        case "4106": #expect(try point(first.frame, "foot.l").y < point(first.frame, "foot.r").y - 0.25)
        default: #expect(abs(try point(first.frame, "foot.l").y - point(first.frame, "foot.r").y) < 0.02)
        }
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

private extension BodyFrame {
    /// The middle of the skull.
    func bulkHead(_ body: Body3D) -> Body3D.V {
        let rest = body.head["head"] ?? Body3D.V(0, 0, 1.5)
        let at = heads["head"].map { Body3D.V($0) } ?? rest
        let turn = rotations["head"].map { Body3D.M($0) } ?? .identity
        return at + turn * (Body3D.V(0, -0.005, 1.59) - rest)
    }
}

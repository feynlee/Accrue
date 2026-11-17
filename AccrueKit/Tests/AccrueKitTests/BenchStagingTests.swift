import Foundation
import Testing
@testable import AccrueKit

struct BenchStagingTests {
    typealias V = Body3D.V
    typealias Skin = BenchStagings.Skin

    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func press(_ id: String) throws -> (HowToGuide, BenchPressStaging) {
        let g = try guide(id)
        return (g, try #require(BenchPressStaging(g, body), "\(id) is not staged"))
    }

    /// The loop's poses, and one more for each of the family's mistakes.
    private func poses(_ g: HowToGuide, steps: Int = 24, faults: Bool = false) -> [JointPose] {
        var out = (0...steps).map { Figure.smooth(g.keyframes, at: Double($0) / Double(steps)) }
        if faults {
            for fault in g.steps.flatMap(\.mistakes).compactMap(\.pose) {
                out.append(Figure.applying(fault, to: Figure.smooth(g.keyframes, at: g.faultT)))
            }
        }
        return out
    }

    private func at(_ f: BodyFrame, _ bone: String) throws -> V { V(try #require(f.heads[bone], "\(bone)")) }

    /// How far `p` is from the line through `c` along `axis`.
    private func off(_ p: V, line c: V, along axis: V) -> Double {
        let d = p - c
        return (d - axis.unit * d.dot(axis.unit)).length
    }

    /// How far `p` is from a handle `length` long centred on `c` along `axis`.
    private func off(_ p: V, handle c: V, along axis: V, length: Double) -> Double {
        let a = axis.unit, d = p - c
        let t = max(-length / 2, min(length / 2, d.dot(a)))
        return (d - a * t).length
    }

    /// Points of the face and the back of the skull in one frame.
    private func headPoints(_ f: BodyFrame) throws -> [V] {
        let neck = try at(f, "neck"), base = try at(f, "head")
        let turn = Body3D.M(try #require(f.rotations["head"]))
        let rest = try #require(body.head["head"])
        return PullUpStaging.face.map { neck + turn * V(0, -$0.0, $0.1) }
            + Skin.skull.map { base + turn * (V(0, $0.0, $0.1) - rest) }
    }

    /// A point of the skin on `bone`, as the stagings place it.
    private func skin(_ f: BodyFrame, _ bone: String, _ pairs: [(Double, Double)]) throws -> [V] {
        let base = try at(f, bone), rest = try #require(body.head[bone])
        let turn = Body3D.M(try #require(f.rotations[bone]))
        return pairs.map { base + turn * (V(0, $0.0, $0.1) - rest) }
    }

    @Test func barbellBenchPressOnItsBench() throws {
        let (g, staging) = try press(StarterIDs.benchPress)
        #expect(staging.kinds == [.barbell, .bench])
        let pad = staging.recline
        #expect(pad.kind == .flat)
        let first = staging.solve(g.keyframes[0].pose, depth: 1).frame
        var high = -Double.infinity, low = Double.infinity
        for pose in poses(g) {
            let (f, holds, _) = staging.solve(pose, depth: staging.depth)
            // Both hands closed on one straight, level bar, at the grip's width.
            #expect(holds.count == 2)
            #expect(abs(holds[0].at.z - holds[1].at.z) < 1e-9 && abs(holds[0].at.y - holds[1].at.y) < 1e-9)
            let bar = (holds[0].at + holds[1].at) * 0.5
            for (i, s) in ["r", "l"].enumerated() {
                let knuckle = try at(f, "f3a.\(s)")
                #expect(off(knuckle, line: bar, along: V(1, 0, 0)) < 0.05)
                #expect(abs(knuckle.x - holds[i].at.x) < 0.04)
            }
            // The feet are flat on the floor beside the bench and never move.
            for s in ["r", "l"] {
                #expect(f.heads["foot.\(s)"] == first.heads["foot.\(s)"])
                #expect(abs(try at(f, "foot.\(s)").z - body.ankleHeight) < 1e-6)
                #expect(try at(f, "toes.\(s)").z < 0.03)
                #expect(abs(try at(f, "foot.\(s)").x) > BenchStagings.Recline.padWidth / 2 + 0.06)
            }
            // Hips, upper back and head rest on the pad: neither sunk in nor floating.
            let hips = try skin(f, "pelvis", Skin.hips).map(pad.height).min() ?? 1
            let back = try skin(f, "thorax", Skin.back).map(pad.height).min() ?? 1
            let skull = try skin(f, "head", Skin.skull).map(pad.height).min() ?? 1
            #expect(abs(hips + pad.sink) < 0.003, "hips \(hips)")
            #expect(abs(back + pad.sink) < 0.003, "back \(back)")
            #expect(abs(skull) < 0.004, "head \(skull)")
            // The bar stays off the chest and clear of the face.
            let chest = try at(f, "thorax"), rest = try #require(body.head["thorax"])
            let turn = Body3D.M(try #require(f.rotations["thorax"]))
            for (up, front) in Skin.chest {
                let p = chest + turn * (V(0, -front, up) - rest)
                #expect(off(p, line: bar, along: V(1, 0, 0)) > BenchPressStaging.barRadius, "chest at \(up)")
            }
            for p in try headPoints(f) { #expect(off(p, line: bar, along: V(1, 0, 0)) > 0.08) }
            high = max(high, bar.z)
            low = min(low, bar.z)
        }
        // Straight arms hold the bar over the shoulders; it comes down a good way, to the chest.
        let (top, holds, _) = staging.solve(g.keyframes[0].pose, depth: 1)
        let shoulder = try at(top, "humerus.r")
        #expect(abs(holds[0].at.y - shoulder.y) < 0.02)
        #expect(high - low > 0.3)
        let bottom = staging.solve(Figure.smooth(g.keyframes, at: 0.6), depth: 1)
        #expect(bottom.holds[0].at.y < (try at(bottom.frame, "humerus.r")).y - 0.08)
        // The rack's hooks are behind the bar's highest place and just under it.
        let hook = try #require(staging.fixed.last { $0.size == [0.05, 0.07, 0.016] })
        #expect(hook.center[1] > holds[0].at.y + 0.05 && hook.center[2] < high && hook.center[2] > high - 0.1)
    }

    @Test func mistakesShowOnTheBench() throws {
        let (g, staging) = try press(StarterIDs.benchPress)
        let pose = Figure.smooth(g.keyframes, at: g.faultT)
        let good = staging.solve(pose, depth: 1)
        // Hips pushed up leave the pad; the feet and the upper back stay where they were.
        let lifted = staging.solve(Figure.applying(JointPose(angles: ["hipFlex": -25, "lumbar": -15]), to: pose), depth: 1)
        #expect(try at(lifted.frame, "pelvis").z > (try at(good.frame, "pelvis")).z + 0.04)
        #expect((try at(lifted.frame, "foot.r") - (try at(good.frame, "foot.r"))).length < 1e-9)
        // Flared elbows bring the bar toward the neck.
        let flared = staging.solve(Figure.applying(JointPose(angles: ["shoulderAbd": 30]), to: pose), depth: 1)
        #expect(flared.holds[0].at.y > good.holds[0].at.y + 0.05)
    }

    @Test func inclineSitsOnTheSeatAndDeclineHooksTheLegs() throws {
        let (gi, incline) = try press("0047")
        #expect(incline.recline.kind == .incline && incline.recline.tilt > 20)
        for pose in poses(gi, steps: 8) {
            let f = incline.solve(pose, depth: 1).frame
            let seat = try skin(f, "pelvis", Skin.seat).map(\.z).min() ?? 0
            #expect(abs(seat - (incline.recline.hinge.z - incline.recline.sink)) < 0.004, "seat \(seat)")
            let back = try skin(f, "thorax", Skin.back).map(incline.recline.height).min() ?? 1
            #expect(abs(back + incline.recline.sink) < 0.003)
            #expect(try at(f, "toes.r").z < 0.03)
            #expect(try at(f, "neck").z > (try at(f, "pelvis")).z + 0.2)
        }
        let (gd, decline) = try press("0033")
        #expect(decline.recline.kind == .decline)
        let first = decline.solve(gd.keyframes[0].pose, depth: 1).frame
        for pose in poses(gd, steps: 8) {
            let f = decline.solve(pose, depth: 1).frame
            // Head lower than the hips, knees over the roller, feet off the floor and still.
            #expect(try at(f, "head").z < (try at(f, "pelvis")).z - 0.1)
            #expect(try at(f, "shin.r").z > (try at(f, "pelvis")).z + 0.05)
            #expect(try at(f, "foot.r").z > 0.3)
            #expect(f.heads["foot.r"] == first.heads["foot.r"])
        }
    }

    @Test func floorPressStopsAtTheFloor() throws {
        let (g, staging) = try press("3724")
        #expect(staging.kinds == [.barbell])
        #expect(staging.fixed.isEmpty)
        var lowest = Double.infinity
        for pose in poses(g) {
            let (f, holds, elbow) = staging.shown(pose)
            lowest = min(lowest, elbow)
            #expect(holds[0].at.z - BenchPressStaging.plate > 0)
            #expect(try skin(f, "pelvis", Skin.hips).map(\.z).min() ?? 1 > -0.01)
        }
        #expect(lowest > BenchPressStaging.elbowRoom - 0.003 && lowest < BenchPressStaging.elbowRoom + 0.02, "elbow \(lowest)")
    }

    /// Every press the staging takes on, through its loop and its mistakes.
    @Test func everyStagedPressHoldsItsWeight() throws {
        var staged = 0
        for ex in catalog.exercises where ex.familyID == "bench-press" {
            guard let g = catalog.howTo(for: ex), let staging = BenchPressStaging(g, body) else { continue }
            staged += 1
            let handles = staging.oneArm ? 1 : 2
            for pose in poses(g, steps: 8, faults: true) {
                let (f, holds, elbow) = staging.shown(pose)
                #expect(holds.count == handles, "\(ex.name)")
                #expect(f.heads.values.allSatisfy { $0.allSatisfy(\.isFinite) }, "\(ex.name)")
                for (i, s) in ["r", "l"].enumerated() where i < holds.count {
                    // The hand is closed on its handle, in the middle of it.
                    let knuckle = try at(f, "f3a.\(s)")
                    #expect(off(knuckle, line: holds[i].at, along: holds[i].across) < 0.05, "\(ex.name)")
                    #expect((knuckle - holds[i].at).length < 0.07, "\(ex.name)")
                    // Nothing held comes near the head or goes through the floor.
                    let clear = staging.load == .dumbbells ? BenchStagings.dumbbellHead : BenchPressStaging.barRadius
                    let length = staging.load == .dumbbells ? 0.27 : 2.0
                    for p in try headPoints(f) {
                        #expect(off(p, handle: holds[i].at, along: holds[i].across, length: length) > clear + 0.02, "\(ex.name)")
                    }
                    #expect(holds[i].at.z > (staging.load == .dumbbells ? BenchStagings.dumbbellHead : 0.15), "\(ex.name)")
                }
                #expect(elbow > BenchPressStaging.elbowRoom - 0.003, "\(ex.name)")
                // Planted feet are flat on the floor.
                if staging.recline.kind != .decline, !staging.recline.legsOut {
                    for s in ["r", "l"] { #expect(try at(f, "toes.\(s)").z < 0.03, "\(ex.name)") }
                }
            }
        }
        #expect(staged >= 65, "\(staged) presses staged")
    }

    @Test func otherPressesKeepThePlainEquipment() throws {
        for name in ["dumbbell press on exercise ball", "barbell jm bench press", "smith bench press",
                     "dumbbell alternate bench press (high start)", "cable bench press"] {
            guard let ex = catalog.exercises.first(where: { $0.name == name }), let g = catalog.howTo(for: ex) else { continue }
            #expect(BenchStagings.make(g, body) == nil, "\(name)")
        }
    }

    // MARK: Fly, pullover and lying extension

    private func lying(_ id: String) throws -> (HowToGuide, BenchLyingStaging) {
        let g = try guide(id)
        return (g, try #require(BenchLyingStaging(g, body), "\(id) is not staged"))
    }

    /// The hands of both sides are closed on their handles, in the middle of them.
    private func handsHold(_ f: BodyFrame, _ holds: [BenchLyingStaging.Hold], _ name: String) throws {
        for (i, s) in ["r", "l"].enumerated() where i < holds.count {
            let knuckle = try at(f, "f3a.\(s)")
            #expect(off(knuckle, line: holds[i].at, along: holds[i].across) < 0.05, "\(name)")
            #expect((knuckle - holds[i].at).length < 0.07, "\(name)")
        }
    }

    /// The body lies on its pad with the feet where they were first put.
    private func lies(_ f: BodyFrame, like first: BodyFrame, on pad: BenchStagings.Recline, _ name: String) throws {
        let hips = try skin(f, "pelvis", Skin.hips).map(pad.height).min() ?? 1
        let back = try skin(f, "thorax", Skin.back).map(pad.height).min() ?? 1
        #expect(abs(hips + pad.sink) < 0.003, "\(name) hips \(hips)")
        #expect(abs(back + pad.sink) < 0.003, "\(name) back \(back)")
        for s in ["r", "l"] {
            #expect((try at(f, "foot.\(s)") - (try at(first, "foot.\(s)"))).length < 1e-6, "\(name)")
            if pad.kind != .decline { #expect(try at(f, "toes.\(s)").z < 0.03, "\(name)") }
        }
    }

    @Test func dumbbellFlyOpensOverTheBench() throws {
        let (g, staging) = try lying("0308")
        #expect(staging.move == .fly && staging.kinds == [.dumbbell, .bench])
        let first = staging.shown(g.keyframes[0].pose).frame
        var narrow = Double.infinity, wide = 0.0, lowest = Double.infinity
        for pose in poses(g) {
            let (f, holds, _, _) = staging.shown(pose)
            #expect(holds.count == 2)
            try handsHold(f, holds, "fly")
            try lies(f, like: first, on: staging.recline, "fly")
            // The two dumbbells move as a pair and never meet.
            #expect(abs(holds[0].at.z - holds[1].at.z) < 1e-3 && abs(holds[0].at.x + holds[1].at.x) < 1e-3)
            #expect(abs(holds[0].at.x - holds[1].at.x) > 2 * BenchStagings.dumbbellHead)
            narrow = min(narrow, abs(holds[0].at.x))
            wide = max(wide, abs(holds[0].at.x))
            lowest = min(lowest, holds[0].at.z - (try at(f, "humerus.r")).z)
        }
        // From together over the chest out to the sides, about level with the shoulders.
        #expect(narrow < 0.08 && wide > 0.55, "from \(narrow) to \(wide)")
        #expect(abs(lowest) < 0.12, "hands end \(lowest) from shoulder height")
    }

    @Test func floorFlyStopsAtTheFloor() throws {
        let (g, staging) = try lying("4149")
        #expect(staging.recline.kind == .floor && staging.fixed.isEmpty && staging.kinds == [.dumbbell])
        for pose in poses(g, faults: true) {
            let (f, holds, elbow, _) = staging.shown(pose)
            try handsHold(f, holds, "floor fly")
            #expect(elbow > BenchLyingStaging.elbowRoom - 0.003, "elbow \(elbow)")
            for hold in holds { #expect(hold.at.z > BenchStagings.dumbbellHead) }
        }
    }

    @Test func barbellPulloverGoesBehindTheHead() throws {
        let (g, staging) = try lying("0073")
        #expect(staging.move == .pullover && staging.load == .barbell)
        let pad = staging.recline
        let first = staging.shown(g.keyframes[0].pose).frame
        var near = Double.infinity, far = -Double.infinity
        for pose in poses(g) {
            let (f, holds, _, _) = staging.shown(pose)
            #expect(holds.count == 2)
            try handsHold(f, holds, "pullover")
            try lies(f, like: first, on: pad, "pullover")
            // One level bar across the body, clear of the head, the pad and the floor.
            #expect(abs(holds[0].at.z - holds[1].at.z) < 1e-9 && abs(holds[0].at.y - holds[1].at.y) < 1e-9)
            let bar = (holds[0].at + holds[1].at) * 0.5
            for p in try headPoints(f) { #expect(off(p, line: bar, along: V(1, 0, 0)) > 0.05) }
            let up = (bar - pad.hinge).dot(pad.along)
            #expect(up > pad.headEnd || pad.height(bar) > BenchLyingStaging.barRadius)
            #expect(bar.z > 0.225)
            near = min(near, up)
            far = max(far, up)
        }
        // From over the chest to past the top of the head.
        let shoulder = (try at(first, "humerus.r") - pad.hinge).dot(pad.along)
        #expect(near < shoulder + 0.12, "starts \(near - shoulder) past the shoulders")
        #expect(far > pad.headEnd - 0.05, "ends \(far) of \(pad.headEnd)")
    }

    @Test func dumbbellPulloverIsClaspedByBothHands() throws {
        let (g, staging) = try lying("0375")
        #expect(staging.load == .single && staging.kinds == [.dumbbell, .bench])
        let pad = staging.recline
        let first = staging.shown(g.keyframes[0].pose).frame
        var near = Double.infinity, far = -Double.infinity
        for pose in poses(g) {
            let (f, holds, _, _) = staging.shown(pose)
            let top = try #require(holds.first).at
            #expect(holds.count == 1 && abs(top.x) < 1e-9)
            try lies(f, like: first, on: pad, "dumbbell pullover")
            // A palm on each side of the upper head.
            for (s, m) in [("r", 1.0), ("l", -1.0)] {
                let palm = try at(f, "f3a.\(s)")
                #expect(-m * palm.x > BenchStagings.dumbbellHead * 0.6 && (palm - top).length < 0.14, "\(s) \(palm - top)")
            }
            // The dumbbell hangs clear of the head and of the pad's end.
            let middle = top - V(0, 0, 0.1)
            for p in try headPoints(f) {
                #expect(off(p, handle: middle, along: V(0, 0, 1), length: 0.27) > BenchStagings.dumbbellHead + 0.005)
            }
            let up = (top - pad.hinge).dot(pad.along)
            #expect(up - BenchStagings.dumbbellHead > pad.headEnd || pad.height(top) > 0.235)
            #expect(top.z > 0.235)
            near = min(near, up)
            far = max(far, up)
        }
        #expect(far - near > 0.3 && far > pad.headEnd, "from \(near) to \(far)")
    }

    @Test func lyingExtensionFoldsOnlyTheElbows() throws {
        for id in ["0061", "5873", "0351"] {
            let (g, staging) = try lying(id)
            #expect(staging.move == .triceps)
            let pad = staging.recline
            let first = staging.shown(g.keyframes[0].pose).frame
            var high = -Double.infinity, low = Double.infinity
            for pose in poses(g) {
                let (f, holds, _, clear) = staging.shown(pose)
                #expect(holds.count == 2)
                try handsHold(f, holds, id)
                try lies(f, like: first, on: pad, id)
                // The elbows stay where the first pose has them.
                for s in ["r", "l"] {
                    #expect((try at(f, "ulna.\(s)") - (try at(first, "ulna.\(s)"))).length < 0.03, "\(id) elbow \(s)")
                }
                #expect(clear > -0.004, "\(id) clear \(clear)")
                if staging.load == .dumbbells {
                    for hold in holds {
                        for p in try headPoints(f) {
                            #expect(off(p, handle: hold.at, along: hold.across, length: 0.27) > BenchStagings.dumbbellHead + 0.01, "\(id)")
                        }
                    }
                } else {
                    let bar = (holds[0].at + holds[1].at) * 0.5
                    #expect(abs(holds[0].at.z - holds[1].at.z) < 1e-9)
                    for p in try headPoints(f) { #expect(off(p, line: bar, along: V(1, 0, 0)) > 0.06, "\(id)") }
                }
                high = max(high, holds[0].at.z)
                low = min(low, holds[0].at.z)
            }
            #expect(high - low > 0.2, "\(id) travels \(high - low)")
        }
    }

    /// Every fly, pullover and extension the staging takes on, through its loop and its mistakes.
    @Test func everyStagedLyingMoveHoldsItsWeight() throws {
        var staged: [BenchLyingStaging.Move: Int] = [:]
        for ex in catalog.exercises where ["chest-fly", "pullover", "triceps-extension"].contains(ex.familyID) {
            guard let g = catalog.howTo(for: ex), let staging = BenchLyingStaging(g, body) else { continue }
            staged[staging.move, default: 0] += 1
            for pose in poses(g, steps: 8, faults: true) {
                let (f, holds, elbow, _) = staging.shown(pose)
                #expect(f.heads.values.allSatisfy { $0.allSatisfy(\.isFinite) }, "\(ex.name)")
                #expect(holds.count == (staging.oneArm || staging.load == .single ? 1 : 2), "\(ex.name)")
                if staging.load != .single { try handsHold(f, holds, ex.name) }
                // Nothing held goes through the floor, and no elbow either.
                let least = staging.load == .barbell ? 0.225 : staging.load == .ezBar ? 0.15 : BenchStagings.dumbbellHead
                for hold in holds { #expect(hold.at.z > least, "\(ex.name)") }
                #expect(elbow > 0.03, "\(ex.name) elbow \(elbow)")
                if staging.recline.kind != .decline {
                    for s in ["r", "l"] { #expect(try at(f, "toes.\(s)").z < 0.03, "\(ex.name)") }
                }
            }
        }
        #expect(staged[.fly, default: 0] >= 8, "\(staged)")
        #expect(staged[.pullover, default: 0] >= 12, "\(staged)")
        #expect(staged[.triceps, default: 0] >= 10, "\(staged)")
    }

    // MARK: Hip thrust and bridge

    private func thrust(_ id: String) throws -> (HowToGuide, BenchThrustStaging) {
        let g = try guide(id)
        return (g, try #require(BenchThrustStaging(g, body), "\(id) is not staged"))
    }

    @Test func hipThrustTipsAboutTheBenchEdge() throws {
        let (g, staging) = try thrust("1060")
        #expect(staging.kinds == [.barbell, .bench])
        #expect(staging.fixed.first?.finish == .pad)
        let first = staging.solve(g.keyframes[0].pose).frame
        let behind = try #require(Skin.back.min { abs($0.1 - staging.rests) < abs($1.1 - staging.rests) }).0
        var high = -Double.infinity, low = Double.infinity
        for pose in poses(g, faults: true) {
            let (f, bar) = staging.solve(pose)
            // The back stays on the bench's edge and the feet stay flat where they are.
            let rest = try #require(try skin(f, "thorax", [(behind, staging.rests)]).first)
            #expect((rest - (staging.edge - V(0, 0, BenchThrustStaging.sink))).length < 1e-6)
            for s in ["r", "l"] {
                #expect((try at(f, "foot.\(s)") - (try at(first, "foot.\(s)"))).length < 1e-6)
                #expect(try at(f, "toes.\(s)").z < 0.03)
                // Both hands closed on the bar beside the hips.
                let knuckle = try at(f, "f3a.\(s)")
                #expect(off(knuckle, line: bar, along: V(1, 0, 0)) < 0.05)
                #expect(abs(abs(knuckle.x) - BenchThrustStaging.halfGrip) < 0.04)
            }
            // The bar rides on the hips: in front of the pelvis, never inside it, plates off the floor.
            let pelvis = try at(f, "pelvis")
            #expect((bar - pelvis).length > 0.1 && (bar - pelvis).length < 0.25, "bar \((bar - pelvis).length) from the hips")
            #expect(bar.z > 0.225 + 0.005, "bar at \(bar.z)")
            high = max(high, pelvis.z)
            low = min(low, pelvis.z)
        }
        #expect(high - low > 0.15, "hips rise \(high - low)")
        // At the top the thighs are about level and the shins about upright.
        let top = staging.solve(g.keyframes.max(by: { staging.travel($0.pose) < staging.travel($1.pose) })!.pose).frame
        #expect(abs(try at(top, "shin.r").z - (try at(top, "femur.r")).z) < 0.08)
        #expect(abs(try at(top, "shin.r").y - (try at(top, "foot.r")).y) < 0.06)
    }

    @Test func barbellBridgeLiesOnTheFloor() throws {
        let (g, staging) = try thrust("1409")
        #expect(staging.kinds == [.barbell] && staging.fixed.isEmpty)
        var high = -Double.infinity, low = Double.infinity
        for pose in poses(g, faults: true) {
            let (f, bar) = staging.solve(pose)
            // Shoulders and head on the floor, feet flat, plates off it.
            let skull = try skin(f, "head", Skin.skull).map(\.z).min() ?? 1
            #expect(abs(skull) < 0.01, "head \(skull) trunk \(pose.angles["trunk"] ?? 0) lumbar \(pose.angles["lumbar"] ?? 0)")
            let back = try skin(f, "thorax", Skin.back).map(\.z).min() ?? 1
            #expect(back > -BenchThrustStaging.sink - 1e-6 && back < 0.01, "back \(back)")
            for s in ["r", "l"] {
                #expect(try at(f, "toes.\(s)").z < 0.03)
                #expect(off(try at(f, "f3a.\(s)"), line: bar, along: V(1, 0, 0)) < 0.05)
            }
            #expect(bar.z > 0.225 + 0.005, "bar at \(bar.z)")
            high = max(high, try at(f, "pelvis").z)
            low = min(low, try at(f, "pelvis").z)
        }
        #expect(high - low > 0.08, "hips rise \(high - low)")
    }

    @Test func otherLyingMovesKeepThePlainEquipment() throws {
        for name in ["dumbbell fly on exercise ball", "cable lying fly", "dumbbell lying extension (across face)",
                     "barbell pullover to press", "barbell one leg hip thrust", "barbell hip thrust with resistance band",
                     "barbell kas glute bridge", "dumbbell incline twisted flyes", "lever pec deck fly",
                     "cable straight arm pulldown", "smith hip thrust"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(BenchStagings.make(g, body) == nil, "\(name)")
        }
    }
}

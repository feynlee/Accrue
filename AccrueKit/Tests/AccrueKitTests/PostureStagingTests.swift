import Foundation
import Testing
@testable import AccrueKit

struct PostureStagingTests {
    typealias V = Body3D.V
    typealias M = Body3D.M

    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func staged(_ id: String) throws -> (HowToGuide, PostureStaging) {
        let g = try guide(id)
        return (g, try #require(Stagings.make(g, body) as? PostureStaging, "\(id) is not staged"))
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

    private func hips(_ f: BodyFrame) throws -> V { (try at(f, "femur.r") + (try at(f, "femur.l"))) * 0.5 }

    /// How far the bar a frame holds is inside the body or `blocks`, and how far each hand's
    /// grip is from it.
    private func bar(_ s: PostureStaging, _ f: BodyFrame, _ held: Held) throws -> (inside: Double, miss: Double) {
        let hands = try #require(s.plan.hands), bar = try #require(hands.bar), line = try #require(held.bar)
        let g = f.rotations.mapValues { M($0) }, h = f.heads.mapValues { V($0) }
        let rods = body.bulk(g, h, behind: bar.behind, walls: false) + s.blocks
        let out = Body3D.wayOut(line.mid, axis: line.axis, half: bar.length, radius: bar.radius, of: rods, front: V(0, -1, 0))
        var miss = 0.0
        for (side, m) in Handhold.sides {
            let c = try #require(hands.centre(side, g, h))
            miss = max(miss, (c - hands.target(side, m, mid: line.mid, axis: line.axis, bar)).length)
        }
        return (out?.length ?? 0, miss)
    }

    @Test func seatedSitsOnTheBenchWithFeetFlat() throws {
        // Dumbbell curl, EZ-bar curl, barbell front raise, band curl, bent-over kickback, and a curl on a ball.
        for id in ["0391", "1458", "4411", "3123", "0394", "0390"] {
            let (g, s) = try staged(id)
            #expect(s.kinds.contains(id == "0390" ? .stabilityBall : .bench))
            let shin = try #require(body.head["foot.r"]).z - (try #require(body.head["shin.r"])).z
            for pose in poses(g, faults: true) {
                let (f, _) = s.solve(pose)
                // Hips on the seat, which is under them and not in them.
                #expect((try hips(f) - s.hip).length < 0.005, "\(id) hips")
                for side in ["r", "l"] {
                    let ankle = try #require(s.ankles[side])
                    #expect((try at(f, "foot.\(side)") - ankle).length < 0.004, "\(id) foot slides")
                    #expect(abs(try at(f, "toes.\(side)").z - (try #require(body.head["toes.\(side)"])).z) < 0.01, "\(id) foot not flat")
                    // Shins upright.
                    #expect(abs(try at(f, "shin.\(side)").z - ankle.z + shin) < 0.01, "\(id) knee height")
                }
                let neck = try at(f, "neck").z - s.hip.z
                #expect(neck > 0.2, "\(id) trunk up \(neck)")
            }
            // The seat's top is a hand under the hip joints.
            let top = s.fixed.filter { $0.finish == .pad || $0.finish == .accent }.map { $0.center[2] + $0.size[2] / 2 }.max() ?? 0
            #expect(abs(s.hip.z - top - MachineFit.seat) < (id == "0390" ? 0.035 : 0.01), "\(id) seat height")
        }
    }

    @Test func seatedPressSitsAgainstItsBackPad() throws {
        let (g, s) = try staged("0091")
        let chair = try #require(s.chair)
        for pose in poses(g, faults: true) {
            let (f, held) = s.solve(pose)
            let off = (try hips(f) - chair.rest.hip).length
            #expect(off < 0.1, "hips \(off) off the seat")
            for side in ["r", "l"] {
                #expect((try at(f, "foot.\(side)") - (try #require(chair.ankles[side]))).length < 0.004)
            }
            // The bar is over the shoulders, in both hands.
            let line = try #require(held.bar)
            #expect(line.mid.z > (try at(f, "humerus.r").z))
            #expect(try bar(s, f, held).miss < 0.02)
        }
    }

    @Test func aBarComesDownOntoTheThighsNotThroughThem() throws {
        for id in ["1458", "4411"] {
            let (g, s) = try staged(id)
            var last: V?
            var lowest = Double.infinity
            for pose in poses(g, steps: 48) {
                let (f, held) = s.solve(pose)
                let line = try #require(held.bar)
                let fit = try bar(s, f, held)
                #expect(fit.inside < 0.012, "\(id) bar in the body by \(fit.inside)")
                #expect(fit.miss < 0.02, "\(id) hands off the bar by \(fit.miss)")
                if let last { #expect((line.mid - last).length < 0.12, "\(id) bar jumps") }
                last = line.mid
                lowest = min(lowest, line.mid.z)
            }
            // Its lowest is on top of the thighs.
            #expect(lowest > s.hip.z + 0.07, "\(id) bar at \(lowest)")
        }
    }

    @Test func lyingBackTakesTheRaiseOverTheChest() throws {
        let (g, s) = try staged("10588")
        let pad = try #require(s.recline)
        var heights: [Double] = []
        for pose in poses(g, faults: true) {
            let (f, held) = s.solve(pose)
            // Hips and upper back on the pad.
            for (bone, skin) in [("pelvis", BenchStagings.Skin.hips), ("thorax", BenchStagings.Skin.back)] {
                let base = try at(f, bone), rest = try #require(body.head[bone])
                let turn = M(try #require(f.rotations[bone]))
                let low = skin.map { pad.height(base + turn * (V(0, $0.0, $0.1) - rest)) }.min() ?? 0
                #expect(low > -0.03 && low < 0.03, "\(bone) \(low) over the pad")
            }
            for side in ["r", "l"] { #expect(abs(try at(f, "foot.\(side)").z - body.ankleHeight) < 0.005) }
            let fit = try bar(s, f, held)
            #expect(fit.inside < 0.012 && fit.miss < 0.02)
            heights.append(try #require(held.bar).mid.z)
        }
        // From over the thighs to an arm's length above the shoulders.
        #expect((heights.max() ?? 0) - (heights.first ?? 0) > 0.3)
    }

    @Test func faceDownLiesOnThePadWithTheArmsHanging() throws {
        // Dumbbell row on an incline, barbell row on one, and a barbell row lying flat.
        for id in ["1331", "0049", "3654"] {
            let (g, s) = try staged(id)
            guard case .prone(let lean) = s.support else { Issue.record("\(id) is not face down"); continue }
            let pad = try #require(s.fixed.first)
            let out = M(pad.rotation) * V(0, 0, 1)
            let all = poses(g, steps: 48)
            var last: V?
            for (i, pose) in all.enumerated() {
                let (f, held) = s.solve(pose)
                #expect((try hips(f) - s.hip).length < 0.005, "\(id) hips")
                // The chest rests on the pad: the hip joints and the rib cage's base are the
                // depth of the trunk above its top.
                for bone in ["femur.r", "thorax"] {
                    let gap = (try at(f, bone) - V(pad.center)).dot(out) - pad.size[2] / 2
                    #expect(gap > 0.09 && gap < 0.2, "\(id) \(bone) \(gap) off the pad")
                }
                if lean <= 80 {
                    for side in ["r", "l"] {
                        #expect((try at(f, "foot.\(side)") - (try #require(s.ankles[side]))).length < 0.004, "\(id) foot slides")
                        let tip = try #require(body.tip("toes.\(side)", f.rotations.mapValues { M($0) }, f.heads.mapValues { V($0) }))
                        #expect(tip.z > -0.01 && tip.z < 0.05, "\(id) toes at \(tip.z)")
                    }
                }
                if i == 0 {
                    // Arms long, straight down from the shoulders.
                    let shoulder = try at(f, "humerus.r"), hand = try at(f, "hand.r")
                    #expect(shoulder.z - hand.z > 0.4 && abs(shoulder.y - hand.y) < 0.2, "\(id) arms hang")
                }
                if let line = held.bar {
                    let fit = try bar(s, f, held)
                    #expect(fit.inside < 0.012, "\(id) bar in the body or the bench by \(fit.inside)")
                    #expect(fit.miss < 0.02, "\(id) hands off the bar")
                    #expect(line.mid.z > 0.22, "\(id) plates in the floor")
                    if let last { #expect((line.mid - last).length < 0.12, "\(id) bar jumps at \(i)") }
                    last = line.mid
                } else {
                    for side in ["r", "l"] { #expect(try at(f, "hand.\(side)").z > 0.1, "\(id) hand in the floor") }
                }
            }
        }
    }

    @Test func everyStagedExerciseRestsOnItsSupport() throws {
        var count = 0
        for ex in catalog.exercises where !ex.hidden {
            guard let g = catalog.howTo(for: ex), let s = Stagings.make(g, body) as? PostureStaging else { continue }
            count += 1
            for pose in poses(g, steps: 6, faults: true) {
                let (f, props) = s.frame(pose)
                #expect(f.heads.values.allSatisfy { $0.allSatisfy(\.isFinite) }, "\(ex.id)")
                #expect(props.allSatisfy { $0.center.allSatisfy(\.isFinite) }, "\(ex.id)")
                if s.recline == nil { #expect((try hips(f) - (s.chair?.rest.hip ?? s.hip)).length < 0.11, "\(ex.id) \(ex.name) hips") }
                for bone in ["foot.r", "foot.l", "toes.r", "toes.l", "hand.r", "hand.l", "head"] {
                    #expect(try at(f, bone).z > 0.0, "\(ex.id) \(ex.name) \(bone) in the floor")
                }
            }
        }
        #expect(count > 100)
    }

    @Test func otherPicturesAreNotSatOrLaidDown() throws {
        // A cable curl, an incline press and raise, a head-supported row, side-lying raises, a
        // band press, a barbell shrug: not these pictures.
        for id in ["1641", "5261", "0323", "4744", "7252", "0341", "3122", "4016"] {
            #expect(PostureStagings.support(for: try guide(id), body) == nil, "\(id)")
        }
        // Standing exercises of the same families stay as they are.
        for ex in catalog.exercises where ["biceps-curl", "front-raise", "lateral-raise"].contains(ex.familyID ?? "") {
            guard let g = catalog.howTo(for: ex), !["seated", "lying", "incline", "prone", "ball", "bench", "supine", "chest support",
                                                    "chair", "sitting", "face down"].contains(where: g.exerciseName.contains) else { continue }
            #expect(PostureStagings.make(g, body) == nil, "\(ex.id) \(ex.name)")
        }
    }

    @Test func aStrayBenchOrBallIsTakenOutOfTheBody() throws {
        // A ball on the wall, a ball to bend over, a bench beside the box, a cable curl's bench.
        for id in ["3240", "0700", "4821", "1641"] {
            let g = try guide(id)
            let plain = PropPlan(guide: g, body: body, plain: true)
            let before = (0...12).map { plain.frame(at: Double($0) / 12).body }
            #expect(PostureAsideStaging.through(before, plain.fixed), "\(id) was not in its bench or ball")
            let s = try #require(Stagings.make(g, body) as? PostureAsideStaging, "\(id)")
            let plan = PropPlan(guide: g, body: body)
            let after = (0...12).map { plan.frame(at: Double($0) / 12).body }
            #expect(!PostureAsideStaging.through(after, s.fixed), "\(id) still in it")
            // The body is the plain picture's.
            for (a, b) in zip(before, after) {
                #expect((try at(a, "pelvis") - (try at(b, "pelvis"))).length < 0.03, "\(id) body moved")
                #expect((try at(a, "hand.r") - (try at(b, "hand.r"))).length < 0.06, "\(id) hand moved")
            }
        }
    }

    /// POSTURE_LIST=/path writes every exercise this group stages, and on what.
    @Test func list() throws {
        guard let path = ProcessInfo.processInfo.environment["POSTURE_LIST"] else { return }
        var lines: [String] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let g = catalog.howTo(for: ex), let staged = Stagings.make(g, body) else { continue }
            var on = ""
            if let s = staged as? PostureStaging { on = "\(s.support)" } else if staged is PostureAsideStaging { on = "aside" } else { continue }
            lines.append("\(ex.id)\t\(g.familyID)\t\(g.subtypeID ?? "-")\t\(g.equipment ?? "-")\t\(on)\t\(g.exerciseName)")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

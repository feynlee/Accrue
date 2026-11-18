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
                                                    "chair", "sitting", "face down", "kneeling"].contains(where: g.exerciseName.contains) else { continue }
            #expect(PostureStagings.make(g, body) == nil, "\(ex.id) \(ex.name)")
        }
    }

    @Test func aStrayBenchOrBallIsTakenOutOfTheBody() throws {
        // A ball on the wall, a ball to bend over, a cable curl's bench.
        for id in ["3240", "0700", "7921"] {
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

    /// How high the lowest skin of `bones` is in a frame.
    private func low(_ f: BodyFrame, _ bones: [String] = FloorSkin.whole) -> Double {
        body.floorLow(bones, f.rotations.mapValues { M($0) }, f.heads.mapValues { V($0) })
    }

    // MARK: - Sitting with nothing drawn to sit on
    @Test func seatedWithNothingDrawnSitsOnABench() throws {
        // Wrist curls and a bent-over stretch whose keyframes sit on nothing; a shoulder turn, arm
        // and wrist stretches and a chin tuck whose keyframes stand.
        for id in ["4234", "5579", "1805", "5001", "1975", "2093", "5063"] {
            let (g, s) = try staged(id)
            #expect(s.support == .seat(back: false), "\(id)")
            #expect(s.kinds.contains(.bench), "\(id)")
            let top = try #require(s.fixed.filter { $0.finish == .pad }.map { $0.center[2] + $0.size[2] / 2 }.max(), "\(id) has no pad")
            var last: BodyFrame?
            for pose in poses(g, faults: true) {
                let f = s.frame(pose).body
                // Hips on the pad, knees level with them, feet flat under the knees.
                #expect(abs(try hips(f).z - MachineFit.seat - top) < 0.01, "\(id) hips off the pad")
                for side in ["r", "l"] {
                    #expect(abs(try at(f, "shin.\(side)").z - (try hips(f).z)) < 0.03, "\(id) knee")
                    #expect(abs(try at(f, "foot.\(side)").z - body.ankleHeight) < 0.005, "\(id) ankle")
                    #expect(try at(f, "hand.\(side)").z > 0.1, "\(id) hand on the floor")
                }
                if let last { #expect((try at(f, "pelvis") - (try at(last, "pelvis"))).length < 0.05, "\(id) jumps") }
                last = f
            }
        }
        // Someone resting the forearms on the thighs keeps the hands above the knees.
        let (g, s) = try staged("4234")
        for pose in poses(g) {
            let f = s.frame(pose).body
            #expect(try at(f, "hand.r").z > (try at(f, "shin.r").z), "wrist below the knee")
        }
    }

    @Test func aSeatAlreadyDrawnIsLeftAlone() throws {
        // A neck movement and a twist the plain picture already sits on a bench; a stretch
        // done sitting on the floor; a twist on a ball.
        for id in ["3441", "1933", "3564", "1807"] {
            #expect(PostureStagings.seat(for: try guide(id), body) == nil, "\(id)")
        }
    }

    // MARK: - Kneeling
    @Test func kneelingPressKneelsOnTheFloor() throws {
        for (id, half) in [("11017", false), ("2932", false), ("11792", false), ("4577", true), ("9694", true)] {
            let (g, s) = try staged(id)
            #expect(s.support == .kneel(half: half), "\(id)")
            #expect(!s.kinds.contains(.bench), "\(id)")
            for pose in poses(g, faults: true) {
                let f = s.frame(pose).body
                // The right knee is down under the hip, its shin and instep along the floor.
                #expect(abs(try at(f, "shin.r").z - PostureStaging.kneePad) < 0.01, "\(id) knee")
                #expect(abs(try at(f, "shin.r").y - (try at(f, "femur.r").y)) < 0.03, "\(id) thigh not upright")
                #expect(try at(f, "foot.r").y > (try at(f, "shin.r").y) + 0.3, "\(id) shin not behind")
                #expect(try at(f, "foot.r").z < 0.08, "\(id) foot in the air")
                if half {
                    // The left foot is flat in front, its knee about as high as the hips.
                    #expect(abs(try at(f, "foot.l").z - body.ankleHeight) < 0.005, "\(id) front ankle")
                    #expect(try at(f, "foot.l").y < (try at(f, "femur.l").y) - 0.3, "\(id) front foot")
                    #expect(abs(try at(f, "shin.l").z - (try hips(f).z)) < 0.05, "\(id) front knee")
                } else {
                    #expect(abs(try at(f, "shin.l").z - PostureStaging.kneePad) < 0.01, "\(id) left knee")
                }
                #expect(low(f, FloorSkin.legs) > -0.03, "\(id) legs under the floor")
                #expect(try at(f, "neck").z > 1.0, "\(id) trunk not upright")
            }
        }
        // Getting up from the knees, and a band, are other pictures.
        for id in ["5064", "3686", "4776", "4195"] {
            #expect(PostureStagings.kneel(for: try guide(id), body) == nil, "\(id)")
        }
    }

    // MARK: - Put down on the floor or a bench
    @Test func aStretchSatOnNothingSitsOnTheFloor() throws {
        // A butterfly, a straddle and a crossed-leg stretch.
        for id in ["1169", "1902", "1424"] {
            let g = try guide(id)
            let s = try #require(Stagings.make(g, body) as? PostureFloorSitStaging, "\(id) is not staged")
            for pose in poses(g, faults: true) {
                let f = s.frame(pose).body
                // The seat and the legs are both down, and nothing is under the floor.
                #expect(abs(low(f, ["pelvis"])) < 0.02, "\(id) seat off the floor")
                #expect(abs(low(f, FloorSkin.legs)) < 0.02, "\(id) legs off the floor")
                #expect(low(f) > -0.02, "\(id) under the floor")
                #expect(try at(f, "neck").z > 0.4, "\(id) not sitting up")
            }
        }
        // A split, and the same stretch against a wall, stay as they are.
        for id in ["3458", "1905"] {
            #expect(PostureStagings.down(try guide(id), body) == nil, "\(id)")
        }
    }

    @Test func halfKneelingStretchKneelsOnTheFloor() throws {
        // The runner's stretch: one knee down, the other leg out straight in front.
        for id in ["1585", "1913"] {
            let g = try guide(id)
            let s = try #require(Stagings.make(g, body) as? PostureFloorSitStaging, "\(id) is not staged")
            #expect(s.pose == .halfKneeling, "\(id)")
            for pose in poses(g, faults: true) {
                let f = s.frame(pose).body
                // The back knee and its shin are down, and the front heel with them.
                #expect(abs(low(f, ["femur.l", "shin.l", "foot.l", "toes.l"])) < 0.02, "\(id) back leg off the floor")
                #expect(abs(try at(f, "foot.l").z - (try at(f, "shin.l").z)) < 0.03, "\(id) shin not along the floor")
                #expect(abs(low(f, ["femur.r", "shin.r", "foot.r", "toes.r"])) < 0.02, "\(id) front leg off the floor")
                #expect(low(f) > -0.02, "\(id) under the floor")
                #expect(try at(f, "pelvis").z > 0.25, "\(id) sat down")
            }
        }
    }

    @Test func lyingWithALegHangingLiesOnABench() throws {
        let g = try guide("1577")
        let s = try #require(Stagings.make(g, body) as? PostureTableStaging)
        let top = try #require(s.fixed.filter { $0.finish == .pad }.map { $0.center[2] + $0.size[2] / 2 }.max())
        #expect(top > 0.35 && top < 0.65)
        for pose in poses(g) {
            let f = s.frame(pose).body
            #expect(abs(low(f, FloorSkin.trunk) - top) < 0.02, "back off the bench")
            // One foot reaches the floor past the end of the bench.
            #expect(min(try at(f, "foot.r").z, try at(f, "foot.l").z) < 0.12, "no foot down")
        }
    }

    // MARK: - Lying on one side
    @Test func sideLyingLiesOnItsSideWithTheUpperLimbMoving() throws {
        // A leg raise, a clam, a pilates side kick, a shoulder turn and a raise with a dumbbell.
        for id in ["4051", "2461", "2852", "0863", "0408"] {
            let g = try guide(id)
            let s = try #require(Stagings.make(g, body) as? PostureSideStaging, "\(id) is not staged")
            var feet: [V] = [], hands: [V] = [], toes: [Double] = []
            for pose in poses(g) {
                let (f, props) = s.frame(pose)
                // The trunk lies level on the floor, the left side down.
                #expect(abs(try at(f, "neck").z - (try at(f, "pelvis").z)) < 0.08, "\(id) trunk not level")
                #expect(try at(f, "pelvis").z < 0.3, "\(id) not lying")
                #expect(try at(f, "femur.l").z < (try at(f, "femur.r").z) - 0.1, "\(id) not on the left side")
                let down = body.floorLowest(FloorSkin.whole, f.rotations.mapValues { M($0) }, f.heads.mapValues { V($0) })
                #expect(low(f) > -0.02 && low(f) < 0.02, "\(id) lowest skin at \(low(f)) \(down?.bone ?? "")")
                #expect(props.isEmpty == (g.equipment == nil), "\(id) equipment")
                feet.append(try at(f, "foot.l"))
                hands.append(try at(f, "hand.r"))
                toes.append(try at(f, "toes.r").z)
            }
            // The lower leg does not move.
            #expect(feet.allSatisfy { ($0 - feet[0]).length < 0.02 }, "\(id) lower leg moves \(feet.map { ($0 - feet[0]).length }.max() ?? 0)")
            let lift = (toes.max() ?? 0) - (toes.min() ?? 0), reach = (hands.map(\.z).max() ?? 0) - (hands.map(\.z).min() ?? 0)
            #expect(max(lift, reach) > 0.15, "\(id) nothing moves")
        }
        // Kneeling and standing versions, a cable, and a neck that the keyframes do not move.
        for id in ["2875", "4691", "2924", "4430"] {
            #expect(!PostureStagings.onSide(try guide(id)), "\(id)")
        }
    }

    /// POSTURE_LIST=/path writes every exercise this group stages, and on what.
    @Test func list() throws {
        guard let path = ProcessInfo.processInfo.environment["POSTURE_LIST"] else { return }
        var lines: [String] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let g = catalog.howTo(for: ex), let staged = Stagings.make(g, body) else { continue }
            var on = ""
            if let s = staged as? PostureStaging { on = "\(s.support)" }
            else if staged is PostureAsideStaging { on = "aside" }
            else if staged is PostureFloorSitStaging { on = "floor sit" }
            else if staged is PostureTableStaging { on = "table" }
            else if staged is PostureSideStaging { on = "side" }
            else { continue }
            lines.append("\(ex.id)\t\(g.familyID)\t\(g.subtypeID ?? "-")\t\(g.equipment ?? "-")\t\(on)\t\(g.exerciseName)")
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

import Foundation
import Testing
@testable import AccrueKit

struct BodyweightStagingTests {
    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func staged(_ id: String) throws -> PropPlan {
        let plan = PropPlan(guide: try guide(id), body: body)
        #expect(plan.staging != nil, "\(id) is not staged")
        return plan
    }

    /// Every frame of the loop, and the common mistakes at the moment they show.
    private func frames(_ plan: PropPlan, _ id: String, mistakes: Bool = true) throws -> [BodyFrame] {
        var out = (0...24).map { plan.frame(at: Double($0) / 24).body }
        if mistakes {
            let g = try guide(id)
            out += g.steps.flatMap(\.mistakes).compactMap { m in m.pose.map { plan.frame(at: g.faultT, fault: $0).body } }
        }
        return out
    }

    private func point(_ f: BodyFrame, _ bone: String) throws -> [Double] { try #require(f.heads[bone], "\(bone)") }

    /// The angle at the hips between the trunk and the thighs, in degrees from straight.
    private func hipBreak(_ f: BodyFrame) throws -> Double {
        let s = try point(f, "humerus.r"), p = try point(f, "femur.r"), k = try point(f, "shin.r")
        let a = [s[1] - p[1], s[2] - p[2]], b = [p[1] - k[1], p[2] - k[2]]
        let dot = (a[0] * b[0] + a[1] * b[1]) / (hypot(a[0], a[1]) * hypot(b[0], b[1]))
        return acos(min(1, max(-1, dot))) * 180 / .pi
    }

    // MARK: Which exercises

    @Test func stagesOnlyWhatFits() throws {
        func kind(_ name: String) throws -> (any BodyStaging)? {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            return Stagings.make(try #require(catalog.howTo(for: ex)), body)
        }
        #expect(try kind("chest dip") is DipStaging)
        #expect(try kind("weighted tricep dips") is DipStaging)
        #expect(try kind("scapula dips") is DipStaging)
        #expect(try kind("bench dip (knees bent)") is BenchDipStaging)
        #expect(try kind("triceps dip (between benches)") is BenchDipStaging)
        #expect(try kind("push-up") is PushUpStaging)
        #expect(try kind("push up (on knees)") is PushUpStaging)
        #expect(try kind("incline push-up") is PushUpStaging)
        #expect(try kind("decline push-up") is PushUpStaging)
        #expect(try kind("front plank") is PlankStaging)
        #expect(try kind("chin-up") is BarHangStaging)
        #expect(try kind("wide grip pull-up") is BarHangStaging)
        #expect(try kind("pull up (neutral grip)") is BarHangStaging)
        #expect(try kind("hanging leg raise") is BarHangStaging)
        // The starter pull-up keeps its own staging.
        #expect(try kind("pull-up") is PullUpStaging)
        // Rings, balls, one arm, jumps and climbs are other pictures.
        for name in ["ring dips", "one arm dip", "korean dips", "triceps dips floor",
                     "push-up (on stability ball)", "clap push up", "single arm push-up", "push-up (wall)", "pike push up",
                     "muscle up", "rope climb", "one arm chin-up",
                     "rear pull-up", "archer pull up", "hanging toes to bar", "captains chair leg raise"] {
            #expect(try kind(name) == nil, "\(name)")
        }
        // How many of the catalog each family's staging covers.
        var count: [String: Int] = [:]
        for ex in catalog.exercises where !ex.hidden {
            guard let fam = ex.familyID, ["dip", "push-up", "plank", "pull-up", "hanging-leg-raise"].contains(fam),
                  let g = catalog.howTo(for: ex), BodyweightStagings.make(g, body) != nil else { continue }
            count[fam, default: 0] += 1
        }
        #expect(count["dip", default: 0] >= 15)
        #expect(count["push-up", default: 0] >= 20)
        #expect(count["plank", default: 0] >= 3)
        #expect(count["pull-up", default: 0] >= 20)
        #expect(count["hanging-leg-raise", default: 0] >= 5)
    }

    // MARK: Dips

    @Test func dipCarriesTheBodyBetweenTheBars() throws {
        for id in ["0251", "1755", "3012"] {
            let plan = try staged(id)
            #expect(plan.kinds == [.dipBars])
            let bar = DipStaging.barHeight, half = DipStaging.halfWidth
            var high = -Double.infinity, low = Double.infinity
            let all = try frames(plan, id)
            let start = try point(all[0], "f3a.r")
            for f in all {
                for (s, x) in [("r", -half), ("l", half)] {
                    // Each hand stays closed on its own bar and does not slide along it.
                    let k = try point(f, "f3a.\(s)")
                    #expect(hypot(k[0] - x, k[2] - bar) < 0.06, "\(id) knuckle \(k)")
                    #expect(abs(k[1] - start[1]) < 0.01)
                    // The arm stays above the bar: elbow and shoulder over the hand.
                    #expect(try point(f, "ulna.\(s)")[2] > bar + 0.1)
                    #expect(try point(f, "humerus.\(s)")[2] > bar + 0.12)
                    // The legs hang between the bars, clear of the floor.
                    for bone in ["femur", "shin", "foot", "toes"] {
                        let p = try point(f, "\(bone).\(s)")
                        #expect(abs(p[0]) < half - 0.08, "\(id) \(bone) \(p)")
                        #expect(p[2] > 0.1)
                    }
                }
                let neck = try point(f, "neck")
                high = max(high, neck[2])
                low = min(low, neck[2])
            }
            // A dip sinks a forearm's length; a scapula dip only as far as the shoulders shrug.
            #expect(high - low > (id == "3012" ? 0.02 : 0.25), "\(id) travels \(high - low)")
        }
    }

    @Test func benchDipKeepsHandsOnTheEdgeAndHeelsDown() throws {
        for (id, feet) in [("0129", BenchDipStaging.Feet.flat), ("0830", .heels), ("0813", .raised), ("4728", .heels)] {
            let plan = try staged(id)
            #expect(plan.kinds.first == .bench)
            let all = try frames(plan, id)
            let first = all[0]
            var high = -Double.infinity, low = Double.infinity
            for f in all {
                for s in ["r", "l"] {
                    // The middle knuckle sits on the bench's front edge, the wrist behind it on the pad.
                    let k = try point(f, "f3a.\(s)"), w = try point(f, "hand.\(s)")
                    #expect(abs(k[1] + 0.012) < 0.02 && abs(k[2] - BenchDipStaging.top - 0.019) < 0.02, "\(id) knuckle \(k)")
                    #expect(w[1] > 0.03 && abs(w[2] - BenchDipStaging.top - 0.027) < 0.02, "\(id) wrist \(w)")
                    // The fingers hang over the edge.
                    #expect(try point(f, "f3c.\(s)")[2] < BenchDipStaging.top)
                    // The feet do not slide, and the elbows bend back, not out.
                    let ankle = try point(f, "foot.\(s)"), was = try point(first, "foot.\(s)")
                    #expect(zip(ankle, was).allSatisfy { abs($0 - $1) < 0.004 }, "\(id) ankle \(ankle)")
                    let elbow = try point(f, "ulna.\(s)"), shoulder = try point(f, "humerus.\(s)")
                    #expect(elbow[1] > shoulder[1])
                }
                let ankle = try point(f, "foot.r")
                switch feet {
                case .flat: #expect(abs(ankle[2] - body.ankleHeight) < 0.005)
                case .heels: #expect(ankle[2] < 0.11)
                case .raised: #expect(ankle[2] > BenchDipStaging.top && ankle[2] < BenchDipStaging.top + 0.11)
                }
                // The hips stay in front of the bench and off the floor.
                let hips = try point(f, "pelvis")
                #expect(hips[1] < -0.12 && hips[2] > 0.19, "\(id) hips \(hips)")
                high = max(high, hips[2])
                low = min(low, hips[2])
            }
            #expect(high - low > 0.18, "\(id) travels \(high - low)")
        }
    }

    // MARK: Push-ups and planks

    @Test func pushUpKeepsPalmsAndToesPlanted() throws {
        // Plain, knees, incline on a bench and on a box, decline, close, diamond, wide, with a plate.
        for id in ["0662", "1182", "0493", "3785", "0279", "0259", "0283", "1311", "8076"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? PushUpStaging)
            let setup = staging.setup
            let handsUp = setup.handsOnBench ? PushUpStaging.benchTop : 0
            let rest = setup.onKnees ? "shin" : "toes"
            let all = try frames(plan, id)
            let first = all[0]
            var high = -Double.infinity, low = Double.infinity
            for (i, f) in all.enumerated() {
                for s in ["r", "l"] {
                    // The hand lies flat where it was put: wrist, knuckles and fingertips all on the surface.
                    let w = try point(f, "hand.\(s)"), was = try point(first, "hand.\(s)")
                    #expect(zip(w, was).allSatisfy { abs($0 - $1) < 0.004 }, "\(id) frame \(i) wrist \(w) was \(was)")
                    #expect(abs(w[2] - handsUp - 0.027) < 0.006)
                    #expect(abs(try point(f, "f3a.\(s)")[2] - handsUp - 0.019) < 0.006)
                    for finger in 1...5 {
                        let tip = try point(f, "f\(finger)c.\(s)")[2] - handsUp
                        #expect(tip > 0.003 && tip < 0.03, "\(id) finger \(finger) \(tip)")
                    }
                    // Fingers forward of the wrist (turned in for the diamond).
                    #expect(try point(f, "f3a.\(s)")[1] < w[1] - 0.05)
                    // The toes (or knees) are the hinge and never slide.
                    let p = try point(f, "\(rest).\(s)"), q = try point(first, "\(rest).\(s)")
                    #expect(zip(p, q).allSatisfy { abs($0 - $1) < 0.002 }, "\(id) \(rest) \(p)")
                    // Elbows bend back toward the feet.
                    #expect(try point(f, "ulna.\(s)")[1] > w[1] - 0.06)
                }
                // Nothing sinks into the floor.
                #expect(f.heads.allSatisfy { $0.value[2] > 0.005 }, "\(id) frame \(i)")
                let neck = try point(f, "neck")
                high = max(high, neck[2])
                low = min(low, neck[2])
                // The body stays in a line through the loop itself (the mistakes break it on purpose).
                if i <= 24 { #expect(try hipBreak(f) < 12, "\(id) frame \(i)") }
            }
            // The chest comes down by most of an arm's length, to just above the floor.
            #expect(high - low > 0.25, "\(id) travels \(high - low)")
            let lowest = "\(id) lowest neck \(low)"
            if !setup.handsOnBench { #expect(lowest.isEmpty || low < 0.3, "\(lowest)") }
        }
    }

    @Test func plankRestsOnForearmsAndToes() throws {
        for id in ["0463", "3238", "2135"] {
            let plan = try staged(id)
            let knees = id == "3238"
            for f in try frames(plan, id) {
                for s in ["r", "l"] {
                    // The forearm lies on the floor, the elbow under the shoulder, the palm down.
                    let elbow = try point(f, "ulna.\(s)"), wrist = try point(f, "hand.\(s)"), shoulder = try point(f, "humerus.\(s)")
                    #expect(abs(elbow[2] - PlankStaging.elbowPad) < 0.012, "\(id) elbow \(elbow)")
                    #expect(abs(wrist[2] - 0.027) < 0.01, "\(id) wrist \(wrist)")
                    #expect(abs(elbow[1] - shoulder[1]) < 0.05 && abs(elbow[0] - shoulder[0]) < 0.05)
                    #expect(wrist[1] < elbow[1] - 0.2)
                    #expect(try point(f, "f3c.\(s)")[2] < 0.03)
                    let rest = try point(f, knees ? "shin.\(s)" : "toes.\(s)")
                    #expect(rest[2] < 0.06 && rest[2] > 0.01)
                }
                #expect(f.heads.allSatisfy { $0.value[2] > 0.005 })
            }
            // Held in a line when nothing is wrong.
            #expect(try hipBreak(plan.frame(at: 0).body) < 8)
        }
    }

    // MARK: The bar

    @Test func everyGripHangsFromTheBar() throws {
        // Chin-up, close chin-up, wide pull-up, neutral grip, weighted chin-up.
        for id in ["1326", "1327", "1429", "0651", "4102"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? BarHangStaging)
            let bar = staging.barHeight
            var top = -Double.infinity, low = Double.infinity
            for f in try frames(plan, id) {
                for s in ["r", "l"] {
                    // The knuckles stay on the bar (or the handle), at the grip's width.
                    let k = try point(f, "f3a.\(s)"), at = staging.hold(s)
                    let off = staging.grip == .neutral ? hypot(k[0] - at.x, k[2] - at.z) : hypot(k[1] - at.y, k[2] - at.z)
                    #expect(off < 0.06, "\(id) knuckle \(k)")
                    #expect(abs(abs(k[0]) - staging.halfGrip) < 0.07)
                    #expect(try point(f, "toes.\(s)")[2] > 0.09)
                    // Palms toward the face: the thumb is outside the little finger. Palms away: inside.
                    let thumb = abs(try point(f, "f2a.\(s)")[0]), little = abs(try point(f, "f5a.\(s)")[0])
                    if staging.grip == .under { #expect(thumb > little) }
                    if staging.grip == .over { #expect(thumb < little) }
                }
                let neck = try point(f, "neck")
                top = max(top, neck[2])
                low = min(low, neck[2])
            }
            // The chin clears the bar at the top, and the arms hang long at the bottom.
            #expect(top > bar - 0.06, "\(id) top \(top)")
            #expect(low < bar - 0.45, "\(id) low \(low)")
        }
    }

    @Test func legRaiseHangsStillAndLiftsTheKnees() throws {
        let plan = try staged("0472")
        let bar = try #require(plan.staging as? BarHangStaging).barHeight
        var kneeTop = -Double.infinity
        let all = try frames(plan, "0472")
        let hips = try point(all[0], "pelvis")
        for f in all {
            for s in ["r", "l"] {
                let k = try point(f, "f3a.\(s)")
                #expect(hypot(k[1], k[2] - bar) < 0.06)
                // The arms stay long: the shoulders hang an arm's length under the bar.
                #expect(try point(f, "humerus.\(s)")[2] < bar - 0.45)
                #expect(try point(f, "toes.\(s)")[2] > 0.09)
            }
            kneeTop = max(kneeTop, try point(f, "shin.r")[2])
        }
        // The knees come up to the hips or higher.
        #expect(kneeTop > hips[2])
    }
}

import Foundation
import Testing
@testable import AccrueKit

struct FloorStagingTests {
    typealias V = Body3D.V
    typealias M = Body3D.M

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

    private func point(_ f: BodyFrame, _ bone: String) throws -> V { V(try #require(f.heads[bone], "\(bone)")) }

    /// How high the lowest skin of `bones` is in a frame.
    private func low(_ f: BodyFrame, _ bones: [String]) -> Double {
        body.floorLow(bones, f.rotations.mapValues { M($0) }, f.heads.mapValues { V($0) })
    }

    /// How far a bone's head strays from where it is in the first frame.
    private func drift(_ frames: [BodyFrame], _ bone: String) throws -> Double {
        let first = try point(frames[0], bone)
        return try frames.map { (try point($0, bone) - first).length }.max() ?? 0
    }

    /// The trunk and legs never go into the floor, beyond the little the skin gives.
    private func staysAbove(_ frames: [BodyFrame], _ id: String) {
        for (i, f) in frames.enumerated() {
            #expect(low(f, FloorSkin.trunk + FloorSkin.legs) > -0.015, "\(id) frame \(i) sinks into the floor")
            #expect(low(f, ["humerus.r", "humerus.l", "ulna.r", "ulna.l"]) > -0.02, "\(id) frame \(i): an arm is in the floor")
        }
    }

    @Test func stagesOnlyWhatFits() throws {
        func kind(_ name: String) throws -> (any BodyStaging)? {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            return Stagings.make(try #require(catalog.howTo(for: ex)), body)
        }
        for name in ["crunch floor", "sit up", "half sit-up (male)", "lying leg raise", "reverse crunch", "flutter kicks",
                     "v up", "glute bridge two legs on floor", "hamstring bridge", "dead bug", "hollow hold"] {
            #expect(try kind(name) is FloorLyingStaging, "\(name)")
        }
        for name in ["side plank", "bent knee side plank", "side plank leg raise"] {
            #expect(try kind(name) is FloorSidePlankStaging, "\(name)")
        }
        // Benches, twists, one leg, weights and other set-ups are other pictures.
        for name in ["decline crunch", "twisting crunch", "crunch (arms on chest)", "weighted crunch", "janda sit-up",
                     "lying leg raise flat bench", "lying criss cross legs", "single leg bridge", "glute bridge march",
                     "side plank rotation", "hollow rock", "bird dog", "mountain climber", "shoulder tap"] {
            let made = try kind(name)
            #expect(!(made is FloorLyingStaging) && !(made is FloorSidePlankStaging), "\(name)")
        }
        // The barbell bridges keep the staging they have.
        #expect(try kind("barbell glute bridge") is BenchThrustStaging)
        var count = 0
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), let made = FloorStagings.make(g, body) else { continue }
            #expect(ex.equipment == nil, "\(ex.name)")
            if made is FloorLyingStaging || made is FloorSidePlankStaging { count += 1 }
        }
        #expect(count >= 55)
    }

    @Test func crunchKeepsHipsAndFeetDown() throws {
        for id in ["0274", "0736"] {
            let plan = try staged(id)
            let all = try frames(plan, id)
            staysAbove(all, id)
            // Feet flat where they were put; hips on the floor, rolling no further than a sit-up takes them.
            for s in ["r", "l"] {
                #expect(try drift(all, "foot.\(s)") < 0.005, "\(id) foot \(s)")
                #expect(try drift(all, "toes.\(s)") < 0.005, "\(id) toes \(s)")
            }
            let hips = try drift(try frames(plan, id, mistakes: false), "pelvis")
            // A sit-up rolls from the back of the hips onto the seat, which carries the hip joints along.
            #expect(hips < (id == "0274" ? 0.01 : 0.26), "\(id) hips move \(hips)")
            for (i, f) in all.enumerated() {
                #expect(abs(low(f, ["pelvis"]) + FloorSupine.sink) < 0.004, "\(id) frame \(i): hips off the floor")
            }
            // Lying back, the head and the shoulders are down; at the top the shoulders are up.
            let loop = try frames(plan, id, mistakes: false)
            #expect(abs(low(loop[0], ["thorax"]) + FloorSupine.sink) < 0.004, "\(id)")
            #expect(abs(low(loop[0], ["head"]) + FloorSupine.sink) < 0.004, "\(id)")
            let lift = try loop.map { try point($0, "neck").z }.max()! - point(loop[0], "neck").z
            #expect(lift > (id == "0274" ? 0.1 : 0.4), "\(id) rises \(lift)")
            // The fingertips stay at the head.
            for f in loop {
                let tip = try point(f, "f3c.r"), head = try point(f, "head")
                #expect((tip - head).length < 0.16, "\(id)")
            }
        }
    }

    @Test func legRaisesKeepTheBackAndHandsDown() throws {
        for id in ["1163", "0872", "0459"] {
            let plan = try staged(id)
            let all = try frames(plan, id)
            staysAbove(all, id)
            for (i, f) in all.enumerated() {
                #expect(abs(low(f, ["thorax"]) + FloorSupine.sink) < 0.004, "\(id) frame \(i): back off the floor")
                #expect(abs(low(f, ["head"]) + FloorSupine.sink) < 0.004, "\(id) frame \(i): head off the floor")
                for s in ["r", "l"] {
                    let wrist = try point(f, "hand.\(s)")
                    #expect(wrist.z > 0.015 && wrist.z < 0.045, "\(id) frame \(i): wrist \(s) at \(wrist.z)")
                }
            }
            let loop = try frames(plan, id, mistakes: false)
            let hands = try max(drift(loop, "hand.r"), drift(loop, "hand.l"))
            #expect(hands < 0.005, "\(id) hands slide \(hands)")
            // A mistake that arches the back may carry the hands a finger's width.
            #expect(try max(drift(all, "hand.r"), drift(all, "hand.l")) < 0.02, "\(id)")
            #expect(try drift(all, "neck") < 0.04, "\(id) shoulders")
        }
        // A reverse crunch curls the hips off the floor.
        let loop = try frames(try staged("0872"), "0872", mistakes: false)
        #expect(loop.map { low($0, ["pelvis"]) }.max()! > 0.03)
    }

    @Test func bridgeLiftsTheHipsBetweenShouldersAndFeet() throws {
        for id in ["2471", "8358"] {
            let plan = try staged(id)
            let loop = try frames(plan, id, mistakes: false)
            staysAbove(try frames(plan, id), id)
            for s in ["r", "l"] {
                let foot = try drift(loop, "foot.\(s)"), hand = try drift(loop, "hand.\(s)")
                #expect(foot < 0.005, "\(id) foot \(s) slides \(foot)")
                #expect(hand < 0.005, "\(id) hand \(s) slides \(hand)")
            }
            for (i, f) in loop.enumerated() {
                #expect(abs(low(f, ["thorax"]) + FloorSupine.sink) < 0.004, "\(id) frame \(i): shoulders off the floor")
            }
            #expect(abs(low(loop[0], ["pelvis"]) + FloorSupine.sink) < 0.006, "\(id) starts with the hips down")
            let rise = try loop.map { try point($0, "pelvis").z }.max()! - point(loop[0], "pelvis").z
            #expect(rise > (id == "2471" ? 0.12 : 0.05), "\(id) rises \(rise)")
        }
    }

    @Test func sidePlankRestsOnForearmAndFeet() throws {
        for id in ["0715", "0133", "0703"] {
            let plan = try staged(id)
            for (i, f) in try frames(plan, id).enumerated() {
                // The lower leg bears on the floor, the elbow is under the shoulder, the hips are up.
                #expect(abs(low(f, FloorSidePlankStaging.lower) + FloorSidePlankStaging.sink) < 0.004, "\(id) frame \(i)")
                #expect(low(f, FloorSkin.trunk + FloorSkin.legs) > -0.012, "\(id) frame \(i) sinks")
                let shoulder = try point(f, "humerus.r"), elbow = try point(f, "ulna.r"), wrist = try point(f, "hand.r")
                #expect(abs(elbow.z - FloorSidePlankStaging.elbowPad) < 0.012, "\(id) frame \(i): elbow at \(elbow.z)")
                #expect(hypot(elbow.x - shoulder.x, elbow.y - shoulder.y) < 0.06, "\(id) frame \(i)")
                #expect(wrist.z > 0.015 && wrist.z < 0.045, "\(id) frame \(i): wrist at \(wrist.z)")
                #expect(try point(f, "pelvis").z > 0.2, "\(id) frame \(i)")
            }
        }
    }
}

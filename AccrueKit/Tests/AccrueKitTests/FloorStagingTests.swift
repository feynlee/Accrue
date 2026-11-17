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
    private func staysAbove(_ frames: [BodyFrame], _ id: String, toes: Double = -0.015) {
        for (i, f) in frames.enumerated() {
            let g = f.rotations.mapValues { M($0) }, h = f.heads.mapValues { V($0) }
            let at = body.floorLowest((FloorSkin.trunk + FloorSkin.legs).filter { !$0.hasPrefix("toes") }, g, h)
            #expect((at?.at.z ?? 0) > -0.015, "\(id) frame \(i) sinks into the floor at \(at?.bone ?? "")")
            #expect(low(f, ["toes.r", "toes.l"]) > toes, "\(id) frame \(i): the toes are in the floor")
            #expect(low(f, ["humerus.r", "humerus.l", "ulna.r", "ulna.l"]) > -0.02, "\(id) frame \(i): an arm is in the floor")
        }
    }

    @Test func stagesOnlyWhatFits() throws {
        func kind(_ name: String) throws -> (any BodyStaging)? {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            return Stagings.make(try #require(catalog.howTo(for: ex)), body)
        }
        for name in ["crunch floor", "sit up", "half sit-up (male)", "lying leg raise", "reverse crunch", "flutter kicks",
                     "v up", "glute bridge two legs on floor", "hamstring bridge", "dead bug", "hollow hold",
                     "crunch (arms on chest)", "sit-up with arms on chest", "single leg bridge", "glute bridge march",
                     "single leg hip bridge (straight leg)", "flutter kicks (hands under hips head up)"] {
            #expect(try kind(name) is FloorLyingStaging, "\(name)")
        }
        for name in ["side plank", "bent knee side plank", "side plank leg raise"] {
            #expect(try kind(name) is FloorSidePlankStaging, "\(name)")
        }
        // Benches, twists, one leg, weights and other set-ups are other pictures.
        for name in ["decline crunch", "twisting crunch", "weighted crunch", "janda sit-up", "lying leg raise flat bench",
                     "lying criss cross legs", "single leg hip thrusts", "glute bridge one leg on bench",
                     "single leg bridge with outstretched leg (left)", "side plank rotation", "hollow rock"] {
            let made = try kind(name)
            #expect(!(made is FloorLyingStaging) && !(made is FloorSidePlankStaging), "\(name)")
        }
        for name in ["plank on hands", "shoulder tap", "kneeling shoulder tap", "bear plank", "bird dog", "mountain climber"] {
            #expect(try kind(name) is FloorProneStaging, "\(name)")
        }
        #expect(try kind("reverse plank") is FloorReversePlankStaging)
        // The forearm plank is the bodyweight group's; the names that check its hips get the same picture.
        #expect(try kind("front plank") is PlankStaging)
        #expect(try kind("plank butt (form check)") is PlankStaging)
        // A plank on a ball, on one arm, walking or with a leg lifted is none of these.
        for name in ["front plank with arm lift", "plank walk up", "decline shoulder tap", "bear plank kickback",
                     "reverse plank with leg lift", "spider mountain climber", "mountain climber cross kick", "sliding leg bird dog"] {
            let made = try kind(name)
            #expect(!(made is FloorProneStaging) && !(made is FloorReversePlankStaging) && !(made is PlankStaging), "\(name)")
        }
        // Poses that only need laying on the floor, and the cat and the cow on hands and knees.
        for name in ["hundred", "teaser", "swimming", "boat yoga pose", "bow yoga pose", "corpse pose savasana", "child pose",
                     "sphinx", "downward facing dog", "knee to chest stretch", "pretzel stretch", "inchworm",
                     "kneeling wrist flexor stretch"] {
            #expect(try kind(name) is FloorRestStaging, "\(name)")
        }
        for name in ["cat stretch", "cow stretch", "cat cow stretch"] {
            #expect(try kind(name) is FloorProneStaging, "\(name)")
        }
        // Not a chair or a wall, not a pose the keyframes do not lay down, and not a name that
        // sits where the keyframes lie.
        for name in ["sitting cat cow stretch on a chair", "tiger yoga pose", "wall flexors stretch", "chaturanga pose",
                     "kneeling back rotation stretch", "seated neck stretch", "all fours squad stretch", "lying calf stretch",
                     "seated single leg hugging knee flexion", "butterfly yoga pose", "standing forward bend uttanasana",
                     "sun salutation a", "pigeon hip stretch"] {
            let made = try kind(name)
            #expect(!(made is FloorRestStaging) && !(made is FloorProneStaging), "\(name)")
        }
        // The barbell bridges keep the staging they have.
        #expect(try kind("barbell glute bridge") is BenchThrustStaging)
        var count = 0, resting = 0
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), let made = FloorStagings.make(g, body) else { continue }
            #expect(ex.equipment == nil, "\(ex.name)")
            if made is FloorLyingStaging || made is FloorSidePlankStaging { count += 1 }
            if made is FloorRestStaging { resting += 1 }
        }
        #expect(count >= 55)
        #expect(resting >= 90)
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

    @Test func planksOnHandsKeepHandsAndFeetWhereTheyAre() throws {
        // Held on straight arms, face down on the toes or face up on the heels.
        for (id, feet) in [("5159", ["toes.r", "toes.l"]), ("4170", ["toes.r", "toes.l"]), ("0867", ["foot.r", "foot.l"])] {
            let plan = try staged(id)
            let all = try frames(plan, id)
            // Toes tucked under press into the floor as far as the bodyweight planks' do.
            staysAbove(all, id, toes: -0.02)
            let loop = try frames(plan, id, mistakes: false)
            for bone in feet + ["hand.r", "hand.l"] { #expect(try drift(loop, bone) < 0.005, "\(id) \(bone)") }
            for s in ["r", "l"] { #expect(try drift(all, "hand.\(s)") < 0.005, "\(id) hand \(s) with mistakes") }
            for f in loop {
                // The shoulders are an arm's length up, over the wrists.
                let shoulder = try point(f, "humerus.r"), wrist = try point(f, "hand.r")
                #expect(shoulder.z > 0.5 && wrist.z < 0.05, "\(id)")
                #expect(abs(shoulder.y - wrist.y) < 0.08, "\(id)")
            }
        }
        // A bear plank's knees are off the floor, under the hips.
        let bear = try frames(try staged("4170"), "4170", mistakes: false)
        for f in bear {
            let knee = try point(f, "shin.r"), hip = try point(f, "femur.r")
            #expect(low(f, ["femur.r", "femur.l", "shin.r", "shin.l"]) > 0.03)
            #expect(knee.z < 0.2 && abs(knee.y - hip.y) < 0.03)
        }
        // A reverse plank faces up with the hips lifted.
        let reverse = try frames(try staged("0867"), "0867", mistakes: false)
        #expect(try point(reverse[0], "pelvis").z > 0.25)
        #expect(try point(reverse[0], "head").y > (try point(reverse[0], "pelvis").y))
        #expect(abs(low(reverse[0], FloorReversePlankStaging.feet) + FloorReversePlankStaging.sink) < 0.002)
    }

    @Test func shoulderTapsLiftOneHandAtATime() throws {
        for (id, feet) in [("3699", ["toes.r", "toes.l"]), ("4506", ["shin.r", "shin.l"])] {
            let plan = try staged(id)
            staysAbove(try frames(plan, id), id, toes: -0.02)
            let loop = try frames(plan, id, mistakes: false)
            for bone in feet + ["pelvis"] { #expect(try drift(loop, bone) < 0.005, "\(id) \(bone)") }
            let start = try ["r", "l"].map { try point(loop[0], "hand.\($0)") }
            var reached = [0.0, 0.0]
            for f in loop {
                let now = try ["r", "l"].map { try point(f, "hand.\($0)") }
                let moved = [(now[0] - start[0]).length, (now[1] - start[1]).length]
                // One hand at least stays planted, and a hand that moves goes up, not along the floor.
                #expect(min(moved[0], moved[1]) < 0.005, "\(id)")
                for i in 0..<2 where moved[i] > 0.03 { #expect(now[i].z > start[i].z + 0.01, "\(id)") }
                reached = [max(reached[0], moved[0]), max(reached[1], moved[1])]
            }
            #expect(reached[0] > 0.35 && reached[1] > 0.35, "\(id): both hands tap")
            // At the tap the hand is on the other shoulder.
            let tap = plan.frame(at: 0.35).body
            #expect((try point(tap, "hand.l") - (try point(tap, "humerus.r"))).length < 0.2, "\(id)")
        }
    }

    @Test func birdDogReachesFromOneKneeAndOneHand() throws {
        let plan = try staged("1241")
        let all = try frames(plan, "1241")
        staysAbove(all, "1241")
        for bone in ["shin.r", "foot.r", "hand.l"] { #expect(try drift(all, bone) < 0.005, "\(bone)") }
        // On all fours to start: both knees and both hands down.
        let start = all[0]
        #expect(abs(low(start, ["femur.l", "shin.l"]) - low(start, ["femur.r", "shin.r"])) < 0.005)
        #expect(low(start, ["femur.r", "shin.r"]) < 0.005)
        #expect(try point(start, "hand.r").z < 0.05)
        // At the reach the right arm and the left leg are level with the trunk.
        let reach = plan.frame(at: 0.45).body
        let hip = try point(reach, "femur.l").z, shoulder = try point(reach, "humerus.r").z
        #expect(abs(try point(reach, "foot.l").z - hip) < 0.12)
        #expect(abs(try point(reach, "hand.r").z - shoulder) < 0.15)
        #expect(try point(reach, "hand.r").y < (try point(reach, "humerus.r").y) - 0.4)
        #expect(try point(reach, "foot.l").y > (try point(reach, "femur.l").y) + 0.6)
    }

    @Test func mountainClimberRunsOnPlantedHands() throws {
        let plan = try staged("0630")
        let all = try frames(plan, "0630")
        staysAbove(all, "0630", toes: -0.02)
        let loop = try frames(plan, "0630", mistakes: false)
        for s in ["r", "l"] { #expect(try drift(loop, "hand.\(s)") < 0.005, "hand \(s)") }
        // The right knee is in at the start and the left one half way round; the long leg's toes
        // come down on the same spot each time.
        let rightIn = plan.frame(at: 0).body, leftIn = plan.frame(at: 0.5).body
        #expect(try point(rightIn, "shin.r").y < (try point(rightIn, "femur.r").y) - 0.1)
        #expect(try point(leftIn, "shin.l").y < (try point(leftIn, "femur.l").y) - 0.1)
        let a = try point(rightIn, "toes.l"), b = try point(leftIn, "toes.r")
        #expect(abs(a.y - b.y) < 0.005 && abs(a.z - b.z) < 0.005 && a.z < 0.06)
        // The toes of the leg that is in touch the floor under the hips.
        #expect(abs(low(rightIn, ["foot.r", "toes.r"])) < 0.01)
        #expect(abs(try point(rightIn, "toes.r").y - (try point(rightIn, "femur.r").y)) < 0.3)
    }

    @Test func armsOnChestLieOnTheShoulders() throws {
        for id in ["4727", "3679"] {
            let plan = try staged(id)
            staysAbove(try frames(plan, id), id)
            for f in try frames(plan, id, mistakes: false) {
                // Each wrist stays by the other shoulder, in front of the chest, all the way up.
                for (s, other) in [("r", "l"), ("l", "r")] {
                    #expect((try point(f, "hand.\(s)") - (try point(f, "humerus.\(other)"))).length < 0.27, "\(id) \(s)")
                }
            }
        }
    }

    @Test func oneLegBridgesKeepTheOtherFootDown() throws {
        // One leg held up, bent or straight.
        for id in ["0726", "2474"] {
            let plan = try staged(id)
            let all = try frames(plan, id)
            staysAbove(all, id)
            // The last mistake is the foot set too far away; in every other frame it stays put.
            #expect(try drift(Array(all.dropLast()), "foot.r") < 0.005, "\(id)")
            for f in all { #expect(try point(f, "foot.l").z > 0.2, "\(id): the left foot is up") }
            #expect(try point(plan.frame(at: 0.5).body, "pelvis").z > (try point(all[0], "pelvis").z) + 0.1, "\(id)")
        }
        // A march: the hips stay up while the left knee comes up over the hip and goes back.
        let plan = try staged("3561")
        let loop = try frames(plan, "3561", mistakes: false)
        staysAbove(loop, "3561")
        #expect(try drift(loop, "pelvis") < 0.01)
        #expect(try drift(loop, "foot.r") < 0.005)
        #expect(try point(loop[0], "pelvis").z > 0.2)
        #expect(abs(try point(loop[0], "foot.l").z - (try point(loop[0], "foot.r").z)) < 0.005)
        let up = plan.frame(at: 0.5).body
        #expect(try point(up, "foot.l").z > 0.35)
        #expect(abs(try point(up, "shin.l").y - (try point(up, "femur.l").y)) < 0.2)
    }

    @Test func handsUnderHipsAndHeadUp() throws {
        let plan = try staged("2891")
        let all = try frames(plan, "2891")
        staysAbove(all, "2891")
        let plain = try staged("0459").frame(at: 0).body
        for s in ["r", "l"] {
            #expect(try drift(try frames(plan, "2891", mistakes: false), "hand.\(s)") < 0.005)
            // The hands lie in under the hips, nearer the middle than with the arms at the sides.
            #expect(abs(try point(all[0], "hand.\(s)").x) < abs(try point(plain, "hand.\(s)").x) - 0.08)
        }
        #expect(try point(all[0], "head").z > (try point(plain, "head").z) + 0.01)
    }

    /// How far a bone's head strays over the floor from where it is in the first frame.
    private func slide(_ frames: [BodyFrame], _ bone: String) throws -> Double {
        let first = try point(frames[0], bone)
        return try frames.map { (try point($0, bone) - first).flat.length }.max() ?? 0
    }

    @Test func lyingAndSittingPosesRestOnTheFloor() throws {
        for id in ["2846", "2871", "2856", "2572", "2870", "0136", "1481", "5889", "0559", "0649", "1576", "0693"] {
            let plan = try staged(id)
            let rest = try #require(plan.staging as? FloorRestStaging, "\(id)")
            let lies = rest.level - FloorRestStaging.sink
            for (i, f) in try frames(plan, id).enumerated() {
                // Neither sunk in nor floating, whatever part of the body is lowest.
                #expect(abs(low(f, FloorRestStaging.rests) - lies) < 0.002, "\(id) frame \(i)")
                for s in ["r", "l"] {
                    #expect(low(f, ["humerus.\(s)", "ulna.\(s)", "hand.\(s)"]) > rest.level - 0.012, "\(id) frame \(i): arm \(s)")
                }
            }
            // What it lies on at the start stays where it is.
            #expect(try slide(try frames(plan, id, mistakes: false), rest.anchor) < 0.001, "\(id)")
            // Yoga and pilates are done on a mat, and the body lies on top of it.
            let onMat = ["yoga-pose", "pilates-mat"].contains(try guide(id).familyID)
            #expect(rest.kinds == (onMat ? [.mat] : []), "\(id)")
            #expect(rest.fixed.count == (onMat ? 1 : 0), "\(id)")
            #expect(rest.level == (onMat ? FloorRestStaging.matTop : 0), "\(id)")
        }
    }

    @Test func handsThatAreDownLieFlat() throws {
        for id in ["0949", "1362", "0945", "2842", "0561"] {
            let plan = try staged(id)
            let rest = try #require(plan.staging as? FloorRestStaging, "\(id)")
            let loop = try frames(plan, id, mistakes: false)
            for s in ["r", "l"] {
                let press = try #require(rest.hands[s])
                #expect(rest.spots[s] != nil, "\(id): hand \(s) is down through the loop")
                #expect(try drift(loop, "hand.\(s)") < 0.005, "\(id): hand \(s)")
                for (i, f) in loop.enumerated() {
                    #expect(abs(try point(f, "hand.\(s)").z - rest.level - press.wristLift) < 0.006, "\(id) frame \(i): wrist \(s)")
                }
            }
            for (i, f) in try frames(plan, id).enumerated() {
                #expect(abs(low(f, FloorRestStaging.rests) - rest.level + FloorRestStaging.sink) < 0.002, "\(id) frame \(i)")
            }
        }
        // The inchworm walks its hands out and back from feet that stay.
        let plan = try staged("1471")
        let rest = try #require(plan.staging as? FloorRestStaging)
        let loop = try frames(plan, "1471", mistakes: false)
        #expect(rest.spots.isEmpty)
        #expect(try slide(loop, rest.anchor) < 0.001)
        // A hand that comes down lies flat, its wrist no lower than a flat palm holds it.
        for s in ["r", "l"] {
            let press = try #require(rest.hands[s])
            #expect((try loop.map { try point($0, "hand.\(s)").z }.min() ?? 0) > rest.level + press.wristLift - 0.006)
        }
    }

    @Test func catAndCowStayOnHandsAndKnees() throws {
        for id in ["1051", "2107", "0942"] {
            let plan = try staged(id)
            let prone = try #require(plan.staging as? FloorProneStaging, "\(id)")
            // The yoga pose is on a mat, the stretches on the bare floor.
            #expect(prone.lift == (id == "0942" ? FloorRestStaging.matTop : 0), "\(id)")
            #expect(prone.fixed.count == (id == "0942" ? 1 : 0), "\(id)")
            let all = try frames(plan, id)
            staysAbove(all, id)
            let loop = try frames(plan, id, mistakes: false)
            for bone in ["hand.r", "hand.l", "shin.r", "shin.l"] {
                #expect(try drift(loop, bone) < 0.005, "\(id): \(bone)")
            }
            for (i, f) in all.enumerated() {
                for s in ["r", "l"] {
                    #expect(abs(low(f, ["femur.\(s)", "shin.\(s)"]) - prone.lift) < 0.012, "\(id) frame \(i): knee \(s)")
                }
            }
        }
        // The cat and the cow as stretches are held; the yoga pose goes from one to the other,
        // the hips tipping as the back rounds.
        let tips = try frames(try staged("0942"), "0942", mistakes: false).map { (M(try #require($0.rotations["pelvis"])) * V(0, 0, 1)).y }
        #expect((tips.max() ?? 0) - (tips.min() ?? 0) > 0.05)
    }
}

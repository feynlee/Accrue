import Foundation
import Testing
@testable import AccrueKit

struct CardioStagingTests {
    typealias Sample = (t: Double, body: BodyFrame, props: [PropPiece])

    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func staged(_ id: String, _ kind: PropKind) throws -> PropPlan {
        let plan = PropPlan(guide: try guide(id), body: body)
        #expect(plan.staging != nil, "\(id)")
        #expect(plan.kinds == [kind], "\(id)")
        return plan
    }

    private func at(_ frame: BodyFrame, _ bone: String) throws -> [Double] {
        try #require(frame.heads[bone], "\(bone)")
    }

    private func far(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    /// The loop sampled finely, with the pieces that move.
    private func loop(_ plan: PropPlan, steps: Int = 48) -> [Sample] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let (f, props) = plan.frame(at: t)
            return (t, f, Array(props.dropFirst(plan.fixed.count)))
        }
    }

    /// The named joints stay within `slack` of where they start.
    private func stays(_ frames: [Sample], _ bones: [String], slack: Double = 1e-6) throws {
        let first = try #require(frames.first).body
        for f in frames {
            for bone in bones {
                #expect(far(try at(first, bone), try at(f.body, bone)) < slack, "\(bone) at \(f.t)")
            }
        }
    }

    /// Nothing jumps from one moment to the next.
    private func smooth(_ frames: [Sample], jump: Double = 0.09) throws {
        for (a, b) in zip(frames, frames.dropFirst()) {
            for bone in ["pelvis", "neck", "hand.r", "hand.l", "foot.r", "foot.l", "shin.r", "shin.l"] {
                #expect(far(try at(a.body, bone), try at(b.body, bone)) < jump, "\(bone) jumps at \(b.t)")
            }
        }
    }

    /// How far a joint travels through the loop along axis `k`.
    private func sweep(_ frames: [Sample], _ bone: String, _ k: Int) throws -> Double {
        let values = try frames.map { try at($0.body, bone)[k] }
        return (values.max() ?? 0) - (values.min() ?? 0)
    }

    /// How far `p` is from the middle line of a rod.
    private func off(_ p: [Double], rod: PropPiece) -> Double {
        let axis = Body3D.M(rod.rotation) * Body3D.V(0, 0, 1)
        let d = Body3D.V(p) - Body3D.V(rod.center)
        let along = min(rod.size[2] / 2, max(-rod.size[2] / 2, d.dot(axis)))
        return (d - axis * along).length
    }

    /// Each hand's middle knuckle is on one of the rods: a closed hand's knuckle is a finger's
    /// thickness off the middle of what it holds.
    private func holds(_ f: Sample, _ rods: [PropPiece], within reach: Double = 0.07) throws {
        #expect(!rods.isEmpty, "nothing to hold at \(f.t)")
        for s in ["r", "l"] {
            let k = try at(f.body, "f3a.\(s)")
            let d = rods.map { off(k, rod: $0) }.min() ?? 9
            #expect(d < reach, "hand.\(s) is \(d) from its grip at \(f.t)")
        }
    }

    /// The fingers are curled: the fingertip bones turn well away from the hand.
    private func closed(_ f: Sample) throws {
        for s in ["r", "l"] {
            let hand = Body3D.M(try #require(f.body.rotations["hand.\(s)"]))
            let tip = Body3D.M(try #require(f.body.rotations["f3c.\(s)"]))
            let q = (hand.t * tip).quat
            #expect(2 * acos(min(1, abs(q.w))) > 1.0, "hand.\(s) is open at \(f.t)")
        }
    }

    private func dark(_ props: [PropPiece], _ shape: PropPiece.Shape) -> [PropPiece] {
        props.filter { $0.shape == shape && $0.finish == .dark }
    }

    // MARK: The loop's phase

    @Test func aPoseIsFoundOnItsLoop() throws {
        let g = try guide("0798")
        let keys = g.keyframes
        let phase = CardioLoop(g, keys: ["hipFlex", "kneeFlex", "hipFlexL", "kneeFlexL"])
        let mistakes = g.steps.flatMap(\.mistakes).compactMap(\.pose)
        #expect(mistakes.count >= 3)
        for i in 0..<40 {
            let t = Double(i) / 40 + 0.003
            let pose = Figure.smooth(keys, at: t)
            #expect(abs(phase(pose) - t) < 0.004, "\(t) read as \(phase(pose))")
            // A mistake's extra bend does not change the reading.
            for mistake in mistakes {
                let found = phase(Figure.applying(mistake, to: pose))
                #expect(abs(found - t) < 0.004, "\(t) with a mistake read as \(found)")
            }
        }
    }

    // MARK: Rowing machine

    @Test func rowerSlidesOnItsSeatWithFeetFixedAndHandsOnTheHandle() throws {
        let plan = try staged("1161", .rower)
        let frames = loop(plan)
        // The drive is quick: the body goes the length of the rail in a sixth of the loop.
        try smooth(frames, jump: 0.16)
        // The balls of the feet never leave the footplates.
        try stays(frames, ["toes.r", "toes.l"])
        // The hips ride at one height and travel the length of the legs.
        #expect(try sweep(frames, "pelvis", 2) < 1e-6)
        #expect(try sweep(frames, "pelvis", 1) > 0.3)
        for f in frames {
            let hips = try at(f.body, "pelvis")
            // The seat is under the hips wherever they are.
            let seat = try #require(dark(f.props, .box).first, "seat at \(f.t)")
            #expect(abs(seat.center[1] - hips[1]) < 0.05, "seat at \(f.t)")
            #expect(abs(hips[2] - (seat.center[2] + seat.size[2] / 2) - CardioRowerStaging.sit) < 1e-6, "hips at \(f.t)")
            // Both hands closed on the one handle, and the chain runs from its middle.
            let handle = try #require(dark(f.props, .cylinder).first, "handle at \(f.t)")
            try holds(f, [handle])
            try closed(f)
            #expect(abs(handle.center[0]) < 1e-4, "handle at \(f.t)")
            let chain = try #require(f.props.first { $0.finish == .cable }, "chain at \(f.t)")
            #expect(off(handle.center, rod: chain) < 1e-6, "chain at \(f.t)")
            // The knees bend upward, never sideways or down.
            for s in ["r", "l"] {
                let hip = try at(f.body, "femur.\(s)"), knee = try at(f.body, "shin.\(s)"), ankle = try at(f.body, "foot.\(s)")
                #expect(knee[2] > min(hip[2], ankle[2]) - 0.02, "knee.\(s) at \(f.t)")
            }
        }
        // The handle comes in to the body at the finish and goes out past the feet at the catch.
        let handles = try frames.map { try #require(dark($0.props, .cylinder).first).center[1] }
        let toes = try at(frames[0].body, "toes.r")[1]
        #expect((handles.min() ?? 0) < toes - 0.1)
        #expect((handles.max() ?? 0) - (handles.min() ?? 0) > 0.6)
    }

    // MARK: Exercise bikes

    @Test func bikesKeepHipsOnTheSaddleFeetOnTurningPedalsAndHandsOnTheBar() throws {
        for id in ["0798", "10729", "3893"] {
            let plan = try staged(id, .bike)
            let frames = loop(plan)
            try smooth(frames)
            try stays(frames, ["pelvis"])
            var turned = ["r": 0.0, "l": 0.0]
            var before: [String: Double] = [:]
            for f in frames {
                let pedals = dark(f.props, .box).filter { $0.size[2] < 0.03 }
                #expect(pedals.count == 2, "\(id) pedals at \(f.t)")
                let axle = (0..<3).map { k in pedals.reduce(0.0) { $0 + $1.center[k] } / 2 }
                for s in ["r", "l"] {
                    // The ball of each foot is over its own pedal, which is a crank's length from the axle.
                    let ball = try at(f.body, "toes.\(s)")
                    let pedal = try #require(pedals.min { far($0.center, ball) < far($1.center, ball) })
                    #expect(far(pedal.center, ball) < 0.05, "\(id) foot.\(s) at \(f.t)")
                    let arm = [pedal.center[1] - axle[1], pedal.center[2] - axle[2]]
                    #expect(abs(hypot(arm[0], arm[1]) - CardioBikeStaging.crank) < 1e-6, "\(id) crank at \(f.t)")
                    // The pedals go round one way.
                    let angle = atan2(arm[0], arm[1])
                    if let last = before[s] {
                        var step = angle - last
                        if step > .pi { step -= 2 * .pi } else if step < -.pi { step += 2 * .pi }
                        #expect(step < 0.02 && step > -0.5, "\(id) pedal.\(s) turns \(step) at \(f.t)")
                        turned[s, default: 0] += step
                    }
                    before[s] = angle
                    // The knee is in front of the hip and never locks.
                    let hip = try at(f.body, "femur.\(s)"), knee = try at(f.body, "shin.\(s)"), ankle = try at(f.body, "foot.\(s)")
                    #expect(knee[1] < hip[1], "\(id) knee.\(s) at \(f.t)")
                    #expect(far(hip, ankle) < far(hip, knee) + far(knee, ankle) - 0.004, "\(id) leg.\(s) locks at \(f.t)")
                }
                // The hands are closed on the bar, or on an air bike's handles.
                let grips = dark(f.props, .cylinder) + dark(plan.fixed, .cylinder).filter { $0.size[0] < 0.04 }
                try holds(f, grips)
                try closed(f)
            }
            for s in ["r", "l"] { #expect(abs(abs(turned[s] ?? 0) - 2 * .pi) < 0.05, "\(id) pedal.\(s) turned \(turned[s] ?? 0)") }
        }
        // An air bike's handles rock; an upright's bar stays put.
        #expect(try sweep(loop(try staged("3893", .bike)), "hand.r", 1) > 0.1)
        #expect(try sweep(loop(try staged("0798", .bike)), "hand.r", 1) < 1e-6)
    }

    @Test func aSaddleSetTooLowSitsTheHipsLower() throws {
        let plan = try staged("0798", .bike)
        let g = try guide("0798")
        let low = try #require(g.steps.flatMap(\.mistakes).first { $0.id == "low-saddle" }?.pose)
        let good = plan.frame(at: g.faultT).body, bad = plan.frame(at: g.faultT, fault: low).body
        #expect(try at(bad, "pelvis")[2] < (try at(good, "pelvis")[2]) - 0.03)
    }

    @Test func otherBikesKeepThePlainEquipment() throws {
        // A recumbent, an arm crank and a bicycle on the road are other machines.
        for id in ["2193", "2139", "5214"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }
}

extension CardioStagingTests {
    /// The lowest point of either foot: the toe tips, the balls and the heels, less the skin under them.
    private func lowest(_ f: BodyFrame) throws -> Double {
        var low = Double.infinity
        for s in ["r", "l"] {
            let ankle = Body3D.V(try at(f, "foot.\(s)")), ball = Body3D.V(try at(f, "toes.\(s)"))
            let foot = Body3D.M(try #require(f.rotations["foot.\(s)"])), toes = Body3D.M(try #require(f.rotations["toes.\(s)"]))
            let rAnkle = try #require(body.head["foot.\(s)"]), rBall = try #require(body.head["toes.\(s)"])
            let rTip = try #require(body.tail["toes.\(s)"])
            let tip = ball + toes * (rTip - rBall)
            let heel = ankle + foot * (Body3D.V(rAnkle.x, rAnkle.y + 0.045, rTip.z) - rAnkle)
            low = min(low, tip.z - 0.01, heel.z - 0.01, ball.z - 0.02)
        }
        return low
    }

    // MARK: Elliptical

    @Test func ellipticalKeepsFeetOnThePlatesAndHandsOnTheRockingHandles() throws {
        for id in ["2141", "2192", "2331"] {
            let plan = try staged(id, .elliptical)
            let frames = loop(plan)
            try smooth(frames)
            try stays(frames, ["pelvis"])
            for f in frames {
                let plates = dark(f.props, .box)
                #expect(plates.count == 2, "\(id) plates at \(f.t)")
                for s in ["r", "l"] {
                    // The ball of the foot rests on its own plate: a sole's thickness above its top.
                    let ball = Body3D.V(try at(f.body, "toes.\(s)"))
                    let plate = try #require(plates.min { far($0.center, ball.array) < far($1.center, ball.array) })
                    let up = Body3D.M(plate.rotation) * Body3D.V(0, 0, 1)
                    let d = ball - Body3D.V(plate.center)
                    #expect(abs(d.dot(up) - plate.size[2] / 2 - 0.02) < 0.012, "\(id) foot.\(s) is \(d.dot(up)) above its plate at \(f.t)")
                    #expect((d - up * d.dot(up)).length < 0.12, "\(id) foot.\(s) off its plate at \(f.t)")
                    let hip = try at(f.body, "femur.\(s)"), knee = try at(f.body, "shin.\(s)")
                    #expect(knee[1] < hip[1], "\(id) knee.\(s) at \(f.t)")
                }
                try holds(f, dark(f.props, .cylinder))
                try closed(f)
            }
            // The plates go round an oval a stride long, and the handles rock against them.
            #expect(try sweep(frames, "foot.r", 1) > 0.3)
            #expect(try sweep(frames, "foot.r", 2) > 0.06)
            #expect(try sweep(frames, "hand.r", 1) > 0.15)
            let front = try #require(frames.min { (try? at($0.body, "foot.r")[1]) ?? 0 < (try? at($1.body, "foot.r")[1]) ?? 0 })
            #expect(try at(front.body, "hand.r")[1] > (try at(front.body, "hand.l")[1]) + 0.1)
        }
    }

    // MARK: Sled

    @Test func sledPushKeepsHandsOnThePostsAndAFootOnTheFloor() throws {
        for id in ["4428", "8702"] {
            let plan = try staged(id, .sled)
            let frames = loop(plan)
            try smooth(frames)
            let posts = dark(plan.fixed, .cylinder)
            #expect(posts.count == 2)
            for f in frames {
                try holds(f, posts)
                try closed(f)
                #expect(abs(try lowest(f.body)) < 1e-6, "\(id) feet at \(f.t)")
                let hips = try at(f.body, "pelvis")
                #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 1e-6, "\(id) hips drift at \(f.t)")
            }
            // The hands turn a little on the posts as the hips rise and fall, and go nowhere.
            try stays(frames, ["f3a.r", "f3a.l"], slack: 0.06)
        }
    }

    @Test func sledDragsHoldTheirStraps() throws {
        // Walking backward: a handle in each fist, a strap from each to the sled in front.
        let rear = try staged("2906", .sled)
        for f in loop(rear) {
            try holds(f, dark(f.props, .cylinder))
            try closed(f)
            #expect(abs(try lowest(f.body)) < 1e-6, "feet at \(f.t)")
            #expect(f.props.filter { $0.finish == .cable }.count == 6)
        }
        // Walking forward: the straps run back from the belt, and the hands are free.
        let forward = try staged("5143", .sled)
        for f in loop(forward) {
            #expect(abs(try lowest(f.body)) < 1e-6, "feet at \(f.t)")
            let hips = try at(f.body, "pelvis")
            for strap in f.props.filter({ $0.finish == .cable }) {
                #expect(far(strap.center, hips) < 1.0 && strap.center[1] > hips[1], "strap at \(f.t)")
            }
        }
        // Other ways of moving a sled keep the plain equipment.
        for id in ["7882", "8703", "9939", "10193", "2907"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    // MARK: Running and walking

    @Test func runningAndWalkingStayOnTheSpotWithAFootOnTheFloor() throws {
        for (id, floor) in [("0685", 0.0), ("5216", 0), ("4004", 0), ("2258", 0), ("4420", 0), ("s:hike", 0),
                            ("2197", CardioGaitStaging.deck), ("2259", CardioGaitStaging.deck)] {
            // Fine steps, so that a loop that froze or snapped at its end would show.
            let frames: [Sample]
            if floor > 0 {
                frames = try treadmill(id, steps: 96).frames
            } else {
                let plan = PropPlan(guide: try guide(id), body: body)
                #expect(plan.staging != nil, "\(id)")
                #expect(plan.kinds == [], "\(id)")
                frames = loop(plan, steps: 96)
            }
            try smooth(frames, jump: 0.085)
            var still = 0
            for (i, f) in frames.enumerated() {
                let hips = try at(f.body, "pelvis")
                #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 1e-6, "\(id) hips drift at \(f.t)")
                #expect(abs(try lowest(f.body) - floor) < 1e-6, "\(id) feet at \(f.t)")
                #expect((0.6...1.1).contains(hips[2] - floor), "\(id) hips at \(f.t)")
                // No joint bends the wrong way, even where the plan's own curve runs off its end.
                for s in ["r", "l"] {
                    let hip = Body3D.V(try at(f.body, "femur.\(s)")), knee = Body3D.V(try at(f.body, "shin.\(s)"))
                    let ankle = Body3D.V(try at(f.body, "foot.\(s)"))
                    #expect((knee - hip).cross(ankle - knee).x > -0.004, "\(id) knee.\(s) at \(f.t)")
                }
                if i > 0, far(try at(frames[i - 1].body, "foot.r"), try at(f.body, "foot.r")) < 1e-5,
                   far(try at(frames[i - 1].body, "foot.l"), try at(f.body, "foot.l")) < 1e-5 { still += 1 }
            }
            #expect(still < 3, "\(id) stands still for \(still) steps")
            // The loop closes: its end is its start.
            let first = try #require(frames.first).body, last = try #require(frames.last).body
            for bone in ["foot.r", "foot.l", "hand.r", "neck"] {
                #expect(far(try at(first, bone), try at(last, bone)) < 1e-6, "\(id) \(bone) does not close")
            }
        }
    }

    /// The treadmill staging, sampled as a plan would sample it.
    private func treadmill(_ id: String, steps: Int) throws -> (fixed: [PropPiece], frames: [Sample]) {
        let g = try guide(id)
        let staging = try #require(CardioGaitStaging(g, body, treadmills: true), "\(id)")
        #expect(staging.kinds == [.treadmill], "\(id)")
        let frames = (0...steps).map { i -> Sample in
            let t = Double(i) / Double(steps)
            let (f, props) = staging.frame(Figure.smooth(g.keyframes, at: t))
            return (t, f, props)
        }
        return (staging.fixed, frames)
    }

    @Test func treadmillsAreStaged() throws {
        for id in ["2197", "2259", "3666"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging is CardioGaitStaging, "\(id)")
        }
    }

    @Test func anInclineTreadmillTiltsTheDeckUnderTheFeet() throws {
        let plan = try treadmill("3666", steps: 48)
        let belt = try #require(plan.fixed.first { $0.finish == .rubber })
        let up = Body3D.M(belt.rotation) * Body3D.V(0, 0, 1)
        #expect(up.y > 0.08)
        // Its back end stays on the floor.
        #expect(abs(belt.center[2] - belt.size[1] / 2 * up.y - CardioGaitStaging.deck) < 0.02)
        for f in plan.frames {
            // The lowest of the toes, the balls and the heels is on the belt.
            var gap = Double.infinity
            for s in ["r", "l"] {
                for (bone, skin) in [("toes.\(s)", 0.02), ("foot.\(s)", 0.05)] {
                    let p = Body3D.V(try at(f.body, bone)) - Body3D.V(belt.center)
                    gap = min(gap, p.dot(up) - skin)
                }
            }
            #expect(gap > -0.03 && gap < 0.09, "feet are \(gap) off the belt at \(f.t)")
        }
    }

    @Test func gaitsWithSomethingElseGoingOnKeepThePlainEquipment() throws {
        // Against a wall, backward, with a band, on a treadmill backward, prancing, with kicks.
        for id in ["9040", "4258", "3653", "9608", "3197", "10749"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    @Test func aRuckAndABackpackRunWearTheRucksackOnTheBackClearOfTheArms() throws {
        for id in ["s:ruck", "10677"] {
            let plan = PropPlan(guide: try guide(id), body: body)
            #expect(plan.staging is CardioGaitStaging, "\(id)")
            #expect(plan.kinds == [], "\(id)")
            for f in loop(plan, steps: 96) {
                let pack = try #require(f.props.first, "\(id)")
                let ribs = Body3D.V(try at(f.body, "thorax")), neck = Body3D.V(try at(f.body, "neck"))
                let turn = Body3D.M(pack.rotation)
                let back = turn * Body3D.V(0, 1, 0), up = turn * Body3D.V(0, 0, 1)
                // It leans with the trunk, and lies against the back between the waist and the neck.
                #expect(up.dot((neck - ribs).unit) > 0.99, "\(id) leans at \(f.t)")
                let face = Body3D.V(pack.center) - back * (pack.size[1] / 2)
                #expect((0.06...0.12).contains((face - ribs).dot(back)), "\(id) on the back at \(f.t)")
                #expect((Body3D.V(pack.center) - ribs).dot(up) > 0 && (Body3D.V(pack.center) + up * (pack.size[2] / 2) - neck).dot(up) < 0, "\(id) height at \(f.t)")
                // The elbows and hands swing past its sides, not through it.
                for bone in ["ulna.r", "ulna.l", "hand.r", "hand.l"] {
                    let p = Body3D.V(try at(f.body, bone))
                    #expect(abs(p.x) > pack.size[0] / 2 + 0.04 || (p - face).dot(back) < -0.04, "\(id) \(bone) at \(f.t)")
                }
                // The feet are as in any walk or run: the lowest on the floor, the hips on the spot.
                let hips = try at(f.body, "pelvis")
                #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 1e-6, "\(id) hips drift at \(f.t)")
                #expect(abs(try lowest(f.body)) < 1e-6, "\(id) feet at \(f.t)")
            }
        }
        // Nobody else wears one.
        for id in ["2258", "0685", "s:hike"] {
            #expect(PropPlan(guide: try guide(id), body: body).frame(at: 0.3).props.isEmpty, "\(id)")
        }
    }
}

extension CardioStagingTests {
    // MARK: Ski ergometer

    @Test func skiErgStandsOnFlatFeetWithAHandleAndItsCordInEachHand() throws {
        let plan = try staged("2142", .skiErg)
        let g = try guide("2142")
        let frames = loop(plan, steps: 96)
        // The pull is quick: the hands come down the height of the body in a fifth of the loop.
        try smooth(frames, jump: 0.2)
        try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
        let pulleys = dark(plan.fixed, .cylinder).filter { $0.size[0] < 0.1 }
        #expect(pulleys.count == 2)
        var shots = frames
        for mistake in g.steps.flatMap(\.mistakes) {
            guard let pose = mistake.pose else { continue }
            let (f, props) = plan.frame(at: g.faultT, fault: pose)
            shots.append((g.faultT, f, Array(props.dropFirst(plan.fixed.count))))
        }
        for f in shots {
            #expect(abs(try lowest(f.body)) < 0.005, "feet at \(f.t)")
            try holds(f, dark(f.props, .cylinder))
            try closed(f)
            // A cord from each handle up to its own pulley, on the hand's side of the body.
            let cords = f.props.filter { $0.finish == .cable }
            #expect(cords.count == 2)
            for cord in cords {
                let top = cord.center[2] + abs((Body3D.M(cord.rotation) * Body3D.V(0, 0, 1)).z) * cord.size[2] / 2
                #expect(abs(top - pulleys[0].center[2]) < 1e-6, "cord at \(f.t)")
            }
            // Standing, even with a mistake: the knees stay off the floor and the hips over the feet.
            for s in ["r", "l"] { #expect(try at(f.body, "shin.\(s)")[2] > 0.3, "knee.\(s) at \(f.t)") }
            #expect(abs(try at(f.body, "pelvis")[1]) < 0.35, "hips at \(f.t)")
        }
        // The hands come from overhead down past the hips.
        #expect(try sweep(frames, "hand.r", 2) > 0.9)
    }
}

extension CardioStagingTests {
    // MARK: Stairs

    @Test func stairsComeDownUnderFeetThatStandOnThem() throws {
        for id in ["2311", "3009"] {
            let plan = try staged(id, .stairs)
            let frames = loop(plan, steps: 96)
            try smooth(frames)
            try stays(frames, ["pelvis"])
            let rAnkle = try #require(body.head["foot.r"]), rBall = try #require(body.head["toes.r"])
            let floor = try #require(body.tail["toes.r"]).z - 0.01
            /// The top of the step under a point, or the floor behind the flight.
            func top(_ steps: [PropPiece], under p: [Double]) -> Double {
                steps.filter { abs($0.center[1] - p[1]) <= $0.size[1] / 2 }.map { $0.size[2] }.max() ?? 0
            }
            var rode = 0.0
            for (i, f) in frames.enumerated() {
                let steps = dark(f.props, .box)
                #expect(steps.count >= 4, "\(id) steps at \(f.t)")
                var standing = 0
                for s in ["r", "l"] {
                    let ankle = try at(f.body, "foot.\(s)"), ball = try at(f.body, "toes.\(s)")
                    // Neither the heel nor the ball of a foot is ever inside a step.
                    #expect(ankle[2] - (rAnkle.z - floor) > top(steps, under: ankle) - 0.03, "\(id) heel.\(s) in a step at \(f.t)")
                    #expect(ball[2] - (rBall.z - floor) > top(steps, under: ball) - 0.03, "\(id) toes.\(s) in a step at \(f.t)")
                    let gap = ankle[2] - (rAnkle.z - floor) - top(steps, under: ankle)
                    guard abs(gap) < 0.002 else { continue }
                    standing += 1
                    // A foot on a step goes down and back with it.
                    if i > 0 {
                        let before = try at(frames[i - 1].body, "foot.\(s)")
                        let was = before[2] - (rAnkle.z - floor) - top(dark(frames[i - 1].props, .box), under: before)
                        if abs(was) < 0.002 {
                            #expect(ankle[2] <= before[2] + 1e-9 && ankle[1] >= before[1] - 1e-9, "\(id) foot.\(s) at \(f.t)")
                            rode += before[2] - ankle[2]
                        }
                    }
                    let hip = try at(f.body, "femur.\(s)"), knee = try at(f.body, "shin.\(s)")
                    #expect(far(hip, ankle) < far(hip, knee) + far(knee, ankle) - 0.003, "\(id) leg.\(s) locks at \(f.t)")
                }
                #expect(standing >= 1, "\(id) no foot on a step at \(f.t)")
            }
            // Two steps pass in a loop, and each foot rides its own for its share of that.
            #expect(rode > 2 * 2 * CardioStairsStaging.stance * CardioStairsStaging.rise * 0.95, "\(id) rode \(rode)")
            let first = try #require(frames.first).body, last = try #require(frames.last).body
            for bone in ["foot.r", "foot.l", "neck"] {
                #expect(far(try at(first, bone), try at(last, bone)) < 1e-6, "\(id) \(bone) does not close")
            }
        }
        // A lever stepper, a carried load and single steps are other things.
        for id in ["0938", "2725", "11450"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    // MARK: Carries

    /// The long thin pieces: handles and bars, not plates or dumbbell heads.
    private func bars(_ props: [PropPiece]) -> [PropPiece] {
        props.filter { $0.shape == .cylinder && $0.size[2] > $0.size[0] }
    }

    /// The least room between the body's bulk and the round parts of what is carried (plates,
    /// dumbbell heads, a kettlebell's ball): less than nothing when one is inside the body.
    private func room(_ f: Sample) -> Double {
        let g = f.body.rotations.mapValues { Body3D.M($0) }, h = f.body.heads.mapValues { Body3D.V($0) }
        let rods = body.bulk(g, h, walls: false)
        var least = Double.infinity
        for p in f.props where p.shape == .sphere || (p.shape == .cylinder && p.size[2] < p.size[0]) {
            let c = Body3D.V(p.center)
            for rod in rods {
                let share = Body3D.nearest(c, c, rod.a, rod.b).1
                least = min(least, (c - mix(rod.a, rod.b, share)).length - (rod.ra + (rod.rb - rod.ra) * share) - p.size[0] / 2)
            }
        }
        return least
    }

    /// One hand is closed on one of the bars.
    private func grips(_ f: Sample, _ s: String, within reach: Double = 0.07) throws {
        let k = try at(f.body, "f3a.\(s)")
        let d = bars(f.props).map { off(k, rod: $0) }.min() ?? 9
        #expect(d < reach, "hand.\(s) is \(d) from its grip at \(f.t)")
        let hand = Body3D.M(try #require(f.body.rotations["hand.\(s)"]))
        let tip = Body3D.M(try #require(f.body.rotations["f3c.\(s)"]))
        let q = (hand.t * tip).quat
        #expect(2 * acos(min(1, abs(q.w))) > 1.0, "hand.\(s) is open at \(f.t)")
    }

    /// How far the elbow is bent, in degrees.
    private func elbow(_ f: Sample, _ s: String) throws -> Double {
        let a = Body3D.V(try at(f.body, "humerus.\(s)")), b = Body3D.V(try at(f.body, "ulna.\(s)"))
        let c = Body3D.V(try at(f.body, "hand.\(s)"))
        return acos(min(1, max(-1, (b - a).unit.dot((c - b).unit)))) * 180 / .pi
    }

    /// Walking on the spot: the hips stay over one place, the lower foot is on the floor, the
    /// legs keep moving and the loop closes.
    private func walksOnTheSpot(_ frames: [Sample], _ id: String) throws {
        for f in frames {
            let hips = try at(f.body, "pelvis")
            #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 1e-6, "\(id) hips drift at \(f.t)")
            #expect(abs(try lowest(f.body)) < 1e-6, "\(id) feet at \(f.t)")
        }
        #expect(try sweep(frames, "foot.r", 1) > 0.3, "\(id) does not walk")
        let first = try #require(frames.first).body, last = try #require(frames.last).body
        for bone in ["foot.r", "foot.l", "hand.r", "hand.l", "neck"] {
            #expect(far(try at(first, bone), try at(last, bone)) < 1e-6, "\(id) \(bone) does not close")
        }
    }

    /// The hand of side `s` hangs beside the hip on a straight arm, outside the thigh.
    private func hangsAtTheSide(_ f: Sample, _ s: String, _ id: String) throws {
        try grips(f, s)
        let wrist = try at(f.body, "hand.\(s)"), hip = try at(f.body, "femur.\(s)"), shoulder = try at(f.body, "humerus.\(s)")
        #expect(try elbow(f, s) < 12, "\(id) elbow.\(s) at \(f.t)")
        // A hanging wrist is about as high as the hip joint.
        #expect(wrist[2] < hip[2] + 0.08 && wrist[2] > hip[2] - 0.25, "\(id) hand.\(s) height at \(f.t)")
        #expect(abs(wrist[0]) > abs(hip[0]) + 0.12, "\(id) hand.\(s) is in front of the thigh at \(f.t)")
        #expect(abs(wrist[1] - shoulder[1]) < 0.08, "\(id) hand.\(s) is not under its shoulder at \(f.t)")
    }

    /// The hand of side `s` is locked out above the head.
    private func standsOverhead(_ f: Sample, _ s: String, _ id: String) throws {
        try grips(f, s)
        let wrist = try at(f.body, "hand.\(s)"), head = try at(f.body, "head"), shoulder = try at(f.body, "humerus.\(s)")
        #expect(try elbow(f, s) < 12, "\(id) elbow.\(s) at \(f.t)")
        #expect(wrist[2] > head[2] + 0.3, "\(id) hand.\(s) height at \(f.t)")
        #expect(abs(wrist[1] - shoulder[1]) < 0.08, "\(id) hand.\(s) is not over its shoulder at \(f.t)")
    }

    @Test func farmersWalkHangsAWeightAtEachSideClearOfTheLegs() throws {
        for (id, kind) in [("2133", PropKind.dumbbell), ("2917", .dumbbell), ("3576", .kettlebell), ("4528", .kettlebell),
                           ("2734", .barbell), ("2912", .trapBar)] {
            let plan = try staged(id, kind)
            let frames = loop(plan)
            try smooth(frames)
            try walksOnTheSpot(frames, id)
            for f in frames {
                for s in ["r", "l"] { try hangsAtTheSide(f, s, id) }
                #expect(room(f) > 0.01, "\(id) the weight is \(room(f)) from the body at \(f.t)")
            }
            // The weights hang still: they only rise and fall with the shoulders.
            for hand in ["hand.r", "hand.l"] {
                #expect(try sweep(frames, hand, 0) < 1e-6 && sweep(frames, hand, 1) < 1e-6, "\(id) \(hand) swings")
            }
        }
    }

    @Test func suitcaseCarryHasOneWeightInTheRightHand() throws {
        for (id, kind) in [("2910", PropKind.dumbbell), ("5099", .kettlebell), ("2918", .barbell)] {
            let plan = try staged(id, kind)
            let frames = loop(plan)
            try smooth(frames)
            try walksOnTheSpot(frames, id)
            for f in frames {
                try hangsAtTheSide(f, "r", id)
                #expect(room(f) > 0.01, "\(id) the weight is \(room(f)) from the body at \(f.t)")
                // Everything carried is on the right; the left arm is empty.
                #expect(f.props.allSatisfy { $0.center[0] < -0.1 }, "\(id) at \(f.t)")
                let wrist = try at(f.body, "hand.l"), hip = try at(f.body, "femur.l")
                #expect(wrist[0] > hip[0] + 0.1 && wrist[2] < hip[2] + 0.1, "\(id) hand.l at \(f.t)")
            }
            // The empty arm swings as the legs walk.
            #expect(try sweep(frames, "hand.l", 1) > 0.05, "\(id) hand.l is still")
        }
    }

    @Test func overheadCarriesLockTheWeightOutAboveTheShoulders() throws {
        // Both arms up, one arm up with the other empty, and one up with the other at the side.
        for (id, kind, left) in [("2913", PropKind.dumbbell, "up"), ("4244", .kettlebell, "up"), ("2914", .barbell, "up"),
                                 ("3548", .dumbbell, "free"), ("9697", .kettlebell, "free"), ("2911", .dumbbell, "side")] {
            let plan = try staged(id, kind)
            let frames = loop(plan)
            try smooth(frames)
            try walksOnTheSpot(frames, id)
            for f in frames {
                try standsOverhead(f, "r", id)
                switch left {
                case "up": try standsOverhead(f, "l", id)
                case "side": try hangsAtTheSide(f, "l", id)
                default:
                    let wrist = try at(f.body, "hand.l"), hip = try at(f.body, "femur.l")
                    #expect(wrist[2] < hip[2] + 0.1 && f.props.allSatisfy { $0.center[0] < 0 }, "\(id) hand.l at \(f.t)")
                }
                #expect(room(f) > 0, "\(id) the weight is \(room(f)) from the body at \(f.t)")
            }
        }
        // A kettlebell held bottoms up stands above the fist; otherwise it lies below it.
        for (id, above) in [("9697", true), ("4244", false)] {
            let f = try #require(loop(PropPlan(guide: try guide(id), body: body), steps: 4).first)
            let ball = try #require(f.props.filter { $0.shape == .sphere }.max { $0.size[0] < $1.size[0] })
            #expect((ball.center[2] > (try at(f.body, "f3a.r"))[2]) == above, "\(id)")
        }
    }

    @Test func gobletCarryHoldsTheKettlebellAtTheChest() throws {
        let plan = try staged("2916", .kettlebell)
        let frames = loop(plan)
        try smooth(frames)
        try walksOnTheSpot(frames, "2916")
        for f in frames {
            try holds(f, bars(f.props), within: 0.09)
            let ball = try #require(f.props.filter { $0.shape == .sphere }.max { $0.size[0] < $1.size[0] })
            let neck = try at(f.body, "neck"), hips = try at(f.body, "pelvis")
            #expect(ball.center[1] < neck[1] - 0.15 && ball.center[2] < neck[2] && ball.center[2] > hips[2], "bell at \(f.t)")
            #expect(room(f) > 0, "the bell is \(room(f)) from the body at \(f.t)")
        }
    }

    @Test func leaningInACarryKeepsTheFeetUnderTheHipsAndTheWeightsClear() throws {
        let g = try guide("2133")
        let plan = PropPlan(guide: g, body: body)
        for fault in g.steps.flatMap(\.mistakes).compactMap(\.pose) {
            for i in 0...24 {
                let t = Double(i) / 24
                let (frame, props) = plan.frame(at: t, fault: fault)
                let f: Sample = (t, frame, Array(props.dropFirst(plan.fixed.count)))
                #expect(abs(try lowest(frame)) < 1e-6, "feet at \(t)")
                for s in ["r", "l"] {
                    try grips(f, s)
                    #expect(abs((try at(frame, "foot.\(s)"))[0] - (try at(frame, "femur.\(s)"))[0]) < 0.03, "foot.\(s) at \(t)")
                }
                #expect(room(f) > 0.01, "the weight is \(room(f)) from the body at \(t)")
            }
        }
    }

    @Test func carriesThatAreNotRecognisedKeepThePlainEquipment() throws {
        for id in ["10386", "10387", "10676", "2711", "2712", "2715", "2723", "2727", "2915"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    // MARK: Jumps

    /// Every point a foot can stand on, with its skin's thickness taken off: toe tips, balls, heels.
    private func soles(_ f: BodyFrame) throws -> [Body3D.V] {
        var out: [Body3D.V] = []
        for s in ["r", "l"] {
            let ankle = Body3D.V(try at(f, "foot.\(s)")), ball = Body3D.V(try at(f, "toes.\(s)"))
            let foot = Body3D.M(try #require(f.rotations["foot.\(s)"])), toes = Body3D.M(try #require(f.rotations["toes.\(s)"]))
            let rAnkle = try #require(body.head["foot.\(s)"]), rBall = try #require(body.head["toes.\(s)"])
            let rTip = try #require(body.tail["toes.\(s)"])
            let tip = ball + toes * (rTip - rBall)
            let heel = ankle + foot * (Body3D.V(rAnkle.x, rAnkle.y + 0.045, rTip.z) - rAnkle)
            out += [tip - Body3D.V(0, 0, 0.01), heel - Body3D.V(0, 0, 0.01), ball - Body3D.V(0, 0, 0.02)]
        }
        return out
    }

    @Test func boxJumpTakesOffFromTheFloorAndLandsFlatOnTopOfTheBox() throws {
        for id in ["3650", "3892", "0564"] {
            let g = try guide(id)
            let plan = try staged(id, .box)
            let staging = try #require(plan.staging as? CardioBoxJumpStaging)
            let box = try #require(plan.fixed.first)
            let top = box.center[2] + box.size[2] / 2
            #expect(abs(top - CardioBoxJumpStaging.top) < 1e-9)
            // The loop ends standing as it began, and starts again from the floor.
            let frames = Array(loop(plan, steps: 200).dropLast())
            // A jump is fast: the arms swing from behind the hips to overhead as the feet leave.
            try smooth(frames, jump: 0.13)
            let poses = [nil] + g.steps.flatMap(\.mistakes).compactMap(\.pose).map { Optional($0) }
            for fault in poses {
                for i in 0..<100 {
                    let t = Double(i) / 100
                    let frame = plan.frame(at: t, fault: fault).body
                    let soles = try soles(frame)
                    let low = soles.map(\.z).min() ?? 0
                    // Inside the box's outline, seen from above.
                    func over(_ p: Body3D.V) -> Bool {
                        abs(p.x - box.center[0]) < box.size[0] / 2 && abs(p.y - box.center[1]) < box.size[1] / 2
                    }
                    if t <= staging.off {
                        #expect(abs(low) < 1e-6, "\(id) feet on the floor at \(t)")
                        #expect(!soles.contains(where: over), "\(id) feet under the box at \(t)")
                    } else if t >= staging.land {
                        // Both whole feet are on the top, and stand on it.
                        #expect(abs(low - top) < 1e-6, "\(id) feet on the box at \(t)")
                        #expect(soles.allSatisfy(over), "\(id) feet off the box at \(t)")
                        if fault == nil, t >= staging.land + 0.05 {
                            #expect(soles.allSatisfy { $0.z - top < 0.012 }, "\(id) feet not flat on the box at \(t)")
                        }
                    } else {
                        // In flight nothing of a foot is inside the box.
                        #expect(low > -1e-6, "\(id) feet in the floor at \(t)")
                        #expect(soles.allSatisfy { !over($0) || $0.z > top - 0.002 }, "\(id) feet in the box at \(t)")
                    }
                }
            }
            // The hips end over the box, higher than they began by its height.
            let first = try at(try #require(frames.first).body, "pelvis"), last = try at(try #require(frames.last).body, "pelvis")
            #expect(abs(last[2] - first[2] - top) < 0.03, "\(id)")
            #expect(abs(last[0] - box.center[0]) < 0.2 && abs(last[1] - box.center[1]) < 0.25, "\(id)")
        }
        // Other ways on and off a box keep the plain equipment.
        for id in ["10160", "4844", "0567", "5166", "10987", "3887", "4168"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    /// How far `p` is from the undersides of the feet: `soles` holds a toe tip, a heel and a
    /// ball for each foot, and a sole runs from the heel to the ball to the tip.
    private func clear(_ p: Body3D.V, of soles: [Body3D.V]) -> Double {
        var least = Double.infinity
        for i in stride(from: 0, to: soles.count, by: 3) {
            for (a, b) in [(soles[i + 1], soles[i + 2]), (soles[i + 2], soles[i])] {
                let share = Body3D.nearest(p, p, a, b).1
                least = min(least, (p - mix(a, b, share)).length)
            }
        }
        return least
    }

    @Test func jumpRopeHopsOnTheSpotWithTheRopeUnderTheFeetAndOverTheHead() throws {
        for (id, turns) in [("2612", 1.0), ("3678", 1), ("3885", 2), ("5038", 2)] {
            let g = try guide(id)
            let plan = try staged(id, .jumpRope)
            let staging = try #require(plan.staging as? CardioJumpRopeStaging)
            let steps = 96
            let frames = loop(plan, steps: steps)
            try smooth(frames, jump: 0.09)
            var top = 0.0, under = 0, over = 0, last: Double?
            for f in frames {
                let handles = f.props.filter { $0.shape == .cylinder && abs($0.size[0] - 0.026) < 1e-9 }
                let rope = f.props.filter { $0.shape == .cylinder && abs($0.size[0] - 0.012) < 1e-9 }
                #expect(handles.count == 2 && rope.count == 16, "\(id) at \(f.t)")
                try holds(f, handles)
                try closed(f)
                // Feet on the floor until they push off, then no higher than the hop.
                let soles = try soles(f.body)
                let low = soles.map(\.z).min() ?? 0
                if f.t <= staging.off || f.t == 1 { #expect(abs(low) < 1e-6, "\(id) feet at \(f.t)") }
                #expect(low > -1e-6 && low < staging.height + 1e-6, "\(id) feet at \(f.t)")
                top = max(top, low)
                // The balls of the feet come down where they left, and the hips stay over them.
                let ball = (try at(f.body, "toes.r"))[1], start = (try at(frames[0].body, "toes.r"))[1]
                #expect(abs(ball - start) < 1e-3, "\(id) feet slide at \(f.t)")
                let hips = try at(f.body, "pelvis")
                #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 0.12, "\(id) hips at \(f.t)")
                // The rope stays out of the floor and out of the body.
                let bulk = body.bulk(f.body.rotations.mapValues { Body3D.M($0) }, f.body.heads.mapValues { Body3D.V($0) }, walls: false)
                let back = soles.map(\.y).max() ?? 0, front = soles.map(\.y).min() ?? 0
                for piece in rope {
                    let c = Body3D.V(piece.center)
                    #expect(c.z > 0.005, "\(id) rope in the floor at \(f.t)")
                    for rod in bulk {
                        let share = Body3D.nearest(c, c, rod.a, rod.b).1
                        #expect((c - mix(rod.a, rod.b, share)).length > rod.ra + (rod.rb - rod.ra) * share + 0.02, "\(id) rope in the body at \(f.t)")
                    }
                    #expect(clear(c, of: soles) > 0.012, "\(id) rope through the feet at \(f.t)")
                }
                let middle = (Body3D.V(rope[7].center) + Body3D.V(rope[8].center)) * 0.5
                let axis = (Body3D.V(handles[0].center) + Body3D.V(handles[1].center)) * 0.5
                if middle.z < low, middle.y > front, middle.y < back { under += 1 }
                if middle.z > (try at(f.body, "head"))[2] + 0.3, abs(middle.y - axis.y) < 0.3 { over += 1 }
                // It turns steadily, the same way all the time.
                let angle = atan2(middle.y - axis.y, axis.z - middle.z)
                if let last {
                    var step = angle - last
                    while step < 0 { step += 2 * Double.pi }
                    #expect(abs(step - 2 * Double.pi * turns / Double(steps)) < 0.05, "\(id) rope jumps at \(f.t)")
                }
                last = angle
            }
            #expect(abs(top - staging.height) < 0.003, "\(id) hop height \(top)")
            #expect(under >= 1 && over >= 1, "\(id) rope under \(under) over \(over)")
            // With every mistake the feet still meet the floor and the rope still clears them.
            for fault in g.steps.flatMap(\.mistakes).compactMap(\.pose) {
                for i in 0...48 {
                    let t = Double(i) / 48
                    let (frame, props) = plan.frame(at: t, fault: fault)
                    let soles = try soles(frame)
                    let low = soles.map(\.z).min() ?? 0
                    #expect(low > -1e-6, "\(id) feet at \(t)")
                    if t <= staging.off { #expect(abs(low) < 1e-6, "\(id) feet at \(t)") }
                    for piece in props where abs(piece.size[0] - 0.012) < 1e-9 {
                        let c = Body3D.V(piece.center)
                        #expect(c.z > 0.005, "\(id) rope in the floor at \(t)")
                        #expect(clear(c, of: soles) > 0.012, "\(id) rope through the feet at \(t)")
                    }
                }
            }
        }
        // Skipping from foot to foot, hopping from side to side and hops with no rope keep the plain plan.
        for id in ["3675", "3676", "3677", "4829", "9408"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    @Test func jumpingJackLandsWideAndTogetherOnTheFloorWithoutSliding() throws {
        for id in ["3094", "3220"] {
            let g = try guide(id)
            let plan = PropPlan(guide: g, body: body)
            let staging = try #require(plan.staging as? CardioJumpingJackStaging)
            #expect(plan.kinds == [], "\(id)")
            let poses = [nil] + g.steps.flatMap(\.mistakes).compactMap(\.pose).map { Optional($0) }
            for fault in poses {
                var top = 0.0, last: BodyFrame?, widest = 0.0
                for i in 0...200 {
                    let t = Double(i) / 200
                    let frame = plan.frame(at: t, fault: fault).body
                    let low = try soles(frame).map(\.z).min() ?? 0
                    let hop = staging.hop(at: t)
                    // The lowest part of the feet is on the floor, or as high as the hop has got.
                    #expect(abs(low - hop.height) < 1e-3, "\(id) feet at \(t)")
                    top = max(top, low)
                    let hips = try at(frame, "pelvis")
                    #expect(abs(hips[0]) < 1e-3 && abs(hips[1]) < 0.1, "\(id) hips at \(t)")
                    let apart = (try at(frame, "foot.l"))[0] - (try at(frame, "foot.r"))[0]
                    widest = max(widest, apart)
                    if let last, hop.air == 0, staging.hop(at: t - 0.005).air == 0 {
                        // Feet that are down stay where they are.
                        for bone in ["toes.r", "toes.l"] {
                            #expect(far(try at(last, bone), try at(frame, bone)) < 0.004, "\(id) \(bone) slides at \(t)")
                        }
                        #expect(try soles(frame).allSatisfy { $0.z < 0.03 } || fault != nil, "\(id) feet not flat at \(t)")
                    }
                    if let last {
                        for bone in ["pelvis", "foot.r", "foot.l", "hand.r", "hand.l"] {
                            #expect(far(try at(last, bone), try at(frame, bone)) < 0.09, "\(id) \(bone) jumps at \(t)")
                        }
                    }
                    last = frame
                }
                #expect(abs(top - CardioJumpingJackStaging.height) < 1e-3, "\(id)")
                #expect(widest > 0.5, "\(id) feet only \(widest) apart")
            }
            // Hands meet over the head at the widest point, and hang at the start.
            let high = plan.frame(at: staging.wide).body, low = plan.frame(at: 0).body
            #expect((try at(high, "hand.r"))[2] > (try at(high, "head"))[2] + 0.2, "\(id)")
            #expect((try at(low, "hand.r"))[2] < (try at(low, "pelvis"))[2] + 0.1, "\(id)")
        }
        for id in ["0264", "0785", "3223", "4438", "1478", "7555", "0504"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    @Test func burpeeHasHandsAndFeetOnTheFloorInThePlankAndJumpsFromItsSpot() throws {
        for id in ["1160", "3457"] {
            let g = try guide(id)
            let plan = PropPlan(guide: g, body: body)
            let staging = try #require(plan.staging as? CardioBurpeeStaging)
            #expect(plan.kinds == [], "\(id)")
            let poses = [nil] + g.steps.flatMap(\.mistakes).compactMap(\.pose).map { Optional($0) }
            for (k, fault) in poses.enumerated() {
                let id = "\(id)/\(k)"
                var last: BodyFrame?, top = 0.0
                let start = plan.frame(at: staging.squat, fault: fault).body
                for i in 0...400 {
                    let t = Double(i) / 400
                    let frame = plan.frame(at: t, fault: fault).body
                    let low = try soles(frame).map(\.z).min() ?? 0
                    let hop = staging.hop(at: t)
                    // Nothing goes into the floor, and the feet are on it except in the jump
                    // and as they skim back and in.
                    let sunk = frame.heads.filter { $0.value[2] < 0 }.map(\.key).sorted()
                    #expect(sunk.isEmpty, "\(id) \(sunk.prefix(3)) in the floor at \(t)")
                    let share = staging.plank(at: t)
                    #expect(low > -1e-6 && low < hop.height + CardioBurpeeStaging.skim + 1e-3, "\(id) feet at \(t)")
                    if share == 0 || share == 1 { #expect(abs(low - hop.height) < 4e-3, "\(id) feet at \(t)") }
                    top = max(top, hop.height > 0 ? low : 0)
                    if t >= staging.squat, t <= staging.back {
                        // The hands lie on the floor where they went down.
                        for s in ["r", "l"] {
                            #expect((try at(frame, "f3a.\(s)"))[2] < 0.04, "\(id) hand.\(s) off the floor at \(t)")
                            #expect(far(try at(frame, "f3a.\(s)"), try at(start, "f3a.\(s)")) < 0.01, "\(id) hand.\(s) moves at \(t)")
                        }
                    }
                    if share == 1 {
                        // The plank: shoulders over the wrists, hips off the floor, feet well behind.
                        let shoulder = try at(frame, "humerus.r"), wrist = try at(frame, "hand.r")
                        #expect(abs(shoulder[1] - wrist[1]) < 0.03, "\(id) shoulders at \(t)")
                        #expect((try at(frame, "pelvis"))[2] > 0.1, "\(id) hips at \(t)")
                        #expect((try at(frame, "foot.r"))[1] - wrist[1] > 0.9, "\(id) feet at \(t)")
                    }
                    if let last {
                        for bone in ["pelvis", "neck", "foot.r", "foot.l", "hand.r", "hand.l"] {
                            #expect(far(try at(last, bone), try at(frame, bone)) < 0.13, "\(id) \(bone) jumps at \(t)")
                        }
                    }
                    last = frame
                }
                #expect(abs(top - CardioBurpeeStaging.height) < 2e-3, "\(id) jump \(top)")
            }
        }
        for id in ["0501", "3703", "3705", "1201", "4548", "8704", "3970"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }

    @Test func highKneesAndButtKicksRunOnTheSpotWithTheStandingFootStill() throws {
        for (id, knees) in [("3556", true), ("3701", true), ("3037", false)] {
            let g = try guide(id)
            let plan = PropPlan(guide: g, body: body)
            #expect(plan.staging is CardioHighKneesStaging, "\(id)")
            #expect(plan.kinds == [], "\(id)")
            let poses = [nil] + g.steps.flatMap(\.mistakes).compactMap(\.pose).map { Optional($0) }
            for fault in poses {
                var last: BodyFrame?, lastLow: [Double] = []
                var knee = 0.0, heel = 0.0
                for i in 0...192 {
                    let t = Double(i) / 192
                    let frame = plan.frame(at: t, fault: fault).body
                    let soles = try soles(frame)
                    // The lower foot is on the floor, and the hips stay over the spot.
                    #expect(abs(soles.map(\.z).min() ?? 1) < 1e-6, "\(id) feet at \(t)")
                    let hips = try at(frame, "pelvis")
                    #expect(abs(hips[0]) < 1e-6 && abs(hips[1]) < 0.12, "\(id) hips at \(t)")
                    let low = [soles[0...2].map(\.z).min() ?? 0, soles[3...5].map(\.z).min() ?? 0]
                    if let last {
                        for (k, s) in ["r", "l"].enumerated() where low[k] < 1e-4 && lastLow[k] < 1e-4 && low[1 - k] > 0.03 && lastLow[1 - k] > 0.03 {
                            // A foot that stands alone does not slide.
                            #expect(far(try at(last, "toes.\(s)"), try at(frame, "toes.\(s)")) < 0.003, "\(id) foot.\(s) slides at \(t)")
                        }
                        for bone in ["pelvis", "neck", "foot.r", "foot.l", "hand.r"] {
                            #expect(far(try at(last, bone), try at(frame, bone)) < 0.09, "\(id) \(bone) jumps at \(t)")
                        }
                    }
                    knee = max(knee, (try at(frame, "shin.r"))[2] - (try at(frame, "femur.r"))[2])
                    heel = max(heel, (try at(frame, "foot.r"))[2])
                    (last, lastLow) = (frame, low)
                }
                if fault == nil {
                    // The knee comes up to the hip, or the heel up toward the seat.
                    if knees { #expect(knee > -0.06, "\(id) knee \(knee)") } else { #expect(heel > 0.5, "\(id) heel \(heel)") }
                }
            }
            // The loop ends as it began.
            let first = plan.frame(at: 0).body, end = plan.frame(at: 1).body
            for bone in ["pelvis", "foot.r", "foot.l", "hand.r"] {
                #expect(far(try at(first, bone), try at(end, bone)) < 1e-6, "\(id) \(bone) does not close")
            }
        }
        for id in ["0480", "0481", "10759", "3091", "3092", "3636", "5537", "1589", "6100", "1140", "9679"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
        }
    }
}

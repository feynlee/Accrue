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
        // Against a wall, backward, with a band, on a treadmill backward.
        for id in ["9040", "4258", "3653", "9608", "10677"] {
            #expect(PropPlan(guide: try guide(id), body: body).staging == nil, "\(id)")
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
}

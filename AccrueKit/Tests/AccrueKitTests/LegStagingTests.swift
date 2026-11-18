import Foundation
import Testing
@testable import AccrueKit

struct LegStagingTests {
    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id })
        return try #require(catalog.howTo(for: ex))
    }

    private func staged(_ id: String) throws -> PropPlan {
        let plan = PropPlan(guide: try guide(id), body: body)
        #expect(plan.staging != nil, "\(id)")
        return plan
    }

    /// How far the middle knuckle of each hand is from a line through `point` along `axis`.
    private func knuckles(_ frame: BodyFrame, from point: (String) -> [Double], along axis: Int?) throws -> [Double] {
        try ["r", "l"].map { s in
            let k = try #require(frame.heads["f3a.\(s)"])
            let p = point(s)
            return (0..<3).filter { $0 != axis }.reduce(0.0) { $0 + (k[$1] - p[$1]) * (k[$1] - p[$1]) }.squareRoot()
        }
    }

    private func at(_ frame: BodyFrame, _ bone: String) throws -> [Double] {
        try #require(frame.heads[bone], "\(bone)")
    }

    private func far(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    /// The loop sampled finely, with the bar (the first piece that moves) when there is one.
    private func loop(_ plan: PropPlan, steps: Int = 48) -> [(t: Double, body: BodyFrame, props: [PropPiece])] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let (f, props) = plan.frame(at: t)
            return (t, f, Array(props.dropFirst(plan.fixed.count)))
        }
    }

    /// The named joints stay where they are through the whole loop, and nothing jumps.
    private func stays(_ frames: [(t: Double, body: BodyFrame, props: [PropPiece])], _ bones: [String],
                       jump: Double = 0.09) throws {
        let first = try #require(frames.first).body
        for (i, f) in frames.enumerated() {
            for bone in bones {
                let a = try #require(first.heads[bone]), b = try #require(f.body.heads[bone])
                #expect(far(a, b) < 1e-6, "\(bone) at \(f.t)")
            }
            guard i > 0 else { continue }
            for bone in ["pelvis", "neck", "hand.r", "hand.l", "foot.r", "foot.l", "shin.r", "shin.l"] {
                let a = try #require(frames[i - 1].body.heads[bone]), b = try #require(f.body.heads[bone])
                #expect(far(a, b) < jump, "\(bone) jumps at \(f.t)")
            }
        }
    }

    // MARK: Squat

    @Test func backSquatCarriesTheBarOnTheUpperBack() throws {
        let plan = try staged(StarterIDs.squat)
        #expect(plan.staging is SquatStaging)
        #expect(plan.kinds == [.barbell])
        let frames = loop(plan)
        // Both feet flat and still: ankles, balls of the feet, on the floor.
        try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
        let ankle = try #require(frames[0].body.heads["foot.r"])
        #expect(abs(ankle[2] - body.ankleHeight) < 1e-6)
        for f in frames {
            let bar = try #require(f.props.first)
            #expect(bar.shape == .cylinder && bar.size[2] > 1.9 && abs(bar.center[0]) < 1e-9)
            // Both hands closed on the bar, outside the shoulders.
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06, "knuckles \(d) at \(f.t)") }
            for s in ["r", "l"] {
                let k = try #require(f.body.heads["f3a.\(s)"]), shoulder = try #require(f.body.heads["humerus.\(s)"])
                #expect(abs(k[0]) > abs(shoulder[0]) + 0.1)
            }
            // The bar lies behind the neck, at its base, never through it: the neck's skin is
            // some 6 cm behind the line of its joints.
            let neck = try #require(f.body.heads["neck"]), head = try #require(f.body.heads["head"])
            #expect(far(bar.center, [0, neck[1], neck[2]]) < 0.1)
            let along = [head[1] - neck[1], head[2] - neck[2]], to = [bar.center[1] - neck[1], bar.center[2] - neck[2]]
            let behind = (to[0] * along[1] - to[1] * along[0]) / (along[0] * along[0] + along[1] * along[1]).squareRoot()
            #expect(behind > 0.065, "bar \(behind) behind the neck at \(f.t)")
            // Plates clear of the floor, and the bar over the feet.
            #expect(bar.center[2] - LegWeights.plateRadius > 0.3)
            #expect(abs(bar.center[1] - (ankle[1] - 0.055)) < 0.1, "bar \(bar.center[1]) at \(f.t)")
            // Knees out over the toes as they bend, not inside the feet.
            for s in ["r", "l"] {
                let knee = try at(f.body, "shin.\(s)"), foot = try at(f.body, "foot.\(s)"), hip = try at(f.body, "femur.\(s)")
                #expect(abs(knee[0]) > abs(hip[0]) + 0.05)
                if knee[2] - hip[2] > -0.2 { #expect(abs(knee[0]) > abs(foot[0])) }
            }
        }
        // The hips go down by a third of a metre and more, to below the knees' height.
        let top = try #require(frames[0].body.heads["pelvis"]), bottom = try #require(frames[24].body.heads["pelvis"])
        let knee = try #require(frames[24].body.heads["shin.r"])
        #expect(top[2] - bottom[2] > 0.33)
        #expect(bottom[2] < knee[2] + 0.03)
    }

    @Test func squatMistakesShow() throws {
        let g = try guide(StarterIDs.squat)
        let plan = PropPlan(guide: g, body: body)
        let good = plan.frame(at: g.faultT).body
        let mistakes = g.steps.flatMap(\.mistakes)
        // Knees caving in come inside the feet; the feet stay.
        let valgus = try #require(mistakes.first { $0.id == "valgus" }?.pose)
        let caved = plan.frame(at: g.faultT, fault: valgus).body
        let knee = try at(good, "shin.r"), cavedKnee = try at(caved, "shin.r")
        #expect(abs(cavedKnee[0]) < abs(knee[0]) - 0.06)
        #expect(far(try at(caved, "toes.r"), try at(good, "toes.r")) < 1e-6)
        // Heels lifting turn the feet on their balls.
        let heels = try #require(mistakes.first { $0.id == "heels" }?.pose)
        let lifted = plan.frame(at: g.faultT, fault: heels).body
        let ankle = try at(good, "foot.r"), liftedAnkle = try at(lifted, "foot.r")
        #expect(liftedAnkle[2] > ankle[2] + 0.015)
        #expect(far(try at(lifted, "toes.r"), try at(good, "toes.r")) < 1e-6)
    }

    @Test func frontSquatRacksTheBarOnTheShoulders() throws {
        let plan = try staged("0042")
        let frames = loop(plan)
        try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
        for f in frames {
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06, "knuckles \(d) at \(f.t)") }
            // In front of the neck and under the chin, level with the tops of the shoulders.
            let neck = try #require(f.body.heads["neck"]), head = try #require(f.body.heads["head"])
            let shoulder = try #require(f.body.heads["humerus.r"])
            let along = [head[1] - neck[1], head[2] - neck[2]], to = [bar.center[1] - neck[1], bar.center[2] - neck[2]]
            let n = (along[0] * along[0] + along[1] * along[1]).squareRoot()
            #expect((to[0] * along[1] - to[1] * along[0]) / n < -0.09)
            #expect((to[0] * along[0] + to[1] * along[1]) / n < 0.02)
            #expect(far(bar.center, [0, shoulder[1], shoulder[2]]) < 0.12)
            // Elbows up in front of the bar.
            let elbow = try #require(f.body.heads["ulna.r"])
            #expect(elbow[1] < bar.center[1] - 0.1)
        }
    }

    @Test func gobletAndDumbbellSquatsHoldTheirWeights() throws {
        // One weight at the chest, a hand on each side of it.
        for (id, reach) in [("0534", 0.11), ("1760", 0.115)] {
            let plan = try staged(id)
            let lifter = try #require(plan.staging as? SquatStaging).lifter
            let g = try guide(id)
            for i in 0...24 {
                let (f, held) = lifter.solve(Figure.smooth(g.keyframes, at: Double(i) / 24))
                let at = try #require(held.first).array
                for d in try knuckles(f, from: { _ in at }, along: 2) { #expect(d < reach, "\(id) knuckles \(d)") }
                let chest = try #require(f.heads["thorax"]), neck = try #require(f.heads["neck"])
                #expect(at[1] < min(chest[1], neck[1]) - 0.15)
                #expect(at[2] < neck[2] && at[2] > chest[2])
            }
            try stays(loop(plan), ["foot.r", "foot.l", "toes.r", "toes.l"])
        }
        // A dumbbell in each hand, hanging outside the legs and off the floor.
        let plan = try staged("0413")
        #expect(plan.kinds == [.dumbbell])
        let frames = loop(plan)
        try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
        for f in frames {
            let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
            for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 1) { #expect(d < 0.06) }
            for s in ["r", "l"] {
                let at = try #require(handles[s]), knee = try #require(f.body.heads["shin.\(s)"])
                #expect(at[2] - 0.06 > 0.03)
                #expect(abs(at[0]) > abs(knee[0]) + 0.1)
            }
        }
    }

    @Test func boxSquatSitsOnItsBox() throws {
        for id in ["4962", "0026"] {
            let plan = try staged(id)
            let seat = try #require(plan.fixed.first)
            let top = seat.center[2] + seat.size[2] / 2
            let frames = loop(plan)
            let low = try frames.map { try at($0.body, "pelvis")[2] }.min() ?? 9
            // The hips come down to rest on the box, no lower.
            #expect(abs(low - 0.105 - top) < 0.01)
            // The box is behind the heels.
            let ankle = try #require(frames[0].body.heads["foot.r"])
            #expect(seat.center[1] - seat.size[1] / 2 > ankle[1] + 0.08)
        }
    }

    // MARK: Good morning

    @Test func goodMorningBowsUnderTheBar() throws {
        let plan = try staged("0044")
        #expect(plan.staging is SquatStaging)
        let frames = loop(plan)
        try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
        for f in frames {
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06) }
            #expect(bar.center[2] - LegWeights.plateRadius > 0.3)
            let neck = try #require(f.body.heads["neck"])
            #expect(far(bar.center, [0, neck[1], neck[2]]) < 0.1)
        }
        // The hips go back as the bar comes down and forward; the knees stay soft.
        let top = try at(frames[0].body, "pelvis"), bottom = try at(frames[24].body, "pelvis")
        let high = try #require(frames[0].props.first).center, low = try #require(frames[24].props.first).center
        #expect(bottom[1] > top[1] + 0.1)
        #expect(high[2] - low[2] > 0.3)
        #expect(top[2] - bottom[2] < 0.1)
    }

    @Test func squatStandIsClearOfTheLift() throws {
        for id in [StarterIDs.squat, "0042", "0124"] {
            let plan = try staged(id)
            let uprights = plan.fixed.filter { $0.shape == .box && $0.size[2] > 1 }
            #expect(uprights.count == 2, "\(id)")
            let frames = loop(plan)
            let top = try #require(frames[0].props.first).center
            // Hooks a little under the bar as it rides at the top, on uprights between the hands and the plates.
            let hooks = plan.fixed.filter { $0.size[2] < 0.02 }
            #expect(hooks.count == 2)
            for hook in hooks { #expect(top[2] - hook.center[2] > 0.03 && top[2] - hook.center[2] < 0.12) }
            for post in uprights { #expect(abs(post.center[0]) > 0.48 && abs(post.center[0]) < 0.68) }
            // Every piece is out at the sides, where a machine with its own rails leaves it out.
            #expect(plan.fixed.allSatisfy { abs($0.center[0]) > 0.5 })
            // Nothing of the stand is near the bar's path or the hips, in any frame.
            let front = try #require(plan.fixed.map { $0.center[1] - $0.size[1] / 2 }.min())
            for f in frames {
                let bar = try #require(f.props.first).center
                let pelvis = try at(f.body, "pelvis")
                #expect(front - bar[1] > 0.25, "\(id) bar at \(f.t)")
                for post in uprights { #expect(post.center[1] - pelvis[1] > 0.15, "\(id) hips at \(f.t)") }
            }
        }
        // A box squat and a lunge are shown without one.
        for id in ["4962", "0054"] { #expect(try staged(id).fixed.allSatisfy { $0.size[2] < 1 }) }
    }

    @Test func overheadSquatKeepsTheWeightOverTheShoulders() throws {
        for (id, bar) in [("0069", true), ("3709", false)] {
            let plan = try staged(id)
            #expect(plan.staging is SquatStaging)
            let frames = loop(plan)
            try stays(frames, ["foot.r", "foot.l", "toes.r", "toes.l"])
            for f in frames {
                let handles: [String: [Double]]
                if bar {
                    let rod = try #require(f.props.first)
                    #expect(rod.shape == .cylinder && rod.size[2] > 1.9 && abs(rod.center[0]) < 1e-3)
                    handles = ["r": rod.center, "l": rod.center]
                } else {
                    handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
                    #expect(abs((handles["r"] ?? [])[2] - (handles["l"] ?? [])[2]) < 1e-6)
                }
                for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 0) { #expect(d < 0.06, "\(id) \(d) at \(f.t)") }
                for s in ["r", "l"] {
                    // Arms straight, the weight above the head and over the shoulders and the feet.
                    let shoulder = try at(f.body, "humerus.\(s)"), elbow = try at(f.body, "ulna.\(s)"), wrist = try at(f.body, "hand.\(s)")
                    #expect(far(shoulder, wrist) > 0.97 * (far(shoulder, elbow) + far(elbow, wrist)))
                    let weight = try #require(handles[s]), head = try at(f.body, "head"), foot = try at(f.body, "foot.\(s)")
                    #expect(weight[2] > head[2] + 0.25, "\(id) at \(f.t)")
                    #expect(abs(weight[1] - shoulder[1]) < 0.05)
                    #expect(abs(weight[1] - foot[1]) < 0.2, "\(id) at \(f.t)")
                }
            }
        }
        // With empty hands the arms still point up.
        for f in loop(try staged("4294")) {
            let shoulder = try at(f.body, "humerus.r"), wrist = try at(f.body, "hand.r")
            #expect(wrist[2] - shoulder[2] > 0.4, "at \(f.t)")
        }
    }

    @Test func oneLegSquatStandsOnOneFoot() throws {
        for (id, deep) in [("1476", false), ("7560", false), ("0068", false), ("0411", false), ("1759", true)] {
            let plan = try staged(id)
            #expect(plan.staging is SingleLegSquatStaging)
            let frames = loop(plan)
            try stays(frames, ["foot.r", "toes.r"])
            #expect(abs(try at(frames[0].body, "foot.r")[2] - body.ankleHeight) < 1e-6)
            var low = Double.infinity, high = -Double.infinity
            for f in frames {
                let pelvis = try at(f.body, "pelvis"), free = try at(f.body, "foot.l"), stood = try at(f.body, "foot.r")
                (low, high) = (min(low, pelvis[2]), max(high, pelvis[2]))
                // The free foot never touches down, and stays in front.
                #expect(free[2] > body.ankleHeight + 0.05, "\(id) at \(f.t)")
                #expect(try at(f.body, "toes.l")[2] > 0.04, "\(id) at \(f.t)")
                #expect(free[1] < stood[1])
                // The body stays over its one foot.
                #expect(abs(pelvis[0]) < 1e-6 && abs(pelvis[1] - stood[1]) < 0.4)
            }
            #expect(high - low > (deep ? 0.45 : 0.22), "\(id) \(high - low)")
        }
    }

    @Test func jumpSquatLeavesTheFloorAndLandsWhereItStood() throws {
        for id in ["0514", "0053", "1552", "3187"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? JumpSquatStaging)
            #expect(staging.height > 0.08 && staging.height < 0.36)
            let frames = loop(plan, steps: 96)
            // The arms swing fast; nothing else moves as far in one step.
            try stays(frames, [], jump: 0.2)
            let start = try at(frames[0].body, "toes.r")
            var top = 0.0
            for f in frames {
                for s in ["r", "l"] {
                    let ball = try at(f.body, "toes.\(s)"), first = try at(frames[0].body, "toes.\(s)")
                    // Straight up and straight down: the feet come back to their own spots.
                    #expect(abs(ball[0] - first[0]) < 1e-6 && abs(ball[1] - first[1]) < 1e-6)
                    #expect(ball[2] > first[2] - 1e-9)
                    if f.t <= staging.off || f.t >= staging.land { #expect(abs(ball[2] - first[2]) < 1e-6, "\(id) at \(f.t)") }
                    top = max(top, ball[2] - start[2])
                }
            }
            #expect(abs(top - staging.height) < 0.01)
            // Heels down in the dip, up as the feet leave.
            let dip = frames[24].body, leaving = try #require(frames.last { $0.t <= staging.off }).body
            let flat = try at(dip, "foot.r"), raised = try at(leaving, "foot.r")
            let sunk = try at(dip, "pelvis"), tall = try at(frames[0].body, "pelvis")
            #expect(abs(flat[2] - body.ankleHeight) < 1e-6)
            #expect(raised[2] > body.ankleHeight + 0.03)
            #expect(sunk[2] < tall[2] - 0.2)
        }
        // A bar on the back goes up with the body, both hands on it.
        for f in loop(try staged("0053")) {
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06) }
        }
    }

    // MARK: Calf raise

    @Test func calfRaiseRisesOnTheBallsOfTheFeet() throws {
        let plan = try staged(StarterIDs.calfRaise)
        #expect(plan.staging is CalfRaiseStaging)
        let step = try #require(plan.fixed.first)
        let top = step.center[2] + step.size[2] / 2
        let frames = loop(plan)
        // The balls of the feet never leave the step; the heels hang behind its edge.
        try stays(frames, ["toes.r", "toes.l"])
        let ball = try #require(frames[0].body.heads["toes.r"])
        #expect(abs(ball[2] - top - 0.017) < 0.005)
        #expect(ball[1] < step.center[1] + step.size[1] / 2 && ball[1] > step.center[1] - step.size[1] / 2)
        var high = -Double.infinity, low = Double.infinity
        for f in frames {
            let ankle = try #require(f.body.heads["foot.r"])
            #expect(ankle[1] > step.center[1] + step.size[1] / 2)
            high = max(high, ankle[2])
            low = min(low, ankle[2])
            // The legs stay long: the hips ride straight up on the ankles.
            let pelvis = try #require(f.body.heads["pelvis"])
            #expect(abs(pelvis[2] - ankle[2] - 0.76) < 0.03)
        }
        // The heels drop below the step and rise well above it.
        #expect(low < top + body.ankleHeight - 0.02)
        #expect(high - low > 0.08)

        // On the floor the heels stop at the floor; with weights the hands stay closed on them.
        let floor = try staged("1370")
        #expect(floor.fixed.isEmpty)
        for f in loop(floor) {
            let ankle = try at(f.body, "foot.r")
            #expect(ankle[2] > body.ankleHeight - 1e-6)
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06) }
        }
        for f in loop(try staged("0417")) {
            let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
            for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 1) { #expect(d < 0.06) }
        }
    }

    @Test func oneLegCalfRaiseStandsOnOneFoot() throws {
        for (id, onFloor) in [("1387", true), ("5052", false), ("0409", false), ("1178", false)] {
            let plan = try staged(id)
            #expect(plan.staging is CalfRaiseStaging)
            #expect(plan.fixed.isEmpty == onFloor)
            let top = plan.fixed.first.map { $0.center[2] + $0.size[2] / 2 } ?? 0
            let frames = loop(plan)
            // The ball of the standing foot never leaves its spot, under the middle of the body.
            try stays(frames, ["toes.r"])
            let ball = try at(frames[0].body, "toes.r")
            #expect(abs(ball[2] - top - 0.017) < 0.005)
            #expect(abs(ball[0]) < 0.08)
            var high = -Double.infinity, low = Double.infinity
            for f in frames {
                let ankle = try at(f.body, "foot.r"), pelvis = try at(f.body, "pelvis")
                high = max(high, ankle[2])
                low = min(low, ankle[2])
                #expect(abs(pelvis[2] - ankle[2] - 0.76) < 0.03)
                // The other foot is held up behind, clear of the floor and the step.
                let free = try at(f.body, "foot.l"), toes = try at(f.body, "toes.l")
                #expect(min(free[2], toes[2]) > top + 0.15, "\(id) free foot at \(f.t)")
                #expect(free[1] > ankle[1] + 0.2)
            }
            #expect(high - low > (onFloor ? 0.05 : 0.08))
            if onFloor { #expect(low > body.ankleHeight - 1e-6) }
        }
    }

    @Test func seatedCalfRaiseKeepsTheWeightOnTheKnees() throws {
        for (id, bar) in [("1379", false), ("0088", true), ("1371", true)] {
            let plan = try staged(id)
            #expect(plan.staging is SeatedCalfRaiseStaging)
            #expect(plan.kinds == [bar ? .barbell : .dumbbell, .bench, .step])
            let pad = try #require(plan.fixed.first), block = try #require(plan.fixed.last)
            let seat = pad.center[2] + pad.size[2] / 2, top = block.center[2] + block.size[2] / 2
            let frames = loop(plan)
            // The hips stay on the bench and the balls of the feet on the block.
            try stays(frames, ["pelvis", "femur.r", "femur.l", "toes.r", "toes.l"])
            let hip = try at(frames[0].body, "femur.r"), ball = try at(frames[0].body, "toes.r")
            #expect(abs(hip[2] - seat - 0.095) < 0.01)
            #expect(abs(hip[1] - pad.center[1]) < pad.size[1] / 2)
            #expect(abs(ball[2] - top - 0.017) < 0.005)
            #expect(abs(ball[1] - block.center[1]) < block.size[1] / 2)
            var heels: [Double] = [], knees: [Double] = []
            for f in frames {
                let ankle = try at(f.body, "foot.r"), knee = try at(f.body, "shin.r")
                // The heels hang behind the block's edge, above the floor.
                #expect(ankle[1] > block.center[1] + block.size[1] / 2)
                #expect(ankle[2] > 0.04)
                heels.append(ankle[2])
                knees.append(knee[2])
                if bar {
                    // The bar lies level on the thighs just behind the knees, the hands closed on it.
                    let rod = try #require(f.props.first)
                    #expect(abs(rod.center[0]) < 1e-6)
                    #expect(rod.center[2] - knee[2] > 0.08 && rod.center[2] - knee[2] < 0.13, "\(id) bar at \(f.t)")
                    #expect(rod.center[1] > knee[1] + 0.05 && rod.center[1] < knee[1] + 0.2)
                    for d in try knuckles(f.body, from: { _ in rod.center }, along: 0) { #expect(d < 0.06) }
                } else {
                    // A dumbbell stands on each knee, its hand closed round the handle.
                    let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
                    for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 2) { #expect(d < 0.06) }
                    for s in ["r", "l"] {
                        let k = try at(f.body, "shin.\(s)"), mid = try #require(handles[s])
                        #expect(abs(mid[0] - k[0]) < 0.02)
                        #expect(mid[2] - 0.135 - k[2] > 0.07 && mid[2] - 0.135 - k[2] < 0.12, "\(id) dumbbell at \(f.t)")
                    }
                }
            }
            // The heels drop below the block's level and rise above it, and the knees go with them.
            #expect(try #require(heels.min()) < top + body.ankleHeight - 0.02)
            #expect(try #require(heels.max()) - (try #require(heels.min())) > 0.07)
            #expect(try #require(knees.max()) - (try #require(knees.min())) > 0.05)
        }
    }

    // MARK: Lunges

    @Test func splitSquatKeepsBothFeetPlanted() throws {
        for id in ["0781", "2960", "3030"] {
            let plan = try staged(id)
            #expect(plan.staging is LungeStaging)
            let frames = loop(plan)
            // The front foot flat, the back foot on its ball, neither sliding.
            try stays(frames, ["foot.r", "toes.r", "toes.l"])
            let front = try #require(frames[0].body.heads["foot.r"]), back = try #require(frames[0].body.heads["toes.l"])
            #expect(abs(front[2] - body.ankleHeight) < 1e-6)
            #expect(back[1] - front[1] > 0.6)
            var low = Double.infinity, high = -Double.infinity
            for f in frames {
                let pelvis = try #require(f.body.heads["pelvis"])
                low = min(low, pelvis[2])
                high = max(high, pelvis[2])
                // The hips stay between the feet, and the back heel stays up.
                #expect(pelvis[1] > front[1] + 0.2 && pelvis[1] < back[1] - 0.2)
                let heel = try at(f.body, "foot.l")
                #expect(heel[2] > back[2] + 0.05)
                // The back knee comes close to the floor and never into it; the front knee stays
                // over its foot.
                let rear = try #require(f.body.heads["shin.l"]), knee = try #require(f.body.heads["shin.r"])
                #expect(rear[2] > 0.065, "\(id) back knee \(rear[2]) at \(f.t)")
                #expect(knee[1] > front[1] - 0.12 && knee[1] < front[1] + 0.22)
            }
            #expect(high - low > 0.22)
            let rear = try #require(frames[24].body.heads["shin.l"])
            #expect(rear[2] < 0.16)
        }
        // Dumbbells hang at the sides; a bar rides on the back.
        for f in loop(try staged("2960")) {
            let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
            for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 1) { #expect(d < 0.06) }
            for at in handles.values { #expect(at[2] - 0.06 > 0.03) }
        }
        for f in loop(try staged("3030")) {
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06) }
        }
    }

    /// The places the ball of a foot rests on the floor during the loop. A foot that stays put,
    /// or turns on its ball, has one; a foot that steps has two, and is in the air between them.
    private func rests(_ frames: [(t: Double, body: BodyFrame, props: [PropPiece])], _ side: String) throws -> [[Double]] {
        let balls = try frames.map { try at($0.body, "toes.\(side)") }
        var found: [[Double]] = []
        for (i, ball) in balls.enumerated() {
            // Down is no higher than the lower of the two spots it is travelling between.
            let around = balls[max(0, i - 1)...min(balls.count - 1, i + 1)].map { $0[2] }.min() ?? ball[2]
            guard ball[2] <= around + 1e-9, i == 0 || far(ball, balls[i - 1]) < 1e-6 || i == balls.count - 1
                    || far(ball, balls[i + 1]) < 1e-6 else { continue }
            if !found.contains(where: { far($0, ball) < 1e-4 }) { found.append(ball) }
        }
        // Whenever the ball moves along the floor's level it is off the floor.
        for (i, ball) in balls.enumerated() where i > 0 && far(ball, balls[i - 1]) > 1e-6 {
            let low = found.map { $0[2] }.min() ?? 0
            #expect(max(ball[2], balls[i - 1][2]) > low + 1e-5, "toes.\(side) slides at \(frames[i].t)")
        }
        return found
    }

    @Test func forwardAndReverseLungesStepOutAndBack() throws {
        for (id, stepping, planted) in [("0612", "r", "l"), ("0336", "r", "l"), ("0054", "r", "l"),
                                        ("1581", "l", "r"), ("0381", "l", "r"), ("0078", "l", "r")] {
            let plan = try staged(id)
            #expect(plan.staging is LungeStaging)
            let frames = loop(plan)
            try stays(frames, ["toes.\(planted)"], jump: 0.2)
            // The stepping foot rests in two places, a long stride apart, and is carried between them.
            let spots = try rests(frames, stepping)
            #expect(spots.count == 2, "\(id) \(spots)")
            if spots.count == 2 { #expect(abs(spots[0][1] - spots[1][1]) > 0.6) }
            // Tall with the feet side by side at the start and the end; front foot ahead in the lunge.
            for f in [frames[0], frames[48]] {
                #expect(abs(try at(f.body, "foot.r")[1] - at(f.body, "foot.l")[1]) < 0.02)
                #expect(try at(f.body, "pelvis")[2] > 0.8)
            }
            let low = frames[24].body
            #expect(try at(low, "foot.l")[1] - at(low, "foot.r")[1] > 0.5)
            #expect(try at(low, "foot.r")[2] - body.ankleHeight < 1e-6)
            #expect(try at(low, "shin.l")[2] < 0.16)
            for f in frames {
                #expect(try at(f.body, "shin.l")[2] > 0.065, "\(id) back knee at \(f.t)")
                #expect(try at(f.body, "foot.r")[2] > body.ankleHeight - 1e-6 && at(f.body, "foot.l")[2] > body.ankleHeight - 1e-6)
            }
        }
        // Dumbbells hang at the sides; a bar rides on the back.
        for f in loop(try staged("0336")) {
            let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
            for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 1) { #expect(d < 0.06) }
            for at in handles.values { #expect(at[2] - 0.06 > 0.03) }
        }
        for f in loop(try staged("0054")) {
            let bar = try #require(f.props.first)
            for d in try knuckles(f.body, from: { _ in bar.center }, along: 0) { #expect(d < 0.06) }
        }
    }

    @Test func walkingLungeBringsTheRearFootThrough() throws {
        for id in ["1460", "4295", "5823"] {
            let plan = try staged(id)
            let frames = loop(plan)
            try stays(frames, [], jump: 0.2)
            // Each foot takes one step: the right on the way down, the left on the way up.
            for s in ["r", "l"] {
                let spots = try rests(frames, s)
                #expect(spots.count == 2, "\(id) \(s) \(spots)")
                if spots.count == 2 { #expect(spots[0][1] - spots[1][1] > 0.6) }
            }
            for f in frames {
                let right = try at(f.body, "toes.r"), left = try at(f.body, "toes.l")
                if f.t <= 0.5 { #expect(far(left, try at(frames[0].body, "toes.l")) < 1e-6) }
                if f.t >= 0.5 { #expect(far(right, try at(frames[48].body, "toes.r")) < 1e-6) }
            }
            // It ends standing tall a stride further on.
            let start = try at(frames[0].body, "pelvis"), end = try at(frames[48].body, "pelvis")
            #expect(start[1] - end[1] > 0.6 && abs(start[2] - end[2]) < 0.01)
            #expect(abs(try at(frames[48].body, "foot.r")[1] - at(frames[48].body, "foot.l")[1]) < 0.02)
        }
        // With no moment of the loop to go by, the staging shows the way down.
        let plan = try staged("1460")
        let pose = Figure.smooth(plan.guide.keyframes, at: 0.75)
        let down = try #require(plan.staging).frame(pose).body, timed = plan.frame(at: 0.3).body
        #expect(far(try at(down, "pelvis"), try at(timed, "pelvis")) < 1e-6)
        #expect(far(try at(down, "pelvis"), try at(plan.frame(at: 0.75).body, "pelvis")) > 0.1)
    }

    @Test func sideLungeSitsOverTheBentLeg() throws {
        // 2972 and 1410 step out; 2569 is a Cossack squat, which keeps its wide stance.
        for (id, steps) in [("2972", true), ("1410", true), ("4045", true), ("2569", false)] {
            let plan = try staged(id)
            let frames = loop(plan)
            try stays(frames, ["foot.l", "toes.l"], jump: 0.16)
            let spots = try rests(frames, "r")
            #expect(spots.count == (steps ? 2 : 1), "\(id) \(spots)")
            if steps { #expect(abs(try at(frames[0].body, "foot.r")[0] - at(frames[0].body, "foot.l")[0]) < 0.3) }
            let low = frames[24].body
            let right = try at(low, "foot.r"), left = try at(low, "foot.l"), pelvis = try at(low, "pelvis")
            #expect(left[0] - right[0] > 0.7)
            // Both feet flat; the hips low and well over toward the bent leg, whose knee is over its foot.
            #expect(abs(right[2] - body.ankleHeight) < 1e-6 && abs(left[2] - body.ankleHeight) < 1e-6)
            #expect(pelvis[2] < 0.62 && pelvis[0] < (right[0] + left[0]) / 2 - 0.12, "\(id) \(pelvis)")
            #expect(abs(try at(low, "shin.r")[0] - right[0]) < 0.12)
            // The other leg stays straight.
            let hip = try at(low, "femur.l"), knee = try at(low, "shin.l")
            #expect(far(hip, left) > 0.97 * (far(hip, knee) + far(knee, left)))
        }
    }

    @Test func curtsyStepsBehindAndAcross() throws {
        for id in ["6318", "3723", "3683"] {
            let plan = try staged(id)
            let frames = loop(plan)
            try stays(frames, ["foot.r", "toes.r"], jump: 0.16)
            let spots = try rests(frames, "l")
            #expect(spots.count == 2, "\(id) \(spots)")
            let low = frames[24].body
            let front = try at(low, "foot.r"), ball = try at(low, "toes.l")
            #expect(ball[1] - front[1] > 0.35 && ball[0] < front[0] - 0.05, "\(id) \(ball)")
            for f in frames { #expect(try at(f.body, "shin.l")[2] > 0.065, "\(id) back knee at \(f.t)") }
        }
    }

    @Test func bulgarianSplitSquatRestsTheRearFootOnTheBench() throws {
        for id in ["2290", "7549", "9315"] {
            let plan = try staged(id)
            #expect(plan.kinds.contains(.bench))
            let frames = loop(plan)
            try stays(frames, ["foot.r", "toes.r", "foot.l"])
            let pad = try #require(plan.fixed.first)
            let top = pad.center[2] + pad.size[2] / 2
            let rear = try at(frames[0].body, "foot.l")
            // The ankle lies just over the pad, inside its edges, and the toes point back.
            #expect(rear[2] - top > 0.02 && rear[2] - top < 0.08)
            #expect(abs(rear[1] - pad.center[1]) < pad.size[1] / 2)
            #expect(try at(frames[0].body, "toes.l")[1] > rear[1] + 0.05)
            var low = Double.infinity, high = -Double.infinity
            for f in frames {
                let pelvis = try at(f.body, "pelvis")
                (low, high) = (min(low, pelvis[2]), max(high, pelvis[2]))
                #expect(try at(f.body, "shin.l")[2] > 0.065, "\(id) back knee at \(f.t)")
            }
            #expect(high - low > 0.25)
        }
    }

    @Test func raisedFrontFootStandsOnItsStep() throws {
        // A split squat with the front foot raised, and a reverse lunge that steps back down off a step.
        for (id, steps) in [("2957", false), ("7326", true), ("5312", true)] {
            let plan = try staged(id)
            #expect(plan.kinds.contains(.step))
            let step = try #require(plan.fixed.last)
            let top = step.center[2] + step.size[2] / 2
            let frames = loop(plan)
            try stays(frames, ["foot.r", "toes.r"], jump: 0.2)
            let front = try at(frames[0].body, "foot.r"), ball = try at(frames[0].body, "toes.r")
            #expect(abs(front[2] - top - body.ankleHeight) < 1e-6)
            for p in [front, ball] { #expect(abs(p[1] - step.center[1]) < step.size[1] / 2 - 0.02) }
            // The rear foot comes down on the floor, behind the step.
            let spots = try rests(frames, "l")
            #expect(spots.count == (steps ? 2 : 1), "\(id) \(spots)")
            let rear = try at(frames[24].body, "toes.l")
            #expect(rear[2] < 0.03 && rear[1] > step.center[1] + step.size[1] / 2 + 0.2)
            if steps { #expect(abs(try at(frames[0].body, "foot.l")[2] - front[2]) < 1e-6) }
        }
    }

    // MARK: Step-up

    @Test func stepUpStandsOnTheBox() throws {
        // Onto a box, and onto a bench where the name says so.
        for (id, bench) in [("0801", false), ("0431", false), ("0114", false), ("0733", false), ("4821", true), ("4795", true)] {
            let plan = try staged(id)
            #expect(plan.staging is StepUpStaging)
            #expect(plan.kinds.contains(bench ? .bench : .box))
            let box = try #require(plan.fixed.first)
            let top = box.center[2] + box.size[2] / 2, near = box.center[1] + box.size[1] / 2
            let frames = loop(plan)
            // The box foot is flat on the box and never moves.
            try stays(frames, ["foot.r", "toes.r"], jump: bench ? 0.15 : 0.13)
            let lead = try #require(frames[0].body.heads["foot.r"])
            #expect(abs(lead[2] - top - body.ankleHeight) < 1e-6)
            #expect(lead[1] + 0.075 < near)
            // The loop starts with the other foot flat on the floor behind the box.
            let start = try #require(frames[0].body.heads["foot.l"])
            #expect(abs(start[2] - body.ankleHeight) < 0.005)
            var high = -Double.infinity
            for f in frames {
                let pelvis = try #require(f.body.heads["pelvis"])
                high = max(high, pelvis[2])
                // The trailing foot never goes under the floor or into the box.
                let ankle = try #require(f.body.heads["foot.l"]), ball = try #require(f.body.heads["toes.l"])
                #expect(ankle[2] > body.ankleHeight - 0.005)
                if ball[2] < top + 0.015 { #expect(ball[1] > near + 0.04, "\(id) foot in the box at \(f.t)") }
            }
            // At the top the body stands straight over the box foot.
            let first = try #require(frames[0].body.heads["pelvis"])
            #expect(high - first[2] > 0.25)
            let up = try #require(try frames.max { try at($0.body, "pelvis")[2] < at($1.body, "pelvis")[2] }).body
            let over = try at(up, "pelvis"), hanging = try at(up, "foot.l")
            #expect(abs(over[1] - lead[1]) < 0.08)
            #expect(hanging[2] > top + body.ankleHeight)
        }
    }

    @Test func sideStepUpCrossesOverTheBoxFoot() throws {
        for id in ["5154", "2468"] {
            let plan = try staged(id)
            #expect(plan.staging is SideStepUpStaging)
            let box = try #require(plan.fixed.first)
            let top = box.center[2] + box.size[2] / 2, face = box.center[0] + box.size[0] / 2
            let frames = loop(plan)
            // The box foot is flat on the box, inside its edge, and never moves.
            try stays(frames, ["foot.r", "toes.r"], jump: 0.13)
            let lead = try at(frames[0].body, "foot.r")
            #expect(abs(lead[2] - top - body.ankleHeight) < 1e-6)
            #expect(lead[0] + 0.05 < face)
            // The loop starts with the other foot flat on the floor beside the box, the hips over it.
            let start = try at(frames[0].body, "foot.l"), first = try at(frames[0].body, "pelvis")
            #expect(abs(start[2] - body.ankleHeight) < 0.005)
            #expect(first[0] > lead[0] + 0.12)
            for f in frames {
                // The other foot never goes under the floor, into the box or over it.
                let ankle = try at(f.body, "foot.l"), ball = try at(f.body, "toes.l")
                #expect(ankle[2] > body.ankleHeight - 0.005)
                #expect(ankle[0] > face + 0.06 && ball[0] > face + 0.03, "\(id) foot in the box at \(f.t)")
            }
            // At the top the body stands straight over the box foot, the other foot hanging beside the box.
            let up = try #require(try frames.max { try at($0.body, "pelvis")[2] < at($1.body, "pelvis")[2] }).body
            let over = try at(up, "pelvis"), hanging = try at(up, "foot.l")
            #expect(over[2] - first[2] > 0.2)
            #expect(abs(over[0] - lead[0]) < 0.08)
            #expect(abs(over[1] - lead[1]) < 0.1)
            #expect(hanging[2] > body.ankleHeight + 0.12)
        }
        for f in loop(try staged("2468")) {
            let handles = ["r": try #require(f.props.first).center, "l": try #require(f.props.dropFirst(3).first).center]
            for d in try knuckles(f.body, from: { handles[$0] ?? [0, 0, 0] }, along: 1) { #expect(d < 0.06) }
        }
    }

    // MARK: Which exercises

    @Test func stagesOnlyWhatItKnows() throws {
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), LegStagings.make(g, body) != nil else { continue }
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts["squat", default: 0] >= 45)
        #expect(counts["calf-raise", default: 0] >= 19)
        #expect(counts["lunge-split-squat", default: 0] >= 25)
        #expect(counts["step-up", default: 0] >= 11)
        #expect(counts["back-extension", default: 0] >= 2)
        #expect(counts["single-leg-squat", default: 0] >= 6)
        #expect(counts["jump-squat-tuck", default: 0] >= 4)
        #expect(Set(counts.keys).isSubset(of: ["squat", "calf-raise", "lunge-split-squat", "step-up", "back-extension",
                                               "single-leg-squat", "jump-squat-tuck"]))
        // Other bars, machines, one-legged and sideways versions keep the plain equipment.
        for name in ["smith squat", "barbell zercher squat", "squat to overhead reach", "skater squat", "knee tuck jump",
                     "single leg squat with support", "prisoner jump squat", "kettlebell pistol squat", "sled hack squat", "donkey calf raise",
                     "standing single leg calf raise with support", "dumbbell seated one leg calf raise", "lever standing calf raise", "dumbbell lateral lunge with bicep curl",
                     "dumbbell contralateral forward lunge", "kettlebell forward lunge", "barbell zercher bulgarian split squat",
                     "lateral step up with knee drive", "lever seated calf raise", "barbell seated good morning", "barbell bench front squat",
                     "45 degree hyperextension (arms in front of chest)"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(LegStagings.make(g, body) == nil, "\(name)")
        }
    }

    /// LEG_LIST=<path> writes which staging every exercise of the leg families gets.
    @Test func listForReview() throws {
        guard let path = ProcessInfo.processInfo.environment["LEG_LIST"] else { return }
        var lines: [String] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let g = catalog.howTo(for: ex),
                  ["squat", "calf-raise", "lunge-split-squat", "step-up", "back-extension", "single-leg-squat", "jump-squat-tuck"].contains(g.familyID) else { continue }
            let staging = Stagings.make(g, body).map { String(describing: type(of: $0)) } ?? "-"
            lines.append([g.familyID, g.subtypeID ?? "", g.equipment ?? "", ex.id, staging, ex.name].joined(separator: "\t"))
        }
        try lines.sorted().joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

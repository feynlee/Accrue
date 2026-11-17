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

    // MARK: Lunge

    @Test func splitSquatKeepsBothFeetPlanted() throws {
        for id in ["0612", "0336", "0054"] {
            let plan = try staged(id)
            #expect(plan.staging is SplitSquatStaging)
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

    // MARK: Step-up

    @Test func stepUpStandsOnTheBox() throws {
        for id in ["0801", "0431", "0114"] {
            let plan = try staged(id)
            #expect(plan.staging is StepUpStaging)
            let box = try #require(plan.fixed.first)
            let top = box.center[2] + box.size[2] / 2, near = box.center[1] + box.size[1] / 2
            let frames = loop(plan)
            // The box foot is flat on the box and never moves.
            try stays(frames, ["foot.r", "toes.r"], jump: 0.13)
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

    // MARK: Which exercises

    @Test func stagesOnlyWhatItKnows() throws {
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), LegStagings.make(g, body) != nil else { continue }
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts["squat", default: 0] >= 45)
        #expect(counts["calf-raise", default: 0] >= 9)
        #expect(counts["lunge-split-squat", default: 0] >= 25)
        #expect(counts["step-up", default: 0] >= 6)
        #expect(counts["back-extension", default: 0] >= 2)
        #expect(Set(counts.keys).isSubset(of: ["squat", "calf-raise", "lunge-split-squat", "step-up", "back-extension"]))
        // Other bars, machines, one-legged and sideways versions keep the plain equipment.
        for name in ["smith squat", "barbell zercher squat", "barbell overhead squat", "sled hack squat", "donkey calf raise",
                     "dumbbell single leg calf raise", "lever standing calf raise", "dumbbell lateral lunge",
                     "dumbbell bulgarian split squat", "lateral step up", "barbell seated good morning", "barbell bench front squat",
                     "45 degree hyperextension (arms in front of chest)"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(LegStagings.make(g, body) == nil, "\(name)")
        }
    }
}

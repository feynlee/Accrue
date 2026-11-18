import Foundation
import Testing
@testable import AccrueKit

struct FreeWeightStagingTests {
    typealias V = Body3D.V

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

    private func at(_ frame: BodyFrame, _ bone: String) throws -> V {
        V(try #require(frame.heads[bone], "\(bone)"))
    }

    /// The loop sampled finely, with the pieces that move.
    private func loop(_ plan: PropPlan, steps: Int = 96) -> [(t: Double, body: BodyFrame, props: [PropPiece])] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let (f, props) = plan.frame(at: t)
            return (t, f, Array(props.dropFirst(plan.fixed.count)))
        }
    }

    /// The feet stay where they are through the whole loop, flat on the floor, and nothing
    /// jumps: the fastest lift moves a hand or the head some 5 cm in a hundredth of its loop.
    private func planted(_ frames: [(t: Double, body: BodyFrame, props: [PropPiece])], jump: Double = 0.055) throws {
        let first = try #require(frames.first).body
        let ankle = try at(first, "foot.r")
        #expect(abs(ankle.z - body.ankleHeight) < 1e-6)
        for (i, f) in frames.enumerated() {
            for bone in ["foot.r", "foot.l", "toes.r", "toes.l"] {
                let a = try at(first, bone), b = try at(f.body, bone)
                #expect((a - b).length < 1e-6, "\(bone) at \(f.t)")
            }
            guard i > 0 else { continue }
            for bone in ["pelvis", "neck", "hand.r", "hand.l", "shin.r", "shin.l", "ulna.r", "ulna.l"] {
                let a = try at(frames[i - 1].body, bone), b = try at(f.body, bone)
                #expect((a - b).length < jump, "\(bone) jumps at \(f.t)")
            }
        }
    }

    /// How far the middle knuckle and the fingertip joint of each hand are from the line of `rod`.
    private func fingers(_ frame: BodyFrame, on rod: PropPiece) throws -> [Double] {
        let axis = Body3D.M(rod.rotation) * V(0, 0, 1)
        return try ["r", "l"].flatMap { s in
            try ["f3a", "f3c"].map { bone in
                let d = try at(frame, "\(bone).\(s)") - V(rod.center)
                return (d - axis * d.dot(axis)).length
            }
        }
    }

    /// The room between a level bar at `mid` and the legs, hips, trunk and head of the body in `frame`.
    private func room(_ mid: V, _ frame: BodyFrame, half: Double = 1, radius: Double = LegWeights.barRadius) -> Double {
        let g = frame.rotations.mapValues { Body3D.M($0) }, h = frame.heads.mapValues { V($0) }
        let p = mid - V(half, 0, 0), q = mid + V(half, 0, 0)
        return body.bulk(g, h, walls: false).map { rod in
            let (s, t) = Body3D.nearest(p, q, rod.a, rod.b)
            return (mix(p, q, s) - mix(rod.a, rod.b, t)).length - (rod.ra + (rod.rb - rod.ra) * t) - radius
        }.min() ?? 1
    }

    /// Where the body's weight and the bar's (at `share` of the body's) come down, front to back.
    private func balance(_ frame: BodyFrame, bar: V, share: Double) -> Double {
        let g = frame.rotations.mapValues { Body3D.M($0) }, h = frame.heads.mapValues { V($0) }
        return (body.balance(g, h).y + bar.y * share) / (1 + share)
    }

    // MARK: Deadlift

    @Test func deadliftLiftsTheBarFromTheFloorUpTheLegs() throws {
        // Conventional, then sumo.
        for id in ["0032", "0117"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightDeadliftStaging)
            #expect(plan.kinds == [.barbell])
            let frames = loop(plan)
            try planted(frames)
            let line = try #require(frames.first?.props.first).center[1]
            let ankle = try at(frames[0].body, "foot.l")
            // The bar's line is over the feet, in front of the ankles and behind the toes.
            #expect(line < ankle.y - 0.06 && line > ankle.y - 0.13, "\(id) line \(line)")
            var heights: [Double] = []
            for f in frames {
                let bar = try #require(f.props.first)
                #expect(bar.shape == .cylinder && bar.size[2] > 1.9, "\(id)")
                // Level, across the body, and straight up and down its line.
                #expect(abs(bar.center[0]) < 1e-9 && abs(bar.center[1] - line) < 1e-6, "\(id) \(f.t)")
                #expect(abs((Body3D.M(bar.rotation) * V(0, 0, 1)).x) > 0.999999)
                // Both hands closed on it.
                for d in try fingers(f.body, on: bar) { #expect(d < 0.05, "\(id) fingers \(d) at \(f.t)") }
                // The plates never go into the floor.
                for plate in f.props.filter({ $0.finish == .plate }) {
                    #expect(plate.center[2] - plate.size[0] / 2 > -1e-6, "\(id) \(f.t)")
                }
                // The bar is against the legs or just in front of them, never in them.
                let gap = room(V(bar.center), f.body)
                #expect(gap > -0.003 && gap < 0.06, "\(id) bar \(gap) from the body at \(f.t)")
                // The arms are long.
                for s in ["r", "l"] {
                    let upper = try at(f.body, "ulna.\(s)") - at(f.body, "humerus.\(s)")
                    let lower = try at(f.body, "hand.\(s)") - at(f.body, "ulna.\(s)")
                    #expect(upper.unit.dot(lower.unit) > 0.96, "\(id) elbow at \(f.t)")
                }
                // The lifter does not fall over: the weight comes down between heel and toes.
                let over = balance(f.body, bar: V(bar.center), share: 1)
                #expect(over < ankle.y + 0.04 && over > ankle.y - 0.14, "\(id) weight over \(over) at \(f.t)")
                heights.append(bar.center[2])
            }
            // The plates stand on the floor at the start and the end, and the bar rises to the top of the thighs.
            #expect(abs(heights[0] - LegWeights.plateRadius) < 1e-6 && abs(heights[96] - LegWeights.plateRadius) < 1e-6)
            #expect((heights.max() ?? 0) > 0.7)
            // At the floor the shoulders are over the bar or just in front of it, above the hips,
            // and the hips are above the knees.
            let start = frames[0].body
            let shoulder = try at(start, "humerus.r"), hip = try at(start, "femur.r"), knee = try at(start, "shin.r")
            #expect(shoulder.y < line && shoulder.y > line - 0.16)
            #expect(shoulder.z > hip.z + 0.15 && hip.z > knee.z + 0.05, "\(id)")
            // At the top the lifter stands tall.
            let top = frames[44].body
            let stoodHip = try at(top, "femur.r"), stoodShoulder = try at(top, "humerus.r")
            #expect(stoodHip.z > 0.8 && abs(stoodShoulder.y - stoodHip.y) < 0.08, "\(id)")
        }
        // A sumo lifter's hands are inside the knees, a conventional lifter's outside.
        let sumo = try staged("0117").frame(at: 0).body, plain = try staged("0032").frame(at: 0).body
        let sumoHand = try at(sumo, "hand.l").x, sumoKnee = try at(sumo, "shin.l").x, sumoFoot = try at(sumo, "foot.l").x
        let plainHand = try at(plain, "hand.l").x, plainKnee = try at(plain, "shin.l").x, plainFoot = try at(plain, "foot.l").x
        #expect(sumoHand < sumoKnee - 0.08 && plainHand > plainKnee + 0.08)
        #expect(sumoFoot > plainFoot + 0.15)
    }

    @Test func deadliftMistakesShow() throws {
        let g = try guide("0032")
        let plan = PropPlan(guide: g, body: body)
        let mistakes = g.steps.flatMap(\.mistakes)
        let t = g.faultT
        let (good, props) = plan.frame(at: t)
        let bar = try #require(props.first)
        // A bar that drifts forward swings away from the legs in closed hands; the feet stay.
        let drift = try #require(mistakes.first { $0.id == "drift" }?.pose)
        let (drifted, moved) = plan.frame(at: t, fault: drift)
        let far = try #require(moved.first)
        #expect(far.center[1] < bar.center[1] - 0.08)
        for d in try fingers(drifted, on: far) { #expect(d < 0.05) }
        let toes = try at(good, "toes.r"), head = try at(good, "head")
        #expect((try at(drifted, "toes.r") - toes).length < 1e-6)
        // A rounded back and a lean back move the head; the hands stay on the bar.
        for id in ["round", "leanback", "hipsfirst"] {
            let fault = try #require(mistakes.first { $0.id == id }?.pose)
            let (bad, held) = plan.frame(at: t, fault: fault)
            #expect((try at(bad, "head") - head).length > 0.03, "\(id)")
            for d in try fingers(bad, on: try #require(held.first)) { #expect(d < 0.05, "\(id)") }
            #expect((try at(bad, "toes.r") - toes).length < 1e-6)
        }
    }

    @Test func romanianDeadliftSlidesTheBarDownTheLegs() throws {
        let plan = try staged("0085")
        #expect(plan.staging is FreeWeightHingeStaging)
        let frames = loop(plan)
        try planted(frames)
        var lowest = Double.infinity
        for f in frames {
            let bar = try #require(f.props.first)
            for d in try fingers(f.body, on: bar) { #expect(d < 0.05, "fingers \(d) at \(f.t)") }
            // Against the legs all the way, and never down to the floor.
            let gap = room(V(bar.center), f.body)
            #expect(gap > -0.003 && gap < 0.03, "bar \(gap) from the legs at \(f.t)")
            #expect(bar.center[2] - LegWeights.plateRadius > 0.03, "\(f.t)")
            let ankle = try at(f.body, "foot.l")
            let over = balance(f.body, bar: V(bar.center), share: FreeWeightHingeStaging.mass)
            #expect(abs(over - (ankle.y - 0.055)) < 0.03, "weight over \(over) at \(f.t)")
            lowest = min(lowest, bar.center[2])
        }
        // From the top of the thighs to below the knees, with the knees soft and the hips back.
        let top = try #require(frames[0].props.first), bottom = frames[48].body
        let hip = try at(bottom, "femur.r"), knee = try at(bottom, "shin.r"), foot = try at(bottom, "foot.r")
        #expect(top.center[2] > 0.7 && lowest < knee.z - 0.03)
        #expect(hip.y > foot.y + 0.1 && hip.z > 0.75)
    }

    @Test func dumbbellDeadliftsHoldADumbbellInEachHand() throws {
        for id in ["0300", "1459"] {
            let plan = try staged(id)
            #expect(plan.kinds == [.dumbbell])
            let frames = loop(plan)
            try planted(frames)
            for f in frames {
                let handles = f.props.filter { $0.shape == .cylinder && $0.finish == .metal }
                #expect(handles.count == 2)
                for (s, handle) in zip(["l", "r"], handles.sorted { $0.center[0] > $1.center[0] }) {
                    let d = try at(f.body, "f3a.\(s)") - V(handle.center)
                    #expect(V(0, d.y, d.z).length < 0.05 && abs(d.x) < 0.06, "\(id) \(s) at \(f.t)")
                }
                // Their heads stay off the floor and out of the legs.
                let mid = (V(handles[0].center) + V(handles[1].center)) * 0.5
                #expect(mid.z - 0.06 > 0.02, "\(id) \(f.t)")
                #expect(room(mid, f.body, half: 0.335, radius: 0.06) > -0.003, "\(id) \(f.t)")
            }
        }
    }

    @Test func onlyDeadliftsItKnowsAreStaged() throws {
        // Rack pull, Jefferson, deficit, kettlebell, one arm, band: left to the plain equipment.
        for id in ["0074", "5706", "5702", "3322", "0066", "4841", "4173", "1544"] {
            #expect(FreeWeightStagings.make(try guide(id), body) == nil, "\(id)")
        }
        for id in ["0966", "7237", "5577", "1543", "0116", "0432", "5119"] {
            #expect(FreeWeightStagings.make(try guide(id), body) != nil, "\(id)")
        }
    }

    // MARK: Bent-over row

    @Test func bentOverRowPullsTheBarToTheRibs() throws {
        // Overhand, wide and underhand.
        for id in ["0027", "3721", "0118"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightRowStaging)
            let frames = loop(plan)
            try planted(frames)
            let first = frames[0].body
            let from = V(try #require(frames[0].props.first).center), to = V(try #require(frames[40].props.first).center)
            for f in frames {
                let bar = try #require(f.props.first)
                for d in try fingers(f.body, on: bar) { #expect(d < 0.05, "\(id) fingers \(d) at \(f.t)") }
                // The bowed body holds still but for the little the keyframes shift it: it is
                // the arms and shoulder blades that move.
                for bone in ["pelvis", "thorax", "head", "shin.r", "shin.l"] {
                    let a = try at(first, bone), b = try at(f.body, bone)
                    #expect((a - b).length < 0.02, "\(id) \(bone) at \(f.t)")
                }
                // The bar keeps to one straight line, outside the legs and the trunk, off the floor.
                let c = V(bar.center)
                let along = (to - from).unit
                #expect(((c - from) - along * (c - from).dot(along)).length < 0.01, "\(id) off its line at \(f.t)")
                #expect(room(c, f.body) > -0.003, "\(id) in the body at \(f.t)")
                #expect(c.z - LegWeights.plateRadius > 0.05, "\(id) \(f.t)")
            }
            // It hangs under the shoulders and comes up to touch the trunk below the chest.
            let shoulder = try at(first, "humerus.r")
            #expect(abs(from.y - shoulder.y) < 0.03 && from.z < shoulder.z - 0.5, "\(id)")
            let squeeze = frames[40].body
            #expect(to.z > from.z + 0.25 && room(to, squeeze) < 0.02, "\(id)")
            let ribs = try at(squeeze, "thorax"), chest = try at(squeeze, "neck")
            #expect((to - ribs).length < 0.22 && (to - chest).length > 0.25, "\(id)")
            // The trunk is bowed well over, and the elbows end up above the back.
            let hip = try at(squeeze, "femur.r"), elbow = try at(squeeze, "ulna.r")
            #expect(shoulder.y < hip.y - 0.3)
            #expect(elbow.z > (try at(squeeze, "humerus.r")).z - 0.02, "\(id)")
        }
        // An underhand grip turns the palms up.
        let under = try staged("0118").frame(at: 0).body, over = try staged("0027").frame(at: 0).body
        let thumbUnder = try at(under, "f1a.r").x, littleUnder = try at(under, "f5a.r").x
        let thumbOver = try at(over, "f1a.r").x, littleOver = try at(over, "f5a.r").x
        #expect(thumbUnder < littleUnder && thumbOver > littleOver)
        // Rows on a bench, a machine or a cable, and other bars, are not this staging's.
        for id in ["3017", "0064", "4126", "1344", "0293", "0861"] {
            #expect(FreeWeightStagings.make(try guide(id), body) == nil, "\(id)")
        }
    }

    @Test func rowMistakesShow() throws {
        let g = try guide("0027")
        let plan = PropPlan(guide: g, body: body)
        let mistakes = g.steps.flatMap(\.mistakes)
        let (good, props) = plan.frame(at: g.faultT)
        let bar = V(try #require(props.first).center)
        let toes = try at(good, "toes.r"), head = try at(good, "head")
        // Pulling with the arms only leaves the bar short of the body.
        let short = try #require(mistakes.first { $0.id == "short" }?.pose)
        let (_, low) = plan.frame(at: g.faultT, fault: short)
        #expect(V(try #require(low.first).center).z < bar.z - 0.05)
        // Heaving stands the trunk up; a rounded back drops the head. The feet and hands stay.
        for (id, rise) in [("heave", 0.1), ("round", -0.02)] {
            let fault = try #require(mistakes.first { $0.id == id }?.pose)
            let (bad, held) = plan.frame(at: g.faultT, fault: fault)
            let moved = try at(bad, "head").z - head.z
            #expect(rise > 0 ? moved > rise : moved < rise, "\(id) \(moved)")
            #expect((try at(bad, "toes.r") - toes).length < 1e-6)
            for d in try fingers(bad, on: try #require(held.first)) { #expect(d < 0.05, "\(id)") }
        }
    }

    // MARK: Standing press

    @Test func standingPressTakesTheBarFromTheChestPastTheFace() throws {
        for id in ["1162", "1457", "1456"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightPressStaging)
            let frames = loop(plan)
            try planted(frames)
            var top = V(0, 0, 0)
            for f in frames {
                let bar = try #require(f.props.first)
                let c = V(bar.center)
                #expect(abs(c.x) < 1e-9 && abs((Body3D.M(bar.rotation) * V(0, 0, 1)).x) > 0.999999)
                for d in try fingers(f.body, on: bar) { #expect(d < 0.05, "\(id) fingers \(d) at \(f.t)") }
                // Never through the chest, the face or the head: below the top of the head it is in front of the face.
                #expect(room(c, f.body) > 0.012, "\(id) bar \(room(c, f.body)) from the body at \(f.t)")
                let head = try at(f.body, "head")
                if c.z < head.z + 0.17 { #expect(c.y < head.y - 0.1, "\(id) behind the face at \(f.t)") }
                if c.z > top.z { top = c }
            }
            // It starts under the chin, in front of the collarbones, with the elbows under it.
            let start = frames[0].body, low = V(try #require(frames[0].props.first).center)
            let neck = try at(start, "neck"), chin = try at(start, "head"), elbow = try at(start, "ulna.r")
            #expect(low.z < chin.z - 0.02 && low.z > neck.z - 0.12 && low.y < neck.y - 0.1 && low.y > neck.y - 0.22, "\(id)")
            #expect(elbow.z < low.z - 0.15, "\(id)")
            // It ends on long arms over the shoulders and the middle of the feet.
            let up = frames[36].body
            let shoulder = try at(up, "humerus.r"), ankle = try at(up, "foot.r")
            #expect(top.z > shoulder.z + 0.5 && abs(top.y - shoulder.y) < 0.03, "\(id)")
            #expect(abs(top.y - (ankle.y - 0.055)) < 0.07, "\(id) bar over \(top.y)")
            let upper = try at(up, "ulna.r") - shoulder, lower = try at(up, "hand.r") - at(up, "ulna.r")
            #expect(upper.unit.dot(lower.unit) > 0.96)
        }
        // Seated, behind the neck, kneeling and Bradford presses are not this staging's.
        for id in ["0788", "9694", "0105", "4866", "0426"] {
            #expect(FreeWeightStagings.make(try guide(id), body) == nil, "\(id)")
        }
    }

    @Test func pressMistakesShow() throws {
        let g = try guide("1162")
        let plan = PropPlan(guide: g, body: body)
        let mistakes = g.steps.flatMap(\.mistakes)
        let (good, props) = plan.frame(at: g.faultT)
        let bar = V(try #require(props.first).center)
        let toes = try at(good, "toes.r"), head = try at(good, "head")
        // A press that stops short leaves the bar in front of the head, still in the hands.
        let short = try #require(mistakes.first { $0.id == "short-lockout" }?.pose)
        let (stopped, held) = plan.frame(at: g.faultT, fault: short)
        let front = try #require(held.first)
        #expect(front.center[1] < bar.y - 0.12)
        for d in try fingers(stopped, on: front) { #expect(d < 0.05) }
        // Leaning back takes the head back behind the hips, which go forward to keep the
        // balance; the feet stay.
        let lean = try #require(mistakes.first { $0.id == "lean-back" }?.pose)
        let (leaned, _) = plan.frame(at: g.faultT, fault: lean)
        let over = head.y - (try at(good, "femur.r")).y, back = try at(leaned, "head").y - at(leaned, "femur.r").y
        #expect(back > over + 0.04)
        #expect((try at(leaned, "toes.r") - toes).length < 1e-6)
    }

    // MARK: Kettlebell swing

    @Test func kettlebellSwingsBackBetweenTheLegs() throws {
        for id in ["0549", "3680"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightSwingStaging)
            #expect(plan.kinds == [.kettlebell])
            // The arms sweep fast: a hand covers some 10 cm in a hundredth of the loop.
            let frames = loop(plan)
            try planted(frames, jump: 0.12)
            var lowest = Double.infinity, back = -Double.infinity
            for f in frames {
                // The handle is the first piece, the ball the second.
                let handle = try #require(f.props.first), ball = V(try #require(f.props.dropFirst().first).center)
                for d in try fingers(f.body, on: handle) { #expect(d < 0.05, "\(id) fingers \(d) at \(f.t)") }
                // The ball stays out of the legs and the trunk and off the floor.
                #expect(room(ball, f.body, half: 0.001, radius: FreeWeightSwingStaging.ball) > -0.012, "\(id) ball in the body at \(f.t)")
                #expect(ball.z > 0.25, "\(id) \(f.t)")
                // The lifter stays over the middle of the feet.
                let ankle = try at(f.body, "foot.r")
                #expect(abs(balance(f.body, bar: ball, share: FreeWeightSwingStaging.mass) - (ankle.y - 0.055)) < 0.03, "\(id) balance at \(f.t)")
                lowest = min(lowest, ball.z)
                back = max(back, ball.y - (try at(f.body, "shin.r")).y)
            }
            // At the bottom the ball is behind the knees, between the thighs; at the top it
            // is out in front at shoulder height.
            #expect(back > 0.1, "\(id) ball \(back) behind the knees")
            let hiked = frames[48]
            let ball = V(try #require(hiked.props.dropFirst().first).center)
            let knee = try at(hiked.body, "shin.r"), hip = try at(hiked.body, "femur.r")
            #expect(abs(ball.x) < 0.01 && ball.z > knee.z && ball.z < hip.z + 0.05, "\(id)")
            let top = V(try #require(frames[0].props.dropFirst().first).center), shoulder = try at(frames[0].body, "humerus.r")
            #expect(top.y < shoulder.y - 0.6 && abs(top.z - shoulder.z) < 0.08, "\(id)")
        }
        // One-arm, side, banded and overhead swings, and swings with other weights, are not this staging's.
        for id in ["1568", "10192", "4167", "3571", "3368", "7548", "0532"] {
            #expect(FreeWeightStagings.make(try guide(id), body) == nil, "\(id)")
        }
    }

    @Test func swingMistakesShow() throws {
        let g = try guide("0549")
        let plan = PropPlan(guide: g, body: body)
        let mistakes = g.steps.flatMap(\.mistakes)
        let (good, _) = plan.frame(at: g.faultT)
        // Squatting the swing sends the knees forward; the feet stay.
        let squat = try #require(mistakes.first { $0.id == "squat" }?.pose)
        let (sat, _) = plan.frame(at: g.faultT, fault: squat)
        #expect(try at(sat, "shin.r").y < at(good, "shin.r").y - 0.03)
        #expect((try at(sat, "toes.r") - at(good, "toes.r")).length < 1e-6)
        // Lifting with the arms raises the bell, still in the hands.
        let arms = try #require(mistakes.first { $0.id == "arms" }?.pose)
        let (lifted, high) = plan.frame(at: 0, fault: arms)
        let (_, level) = plan.frame(at: 0)
        #expect(try #require(high.dropFirst().first).center[2] > (try #require(level.dropFirst().first).center[2]) + 0.15)
        for d in try fingers(lifted, on: try #require(high.first)) { #expect(d < 0.05) }
    }

    // MARK: One arm, arms in turn, holds

    /// A hand's wrist as the rib cage carries it, so a trunk that sways does not count as the arm moving.
    private func wrist(_ frame: BodyFrame, _ s: String) throws -> V {
        let ribs = Body3D.M(try #require(frame.rotations["thorax"]))
        return ribs.t * (try at(frame, "hand.\(s)") - at(frame, "thorax"))
    }

    @Test func oneArmVersionsMoveOneArmAndHoldOneWeight() throws {
        // Standing and seated; the last one says it is the left arm's.
        for (id, side) in [("1670", "r"), ("0361", "r"), ("0355", "r"), ("0363", "r"), ("1669", "r"), ("6158", "r"), ("6159", "l")] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightArmsStaging, "\(id)")
            let idle = side == "r" ? "l" : "r"
            let frames = loop(plan, steps: 48)
            let first = frames[0].body
            var travelled = 0.0
            for f in frames {
                // The idle arm hangs at the side and stays there, with nothing near its hand.
                let hung = try wrist(f.body, idle), was = try wrist(first, idle)
                #expect((hung - was).length < 0.03, "\(id) idle arm moves at \(f.t)")
                let hand = try at(f.body, "hand.\(idle)"), shoulder = try at(f.body, "humerus.\(idle)")
                #expect(hand.z < shoulder.z - 0.45, "\(id) idle arm not hanging at \(f.t)")
                #expect(!f.props.isEmpty, "\(id) no weight at \(f.t)")
                let working = try at(f.body, "hand.\(side)")
                for piece in f.props {
                    #expect((V(piece.center) - hand).length > 0.2, "\(id) weight in the idle hand at \(f.t)")
                    #expect((V(piece.center) - working).length < 0.35, "\(id) weight away from the working hand at \(f.t)")
                }
                travelled = max(travelled, (try wrist(f.body, side) - wrist(first, side)).length)
            }
            #expect(travelled > 0.2, "\(id) working arm moves \(travelled)")
        }
        // Lying, bent over and padded versions, and the plain exercises, are left alone.
        for id in ["0362", "4343", "10043", "0354", "1663", "0294", "0334"] {
            #expect(FreeWeightStagings.make(try guide(id), body) == nil, "\(id)")
        }
    }

    @Test func alternatingVersionsTakeTurns() throws {
        for id in ["0285", "0414", "4852", "3761"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightArmsStaging, "\(id)")
            let frames = loop(plan)
            let first = frames[0].body
            var right = 0.0, left = 0.0
            for (i, f) in frames.enumerated() {
                // The right arm works in the first half of the loop and the left in the second;
                // the other waits where the rep starts.
                let r = (try wrist(f.body, "r") - wrist(first, "r")).length, l = (try wrist(f.body, "l") - wrist(first, "l")).length
                if f.t <= 0.5 { #expect(l < 0.03, "\(id) left moves at \(f.t)") } else { #expect(r < 0.03, "\(id) right moves at \(f.t)") }
                if f.t <= 0.5 { right = max(right, r) } else { left = max(left, l) }
                // Each hand keeps its weight.
                for s in ["r", "l"] {
                    let hand = try at(f.body, "hand.\(s)")
                    #expect(f.props.contains { (V($0.center) - hand).length < 0.15 }, "\(id) no weight in hand \(s) at \(f.t)")
                }
                guard i > 0 else { continue }
                for s in ["r", "l"] {
                    let step = (try at(f.body, "hand.\(s)") - at(frames[i - 1].body, "hand.\(s)")).length
                    #expect(step < 0.09, "\(id) hand \(s) jumps at \(f.t)")
                }
            }
            #expect(right > 0.2 && left > 0.2, "\(id) \(right) \(left)")
            #expect(abs(right - left) < 0.02, "\(id) the two arms do the same rep")
            // A mistake shows in the right arm at the moment the how-to shows it.
            let g = try guide(id)
            if let fault = g.steps.flatMap(\.mistakes).first?.pose {
                let (bad, _) = plan.frame(at: g.faultT, fault: fault)
                #expect((try wrist(bad, "r") - wrist(first, "r")).length > 0.15, "\(id)")
                // The waiting arm stays down; a mistake that shrugs lifts both shoulders a little.
                #expect((try wrist(bad, "l") - wrist(first, "l")).length < 0.08, "\(id)")
            }
        }
    }

    @Test func holdsStayAtTheWorkingPosition() throws {
        for id in ["7588", "10138"] {
            let plan = try staged(id)
            #expect(plan.staging is FreeWeightArmsStaging, "\(id)")
            let frames = loop(plan, steps: 24)
            let first = frames[0].body
            for f in frames {
                for s in ["r", "l"] {
                    #expect((try at(f.body, "hand.\(s)") - at(first, "hand.\(s)")).length < 0.03, "\(id) hand \(s) moves at \(f.t)")
                }
            }
            let hand = try at(first, "hand.r"), elbow = try at(first, "ulna.r"), shoulder = try at(first, "humerus.r")
            if id == "7588" {
                // The plate is held out in front at shoulder height.
                #expect(hand.y < shoulder.y - 0.4 && abs(hand.z - shoulder.z) < 0.15)
            } else {
                // The forearms are level, the elbows by the ribs.
                #expect(abs(hand.z - elbow.z) < 0.08 && elbow.z < shoulder.z - 0.2)
            }
        }
    }

    // MARK: EZ bar

    @Test func ezBarIsBentAndTheHandsHoldItsSlopes() throws {
        // Underhand, overhand, overhead and an upright row.
        for id in ["0447", "0451", "1226", "1749", "7114"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? FreeWeightEZStaging, "\(id)")
            #expect(plan.kinds.contains(.ezBar))
            let g = try guide(id)
            for i in 0...24 {
                let t = Double(i) / 24
                let (frame, found) = staging.solve(Figure.smooth(g.keyframes, at: t), at: t)
                let bar = try #require(found, "\(id) at \(t)")
                // The bar is level, and its bends are real: a slope a hand holds leans some 20 degrees off the bar's line.
                #expect(abs(bar.axis.z) < 0.02, "\(id) at \(t)")
                for (s, side) in [("r", -1.0), ("l", 1.0)] {
                    let x = try #require(bar.at[s])
                    let slope = (bar.point(x + side * 0.01) - bar.point(x - side * 0.01)).unit
                    let lean = acos(min(1, abs(slope.dot(bar.axis)))) * 180 / .pi
                    #expect(lean > 15 && lean < 30, "\(id) slope \(lean)")
                    // The knuckles are round the slope itself, not round the straight line.
                    for bone in ["f3a", "f3c"] {
                        let d = try at(frame, "\(bone).\(s)") - bar.point(x)
                        #expect((d - slope * d.dot(slope)).length < 0.05, "\(id) \(bone).\(s) at \(t)")
                    }
                }
                // The plates are outside the body and off the floor.
                for side in [-1.0, 1.0] {
                    let plate = bar.point(side * FreeWeightEZStaging.plates)
                    #expect(plate.z > FreeWeightEZStaging.plateRadius, "\(id) at \(t)")
                    #expect(room(plate, frame, half: 0.035, radius: FreeWeightEZStaging.plateRadius) > 0, "\(id) plate in the body at \(t)")
                }
            }
        }
        // Seated, lying and preacher versions, and a straight bar, are not this staging's.
        for id in ["1458", "5873", "6406", "0031"] {
            #expect(FreeWeightStagings.make(try guide(id), body) as? FreeWeightEZStaging == nil, "\(id)")
        }
    }
}

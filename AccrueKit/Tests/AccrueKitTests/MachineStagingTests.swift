import Foundation
import Testing
@testable import AccrueKit

struct MachineStagingTests {
    typealias Sample = (t: Double, body: BodyFrame, props: [PropPiece])

    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    private func guide(_ id: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.id == id }, "\(id)")
        return try #require(catalog.howTo(for: ex))
    }

    private func staged(_ id: String) throws -> PropPlan {
        let plan = PropPlan(guide: try guide(id), body: body)
        #expect(plan.staging != nil, "\(id)")
        #expect(plan.kinds == [.machine], "\(id)")
        return plan
    }

    private func at(_ frame: BodyFrame, _ bone: String) throws -> [Double] {
        try #require(frame.heads[bone], "\(bone)")
    }

    private func far(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0.0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
    }

    private func list(_ v: Body3D.V) -> [Double] { [v.x, v.y, v.z] }

    private func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 } }

    /// The loop sampled finely, with the pieces that move.
    private func loop(_ plan: PropPlan, steps: Int = 48) -> [Sample] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let (f, props) = plan.frame(at: t)
            return (t, f, Array(props.dropFirst(plan.fixed.count)))
        }
    }

    /// The named joints stay within `slack` of where they start, and nothing jumps from one
    /// moment to the next.
    private func stays(_ frames: [Sample], _ bones: [String], slack: Double = 1e-6, jump: Double = 0.09) throws {
        let first = try #require(frames.first).body
        for (i, f) in frames.enumerated() {
            for bone in bones {
                let a = try at(first, bone), b = try at(f.body, bone)
                #expect(far(a, b) < slack, "\(bone) at \(f.t)")
            }
            guard i > 0 else { continue }
            for bone in ["pelvis", "neck", "hand.r", "hand.l", "foot.r", "foot.l", "shin.r", "shin.l"] {
                let a = try at(frames[i - 1].body, bone), b = try at(f.body, bone)
                #expect(far(a, b) < jump, "\(bone) jumps at \(f.t)")
            }
        }
    }

    /// How far a joint travels through the loop along axis `k`.
    private func sweep(_ frames: [Sample], _ bone: String, _ k: Int) throws -> Double {
        let values = try frames.map { try at($0.body, bone)[k] }
        return (values.max() ?? 0) - (values.min() ?? 0)
    }

    /// The moving grips: the short dark rods the hands close on.
    private func gripRods(_ props: [PropPiece]) -> [PropPiece] {
        props.filter { $0.shape == .cylinder && $0.finish == .dark && $0.size[2] < 0.2 && $0.size[0] < 0.04 }
    }

    /// Each hand's middle knuckle is on one of the points: a closed hand's knuckle is a
    /// finger's thickness off the middle of what it holds.
    private func holds(_ f: Sample, _ points: [[Double]], within reach: Double = 0.07) throws {
        #expect(!points.isEmpty, "no grips at \(f.t)")
        for s in ["r", "l"] {
            let k = try at(f.body, "f3a.\(s)")
            let d = points.map { far(k, $0) }.min() ?? 9
            #expect(d < reach, "hand.\(s) is \(d) from its grip at \(f.t)")
        }
    }

    /// The stack's top plates rise and fall through the loop.
    private func stackMoves(_ frames: [Sample]) throws {
        let count = try #require(frames.first).props.count
        let rise = (0..<count).map { i -> Double in
            let z = frames.map { $0.props[i].center[2] }
            return frames[0].props[i].finish == .plate || frames[0].props[i].finish == .dark ? (z.max() ?? 0) - (z.min() ?? 0) : 0
        }
        #expect((rise.max() ?? 0) > 0.08)
    }

    // MARK: Leg press

    @Test func legPressPushesThePlateWithBothFeetOnIt() throws {
        for id in ["0739", "2267"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineLegPressStaging)
            let frames = loop(plan)
            // Hips in the seat: only the lower back moves them, and not far.
            try stays(frames, ["pelvis"], slack: 0.04)
            let push = list(staging.push)
            let handles = try ["r", "l"].map { list(try #require(staging.handles[$0])) }
            let first = try #require(frames.first)
            var travel: [Double] = []
            for f in frames {
                let plate = try #require(f.props.first)
                #expect(plate.shape == .box && plate.size[0] > 0.6)
                travel.append(dot(plate.center, push))
                // The balls of the feet ride the plate: they keep their place on it.
                for s in ["r", "l"] {
                    let ball = try at(f.body, "toes.\(s)"), ball0 = try at(first.body, "toes.\(s)")
                    let plate0 = try #require(first.props.first)
                    let now = zip(ball, plate.center).map { $0 - $1 }, then = zip(ball0, plate0.center).map { $0 - $1 }
                    #expect(far(now, then) < 0.003, "\(id) toes.\(s) at \(f.t)")
                    // And the knee is in front of the hip, not through the plate.
                    let knee = try at(f.body, "shin.\(s)")
                    #expect(dot(knee, push) < dot(plate.center, push) - 0.05)
                }
                try holds(f, handles)
            }
            #expect((travel.max() ?? 0) - (travel.min() ?? 0) > 0.15, "\(id)")
        }
        // A sled runs uphill, a seated press level.
        let sled = try #require(try staged("0739").staging as? MachineLegPressStaging)
        let level = try #require(try staged("2267").staging as? MachineLegPressStaging)
        #expect(sled.push.z > 0.6)
        #expect(abs(level.push.z) < 1e-9)
    }

    @Test func calfPressKeepsTheLegsLong() throws {
        for id in ["0738", "2335"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineLegPressStaging)
            #expect(staging.setup.calves)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.04)
            let push = list(staging.push)
            let first = try #require(frames.first)
            var heel: [Double] = []
            for f in frames {
                let plate = try #require(f.props.first)
                for s in ["r", "l"] {
                    let ball = try at(f.body, "toes.\(s)"), ball0 = try at(first.body, "toes.\(s)")
                    let plate0 = try #require(first.props.first)
                    let now = zip(ball, plate.center).map { $0 - $1 }, then = zip(ball0, plate0.center).map { $0 - $1 }
                    #expect(far(now, then) < 0.003, "\(id) toes.\(s) at \(f.t)")
                    // Knees all but straight: the hip to the ankle is nearly the whole leg.
                    let hip = try at(f.body, "femur.\(s)"), knee = try at(f.body, "shin.\(s)"), ankle = try at(f.body, "foot.\(s)")
                    #expect(far(hip, ankle) > (far(hip, knee) + far(knee, ankle)) * 0.97, "\(id) knee at \(f.t)")
                }
                let ankle = try at(f.body, "foot.r")
                heel.append(dot(plate.center, push) - dot(ankle, push))
            }
            // The ankles do the work: the heels come toward the plate and away from it.
            #expect((heel.max() ?? 0) - (heel.min() ?? 0) > 0.015, "\(id)")
        }
    }

    @Test func hackSquatRidesTheCarriageOverFeetThatStay() throws {
        for id in ["0743", "5516", "4100"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineHackSquatStaging)
            let frames = loop(plan)
            // Both feet flat on the plate, which is fixed at the foot of the rails.
            try stays(frames, ["toes.r", "toes.l"], slack: 0.003, jump: 0.12)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.02, jump: 0.12)
            let up = list(staging.press.rest.up)
            let first = try #require(frames.first)
            var ride: [Double] = []
            for f in frames {
                // The back pad rides with the hips, along the rails and nowhere else.
                let pad = try #require(f.props.first), pad0 = try #require(first.props.first)
                #expect(pad.finish == .pad)
                let pelvis = try at(f.body, "pelvis"), pelvis0 = try at(first.body, "pelvis")
                let moved = zip(pad.center, pad0.center).map { $0 - $1 }
                let along = dot(moved, up)
                #expect(far(moved, up.map { $0 * along }) < 1e-6, "\(id) pad off its rails at \(f.t)")
                #expect(abs(dot(zip(pelvis, pelvis0).map { $0 - $1 }, up) - along) < 0.04, "\(id) hips leave the pad at \(f.t)")
                ride.append(along)
                try holds(f, gripRods(f.props).map(\.center))
                #expect(f.body.heads.values.allSatisfy { $0[2] > -0.01 }, "\(id) under the floor at \(f.t)")
            }
            #expect((ride.max() ?? 0) - (ride.min() ?? 0) > 0.25, "\(id)")
        }
    }

    // MARK: Leg extension and leg curl

    @Test func seatedLegMachinesTurnTheShinsAboutTheKnees() throws {
        for (id, curl) in [("0585", false), ("0599", true)] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineSeatedLegStaging)
            #expect(staging.curl == curl)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            let handles = try ["r", "l"].map { list(try #require(staging.handles[$0])) }
            var gap: [Double] = []
            for f in frames {
                // The knees are on the lever's axle.
                for s in ["r", "l"] {
                    let knee = try at(f.body, "shin.\(s)")
                    #expect(abs(knee[1] - staging.pivot.y) < 0.02 && abs(knee[2] - staging.pivot.z) < 0.02, "\(id) knee at \(f.t)")
                }
                try holds(f, handles)
                // The roller lies on the shins a hand above the ankles, and stays there.
                let roller = try #require(f.props.first { $0.finish == .pad || $0.finish == .rubber || $0.finish == .dark })
                let ankle = try at(f.body, "foot.r")
                gap.append(far([ankle[1], ankle[2]], [roller.center[1], roller.center[2]]))
            }
            #expect((gap.max() ?? 1) < 0.16, "\(id)")
            #expect((gap.max() ?? 1) - (gap.min() ?? 0) < 0.005, "\(id)")
            let moved0 = try sweep(frames, "foot.r", 2)
            #expect(moved0 > 0.2, "\(id)")
        }
    }

    @Test func oneLegExtensionLeavesTheOtherLegHanging() throws {
        let plan = try staged("1571")
        let frames = loop(plan)
        let moved1 = try sweep(frames, "foot.r", 2)
        #expect(moved1 > 0.2)
        try stays(frames, ["foot.l"], slack: 0.02)
    }

    @Test func lyingLegCurlLiesFaceDownAndBringsTheHeelsUp() throws {
        let plan = try staged("0586")
        let staging = try #require(plan.staging as? MachineLyingLegCurlStaging)
        let frames = loop(plan)
        try stays(frames, ["pelvis"], slack: 0.02)
        let handles = try ["r", "l"].map { list(try #require(staging.handles[$0])) }
        for f in frames {
            // Face down along the bench: the head is well in front of the hips, near their height.
            let pelvis = try at(f.body, "pelvis"), neck = try at(f.body, "neck")
            #expect(neck[1] < pelvis[1] - 0.35 && abs(neck[2] - pelvis[2]) < 0.15)
            for s in ["r", "l"] {
                let knee = try at(f.body, "shin.\(s)")
                #expect(abs(knee[1] - staging.pivot.y) < 0.02 && abs(knee[2] - staging.pivot.z) < 0.02, "knee at \(f.t)")
            }
            try holds(f, handles)
        }
        let moved2 = try sweep(frames, "foot.r", 2)
        #expect(moved2 > 0.2)
    }

    @Test func oneLegCurlKeepsTheOtherLegLong() throws {
        let plan = try staged("1586")
        let frames = loop(plan)
        let worked = try sweep(frames, "foot.r", 2)
        #expect(worked > 0.2)
        try stays(frames, ["foot.l"], slack: 0.02)
    }

    @Test func gluteHamBenchHingesTheTrunkOverThePad() throws {
        for id in ["4762", "4764"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineGluteHamStaging)
            let frames = loop(plan)
            // Ankles between the rollers, knees long: the legs do not move.
            try stays(frames, ["foot.r", "foot.l", "shin.r", "shin.l"], slack: 0.02, jump: 0.2)
            let pad = try #require(plan.fixed.first)
            #expect(pad.finish == .pad)
            for f in frames {
                // The hip joints are the hinge, level with the ankles and clear of the pad.
                let hipR = try at(f.body, "femur.r"), hipL = try at(f.body, "femur.l")
                let hinge = zip(hipR, hipL).map { ($0 + $1) / 2 }
                #expect(far(hinge, list(staging.hip)) < 1e-6, "\(id) at \(f.t)")
                // The thighs lie on top of the pad, and the trunk never goes into it or the floor.
                let knee = try at(f.body, "shin.r")
                #expect(knee[2] > pad.center[2] + pad.size[0] / 2 + 0.05)
                for bone in ["neck", "head", "thorax", "hand.r", "hand.l"] {
                    let p = try at(f.body, bone)
                    #expect(p[2] > 0.08, "\(id) \(bone) on the floor at \(f.t)")
                    #expect(p[1] < pad.center[1] - pad.size[0] / 2 + 0.02, "\(id) \(bone) in the pad at \(f.t)")
                }
            }
            let fold = try sweep(frames, "neck", 2)
            #expect(fold > 0.3, "\(id)")
        }
    }

    // MARK: Calf raises

    @Test func seatedCalfRaiseLiftsThePadOnTheKnees() throws {
        let plan = try staged("0594")
        #expect(plan.staging is MachineSeatedCalfStaging)
        let frames = loop(plan)
        // Hips on the seat, the balls of the feet on the bar.
        try stays(frames, ["pelvis"])
        try stays(frames, ["toes.r", "toes.l"], slack: 0.002)
        var above: [Double] = []
        for f in frames {
            let pad = try #require(f.props.first)
            #expect(pad.finish == .pad)
            let knee = try at(f.body, "shin.r")
            above.append(pad.center[2] - knee[2])
            // Hands on the pad's own grips, outside the thighs.
            try holds(f, gripRods(f.props).map(\.center))
        }
        // The pad stays on the thighs as the knees rise.
        #expect((above.min() ?? 0) > 0.05 && (above.max() ?? 1) < 0.2)
        #expect((above.max() ?? 1) - (above.min() ?? 0) < 0.03)
        let moved3 = try sweep(frames, "foot.r", 2)
        #expect(moved3 > 0.02)
        let moved4 = try sweep(frames, "shin.r", 2)
        #expect(moved4 > 0.015)
    }

    @Test func standingCalfRaiseCarriesThePadsOnTheShoulders() throws {
        let plan = try staged("0605")
        #expect(plan.staging is MachineStandingCalfStaging)
        let frames = loop(plan)
        try stays(frames, ["toes.r", "toes.l"], slack: 0.002)
        var rise: [Double] = []
        for f in frames {
            let pads = f.props.filter { $0.finish == .pad }
            #expect(pads.count == 2)
            for (pad, s) in zip(pads, ["r", "l"]) {
                // Each pad's underside is just above its shoulder joint, on the muscle over it.
                let shoulder = try at(f.body, "humerus.\(s)")
                let under = pad.center[2] - pad.size[2] / 2
                #expect(under > shoulder[2] && under < shoulder[2] + 0.09, "pad \(under - shoulder[2]) over shoulder.\(s) at \(f.t)")
                #expect(abs(pad.center[0] - shoulder[0]) < 0.08)
            }
            rise.append(try #require(pads.first).center[2])
            try holds(f, gripRods(f.props).map(\.center))
        }
        #expect((rise.max() ?? 0) - (rise.min() ?? 0) > 0.03)
    }

    // MARK: Presses and flies

    @Test func machinePressesSwingTheHandlesWithTheHands() throws {
        // Chest press, incline, decline, palms-in, shoulder press, palms-in shoulder press.
        // Then the same machine pulled: seated rows (level, high, low, palms down) and pulldowns.
        for id in ["0576", "1299", "1300", "1029", "0603", "1350", "0581", "4214", "5447", "0579", "2736"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachinePressStaging)
            let frames = loop(plan)
            // Hips on the seat, feet on the floor.
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            let ankle = try at(frames[0].body, "foot.r")
            #expect(abs(ankle[2] - body.ankleHeight) < 0.002)
            for f in frames {
                try holds(f, gripRods(f.props).map(\.center))
                // The handles are on their arc about the axle.
                let hand = try at(f.body, "hand.r")
                let fromAxle = far([hand[1], hand[2]], [staging.pivot.y, staging.pivot.z])
                #expect(abs(fromAxle - staging.radius) < 0.08, "\(id) hand \(fromAxle) from the axle at \(f.t)")
            }
            let overhead = staging.setup.pitch > 45
            let moved5 = try sweep(frames, "hand.r", overhead ? 2 : 1)
            #expect(moved5 > 0.2, "\(id)")
            try stackMoves(frames)
        }
    }

    @Test func flyMachinesSwingTheArmsAboutTheShoulders() throws {
        for (id, reverse) in [("0596", false), ("0602", true), ("0601", true)] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineFlyStaging)
            #expect(staging.reverse == reverse)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            for f in frames {
                try holds(f, gripRods(f.props).map(\.center))
                // Hands at shoulder height, never crossing the middle.
                let hand = try at(f.body, "hand.r"), other = try at(f.body, "hand.l"), shoulder = try at(f.body, "humerus.r")
                #expect(abs(hand[2] - shoulder[2]) < 0.15, "\(id) at \(f.t)")
                #expect(hand[0] < 0 && other[0] > 0, "\(id) at \(f.t)")
            }
            let moved6 = try sweep(frames, "hand.r", 0)
            #expect(moved6 > 0.25, "\(id)")
            try stackMoves(frames)
        }
    }

    // MARK: All of them

    @Test func mistakesStillMakeAWholeBody() throws {
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), MachineStagings.make(g, body) != nil else { continue }
            let plan = PropPlan(guide: g, body: body)
            for mistake in g.steps.flatMap(\.mistakes) {
                guard let pose = mistake.pose else { continue }
                let frame = plan.frame(at: g.faultT, fault: pose).body
                for (bone, p) in frame.heads {
                    #expect(p.allSatisfy { $0.isFinite && abs($0) < 4 }, "\(ex.name) \(mistake.id) \(bone)")
                }
                #expect((frame.heads.values.map { $0[2] }.min() ?? 0) > -0.02, "\(ex.name) \(mistake.id) goes under the floor")
            }
        }
    }

    @Test func stagesOnlyWhatItKnows() throws {
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), g.equipment != "smith-machine", MachineStagings.make(g, body) != nil else { continue }
            #expect(g.equipment == "machine", "\(ex.name)")
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts["leg-press", default: 0] >= 14)
        #expect(counts["leg-extension", default: 0] >= 7)
        #expect(counts["leg-curl", default: 0] >= 5)
        #expect(counts["calf-raise", default: 0] >= 8)
        #expect(counts["bench-press", default: 0] >= 12)
        #expect(counts["overhead-press", default: 0] >= 6)
        #expect(counts["chest-fly", default: 0] >= 2)
        #expect(counts["rear-delt-fly", default: 0] >= 2)
        #expect(counts["row", default: 0] >= 12)
        #expect(counts["lat-pulldown", default: 0] >= 5)
        #expect(Set(counts.keys).isSubset(of: ["leg-press", "leg-extension", "leg-curl", "calf-raise", "bench-press",
                                               "overhead-press", "chest-fly", "rear-delt-fly", "row", "lat-pulldown", "squat", "back-extension"]))
        // Machines it has not built, and one-sided versions, keep the plain equipment.
        for name in ["sled reverse hack squat", "sled one leg hack squat", "lever pendulum squat (plate loaded)", "lever belt squat", "sled angled single leg press", "lever kneeling leg curl",
                     "lever standing leg curl", "lever donkey calf raise", "lever seated one leg calf raise",
                     "sled one leg calf press on leg press", "lever seated hip abduction", "lever seated hip adduction",
                     "lever one arm shoulder press", "lever lying chest press (plate loaded)",
                     "lever reverse shoulder press (plate loaded)", "lever t bar row", "lever lateral raise",
                     "lever one arm seated row (seated row machine)", "lever alternating narrow grip seated row",
                     "lever one arm lateral wide pulldown", "lever cable rear pulldown"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(MachineStagings.make(g, body) == nil, "\(name)")
        }
    }

    // MARK: Smith machine

    @Test func smithBarStaysOnItsRails() throws {
        // Squat, front squat, box squat, calf raise, deadlifts, step-up, standing press,
        // bench presses, rows.
        for id in ["0770", "1595", "0750", "0773", "0752", "1597", "11879", "0774", "0748", "0757", "0753",
                   "1359", "11762"] {
            let g = try guide(id)
            let staging = try #require(MachineSmithStaging(g, body), "\(id)")
            #expect(PropPlan(guide: g, body: body).staging is MachineSmithStaging, "\(id)")
            #expect(staging.kinds == [.smith])
            // Two rails, one each side, outside the hands.
            let rails = staging.fixed.filter { $0.shape == .cylinder && $0.size[2] > 2 }
            #expect(rails.count == 2 && rails.allSatisfy { abs($0.center[1] - staging.railY) < 1e-9 }, "\(id)")
            var heights: [Double] = []
            var last: BodyFrame?
            for k in 0...48 {
                let pose = Figure.smooth(g.keyframes, at: Double(k) / 48)
                let made = staging.frame(pose), free = staging.inner.frame(pose).body
                let bar = try #require(MachineSmithStaging.bar(made.props), "\(id)")
                // The bar is on the rails' line, level and in the middle.
                if abs(bar.center[1] - staging.railY) > 1e-9 || abs(bar.center[0]) > 1e-3 {
                    Issue.record("\(id) bar off its rails at \(k): \(bar.center)")
                }
                heights.append(bar.center[2])
                // The sleeves ride with it.
                let sleeves = made.props.suffix(2)
                #expect(sleeves.allSatisfy { abs($0.center[2] - bar.center[2]) < 1e-9 && abs(abs($0.center[0]) - staging.railX) < 1e-9 })
                // Both hands closed on it.
                for s in ["r", "l"] {
                    let knuckle = try at(made.body, "f3a.\(s)")
                    let d = far([knuckle[1], knuckle[2]], [bar.center[1], bar.center[2]])
                    #expect(d < 0.06, "\(id) hand.\(s) \(d) from the bar at \(k)")
                    #expect(abs(knuckle[0]) < staging.railX - 0.03, "\(id) hand.\(s) outside the rails")
                }
                switch staging.follow {
                case .feet:
                    // The feet stand where the free-bar lift put them.
                    for bone in ["foot.r", "foot.l", "toes.r", "toes.l"] {
                        let a = try at(made.body, bone), b = try at(free, bone)
                        #expect(far(a, b) < 0.012, "\(id) \(bone) moved \(far(a, b)) at \(k)")
                    }
                case .arms:
                    // The body rests where it did.
                    for bone in ["pelvis", "neck", "foot.r"] {
                        let a = try at(made.body, bone), b = try at(free, bone)
                        #expect(far(a, b) < 1e-9, "\(id) \(bone) at \(k)")
                    }
                }
                if let last {
                    for bone in ["pelvis", "neck", "hand.r", "hand.l", "shin.r", "shin.l"] {
                        let a = try at(last, bone), b = try at(made.body, bone)
                        #expect(far(a, b) < 0.12, "\(id) \(bone) jumps at \(k)")
                    }
                }
                last = made.body
            }
            #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.06, "\(id)")
        }
    }

    @Test func smithLeavesWhatRailsWouldNotAllow() throws {
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), g.equipment == "smith-machine", MachineSmithStaging(g, body) != nil else { continue }
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts == ["bench-press": 13, "squat": 9, "row": 6, "overhead-press": 3, "calf-raise": 3, "deadlift": 3,
                           "step-up": 1])
        for name in ["smith hip thrust", "smith seated shoulder press", "smith one arm row", "smith behind neck press", "smith zercher squat", "smith shrug",
                     "resistance band smith squat", "smith seated single arm neutral grip shoulders press"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(MachineSmithStaging(g, body) == nil, "\(name)")
        }
    }
}

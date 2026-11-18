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
        for id in ["0743", "5516", "4100", "4951", "0744"] {
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
            #expect((ride.max() ?? 0) - (ride.min() ?? 0) > 0.2, "\(id)")
        }
    }

    @Test func oneLegPressesRestTheOtherLeg() throws {
        // A sled, a seated press, a seated squat machine, a calf press and a hack squat.
        for id in ["1425", "2611", "1573", "7177", "1579"] {
            let plan = try staged(id)
            let frames = loop(plan)
            let press: MachineLegPressStaging
            if let hack = plan.staging as? MachineHackSquatStaging { press = hack.press } else {
                press = try #require(plan.staging as? MachineLegPressStaging, "\(id)")
            }
            #expect(press.setup.single, "\(id)")
            let push = list(press.push)
            var apart: [Double] = []
            for f in frames {
                // The resting foot is off the plate: nearer the hips along the rails than the working one.
                let r = try at(f.body, "toes.r"), l = try at(f.body, "toes.l")
                apart.append(dot(r, push) - dot(l, push))
                #expect(f.body.heads.values.allSatisfy { $0[2] > -0.01 }, "\(id) under the floor at \(f.t)")
            }
            #expect((apart.max() ?? 0) > 0.2, "\(id)")
            let worked = (apart.max() ?? 0) - (apart.min() ?? 0)
            #expect(worked > (press.setup.calves ? 0.01 : 0.08), "\(id)")
        }
        // Sitting on a seat that stands on the floor, the resting foot is flat on the floor.
        let frames = loop(try staged("2611"))
        try stays(frames, ["foot.l", "toes.l"], slack: 0.003)
        let ankle = try at(frames[0].body, "foot.l")
        #expect(abs(ankle[2] - body.ankleHeight) < 0.003)
    }

    @Test func alternatePressWorksTheLegsInTurn() throws {
        for id in ["2287", "10198"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineLegPressStaging)
            #expect(staging.setup.alternate)
            let frames = loop(plan)
            let push = list(staging.push)
            let first = try #require(frames.first)
            var right: [Double] = [], left: [Double] = []
            for f in frames {
                let plates = f.props.filter { $0.shape == .box && $0.finish == .dark }
                #expect(plates.count == 2)
                let own = try #require(plates.first), other = try #require(plates.last)
                #expect(own.center[0] < 0 && other.center[0] > 0)
                right.append(dot(own.center, push))
                left.append(dot(other.center, push))
                // Each foot rides its own plate.
                for (s, plate, plate0) in [("r", own, first.props.filter { $0.shape == .box && $0.finish == .dark }[0]),
                                           ("l", other, first.props.filter { $0.shape == .box && $0.finish == .dark }[1])] {
                    let ball = try at(f.body, "toes.\(s)"), ball0 = try at(first.body, "toes.\(s)")
                    let now = zip(ball, plate.center).map { $0 - $1 }, then = zip(ball0, plate0.center).map { $0 - $1 }
                    #expect(far(now, then) < 0.004, "\(id) toes.\(s) at \(f.t)")
                }
            }
            // As one plate comes in the other goes out by as much.
            let sums = zip(right, left).map { $0 + $1 }
            #expect((sums.max() ?? 0) - (sums.min() ?? 0) < 1e-6, "\(id)")
            #expect((right.max() ?? 0) - (right.min() ?? 0) > 0.15 && (left.max() ?? 0) - (left.min() ?? 0) > 0.15, "\(id)")
        }
    }

    @Test func verticalAndSeatedSquatPressesPointTheirRails() throws {
        let up = try #require(try staged("4327").staging as? MachineLegPressStaging)
        #expect(up.push.z > 0.999 && up.rest.lean == 90)
        for id in ["4327", "1232", "1574"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineLegPressStaging)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.04)
            let push = list(staging.push)
            var travel: [Double] = []
            for f in frames {
                let plate = try #require(f.props.first)
                travel.append(dot(plate.center, push))
                for s in ["r", "l"] {
                    let ball = try at(f.body, "toes.\(s)"), ball0 = try at(frames[0].body, "toes.\(s)")
                    let plate0 = try #require(frames[0].props.first)
                    let now = zip(ball, plate.center).map { $0 - $1 }, then = zip(ball0, plate0.center).map { $0 - $1 }
                    #expect(far(now, then) < 0.003, "\(id) toes.\(s) at \(f.t)")
                }
                #expect(f.body.heads.values.allSatisfy { $0[2] > -0.01 }, "\(id) under the floor at \(f.t)")
            }
            #expect((travel.max() ?? 0) - (travel.min() ?? 0) > 0.15, "\(id)")
        }
        // The seated squat's plate is below the hips and in front of them.
        let squat = try #require(try staged("1232").staging as? MachineLegPressStaging)
        #expect(squat.push.z < -0.2 && squat.push.y < -0.8)
    }

    @Test func leverSquatCarriesThePadsOnTheShoulders() throws {
        for id in ["1039", "1875"] {
            let plan = try staged(id)
            #expect(plan.staging is MachineLeverSquatStaging)
            let frames = loop(plan)
            try stays(frames, ["toes.r", "toes.l"], slack: 0.003, jump: 0.12)
            var rise: [Double] = []
            for f in frames {
                let pads = f.props.filter { $0.finish == .pad }
                #expect(pads.count == 2)
                for (pad, s) in zip(pads, ["r", "l"]) {
                    let shoulder = try at(f.body, "humerus.\(s)")
                    let under = pad.center[2] - pad.size[2] / 2
                    #expect(under > shoulder[2] - 0.02 && under < shoulder[2] + 0.1, "\(id) pad \(under - shoulder[2]) over shoulder.\(s) at \(f.t)")
                }
                rise.append(try #require(pads.first).center[2])
                try holds(f, gripRods(f.props).map(\.center))
            }
            #expect((rise.max() ?? 0) - (rise.min() ?? 0) > 0.3, "\(id)")
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
      for id in ["0605", "1220"] {
        let plan = try staged(id)
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

    @Test func oneArmOnThePressMachineLeavesTheOtherHandleAtRest() throws {
        // A row, a chest press and a pulldown done with one arm.
        for id in ["1235", "2974", "1347"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachinePressStaging)
            #expect(staging.setup.single, "\(id)")
            let frames = loop(plan)
            try stays(frames, ["hand.l"], slack: 0.05, jump: 0.12)
            for f in frames { try holds(f, gripRods(f.props).map(\.center)) }
            let moved = try sweep(frames, "hand.r", staging.setup.pitch > 45 ? 2 : 1)
            #expect(moved > 0.2, "\(id)")
        }
    }

    @Test func forkLeverTakesTheFreeBarsPlace() throws {
        // A T-bar row, a chest-supported lever row, a lever deadlift and a lever hip thrust.
        for id in ["0606", "10646", "0578", "2146"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineForkLeverStaging)
            let frames = loop(plan)
            var heights: [Double] = []
            for f in frames {
                let props = Array(plan.frame(at: f.t).1.dropFirst(plan.fixed.count))
                // No free bar is left; the hands are on the fork's crossbar.
                #expect(MachineSmithStaging.bar(props) == nil, "\(id)")
                let cross = try #require(props.first { $0.shape == .cylinder && $0.finish == .dark && $0.size[2] > 0.5 }, "\(id)")
                heights.append(cross.center[2])
                for s in ["r", "l"] {
                    let k = try at(f.body, "f3a.\(s)")
                    let d = far([k[1], k[2]], [cross.center[1], cross.center[2]])
                    #expect(d < 0.06 && abs(k[0]) < cross.size[2] / 2, "\(id) hand.\(s) \(d) from the crossbar at \(f.t)")
                }
                // Both arms run from the crossbar's ends to the axle.
                let arms = props.filter { $0.shape == .cylinder && $0.finish == .metal && $0.size[2] > 0.6 }
                #expect(arms.count == 2 && arms.allSatisfy { abs(abs($0.center[0]) - staging.half) < 1e-6 }, "\(id)")
                #expect(props.allSatisfy { $0.center[2] - ($0.shape == .cylinder && $0.finish == .plate ? $0.size[0] / 2 : 0) > -0.001 })
            }
            #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.1, "\(id)")
        }
    }

    @Test func dipMachinePushesTheHandlesDownBesideTheHips() throws {
        for id in ["1451", "0591", "1871"] {
            let plan = try staged(id)
            #expect(plan.staging is MachinePressStaging, "\(id)")
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            for f in frames {
                try holds(f, gripRods(f.props).map(\.center))
                // The hands work below the shoulders, outside the hips.
                let hand = try at(f.body, "hand.r"), shoulder = try at(f.body, "humerus.r")
                #expect(hand[2] < shoulder[2] && hand[0] < -0.15, "\(id) at \(f.t)")
            }
            let moved = try sweep(frames, "hand.r", 2)
            #expect(moved > 0.12, "\(id) \(moved)")
        }
    }

    @Test func armLeverTurnsTheForearmsAboutElbowsOnThePads() throws {
        // Curls palms up, thumbs up and palms down, and a triceps extension.
        for id in ["0575", "0592", "1615", "1616", "0607"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineArmLeverStaging)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            // The elbows lie on the axle the whole way.
            try stays(frames, ["ulna.r", "ulna.l"], slack: 0.03)
            for s in ["r", "l"] {
                let elbow = try at(frames[0].body, "ulna.\(s)")
                #expect(far(elbow, list(try #require(staging.elbows[s]))) < 0.03, "\(id)")
            }
            for f in frames {
                if staging.upright {
                    try holds(f, gripRods(f.props).map(\.center))
                } else {
                    let bar = try #require(f.props.first { $0.shape == .cylinder && $0.finish == .dark && $0.size[2] > 0.5 }, "\(id)")
                    for s in ["r", "l"] {
                        let k = try at(f.body, "f3a.\(s)")
                        let d = far([k[1], k[2]], [bar.center[1], bar.center[2]])
                        #expect(d < 0.06, "\(id) hand.\(s) \(d) from the bar at \(f.t)")
                    }
                }
            }
            let moved = try sweep(frames, "hand.r", 2)
            #expect(moved > 0.15, "\(id) \(moved)")
        }
    }

    @Test func hipMachineSwingsTheLegsApartOnALevel() throws {
        for (id, apart) in [("0597", true), ("0598", false)] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineHipSwingStaging)
            #expect(staging.apart == apart)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["hand.r", "hand.l"], slack: 0.03)
            for f in frames {
                // Knees level with the hips, shins upright, feet on their rests.
                for (s, m) in [("r", 1.0), ("l", -1.0)] {
                    let knee = try at(f.body, "shin.\(s)"), ankle = try at(f.body, "foot.\(s)")
                    #expect(abs(knee[2] - staging.seat.hip.z) < 0.02, "\(id) at \(f.t)")
                    #expect(far([knee[0], knee[1]], [ankle[0], ankle[1]]) < 0.02, "\(id) at \(f.t)")
                    #expect(abs(ankle[2] - body.ankleHeight - MachineHipSwingStaging.rest) < 0.02, "\(id) at \(f.t)")
                    // The pad is on the side the leg pushes.
                    let pads = f.props.filter { $0.finish == .pad && $0.center[0] * m < 0 }
                    let pad = try #require(pads.first, "\(id)")
                    #expect(pads.count == 1 && (abs(pad.center[0]) > abs(knee[0])) == apart, "\(id) at \(f.t)")
                }
            }
            let opened = try sweep(frames, "shin.r", 0)
            #expect(opened > 0.1, "\(id) \(opened)")
        }
    }

    @Test func assistedMachineCarriesTheKneesOnItsPad() throws {
        // Pull-ups kneeling and standing, and dips kneeling.
        for (id, kneeling) in [("0017", true), ("0572", true), ("0015", true), ("1432", false), ("0019", true), ("2364", true)] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineAssistStaging)
            #expect(staging.kneeling == kneeling, "\(id)")
            let frames = loop(plan)
            // The hands stay where the plain bars hold them: only the wrists turn about the bar.
            try stays(frames, ["hand.r", "hand.l"], slack: 0.06, jump: 0.12)
            var tops: [Double] = [], plates: [Double] = []
            for f in frames {
                let pad = try #require(f.props.first { $0.shape == .box && $0.size[0] > 0.4 && $0.size[0] < 0.5 }, "\(id)")
                let top = pad.center[2] + pad.size[2] / 2
                tops.append(top)
                #expect(pad.center[2] - pad.size[2] / 2 > 0, "\(id) at \(f.t)")
                for s in ["r", "l"] {
                    let knee = try at(f.body, "shin.\(s)"), ankle = try at(f.body, "foot.\(s)")
                    if kneeling {
                        // Knees and insteps on the pad, the shins along it.
                        #expect(abs(knee[2] - top - MachineAssistStaging.kneePad) < 0.01, "\(id) knee at \(f.t)")
                        #expect(abs(ankle[2] - top - MachineAssistStaging.instep) < 0.01, "\(id) ankle at \(f.t)")
                        #expect(ankle[1] > knee[1] + 0.3, "\(id) at \(f.t)")
                    } else {
                        #expect(abs(ankle[2] - top - body.ankleHeight) < 0.01, "\(id) ankle at \(f.t)")
                    }
                    #expect(abs(ankle[1] - pad.center[1]) < pad.size[1] / 2, "\(id) at \(f.t)")
                }
                let lifted = try #require(f.props.last { $0.finish == .plate }, "\(id)")
                plates.append(lifted.center[2])
            }
            let ride = (tops.max() ?? 0) - (tops.min() ?? 0)
            #expect(ride > 0.2, "\(id) \(ride)")
            // The plates are up when the body is down.
            let lowest = try #require(tops.indices.min { tops[$0] < tops[$1] })
            #expect(plates[lowest] == plates.max(), "\(id)")
        }
    }

    @Test func lateralRaiseMachineLiftsThePadsWithTheElbows() throws {
        for id in ["0584", "1876", "3343"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineLateralRaiseStaging)
            let frames = loop(plan)
            try stays(frames, ["pelvis"], slack: 0.03)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            for f in frames {
                try holds(f, gripRods(f.props).map(\.center))
                for (s, m) in [("r", 1.0), ("l", -1.0)] {
                    // Each pad lies on its elbow, on the side the arm lifts toward.
                    let elbow = try at(f.body, "ulna.\(s)"), hand = try at(f.body, "hand.\(s)")
                    let pad = try #require(f.props.first { $0.finish == .pad && $0.center[0] * m < 0 }, "\(id)")
                    let d = far(pad.center, elbow)
                    #expect(d > 0.05 && d < 0.14, "\(id) pad \(d) from the elbow at \(f.t)")
                    #expect(hand[0] * m < -0.2, "\(id) at \(f.t)")
                    let shoulder = list(try #require(staging.shoulders[s]))
                    #expect(hand[2] < shoulder[2] + 0.05, "\(id) at \(f.t)")
                }
            }
            let lifted = try sweep(frames, "hand.r", 2)
            #expect(lifted > 0.3, "\(id) \(lifted)")
            try stackMoves(frames)
        }
    }

    @Test func calfRaisesOnOtherMachinesKeepTheBallsOfTheFeetStill() throws {
        // On the hack squat's carriage (both legs, one leg), lying on a sled, seated with one
        // leg under the pad, and bent over under a hip pad.
        for id in ["1383", "1384", "2334", "1216", "1253"] {
            let plan = try staged(id)
            let frames = loop(plan)
            // The ball of the working foot stays on its edge while the ankle goes up and down.
            try stays(frames, ["toes.r"], slack: 0.012)
            var knees: [Double] = [], ankles: [[Double]] = []
            for f in frames {
                let hip = try at(f.body, "femur.r"), knee = try at(f.body, "shin.r"), ankle = try at(f.body, "foot.r")
                knees.append(far(hip, ankle) / (far(hip, knee) + far(knee, ankle)))
                ankles.append(ankle)
            }
            let first = try #require(ankles.first)
            let moved = ankles.map { far($0, first) }.max() ?? 0
            #expect(moved > 0.03, "\(id) heel moves \(moved)")
            if id != "1216" {
                // The legs stay long.
                #expect((knees.min() ?? 0) > 0.97, "\(id)")
            }
            if let hack = plan.staging as? MachineHackSquatStaging {
                #expect(hack.press.setup.calves && hack.press.setup.single == (id == "1384"), "\(id)")
            }
            if let seated = plan.staging as? MachineSeatedCalfStaging {
                // The resting foot is flat on the floor and does not move.
                #expect(seated.single)
                try stays(frames, ["foot.l"], slack: 0.002)
                #expect(abs(try at(frames[0].body, "foot.l")[2] - body.ankleHeight) < 0.002)
            }
            if let donkey = plan.staging as? MachineDonkeyCalfStaging {
                for f in frames {
                    // Hands on the rail, the pad on the hips.
                    for s in ["r", "l"] {
                        let k = try at(f.body, "f3a.\(s)")
                        #expect(far([k[1], k[2]], [donkey.rail.y, donkey.rail.z]) < 0.06, "\(id) hand.\(s) at \(f.t)")
                    }
                    let pad = try #require(f.props.first { $0.finish == .pad })
                    let hip = try at(f.body, "femur.r")
                    let gap = pad.center[2] - pad.size[2] / 2 - hip[2]
                    #expect(gap > 0.1 && gap < 0.17, "\(id) pad \(gap) over the hips at \(f.t)")
                }
                #expect(try sweep(frames, "pelvis", 2) > 0.04)
            }
        }
        #expect(try staged("1383").staging is MachineHackSquatStaging)
        #expect(try staged("1253").staging is MachineDonkeyCalfStaging)
    }

    @Test func crunchMachineBringsTheHandlesDownWithTheTrunk() throws {
        for id in ["1452", "0595", "2268", "3760", "3881", "1857"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineCrunchStaging)
            let frames = loop(plan)
            try stays(frames, ["femur.r", "femur.l"], slack: 0.005)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            let axle = list(staging.axle)
            var radii: [Double] = []
            for f in frames {
                try holds(f, gripRods(f.props).map(\.center))
                // The handles keep their distance from the axle and stay in front of the shoulders.
                let grip = try #require(gripRods(f.props).first).center
                radii.append(far([grip[1], grip[2]], [axle[1], axle[2]]))
                let shoulder = try at(f.body, "humerus.r")
                #expect(far([grip[1], grip[2]], [shoulder[1], shoulder[2]]) < 0.3 && grip[1] < shoulder[1] - 0.05, "\(id) at \(f.t)")
            }
            #expect((radii.max() ?? 0) - (radii.min() ?? 0) < 1e-6, "\(id)")
            #expect(try sweep(frames, "neck", 1) > 0.2, "\(id)")
            try stackMoves(frames)
        }
    }

    @Test func beltDeadliftsHangTheBarFromALeverInFront() throws {
        for id in ["9866", "9494", "9876"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineForkLeverStaging)
            #expect(staging.strapped)
            var heights: [Double] = []
            for f in loop(plan) {
                let props = Array(plan.frame(at: f.t).1.dropFirst(plan.fixed.count))
                #expect(MachineSmithStaging.bar(props) == nil, "\(id)")
                let cross = try #require(props.first { $0.shape == .cylinder && $0.finish == .dark && $0.size[2] > 0.5 }, "\(id)")
                heights.append(cross.center[2])
                for s in ["r", "l"] {
                    let k = try at(f.body, "f3a.\(s)")
                    #expect(far([k[1], k[2]], [cross.center[1], cross.center[2]]) < 0.06, "\(id) hand.\(s) at \(f.t)")
                }
                // The lever's end hangs a strap's length under the bar, and nothing is under the floor.
                let end = try #require(props.first { $0.shape == .sphere }, "\(id)")
                #expect(abs(cross.center[2] - end.center[2] - staging.strap) < 1e-6 && abs(end.center[1] - cross.center[1]) < 1e-6, "\(id)")
                #expect(props.allSatisfy { $0.center[2] - ($0.finish == .plate ? $0.size[0] / 2 : 0) > -0.001 }, "\(id) at \(f.t)")
            }
            #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.25, "\(id)")
        }
        #expect(try staged("5327").staging is MachineForkLeverStaging)
    }

    @Test func backExtensionMachinePushesTheRollerRoundWithTheShoulders() throws {
        for id in ["0573", "2266"] {
            let plan = try staged(id)
            let staging = try #require(plan.staging as? MachineBackExtensionStaging)
            let frames = loop(plan)
            try stays(frames, ["femur.r", "femur.l"], slack: 0.005)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.002)
            let axle = list(staging.axle)
            for f in frames {
                // The roller keeps its distance from the axle and lies behind the upper back.
                let pad = try #require(f.props.first { $0.finish == .pad })
                #expect(abs(far(pad.center, axle) - far(try #require(frames[0].props.first).center, axle)) < 1e-6)
                let chest = try at(f.body, "thorax"), neck = try at(f.body, "neck")
                let mid = zip(chest, neck).map { ($0 + $1) / 2 }
                let d = far([pad.center[1], pad.center[2]], [mid[1], mid[2]])
                #expect(d < 0.3 && pad.center[1] > mid[1], "\(id) roller \(d) from the upper back at \(f.t)")
            }
            #expect(try sweep(frames, "neck", 1) > 0.3, "\(id)")
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
                                               "overhead-press", "chest-fly", "rear-delt-fly", "row", "lat-pulldown", "squat", "back-extension", "single-leg-squat", "deadlift",
                                               "dip", "biceps-curl", "triceps-extension", "hip-abduction", "hip-adduction", "pull-up", "lateral-raise", "hip-thrust-bridge", "crunch-sit-up"]))
        // Machines it has not built, and one-sided versions, keep the plain equipment.
        for name in ["sled reverse hack squat", "lever chair squat", "lever belt squat", "sled side leg press", "lever kneeling leg curl",
                     "lever standing leg curl", "lever rotary calf", "sled forward angled calf raise", "lever sitting toe raise",
                     "lever side hip abduction", "lever side hip adduction", "lever abduction squat",
                     "lever alternate biceps curl", "lever overhead triceps extension", "power sled biceps curl",
                     "lever lying chest press (plate loaded)",
                     "lever reverse shoulder press (plate loaded)", "power sled pull row", "lever standing lateral raise", "lever shrug", "lever lying crunch", "lever ab swing", "lever single leg hip thrust", "lever hip thrust with resistance band",
                     "lever bent over single arm neutral grip row (with chest support)", "lever lying banded t bar row",
                     "lever cable rear pulldown"] {
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
                   "1359", "11762", "3110"] {
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

    @Test func smithStandingLiftsKeepTheBarOnTheRailsInTheHands() throws {
        // Shrugs in front and behind, an upright row, presses from behind the neck, curls.
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), g.equipment == "smith-machine", MachineSmithStandStaging(g, body) != nil else { continue }
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts == ["shrug": 4, "upright-row": 1, "overhead-press": 2, "biceps-curl": 2])
        for (id, travel) in [("0767", 0.02), ("5223", 0.02), ("0746", 0.02), ("0775", 0.3), ("0747", 0.25), ("0772", 0.25),
                             ("1683", 0.3), ("4546", 0.3)] {
            let g = try guide(id)
            let plan = PropPlan(guide: g, body: body)
            let staging = try #require(plan.staging as? MachineSmithStandStaging, "\(id)")
            #expect(plan.kinds == [.smith])
            let rails = staging.fixed.filter { $0.shape == .cylinder && $0.size[2] > 2 }
            #expect(rails.count == 2 && rails.allSatisfy { abs($0.center[1] - staging.railY) < 1e-9 }, "\(id)")
            let frames = loop(plan)
            try stays(frames, ["foot.r", "foot.l"], slack: 0.01)
            var heights: [Double] = []
            for f in frames {
                let bar = try #require(MachineSmithStaging.bar(f.props), "\(id)")
                #expect(abs(bar.center[1] - staging.railY) < 1e-9 && abs(bar.center[0]) < 1e-9, "\(id) at \(f.t)")
                heights.append(bar.center[2])
                let neck = try at(f.body, "neck"), pelvis = try at(f.body, "pelvis")
                for s in ["r", "l"] {
                    let k = try at(f.body, "f3a.\(s)")
                    let d = far([k[1], k[2]], [bar.center[1], bar.center[2]])
                    #expect(d < 0.06, "\(id) hand.\(s) \(d) from the bar at \(f.t)")
                }
                // The bar clears the body: in front of it, behind it, or behind and above the neck.
                switch staging.place {
                case .front: #expect(bar.center[1] < pelvis[1] - 0.12 && bar.center[2] < neck[2], "\(id) at \(f.t)")
                case .back: #expect(bar.center[1] > pelvis[1] + 0.12 && bar.center[2] < neck[2], "\(id) at \(f.t)")
                case .neck: #expect(bar.center[1] > neck[1] + 0.08 && bar.center[2] > neck[2], "\(id) at \(f.t)")
                }
            }
            let rode = (heights.max() ?? 0) - (heights.min() ?? 0)
            #expect(rode > travel, "\(id) \(rode)")
        }
    }

    @Test func smithLungesStepUnderABarThatStaysOnItsRails() throws {
        // A split squat, a split squat with the rear foot on a bench, a curtsy lunge.
        for id in ["0768", "9042", "6606"] {
            let g = try guide(id)
            let plan = PropPlan(guide: g, body: body)
            let staging = try #require(plan.staging as? MachineSmithStaging, "\(id)")
            #expect(staging.inner is LungeStaging)
            var heights: [Double] = []
            var last: BodyFrame?
            for k in 0...48 {
                let t = Double(k) / 48
                let pose = Figure.smooth(g.keyframes, at: t)
                let made = staging.frame(pose, at: t), free = staging.inner.frame(pose, in: t).body
                let bar = try #require(MachineSmithStaging.bar(made.props), "\(id)")
                if abs(bar.center[1] - staging.railY) > 1e-9 || abs(bar.center[0]) > 1e-3 {
                    Issue.record("\(id) bar off its rails at \(k): \(bar.center)")
                }
                heights.append(bar.center[2])
                for s in ["r", "l"] {
                    let knuckle = try at(made.body, "f3a.\(s)")
                    let d = far([knuckle[1], knuckle[2]], [bar.center[1], bar.center[2]])
                    #expect(d < 0.06, "\(id) hand.\(s) \(d) from the bar at \(k)")
                }
                // The feet are where the free lunge puts them, standing or stepping.
                for bone in ["foot.r", "foot.l", "toes.r", "toes.l"] {
                    let a = try at(made.body, bone), b = try at(free, bone)
                    #expect(far(a, b) < 0.012, "\(id) \(bone) moved \(far(a, b)) at \(k)")
                }
                #expect((made.body.heads.values.map { $0[2] }.min() ?? 0) > -0.02, "\(id) under the floor at \(k)")
                if let last {
                    for bone in ["pelvis", "neck", "hand.r", "hand.l", "shin.r", "shin.l"] {
                        let a = try at(last, bone), b = try at(made.body, bone)
                        #expect(far(a, b) < 0.12, "\(id) \(bone) jumps at \(k)")
                    }
                }
                last = made.body
            }
            #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.2, "\(id)")
        }
    }

    @Test func smithLeavesWhatRailsWouldNotAllow() throws {
        var counts: [String: Int] = [:]
        for ex in catalog.exercises {
            guard let g = catalog.howTo(for: ex), g.equipment == "smith-machine", MachineSmithStaging(g, body) != nil else { continue }
            counts[g.familyID, default: 0] += 1
        }
        #expect(counts == ["bench-press": 13, "squat": 9, "row": 6, "overhead-press": 3, "calf-raise": 4, "deadlift": 3,
                           "step-up": 1, "lunge-split-squat": 3, "hip-thrust-bridge": 1])
        for name in ["smith hip raise", "smith seated shoulder press", "smith one arm row", "smith behind neck press", "smith zercher squat", "smith shrug",
                     "resistance band smith squat", "smith seated single arm neutral grip shoulders press"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(MachineSmithStaging(g, body) == nil, "\(name)")
        }
        // Lifts neither Smith staging would show believably.
        for name in ["smith hip raise", "smith seated shoulder press", "smith bent knee good morning", "smith rear lunge v. 2", "smith sprint lunge",
                     "smith one leg deadlift", "smith hang clean"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let g = try #require(catalog.howTo(for: ex))
            #expect(MachineStagings.make(g, body) == nil, "\(name)")
        }
    }
}

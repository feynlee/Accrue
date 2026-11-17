import Foundation
import Testing
@testable import AccrueKit

struct BodyPropsTests {
    let body = Body3D(rig: try! BodyRig.bundled())
    let catalog = try! Catalog.bundled()

    func guide(_ name: String) throws -> HowToGuide {
        let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
        return try #require(catalog.howTo(for: ex))
    }

    @Test func readsTheEquipment() throws {
        #expect(PropPlan(guide: try guide("barbell bench press"), body: body).kinds == [.barbell, .bench])
        #expect(PropPlan(guide: try guide("cable bar lateral pulldown"), body: body).kinds.contains(.pulldown))
        #expect(PropPlan(guide: try guide("run on treadmill"), body: body).kinds == [.treadmill])
        #expect(PropPlan(guide: try guide("dumbbell lateral raise"), body: body).kinds == [.dumbbell])
    }

    @Test func benchPressLiesOnABench() throws {
        let plan = PropPlan(guide: try guide("barbell bench press"), body: body)
        let (f, props) = plan.frame(at: 0)
        let pad = try #require(props.first { $0.finish == .pad })
        // The pad's top is just under the back.
        let top = pad.center[2] + pad.size[2] / 2
        #expect(abs(top - (f.heads["thorax"]![2] - 0.1)) < 0.08, "pad top \(top)")
        // The bar is in the hands, across the body.
        let bar = try #require(props.first { $0.shape == .cylinder && $0.size[2] > 1.9 })
        let hand = f.heads["f3a.r"]!
        #expect(abs(bar.center[2] - hand[2]) < 0.1)
    }

    @Test func treadmillRaisesTheRunner() throws {
        // The plain equipment lifts the runner onto the deck; the staging places the feet itself.
        let plan = PropPlan(guide: try guide("run on treadmill"), body: body, plain: true)
        #expect(plan.lift > 0.1)
        #expect(plan.frame(at: 0).props.count >= 4)
    }

    @Test func everyFamilyGetsFiniteProps() throws {
        var seen = Set<String>()
        for ex in catalog.exercises {
            guard let fam = ex.familyID, seen.insert(fam).inserted, let g = catalog.howTo(for: ex) else { continue }
            let plan = PropPlan(guide: g, body: body)
            for t in [0.0, 0.5] {
                let (_, props) = plan.frame(at: t)
                #expect(props.allSatisfy { ($0.center + $0.size).allSatisfy(\.isFinite) }, "\(fam)")
            }
            #expect(plan.framing.radius.isFinite && plan.framing.yaw.isFinite)
        }
    }

    private func staged(_ id: String) throws -> PropPlan {
        let ex = try #require(catalog.exercises.first { $0.id == id })
        let guide = try #require(catalog.howTo(for: ex))
        let plan = PropPlan(guide: guide, body: body)
        #expect(plan.staging != nil)
        return plan
    }

    /// How far the middle knuckle of each hand is from a bar through `point` along `axis`.
    private func knuckles(_ frame: BodyFrame, from point: (String) -> [Double], along axis: Int?) throws -> [Double] {
        try ["r", "l"].map { s in
            let k = try #require(frame.heads["f3a.\(s)"])
            let p = point(s)
            return (0..<3).filter { $0 != axis }.reduce(0.0) { $0 + (k[$1] - p[$1]) * (k[$1] - p[$1]) }.squareRoot()
        }
    }

    @Test func pullUpHangsFromTheBar() throws {
        let plan = try staged(StarterIDs.pullUp)
        #expect(plan.kinds == [.pullUpBar])
        let bar = PullUpStaging.barHeight
        var top = -Double.infinity, low = Double.infinity
        for i in 0...24 {
            let f = plan.frame(at: Double(i) / 24).body
            // Both hands stay closed on the bar, at the grip's width, the whole way.
            for d in try knuckles(f, from: { _ in [0, 0, bar] }, along: 0) { #expect(d < 0.06) }
            for s in ["r", "l"] {
                let k = try #require(f.heads["f3a.\(s)"])
                #expect(abs(abs(k[0]) - PullUpStaging.halfGrip) < 0.06)
            }
            let toes = try #require(f.heads["toes.r"])
            #expect(toes[2] > 0.1)
            let neck = try #require(f.heads["neck"])
            top = max(top, neck[2])
            low = min(low, neck[2])
        }
        // The chin clears the bar at the top, and the arms hang long at the bottom.
        #expect(top > bar - 0.06)
        #expect(low < bar - 0.5)
    }

    @Test func pulldownBringsTheBarToTheChest() throws {
        let plan = try staged(StarterIDs.pulldown)
        let first = plan.frame(at: 0), squeeze = plan.frame(at: 0.5)
        let ankle = try #require(first.body.heads["foot.r"])
        var bars: [[Double]] = []
        for i in 0...24 {
            let (f, props) = plan.frame(at: Double(i) / 24)
            let bar = props[plan.fixed.count].center
            bars.append(bar)
            for d in try knuckles(f, from: { _ in bar }, along: 0) { #expect(d < 0.06) }
            // Seated: the hips and the feet never move.
            #expect(f.heads["pelvis"] == first.body.heads["pelvis"])
            let foot = try #require(f.heads["foot.r"])
            #expect(abs(foot[2] - ankle[2]) < 0.005)
        }
        // The bar comes down by more than half a metre, to below the chin and in front of the chest.
        let neck = try #require(squeeze.body.heads["neck"])
        let bottom = squeeze.props[plan.fixed.count].center
        #expect(bars[0][2] - bottom[2] > 0.5)
        #expect(bottom[2] < neck[2])
        #expect(bottom[1] < neck[1])
        // The weight stack rises as the bar comes down.
        let plates = { (props: [PropPiece]) in props.last { $0.finish == .plate }?.center[2] ?? 0 }
        #expect(plates(squeeze.props) > plates(first.props) + 0.4)
    }

    @Test func seatedRowPullsTheHandleToTheBelly() throws {
        let plan = try staged(StarterIDs.seatedRow)
        let first = plan.frame(at: 0), squeeze = plan.frame(at: 0.5)
        for i in 0...24 {
            let (f, props) = plan.frame(at: Double(i) / 24)
            // The first two moving pieces are the handle's grips, right then left.
            let grips = ["r": props[plan.fixed.count].center, "l": props[plan.fixed.count + 5].center]
            for d in try knuckles(f, from: { grips[$0] ?? [0, 0, 0] }, along: nil) { #expect(d < 0.07) }
            // Feet stay on the plates.
            for s in ["r", "l"] { #expect(f.heads["foot.\(s)"] == first.body.heads["foot.\(s)"]) }
        }
        let start = first.props[plan.fixed.count].center, end = squeeze.props[plan.fixed.count].center
        #expect(end[1] - start[1] > 0.35)
        // At the squeeze the elbows are behind the shoulders.
        let elbow = try #require(squeeze.body.heads["ulna.r"]), shoulder = try #require(squeeze.body.heads["humerus.r"])
        #expect(elbow[1] > shoulder[1])
    }

    // MARK: Plain equipment in the hands

    /// The plain equipment of an exercise, whether or not something stages it.
    private func plain(_ id: String) throws -> (plan: PropPlan, guide: HowToGuide) {
        let ex = try #require(catalog.exercises.first { $0.id == id })
        let guide = try #require(catalog.howTo(for: ex))
        return (PropPlan(guide: guide, body: body, plain: true), guide)
    }

    /// How far `point` is from the middle line of a rod, and how far along it from its middle.
    private func off(_ point: [Double], from rod: PropPiece) -> (aside: Double, along: Double) {
        let axis = Body3D.M(rod.rotation) * Body3D.V(0, 0, 1)
        let d = Body3D.V(point) - Body3D.V(rod.center)
        let along = d.dot(axis)
        return ((d - axis * along).length, abs(along))
    }

    @Test func barbellSitsInClosedHandsClearOfBodyAndFloor() throws {
        // A deadlift, a curl that the keyframes take through the thighs and up to the face, and a press.
        for id in ["0032", "0023", "1162", "0027"] {
            let (plan, guide) = try plain(id)
            let hands = try #require(plan.hands)
            let held = try #require(hands.bar)
            var last: (bar: Body3D.V, own: Body3D.V)?
            for i in 0...48 {
                let t = Double(i) / 48
                let (f, props) = plan.frame(at: t)
                let bar = try #require(props.first { $0.shape == .cylinder && $0.finish == .metal && $0.size[2] > 1.9 }, "\(id)")
                for s in ["r", "l"] {
                    // The knuckles are a finger's thickness from the bar's middle line, and the
                    // fingertips have come round it.
                    #expect(off(try #require(f.heads["f3a.\(s)"]), from: bar).aside < 0.05, "\(id) \(t) \(s)")
                    #expect(off(try #require(f.heads["f3c.\(s)"]), from: bar).aside < 0.045, "\(id) \(t) \(s)")
                }
                // The bar is level, and its plates stand on the floor or above it.
                #expect(abs((Body3D.M(bar.rotation) * Body3D.V(0, 0, 1)).z) < 1e-6)
                let plates = props.filter { $0.finish == .plate }
                #expect(plates.count == 2)
                for plate in plates { #expect(plate.center[2] - plate.size[0] / 2 > -0.001, "\(id) \(t)") }
                // It is outside the legs, the trunk and the head.
                let pose = Figure.interpolate(guide.keyframes, at: t)
                let p = hands.placed(pose)
                let line = try #require(hands.follow(p.g, p.h, held))
                let centre = Body3D.V(bar.center)
                let inside = Body3D.wayOut(centre, axis: line.axis, half: 1, radius: held.radius, of: body.bulk(p.g, p.h), front: line.front)
                #expect((inside?.length ?? 0) < 0.005, "\(id) \(t) in the body by \(inside?.length ?? 0)")
                // And it never moves much further in one step than the hands were going anyway.
                if let last { #expect((centre - last.bar).length < (line.mid - last.own).length + 0.03, "\(id) \(t)") }
                last = (centre, line.mid)
            }
        }
    }

    @Test func dumbbellsSitInClosedHands() throws {
        // A hammer curl, a lateral raise and a carry.
        for id in ["0313", "0334", "2133"] {
            let (plan, guide) = try plain(id)
            #expect(plan.kinds.contains(.dumbbell))
            for i in 0...24 {
                let t = Double(i) / 24
                let (f, props) = plan.frame(at: t)
                // A dumbbell is a handle and two heads; the handles come first of each three.
                let handles = props.filter { $0.shape == .cylinder && $0.finish == .metal && abs($0.size[2] - 0.26) < 1e-6 }
                #expect(handles.count == 2)
                for s in ["r", "l"] {
                    let knuckle = try #require(f.heads["f3a.\(s)"]), tip = try #require(f.heads["f3c.\(s)"])
                    let handle = try #require(handles.min { off(knuckle, from: $0).aside < off(knuckle, from: $1).aside })
                    #expect(off(knuckle, from: handle).aside < 0.05, "\(id) \(t) \(s)")
                    #expect(off(knuckle, from: handle).along < 0.03, "\(id) \(t) \(s)")
                    #expect(off(tip, from: handle).aside < 0.045, "\(id) \(t) \(s)")
                }
                // Closing the hand leaves the arm where the keyframes put it.
                let own = body.frame(guide, at: t)
                for bone in ["humerus.r", "ulna.l", "hand.r", "hand.l"] { #expect(f.local[bone] == own.local[bone]) }
                let wrist = try #require(f.heads["hand.r"]), ownWrist = try #require(PropPlan.raise(own, by: plan.lift).heads["hand.r"])
                #expect(zip(wrist, ownWrist).allSatisfy { abs($0 - $1) < 1e-9 })
            }
        }
    }

    @Test func emptyHandsStayAsTheKeyframesPoseThem() throws {
        // A push-up, a run and a machine press: nothing is held, nothing changes.
        for name in ["push-up", "run on treadmill", "lever chest press"] {
            let ex = try #require(catalog.exercises.first { $0.name == name }, "\(name)")
            let guide = try #require(catalog.howTo(for: ex))
            let plan = PropPlan(guide: guide, body: body, plain: true)
            let hands = try #require(plan.hands)
            #expect(hands.bar == nil && !hands.each, "\(name) \(plan.kinds)")
            for t in [0.0, 0.3, 0.5, 0.8] {
                let own = PropPlan.raise(body.frame(guide, at: t), by: plan.lift)
                let f = plan.frame(at: t).body
                #expect(f.local == own.local, Comment(rawValue: name))
                for (bone, at) in own.heads {
                    let now = try #require(f.heads[bone])
                    #expect(zip(now, at).allSatisfy { abs($0 - $1) < 1e-9 }, Comment(rawValue: name + " " + bone))
                }
            }
        }
    }

    @Test func ropeAndAnkleCablesGoWhereTheyAreHeld() throws {
        // A rope pushdown and a face pull put an end of the rope in each fist, not a bar through
        // both; cable work for a leg straps to the ankle and leaves the hands as posed.
        for id in ["0200", "5609"] {
            let (plan, _) = try plain(id)
            let hands = try #require(plan.hands)
            #expect(hands.bar == nil && hands.each, "\(id)")
            for t in [0.0, 0.25, 0.5, 0.75] {
                let (f, props) = plan.frame(at: t)
                let stops = props.filter { $0.shape == .sphere && $0.finish == .dark && abs($0.size[0] - 0.042) < 1e-6 }
                #expect(stops.count == 2, "\(id) at \(t)")
                for s in ["r", "l"] {
                    let knuckle = Body3D.V(try #require(f.heads["f3a.\(s)"]))
                    let near = stops.map { (Body3D.V($0.center) - knuckle).length }.min() ?? 1
                    #expect(near < 0.12, "\(id) \(s) at \(t): the rope's stopper is \(near) from the fist")
                }
            }
        }
        for id in ["0168", "0228"] {
            let (plan, guide) = try plain(id)
            let hands = try #require(plan.hands)
            let leg = try #require(hands.ankle, "\(id)")
            #expect(hands.bar == nil && !hands.each, "\(id)")
            for t in [0.0, 0.3, 0.6] {
                let own = PropPlan.raise(body.frame(guide, at: t), by: plan.lift)
                let (f, props) = plan.frame(at: t)
                #expect(f.local == own.local, "\(id)")
                let ankle = Body3D.V(try #require(f.heads["foot.\(leg)"]))
                let cuff = props.filter { $0.finish == .dark }.map { (Body3D.V($0.center) - ankle).length }.min() ?? 1
                #expect(cuff < 0.08, "\(id) at \(t): the cuff is \(cuff) from the ankle")
            }
        }
    }

    /// BODY_HOLD_AUDIT=/path lists, for every exercise whose plain equipment is a bar in both hands, how
    /// far the knuckles are from the bar, how deep the bar is in the body, how low it comes and
    /// how fast it moves off the hands' own line, worst first.
    @Test func auditHeldBars() throws {
        guard let path = ProcessInfo.processInfo.environment["BODY_HOLD_AUDIT"] else { return }
        typealias V = Body3D.V
        // BODY_HOLD_TRACE=0053,0114 writes those exercises' bars moment by moment instead.
        if let ids = ProcessInfo.processInfo.environment["BODY_HOLD_TRACE"] {
            var text = ""
            func f3(_ v: V) -> String { String(format: "(%.3f %.3f %.3f)", v.x, v.y, v.z) }
            for id in ids.split(separator: ",") {
                guard let ex = catalog.exercises.first(where: { $0.id == String(id) }), let g = catalog.howTo(for: ex),
                      let hands = PropPlan(guide: g, body: body, plain: true).hands, let bar = hands.bar else { continue }
                text += "\(ex.id) \(ex.name) half \(bar.half) turn \(bar.turn) contacts \(g.contacts)\n"
                for i in 0...48 {
                    let t = Double(i) / 48
                    let pose = Figure.interpolate(g.keyframes, at: t)
                    let (_, held) = hands.frame(pose, at: t)
                    let p = hands.placed(pose)
                    guard let line = held.bar, let follow = hands.follow(p.g, p.h, bar) else { continue }
                    let track = i % 2 == 0 && bar.track.count > i / 2 ? f3(bar.track[i / 2]) : ""
                    let out = Body3D.wayOut(line.mid, axis: line.axis, half: bar.length, radius: bar.radius,
                                            of: body.bulk(p.g, p.h, behind: bar.behind), front: follow.front)
                    let reach = ["r", "l"].map { s in
                        String(format: "%.3f/%.3f", (hands.target(s, s == "r" ? 1 : -1, mid: line.mid, axis: line.axis, bar) - p.h["humerus.\(s)"]!).length, hands.reach[s] ?? 0)
                    }
                    text += String(format: "  %.3f", t) + " hands \(f3(follow.mid)) bar \(f3(line.mid)) off \(f3(line.mid - follow.mid)) deep \(out.map(f3) ?? "-") reach \(reach) track \(track)\n"
                }
            }
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        var rows: [(Double, String)] = []
        var seen = Set<String>()
        for ex in catalog.exercises where !ex.hidden {
            guard let g = catalog.howTo(for: ex) else { continue }
            let kinds = PropPlan.kinds(for: g)
            // One of each kind of movement is enough.
            let key = "\(g.familyID) \(g.subtypeID ?? "") \(kinds) \(g.contacts) \(g.exerciseName.contains("behind"))"
            guard seen.insert(key).inserted else { continue }
            let plan = PropPlan(guide: g, body: body, plain: true)
            guard let hands = plan.hands, let bar = hands.bar else { continue }
            var knuckle = 0.0, deep = 0.0, low = Double.infinity, jump = 0.0, off = 0.0, bent = 180.0
            var last: V?, lastOwn: V?
            let n = 96
            for i in 0...n {
                let t = Double(i) / Double(n)
                let pose = Figure.interpolate(g.keyframes, at: t)
                let (f, held) = hands.frame(pose, at: t)
                guard let line = held.bar else { continue }
                let p = hands.placed(pose)
                guard let follow = hands.follow(p.g, p.h, bar) else { continue }
                for s in ["r", "l"] {
                    let k = V(f.heads["f3a.\(s)"]!) - line.mid
                    let d: Double
                    switch bar.handles {
                    case .along: d = (k - line.axis * k.dot(line.axis)).length
                    default: d = abs(abs(k.dot(line.axis)) - bar.half)
                    }
                    knuckle = max(knuckle, d)
                    let a = V(f.heads["ulna.\(s)"]!) - V(f.heads["humerus.\(s)"]!), b = V(f.heads["hand.\(s)"]!) - V(f.heads["ulna.\(s)"]!)
                    bent = min(bent, 180 - acos(max(-1, min(1, a.unit.dot(b.unit)))) * 180 / .pi)
                }
                if bar.clear, let move = Body3D.wayOut(line.mid, axis: line.axis, half: bar.length, radius: bar.radius,
                                                       of: body.bulk(p.g, p.h, behind: bar.behind), front: follow.front) {
                    deep = max(deep, move.length)
                }
                low = min(low, line.mid.z - bar.lowest)
                let d = line.mid - follow.mid
                off = max(off, d.length)
                // A jump is the bar moving further in one step than the hands' own line did.
                if let last, let lastOwn { jump = max(jump, (line.mid - last).length - (follow.mid - lastOwn).length) }
                last = line.mid
                lastOwn = follow.mid
            }
            let score = max(knuckle - 0.04, 0) * 10 + deep * 10 + max(0, -low) * 10 + jump * 10 + max(0, off - 0.3)
            rows.append((score, String(format: "%.3f %@ %@ [%@] knuckle %.3f deep %.3f low %.3f jump %.3f off %.3f elbow %.0f half %.2f%@",
                                       score, ex.id, ex.name, g.familyID, knuckle, deep, low, jump, off, bent, bar.half, bar.behind ? " behind" : "")))
        }
        rows.sort { $0.0 > $1.0 }
        try rows.map(\.1).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// BODY_DUMP=/path writes frames, props and framing for a sample of exercises, for the
    /// offline renderer in Body/anatomy/render_app.py.
    @Test func dumpForRenderer() throws {
        guard let path = ProcessInfo.processInfo.environment["BODY_DUMP"] else { return }
        let only = ProcessInfo.processInfo.environment["BODY_DUMP_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        // BODY_DUMP_IDS=0198,0652 dumps just those exercises; BODY_DUMP_FRAMES=9 samples the loop.
        let ids = ProcessInfo.processInfo.environment["BODY_DUMP_IDS"].map { Set($0.split(separator: ",").map(String.init)) }
        let count = ProcessInfo.processInfo.environment["BODY_DUMP_FRAMES"].flatMap(Int.init) ?? 2
        let times = count <= 2 ? [0.0, 0.5] : (0..<count).map { Double($0) / Double(count) }
        var perFamily: [String: [String: Int]] = [:]
        var out: [[String: Any]] = []
        for ex in catalog.exercises where !ex.hidden {
            guard let fam = ex.familyID else { continue }
            if let ids {
                guard ids.contains(ex.id) else { continue }
            } else {
                if let only, !only.contains(fam), !only.contains(ex.id) { continue }
                let key = ex.equipment ?? "-"
                var seen = perFamily[fam, default: [:]]
                if seen[key] != nil || seen.count >= (only == nil ? 2 : 6) { continue }
                seen[key] = 1
                perFamily[fam] = seen
            }
            guard let g = catalog.howTo(for: ex) else { continue }
            let plan = PropPlan(guide: g, body: body)
            var frames: [[String: Any]] = []
            // BODY_DUMP_FAULTS=1 adds one frame per common mistake after the loop's frames.
            var shots: [(Double, JointPose?)] = times.map { ($0, nil) }
            if ProcessInfo.processInfo.environment["BODY_DUMP_FAULTS"] != nil {
                let mistakes = g.steps.flatMap(\.mistakes)
                shots += mistakes.compactMap { m in m.pose.map { (g.faultT, $0) } }
            }
            for (t, fault) in shots {
                let (f, props) = plan.frame(at: t, fault: fault)
                frames.append([
                    "t": t,
                    "root": f.root,
                    "heads": f.heads,
                    "local": f.local.mapValues { [$0.w, $0.x, $0.y, $0.z] },
                    "props": props.map { ["shape": $0.shape.rawValue, "finish": $0.finish.rawValue, "center": $0.center,
                                          "size": $0.size, "q": [$0.rotation.w, $0.rotation.x, $0.rotation.y, $0.rotation.z]] },
                ])
            }
            out.append(["id": ex.id, "name": ex.name, "family": fam, "model": g.bodyModel,
                        "kinds": plan.kinds.map(\.rawValue), "lift": plan.lift,
                        "framing": ["center": plan.framing.center, "radius": plan.framing.radius,
                                    "yaw": plan.framing.yaw, "pitch": plan.framing.pitch, "view": plan.framing.view],
                        "primary": g.muscles.primary, "frames": frames])
        }
        // BODY_DUMP_POSES=/path.json dumps free poses ([{"name", "angles", "scapula", "focus"}]) as
        // one entry instead, to look at the body itself through each joint's range. "focus" is
        // "bone:radius", the close-up a view named with the bone "focus" takes for that pose.
        if let posesPath = ProcessInfo.processInfo.environment["BODY_DUMP_POSES"] {
            struct Named: Decodable { var name: String; var angles: [String: Double]; var scapula: Scapula?; var focus: String? }
            let poses = try JSONDecoder().decode([Named].self, from: Data(contentsOf: URL(fileURLWithPath: posesPath)))
            let frames: [[String: Any]] = poses.map { p in
                let f = body.frame(JointPose(angles: p.angles, scapula: p.scapula), contacts: [])
                return ["t": 0.0, "name": p.name, "focus": p.focus ?? "", "root": f.root, "heads": f.heads,
                        "local": f.local.mapValues { [$0.w, $0.x, $0.y, $0.z] }, "props": [[String: Any]]()]
            }
            out = [["id": "poses", "name": "poses", "family": "rom", "model": "anatomy", "kinds": [String](), "lift": 0.0,
                    "framing": ["center": [0.0, 0.0, 0.95], "radius": 1.25, "yaw": -0.5, "pitch": 0.12, "view": "front"],
                    "primary": [String](), "frames": frames]]
        }
        let data = try JSONSerialization.data(withJSONObject: out)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

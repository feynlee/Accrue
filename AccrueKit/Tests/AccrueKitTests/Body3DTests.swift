import Foundation
import Testing
@testable import AccrueKit

struct Body3DTests {
    let body = Body3D(rig: try! BodyRig.bundled())

    func pose(_ angles: [String: Double]) -> JointPose { JointPose(angles: angles) }

    func dir(_ f: BodyFrame, _ from: String, _ to: String) -> Body3D.V {
        (Body3D.V(f.heads[to]!) - Body3D.V(f.heads[from]!)).unit
    }

    @Test func rigHasEveryBoneTheAppSets() throws {
        let names = Set(body.rig.bones.map(\.name))
        #expect(body.rig.bones.count == 83)
        for b in ["pelvis", "thorax", "head", "femur.r", "shin.l", "toes.r", "humerus.l", "radius.r", "hand.l", "f5c.r", "f1a.l", "fore2.r", "shoulder.r", "delt.l", "lat.l", "pec.r", "hip1.r", "knee1.l", "elbow1.r", "arm1.l", "arm2.r"] {
            #expect(names.contains(b), "\(b)")
        }
        #expect(body.rig.bones.allSatisfy { $0.rest?.count == 9 })
        #expect(body.rig.bones.first?.parent == nil)
    }

    @Test func helperBonesTurnHalfwayAcrossTheirJoint() throws {
        func turn(_ f: BodyFrame, _ a: String, _ b: String) -> Double {
            let q = (Body3D.M(f.rotations[a]!).t * Body3D.M(f.rotations[b]!)).quat
            return 2 * acos(min(1, abs(q.w))) * 180 / .pi
        }
        let bent = body.frame(pose(["kneeFlex": 120, "elbowFlex": 100]), contacts: ["feet"])
        #expect(abs(turn(bent, "femur.r", "knee1.r") - 60) < 0.5)
        #expect(abs(turn(bent, "knee1.r", "shin.r") - 60) < 0.5)
        #expect(abs(turn(bent, "humerus.l", "elbow1.l") - 50) < 0.5)
        // Overhead the arm is opposite to how it hangs, and every way round is equally short:
        // the shoulder's helpers must still not jump as the arm passes through.
        for key in ["shoulderFlex", "shoulderAbd"] {
            var last: [String: Body3D.V] = [:]
            for angle in stride(from: 140.0, through: 180.0, by: 2) {
                let f = body.frame(pose([key: angle]), contacts: ["feet"])
                for helper in ["shoulder.r", "delt.r", "lat.r", "pec.l", "arm1.r", "arm2.l"] {
                    let dir = Body3D.M(f.rotations[helper]!) * Body3D.V(0, 0, -1)
                    #expect(dir.length.isFinite)
                    if let before = last[helper] { #expect((dir - before).length < 0.12, "\(helper) \(key) \(angle)") }
                    last[helper] = dir
                }
            }
        }
    }

    @Test func upperArmTwistBonesSwingWithTheArmAndShareItsTurn() throws {
        // Arm out to the side and turned about its own length: the twist bones point along the
        // humerus, the first without the turn, the second with half of it.
        for rot in [-140.0, -60, 0, 10] {
            let f = body.frame(pose(["shoulderAbd": 90, "shoulderRot": rot]), contacts: ["feet"])
            let m = { (b: String) in Body3D.M(f.rotations[b]!) }
            let along = (Body3D.V(body.rig.bones.first { $0.name == "humerus.r" }!.tail) - Body3D.V(body.rig.bones.first { $0.name == "humerus.r" }!.head)).unit
            for b in ["arm1.r", "arm2.r"] {
                #expect(((m(b) * along) - (m("humerus.r") * along)).length < 1e-6, "\(b) \(rot)")
            }
            func turned(_ a: String, _ b: String) -> Double {
                let q = (m(a).t * m(b)).quat
                return 2 * acos(min(1, abs(q.w))) * 180 / .pi
            }
            let whole = turned("arm1.r", "humerus.r")
            #expect(abs(turned("arm1.r", "arm2.r") - whole / 2) < 0.5, "\(rot)")
            #expect(abs(turned("arm2.r", "humerus.r") - whole / 2) < 0.5, "\(rot)")
        }
        // The turn is what the pose asks for: 100 degrees more of it shows as 100 degrees.
        let a = body.frame(pose(["shoulderAbd": 90, "shoulderRot": -100]), contacts: ["feet"])
        let b = body.frame(pose(["shoulderAbd": 90, "shoulderRot": 0]), contacts: ["feet"])
        let q = (Body3D.M(a.rotations["arm1.r"]!).t * Body3D.M(b.rotations["arm1.r"]!)).quat
        #expect(2 * acos(min(1, abs(q.w))) * 180 / .pi < 1, "the first twist bone does not turn with the humerus")
    }

    @Test func carrierBonesRideTheArmButKeepTheirOriginsFacing() throws {
        // The deltoid, chest and latissimus are stretched between their origin and a bone
        // that sits where they meet the humerus: it goes where the humerus takes it and
        // stays turned the way the origin is, so the muscle shears instead of swinging.
        let rest = { (b: String) in Body3D.V(self.body.rig.bones.first { $0.name == b }!.head) }
        for p in [["shoulderAbd": 90.0], ["shoulderFlex": 170], ["shoulderFlex": -40], ["shoulderAbd": 90, "shoulderRot": -120]] {
            let f = body.frame(pose(p), contacts: ["feet"])
            let m = { (b: String) in Body3D.M(f.rotations[b]!) }
            for (carrier, origin) in [("delt.r", "scapula.r"), ("pec.r", "thorax"), ("lat.l", "thorax")] {
                let q = (m(origin).t * m(carrier)).quat
                #expect(2 * acos(min(1, abs(q.w))) * 180 / .pi < 1e-4, "\(carrier) \(p)")
                let humerus = "humerus." + carrier.suffix(1)
                let at = Body3D.V(f.heads[humerus]!) + m(humerus) * (rest(carrier) - rest(humerus))
                #expect((Body3D.V(f.heads[carrier]!) - at).length < 1e-6, "\(carrier) \(p)")
            }
        }
    }

    @Test func halfWayGirdleTurnsHalfAsFarAsTheCollarBoneAndBlade() throws {
        // What is stretched from the ribs to the blade goes round the chest by way of a
        // collar bone and blade that have made half the turn of the real ones.
        let rest = { (b: String) in Body3D.V(self.body.rig.bones.first { $0.name == b }!.head) }
        let angle = { (q: BodyQuat) in 2 * acos(min(1, abs(q.w))) * 180 / .pi }
        for p in [["shoulderFlex": 170.0], ["shoulderAbd": 90], ["shoulderAbd": 170]] {
            let f = body.frame(pose(p), contacts: ["feet"])
            let m = { (b: String) in Body3D.M(f.rotations[b]!) }
            for (half, whole) in [("clav1.l", "clavicle.l"), ("blade1.l", "scapula.l"), ("blade1.r", "scapula.r")] {
                let all = angle((m("thorax").t * m(whole)).quat)
                #expect(abs(angle((m("thorax").t * m(half)).quat) - all / 2) < 1e-3, "\(half) \(p)")
                #expect(abs(angle((m(half).t * m(whole)).quat) - all / 2) < 1e-3, "\(half) \(p)")
            }
            // its blade hangs from the end of its own collar bone
            let reach = (rest("blade1.l") - rest("clav1.l")).length
            #expect(abs((Body3D.V(f.heads["blade1.l"]!) - Body3D.V(f.heads["clav1.l"]!)).length - reach) < 1e-6)
        }
    }

    @Test func standsOnTheFloor() throws {
        let f = body.frame(pose([:]), contacts: ["feet"])
        #expect(f.floor == 0)
        let pelvis = try #require(f.heads["pelvis"])
        #expect(pelvis[2] > 0.8 && pelvis[2] < 1.0)
        let lowest = body.contactPoints("feet", f.rotations.mapValues { Body3D.M($0) }, f.heads.mapValues { Body3D.V($0) })
            .map { $0.0.z - $0.1 }.min() ?? 1
        #expect(abs(lowest) < 0.001)
        // At rest the trunk and legs do not turn (forearms turn to a neutral grip).
        for b in ["pelvis", "lumbar", "thorax", "neck", "head", "femur.r", "shin.l", "foot.r", "toes.l"] {
            #expect(abs(f.local[b]!.w - 1) < 1e-6, "\(b)")
        }
        #expect(abs(f.local["radius.r"]!.w - 0.5.squareRoot()) < 1e-3)
    }

    @Test func limbsGoWhereTheAnglesSay() throws {
        let f = body.frame(pose(["shoulderFlex": 90, "elbowFlex": 90, "hipFlex": 90, "kneeFlex": 90]), contacts: [])
        // Upper arm straight ahead, forearm then straight up; thigh ahead, shin down.
        #expect(dir(f, "humerus.r", "ulna.r").y < -0.95)
        #expect(dir(f, "ulna.r", "hand.r").z > 0.9)
        #expect(dir(f, "femur.r", "shin.r").y < -0.95)
        #expect(dir(f, "shin.r", "foot.r").z < -0.95)
        // Left side mirrors the right.
        #expect(dir(f, "humerus.l", "ulna.l").y < -0.95)

        let side = body.frame(pose(["shoulderAbd": 90, "hipAbd": 30]), contacts: [])
        #expect(dir(side, "humerus.r", "ulna.r").x < -0.95)  // right arm out to the right (-x)
        #expect(dir(side, "humerus.l", "ulna.l").x > 0.95)
        #expect(dir(side, "femur.r", "shin.r").x < -0.4)

        let overhead = body.frame(pose(["shoulderFlex": 180]), contacts: [])
        #expect(dir(overhead, "humerus.r", "ulna.r").z > 0.95)

        let lean = body.frame(pose(["trunk": 45]), contacts: [])
        let spine = dir(lean, "pelvis", "neck")
        #expect(spine.y < -0.6 && spine.z > 0.6)  // forward and up
    }

    @Test func shoulderBladesGlideOnTheRibs() throws {
        typealias V = Body3D.V
        let cage = try #require(body.rig.girdle)
        let centre = V(cage.center), radii = V(cage.radii)
        /// How far a point is outside the ellipsoid fitted to the back of the rib cage.
        func off(_ p: V) -> Double {
            let q = V((p.x - centre.x) / radii.x, (p.y - centre.y) / radii.y, (p.z - centre.z) / radii.z)
            return (q.length - 1) * q.length / V(q.x / radii.x, q.y / radii.y, q.z / radii.z).length
        }
        func seen(_ border: V) -> Double { atan2(border.x, -border.z) * 180 / .pi }
        let poses: [(name: String, pose: JointPose, upRot: Double)] = [
            ("overhead", pose(["shoulderFlex": 170]), (170.0 - 30) / 3),
            ("hang", JointPose(angles: ["shoulderFlex": 165, "shoulderAbd": 30],
                               scapula: Scapula(protraction: 0.2, elevation: 1, upRot: 50)), 50),
            ("reach", JointPose(angles: ["shoulderFlex": 80], scapula: Scapula(protraction: 0.7, elevation: 0.1, upRot: 10)), 10),
            ("squeeze", JointPose(angles: ["shoulderFlex": -35], scapula: Scapula(protraction: -0.9, elevation: -0.1, upRot: 0)), 0),
            ("shrug", JointPose(angles: [:], scapula: Scapula(protraction: 0, elevation: 1, upRot: 5)), 5),
        ]
        for (name, pose, upRot) in poses {
            let f = body.frame(pose, contacts: [])
            #expect(abs(f.rotations["thorax"]!.w - 1) < 1e-6)
            let shift = V(f.heads["thorax"]!) - body.head["thorax"]!
            for s in ["l", "r"] {
                let marks = try #require(cage.blades[s])
                let turn = Body3D.M(f.rotations["scapula.\(s)"]!)
                let ac0 = body.head["scapula.\(s)"]!, ac = V(f.heads["scapula.\(s)"]!) - shift
                let corner = ac + turn * (V(marks.corner) - ac0), root = ac + turn * (V(marks.root) - ac0)
                // Both ends of the inner border keep their distance from the ribs.
                #expect(abs(off(corner) - off(V(marks.corner))) < 0.001, "\(name) \(s) corner")
                #expect(abs(off(root) - off(V(marks.root))) < 0.001, "\(name) \(s) root")
                // Seen from behind, the lower corner has swung out by about the upward rotation asked for.
                let turned = (seen(corner - root) - seen(V(marks.corner) - V(marks.root))) * (s == "l" ? 1 : -1)
                #expect(turned > upRot * 0.6 - 3 && turned < upRot * 1.1 + 3, "\(name) \(s) turned \(turned)")
                // And the blade never crosses to the spine or leaves the back.
                #expect(abs(root.x) > 0.03 && abs(corner.x) > 0.03, "\(name) \(s) root \(root.x) corner \(corner.x)")
                #expect(root.y > 0 && corner.y > 0, "\(name) \(s)")
                if name == "hang" { #expect(abs(corner.x) > abs(marks.corner[0]) + 0.03) }
                if name == "squeeze" { #expect(abs(root.x) < abs(marks.root[0]) - 0.01) }
                if name == "reach" { #expect(abs(root.x) > abs(marks.root[0]) + 0.01) }
            }
        }
    }

    @Test func localTurnsRebuildTheWorldTurns() throws {
        let f = body.frame(pose(["trunk": 30, "hipFlex": 60, "kneeFlex": 45, "shoulderFlex": 120, "elbowFlex": 70,
                                 "forearm": 20, "wristExt": 15]), contacts: ["feet"])
        func m(_ q: BodyQuat) -> Body3D.M { Body3D.M(q) }
        for bone in body.rig.bones {
            let r = try #require(bone.rest)
            let rest = Body3D.M(r0: .init(r[0], r[1], r[2]), r1: .init(r[3], r[4], r[5]), r2: .init(r[6], r[7], r[8]))
            let parent = bone.parent.map { m(f.rotations[$0]!) } ?? .identity
            let world = parent * rest * m(f.local[bone.name]!) * rest.t
            let want = m(f.rotations[bone.name]!)
            for (a, b) in [(world.r0, want.r0), (world.r1, want.r1), (world.r2, want.r2)] {
                #expect((a - b).length < 1e-4, "\(bone.name)")
            }
        }
    }

    @Test func pushUpRestsOnHandsAndToes() throws {
        let catalog = try Catalog.bundled()
        let ex = try #require(catalog.exercises.first { catalog.family(for: $0)?.id == "push-up" })
        let guide = try #require(catalog.howTo(for: ex))
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let f = body.frame(guide, at: t)
            let h = f.heads.mapValues { Body3D.V($0) }
            let g = f.rotations.mapValues { Body3D.M($0) }
            let hands = body.contactPoints("hands", g, h).map { $0.0.z - $0.1 }
            let toes = body.contactPoints("toes", g, h).map { $0.0.z - $0.1 }
            #expect(abs(hands.min()!) < 0.02, "hands at t \(t): \(hands)")
            #expect(abs(toes.min()!) < 0.03, "toes at t \(t): \(toes)")
            // Head end higher than the feet, body roughly flat.
            #expect(h["neck"]!.z > h["pelvis"]!.z - 0.05)
            #expect(h["pelvis"]!.z > 0.15 && h["pelvis"]!.z < 0.7)
        }
    }

    @Test func pullUpHangsFromTheBar() throws {
        let catalog = try Catalog.bundled()
        let ex = try #require(catalog.exercises.first { catalog.family(for: $0)?.id == "pull-up" })
        let f = body.frame(try #require(catalog.howTo(for: ex)), at: 0)
        #expect(f.floor == nil)
        #expect(f.heads["hand.r"]![2] > f.heads["head"]![2])
    }

    @Test func everyFamilyGivesFiniteFrames() throws {
        let catalog = try Catalog.bundled()
        var seen = Set<String>()
        for ex in catalog.exercises {
            guard let family = catalog.family(for: ex), seen.insert(family.id).inserted,
                  let guide = catalog.howTo(for: ex) else { continue }
            for t in [0.0, 0.5, 1.0] {
                let f = body.frame(guide, at: t)
                #expect(f.heads.values.allSatisfy { $0.allSatisfy(\.isFinite) }, "\(family.id)")
                #expect(f.local.values.allSatisfy { $0.w.isFinite && abs($0.w * $0.w + $0.x * $0.x + $0.y * $0.y + $0.z * $0.z - 1) < 1e-6 },
                        "\(family.id)")
            }
        }
        #expect(seen.count > 100)
    }
}

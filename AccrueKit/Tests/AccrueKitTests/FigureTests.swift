import Foundation
import Testing
@testable import AccrueKit

@Suite struct FigureTests {
    static var catalog: Catalog { CatalogTests.catalog }

    @Test func standingFigureIsUprightOnTheFloor() {
        let p = Figure.pose(JointPose(), contacts: ["feet"])
        #expect(p.groundY == 0)
        #expect(abs(min(p[.heel].y, p[.toe].y)) < 1e-9)
        #expect(p[.head].y > p[.shoulder].y && p[.shoulder].y > p[.hip].y && p[.hip].y > p[.knee].y)
        #expect(abs(p[.head].y - 1.0) < 0.1)  // about one body height tall
        #expect(p[.toe].x > p[.heel].x)       // feet point forward
    }

    @Test func raisedArmsGoOverheadEvenWhenRaisedToTheSide() {
        let side = Figure.raw(JointPose(angles: ["shoulderAbd": 170]))
        let front = Figure.raw(JointPose(angles: ["shoulderFlex": 170]))
        #expect(side[.hand]!.y > side[.head]!.y)
        #expect(front[.hand]!.y > front[.head]!.y)
    }

    @Test func kneesBendBackAndElbowsBendForward() {
        let squat = Figure.raw(JointPose(angles: ["hipFlex": 90, "kneeFlex": 90]))
        #expect(squat[.knee]!.x > 0.2)                       // thigh forward
        #expect(squat[.ankle]!.y < squat[.knee]!.y - 0.2)    // shin down
        let curl = Figure.raw(JointPose(angles: ["elbowFlex": 90]))
        #expect(curl[.wrist]!.x > curl[.elbow]!.x + 0.1)     // forearm forward
    }

    @Test func pushUpBottomIsLowerThanTheTop() throws {
        let push = try #require(Self.catalog.exercise(StarterIDs.pushUp))
        let guide = try #require(Self.catalog.howTo(for: push))
        let top = Figure.pose(Figure.interpolate(guide.keyframes, at: 0), contacts: guide.contacts)
        let bottomT = try #require(guide.keyframes.first { $0.phase == "Bottom" }).t
        let bottom = Figure.pose(Figure.interpolate(guide.keyframes, at: bottomT), contacts: guide.contacts)
        #expect(bottom[.shoulder].y < top[.shoulder].y - 0.05)
        // Hands stay planted: the first contact is the anchor.
        #expect(abs(bottom[.hand].x - top[.hand].x) < 1e-6)
    }

    @Test func saggingHipsKeepHandsAndFeetOnTheFloor() throws {
        let push = try #require(Self.catalog.exercise(StarterIDs.pushUp))
        let guide = try #require(Self.catalog.howTo(for: push))
        let sag = try #require(guide.steps.flatMap(\.mistakes).first { $0.name == "Hips sag" }?.pose)
        let good = Figure.pose(Figure.interpolate(guide.keyframes, at: guide.faultT), contacts: guide.contacts)
        let bad = Figure.pose(Figure.applying(sag, to: Figure.interpolate(guide.keyframes, at: guide.faultT)), contacts: guide.contacts)
        #expect(min(bad[.toe].y, bad[.heel].y) < 0.02)
        #expect(bad[.hand].y < 0.02)
        #expect(bad[.hip].y < good[.hip].y)
    }

    @Test func pullUpHangsFromTheBar() throws {
        let pull = try #require(Self.catalog.exercise(StarterIDs.pullUp))
        let guide = try #require(Self.catalog.howTo(for: pull))
        let p = Figure.pose(Figure.interpolate(guide.keyframes, at: 0), contacts: guide.contacts)
        #expect(p[.hand].y >= p[.head].y)
    }

    @Test func everyFamilyGivesFiniteFigures() {
        for family in Self.catalog.families.values {
            for k in family.motion.keyframes {
                let p = Figure.pose(k.pose, contacts: family.motion.contacts)
                #expect(p.joints.values.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(family.id)")
            }
        }
    }

    @Test func howToHasSetUpPhasesAndMistakes() throws {
        let push = try #require(Self.catalog.exercise(StarterIDs.pushUp))
        let guide = try #require(Self.catalog.howTo(for: push))
        #expect(guide.steps.first?.kind == .setup)
        #expect(guide.steps.last?.kind == .mistakes)
        let phases = guide.steps.filter { $0.kind == .phase }
        #expect(phases.map(\.title) == ["Lower", "Bottom", "Press", "Plus"])
        // "Bottom" plays from Lower to Bottom.
        let bottom = try #require(phases.first { $0.title == "Bottom" })
        #expect(bottom.window.lowerBound < bottom.window.upperBound)
        // The elbow cue lands on a step that talks about elbows.
        let elbowCue = guide.steps.first { $0.cues.contains { $0.joint == "elbows" } }
        #expect(elbowCue?.body.lowercased().contains("elbow") == true)
    }
}

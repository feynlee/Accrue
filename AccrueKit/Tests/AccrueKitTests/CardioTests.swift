import Foundation
import Testing
@testable import AccrueKit

@Suite struct CardioTests {
    @Test func zonesSplitTheMaxHeartRate() {
        let zones = HeartZones(maxHR: 190)
        #expect(zones.range(2) == 114...132)
        #expect(zones.range(5) == 171...190)
        #expect(zones.zone(for: 120) == 2)
        #expect(zones.zone(for: 133) == 3)
        #expect(zones.zone(for: 90) == 1)
        #expect(zones.zone(for: 200) == 5)
        // The zones meet without gaps.
        for z in 1...4 { #expect(zones.range(z).upperBound + 1 == zones.range(z + 1).lowerBound) }
    }

    @Test func routeDistanceSkipsRoughFixesAndPauses() {
        var route = RouteDistance()
        let start = RouteDistance.Point(latitude: 40.0, longitude: -74.0)
        // About 11 m per 0.0001° of latitude.
        func north(_ n: Int) -> RouteDistance.Point { .init(latitude: 40.0 + Double(n) * 0.0001, longitude: -74.0) }
        route.add(start, accuracy: 5, paused: false)
        for i in 1...10 { route.add(north(i), accuracy: 5, paused: false) }
        #expect(abs(route.meters - 111) < 2)
        route.add(north(11), accuracy: 80, paused: false)        // rough fix: ignored
        route.add(north(12), accuracy: 5, paused: true)          // paused: not counted
        route.add(north(30), accuracy: 5, paused: false)         // picks up here
        route.add(north(31), accuracy: 5, paused: false)
        #expect(abs(route.meters - 122) < 2)
        route.add(north(200), accuracy: 5, paused: false)        // a jump: noise
        #expect(abs(route.meters - 122) < 2)
    }

    @Test func distanceAndPaceFollowTheUnit() {
        #expect(WeightUnit.lb.formatDistance(meters: 1609.344 * 2.87) == "2.87")
        #expect(WeightUnit.kg.formatDistance(meters: 5000) == "5.00")
        #expect(WeightUnit.kg.formatPace(seconds: 1800, meters: 5000) == "6'00\"")
        #expect(WeightUnit.lb.formatPace(seconds: 590 * 2, meters: 1609.344 * 2) == "9'50\"")
        #expect(WeightUnit.kg.formatPace(seconds: 60, meters: 0) == nil)
    }

    @Test func startingARunSetsItsGoal() throws {
        var data = AccrueData.starter()
        let wednesday = DayKey.today().startOfWeek().adding(days: 2)
        let run = try #require(data.parts(on: wednesday).first { $0.timedID == nil })
        let session = data.startSession(day: wednesday, partID: run.id, title: "Run")
        #expect(session.goalSeconds == 30 * 60)
        data.updateSession(session.id) { $0.goalSeconds = ($0.goalSeconds ?? 0) + 300; $0.distanceMeters = 1200 }
        #expect(data.sessions.last?.goalSeconds == 35 * 60)
        #expect(data.sessions.last?.distanceMeters == 1200)
        if case .exercise(let item) = run.content { #expect(item.targetZone == 2) }
    }

    @Test func targetDefaultsToLastTimeAndNeverStopsTheClock() throws {
        let last = DaySummary(day: DayKey.today().adding(days: -2),
                              sets: [LoggedSet(day: DayKey.today().adding(days: -2), exerciseID: StarterIDs.run,
                                               distanceMeters: 5100, durationSeconds: 1880)],
                              tracking: .distanceTimeHR)
        var data = AccrueData.starter()
        #expect(data.cardioTarget(for: StarterIDs.run) == .lastTime)

        var session = WorkoutSession(day: .today(), partID: nil, title: "Run", startedAt: Date())
        session.setGoal(.lastTime, last: last, plannedMinutes: 30)
        #expect(session.goalSeconds == 1880 && session.goalMeters == nil && session.goalIsLastTime == true)
        #expect(!session.reachedGoal(active: 1879))
        #expect(session.reachedGoal(active: 1880))
        #expect(session.isActive)

        // No history: the plan's minutes.
        session.setGoal(.lastTime, last: nil, plannedMinutes: 30)
        #expect(session.goalSeconds == 1800 && session.goalIsLastTime == false)

        // Last time's distance, then the user's own 6 km.
        session.setGoal(CardioTarget(metric: .distance), last: last, plannedMinutes: 30)
        #expect(session.goalMeters == 5100 && session.goalSeconds == nil)
        session.distanceMeters = 5200
        #expect(session.reachedGoal(active: 10))
        let own = CardioTarget(metric: .distance, value: 6000)
        data.setCardioTarget(own, for: StarterIDs.run)
        #expect(data.cardioTarget(for: StarterIDs.run) == own)
        session.setGoal(own, last: last, plannedMinutes: 30)
        #expect(!session.reachedGoal(active: 10) && session.goalIsLastTime == false)
        data.setCardioTarget(.lastTime, for: StarterIDs.run)
        #expect(data.cardioTargets.isEmpty)
    }

    @Test func runsAreSplitOutdoorAndTreadmill() throws {
        let c = try Catalog.bundled()
        let outdoor = try #require(c.exercise(StarterIDs.run))
        let treadmill = try #require(c.exercise(StarterIDs.treadmillRun))
        #expect(outdoor.displayName == "Outdoor run" && outdoor.isOutdoor && outdoor.healthKit == "running")
        #expect(treadmill.displayName == "Treadmill run" && !treadmill.isOutdoor && treadmill.location == "indoor")
        #expect(c.tracking(for: treadmill) == .distanceTimeHR)
        #expect(c.howTo(for: outdoor)?.keyframes.isEmpty == false)
        #expect(c.howTo(for: treadmill)?.bodyModel == "skin")
    }

    @Test func timeInZoneCountsOnlyInZoneAndUnpaused() {
        let zones = HeartZones(maxHR: 190) // Z2 = 114...132
        var session = WorkoutSession(day: .today(), partID: nil, title: "Run", startedAt: Date(timeIntervalSince1970: 0))
        session.setGoal(CardioTarget(metric: .zoneTime), last: nil, plannedMinutes: 1, zone: 2)
        #expect(session.goalZone == 2 && session.goalSeconds == 60 && session.goalMeters == nil)
        var t = Date(timeIntervalSince1970: 0)
        // 30 s in Z2, then 10 s above it, then a 5-minute gap (watch lost) counts 15 s.
        session.recordHeartRate(120, at: t, zones: zones)
        for _ in 0..<6 { t += 5; session.recordHeartRate(125, at: t, zones: zones) }
        t += 5; session.recordHeartRate(150, at: t, zones: zones)
        t += 10; session.recordHeartRate(125, at: t, zones: zones)
        #expect(session.secondsIn(zone: 2) == 35)
        #expect(session.secondsIn(zone: 3) == 10)
        #expect(!session.reachedGoal(active: 9999))
        t += 300; session.recordHeartRate(125, at: t, zones: zones)
        #expect(session.secondsIn(zone: 2) == 50)
        // Paused time doesn't count.
        session.pausedAt = t
        t += 5; session.recordHeartRate(125, at: t, zones: zones)
        #expect(session.secondsIn(zone: 2) == 50)
        session.pausedAt = nil
        for _ in 0..<2 { t += 5; session.recordHeartRate(125, at: t, zones: zones) }
        #expect(session.reachedGoal(active: 0))
        #expect(session.goalProgress(active: 0) == 1)
    }

    @Test func watchMessagesRoundTripAndFeedTheSession() throws {
        let setup = WorkoutLink.Message.setup(.init(title: "Outdoor run", maxHR: 190, targetZone: 2, goalSeconds: 1500, goalZone: 2))
        #expect(WorkoutLink.decode(WorkoutLink.encode(setup)) == setup)
        #expect(WorkoutLink.decode(WorkoutLink.encode(.command(.pause))) == .command(.pause))
        #expect(WorkoutLink.decode(Data("{}".utf8)) == nil)

        var session = WorkoutSession(day: .today(), partID: nil, title: "Run", startedAt: Date(timeIntervalSince1970: 0))
        session.distanceMeters = 800 // phone GPS
        let zones = HeartZones(maxHR: 190)
        session.apply(.init(heartRate: 120, activeKcal: 40, meters: 750, at: Date(timeIntervalSince1970: 0)), zones: zones)
        session.apply(.init(heartRate: 125, activeKcal: 42, meters: 820, at: Date(timeIntervalSince1970: 5)), zones: zones)
        #expect(session.heartRate == 125 && session.activeKcal == 42)
        #expect(session.distanceMeters == 820)
        #expect(session.secondsIn(zone: 2) == 5)
    }
}

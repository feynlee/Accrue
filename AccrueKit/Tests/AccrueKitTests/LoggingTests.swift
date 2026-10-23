import Foundation
import Testing
@testable import AccrueKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func set(_ day: DayKey, _ kg: Double?, _ reps: Int?, warmup: Bool = false, hold: Int? = nil,
                 ex: String = "0025", at offset: TimeInterval = 0) -> LoggedSet {
    LoggedSet(day: day, exerciseID: ex, weightKg: kg, reps: reps, holdSeconds: hold, isWarmup: warmup,
              loggedAt: day.date(calendar: utc).addingTimeInterval(offset))
}

@Suite struct DayKeyTests {
    @Test func weekdayIsMondayFirst() {
        // 2026-10-23 is a Friday.
        let day = DayKey(year: 2026, month: 10, day: 23)
        #expect(day.weekday(calendar: utc) == .friday)
        #expect(day.startOfWeek(calendar: utc) == DayKey(year: 2026, month: 10, day: 19))
        #expect(DayKey(year: 2026, month: 10, day: 25).weekday(calendar: utc) == .sunday)
    }

    @Test func addingCrossesMonthsAndRoundTrips() throws {
        let day = DayKey(year: 2026, month: 10, day: 30)
        #expect(day.adding(days: 3, calendar: utc) == DayKey(year: 2026, month: 11, day: 2))
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-30\"]")
        #expect(try JSONDecoder().decode([DayKey].self, from: data) == [day])
    }
}

@Suite struct TrainingMathTests {
    let day = DayKey(year: 2026, month: 10, day: 23)

    @Test func estimatedMaxUsesEpley() {
        #expect(TrainingMath.estimatedMax(weightKg: 100, reps: 1) == 100)
        #expect(abs(TrainingMath.estimatedMax(weightKg: 100, reps: 10)! - 133.333) < 0.01)
        #expect(TrainingMath.estimatedMax(weightKg: 100, reps: 15) == nil)
    }

    @Test func lightSetsAndFlaggedSetsAreWarmups() {
        let sets = [set(day, 40, 10), set(day, 60, 5, warmup: true), set(day, 100, 8), set(day, 100, 7), set(day, 70, 10)]
        let working = TrainingMath.workingSets(sets)
        #expect(working.map(\.weightKg) == [100, 100, 70])
        let expected: Double = 800 + 700 + 700
        #expect(TrainingMath.volume(sets) == expected)
    }

    @Test func bodyweightSetsStayWorkingNextToWeightedOnes() {
        let sets = [set(day, 5, 8), set(day, nil, 10), set(day, nil, 9)]
        #expect(TrainingMath.workingSets(sets, tracking: .reps).count == 3)
        #expect(TrainingMath.strength(sets, tracking: .reps) == 10)
    }

    @Test func holdsTrackTheLongestHold() {
        let sets = [set(day, nil, nil, hold: 40), set(day, nil, nil, hold: 52)]
        #expect(TrainingMath.strength(sets, tracking: .hold) == 52)
    }
}

@Suite struct HistoryTests {
    let today = DayKey(year: 2026, month: 10, day: 23)

    @Test func lastTimeLine() throws {
        let before = today.adding(days: -3, calendar: utc)
        let sets = [set(before, 20, 10, warmup: true)] + (0..<5).map { set(before, 45.359_237, $0 == 4 ? 8 : 9, at: Double($0)) }
        let history = ExerciseHistory(exerciseID: "0025", tracking: .weightReps, sets: sets)
        let last = try #require(history.lastTime(before: today))
        #expect(last.workingSets == 5)
        #expect(last.typicalReps == 9)
        #expect(last.line(unit: .lb, tracking: .weightReps) == "100 × 9 × 5")
        #expect(last.line(unit: .kg, tracking: .weightReps) == "45.4 × 9 × 5")
    }

    @Test func comparesWithFourWeeksAgo() throws {
        let old = today.adding(days: -30, calendar: utc)
        let sets = [set(old, 100, 5), set(today, 105, 5)]
        let history = ExerciseHistory(exerciseID: "0025", tracking: .weightReps, sets: sets)
        let change = try #require(history.strengthChange(on: today, calendar: utc))
        #expect(abs(change - 5) < 0.001)
    }

    @Test func suggestionPrefersTodayThenLastTimeThenPlan() {
        let plan = PlannedExercise(exerciseID: "0025", sets: 4, reps: 8, weightKg: 60)
        let lastDay = today.adding(days: -7, calendar: utc)
        let last = DaySummary(day: lastDay, sets: [set(lastDay, 80, 6)], tracking: .weightReps)

        let fromPlan = SetSuggestion(plan: plan, today: [], lastTime: nil, tracking: .weightReps)
        #expect(fromPlan.weightKg == 60 && fromPlan.reps == 8)
        let fromLast = SetSuggestion(plan: plan, today: [], lastTime: last, tracking: .weightReps)
        #expect(fromLast.weightKg == 80 && fromLast.reps == 6)
        let fromToday = SetSuggestion(plan: plan, today: [set(today, 85, 5)], lastTime: last, tracking: .weightReps)
        #expect(fromToday.weightKg == 85 && fromToday.reps == 5)
    }
}

@Suite struct RoutineTests {
    let friday = DayKey(year: 2026, month: 10, day: 23)

    @Test func starterWeekFollowsTheMockups() {
        let data = AccrueData.starter()
        let catalog = Catalog.empty
        #expect(data.routine[.monday].map { data.title(of: $0, catalog: catalog) } == ["Push"])
        #expect(data.routine[.friday].map { data.title(of: $0, catalog: catalog) } == ["Pull B"])
        #expect(data.routine[.sunday].isEmpty)
        #expect(data.parts(on: friday, calendar: utc).count == 1)
    }

    @Test func todayOnlyEditLeavesTheRoutineAlone() {
        var data = AccrueData.starter()
        let extra = DayPart.exercise(PlannedExercise(exerciseID: StarterIDs.plank, sets: 3, reps: nil, holdSeconds: 45))
        let parts = data.parts(on: friday, calendar: utc) + [extra]
        data.setParts(parts, on: friday, scope: .thisDayOnly, calendar: utc)
        #expect(data.parts(on: friday, calendar: utc).count == 2)
        #expect(data.parts(on: friday.adding(days: 7, calendar: utc), calendar: utc).count == 1)

        data.setParts(parts, on: friday, scope: .everyWeek, calendar: utc)
        #expect(!data.hasOverride(on: friday))
        #expect(data.parts(on: friday.adding(days: 7, calendar: utc), calendar: utc).count == 2)
    }

    @Test func deletingAPresetRemovesItsParts() throws {
        var data = AccrueData.starter()
        let pull = try #require(data.presets.first { $0.name == "Pull" })
        #expect(data.weekdays(using: pull.id) == [.tuesday])
        data.schedule(pull.id, on: .sunday, true)
        #expect(data.weekdays(using: pull.id) == [.tuesday, .sunday])
        data.deletePreset(pull.id)
        #expect(data.routine[.tuesday].isEmpty && data.routine[.sunday].isEmpty)
    }

    @Test func sessionsPauseAndEnd() {
        var data = AccrueData()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let s = data.startSession(day: friday, partID: nil, title: "Pull", at: start)
        data.togglePause(s.id, at: start.addingTimeInterval(600))
        data.togglePause(s.id, at: start.addingTimeInterval(660))
        data.endSession(s.id, at: start.addingTimeInterval(1800))
        let done = data.sessions[0]
        #expect(done.activeSeconds(at: .now) == 1740)
        #expect(done.totalSeconds(at: .now) == 1800)
        #expect(data.activeSession == nil)
    }
}

@Suite struct StoreTests {
    @Test func fileStoreRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("accrue-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONFileStore(url: url)
        #expect(try store.load() == nil)
        var data = AccrueData.starter()
        data.log(LoggedSet(day: DayKey(year: 2026, month: 10, day: 23), exerciseID: "0025", weightKg: 60, reps: 8))
        try store.save(data)
        #expect(try store.load() == data)
    }
}

@Suite struct UnitTests {
    @Test func poundsRoundTripCleanly() {
        let kg = WeightUnit.lb.toKg(100)
        #expect(WeightUnit.lb.format(kg: kg) == "100")
        #expect(WeightUnit.kg.format(kg: 102.5) == "102.5")
        #expect(DurationFormat.clock(75) == "1:15")
        #expect(DurationFormat.clock(3725) == "1:02:05")
    }
}

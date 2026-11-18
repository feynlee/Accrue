import Foundation
import Testing
@testable import AccrueKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func lift(_ day: DayKey, _ kg: Double, _ reps: Int, ex: String = StarterIDs.benchPress, warmup: Bool = false) -> LoggedSet {
    LoggedSet(day: day, exerciseID: ex, weightKg: kg, reps: reps, isWarmup: warmup, loggedAt: day.date(calendar: utc))
}

@Suite struct ProgressTests {
    let friday = DayKey(year: 2026, month: 10, day: 23)

    @Test func comparisonPicksTheRightSession() {
        let days = [-1, -3, -30, -95, -370].map { friday.adding(days: $0, calendar: utc) }
        let sets = days.map { lift($0, 100, 5) } + [lift(friday, 100, 5)]
        let history = ExerciseHistory(exerciseID: StarterIDs.benchPress, tracking: .weightReps, sets: sets)
        #expect(history.compared(.lastTime, to: friday, calendar: utc)?.day == days[0])
        #expect(history.compared(.fourWeeks, to: friday, calendar: utc)?.day == days[2])
        #expect(history.compared(.threeMonths, to: friday, calendar: utc)?.day == days[3])
        #expect(history.compared(.oneYear, to: friday, calendar: utc)?.day == days[4])
        #expect(history.compared(.oneYear, to: days[4], calendar: utc) == nil)
    }

    @Test func weeklyVolumeBucketsMondayFirst() {
        let monday = friday.startOfWeek(calendar: utc)
        let sets = [lift(monday, 100, 10), lift(friday, 50, 10), lift(monday.adding(days: -1, calendar: utc), 80, 10)]
        let history = ExerciseHistory(exerciseID: StarterIDs.benchPress, tracking: .weightReps, sets: sets)
        let weeks = history.weeklyVolume(weeks: 3, endingOn: friday, calendar: utc)
        #expect(weeks.map(\.week) == [monday.adding(days: -14, calendar: utc), monday.adding(days: -7, calendar: utc), monday])
        // The warm-up rule is per day, so the lighter Friday still counts.
        #expect(weeks.map(\.volumeKg) == [0, 800, 1500])
    }

    @Test func dayTotalsSplitStrengthAndCardio() throws {
        let catalog = try Catalog.bundled()
        var data = AccrueData()
        data.log(lift(friday, 100, 10))
        data.log(lift(friday, 40, 10, warmup: true))
        data.log(LoggedSet(day: friday, exerciseID: StarterIDs.run, distanceMeters: 5000, durationSeconds: 1800))
        let totals = data.totals(on: friday, catalog: catalog)
        #expect(totals.workingSets == 1)
        #expect(totals.volumeKg == 1000)
        #expect(totals.cardioSeconds == 1800)
        #expect(totals.cardioMeters == 5000)
        #expect(totals.strengthExercises == [StarterIDs.benchPress])
        #expect(totals.cardioExercises == [StarterIDs.run])
        #expect(data.totals(on: friday.adding(days: 1), catalog: catalog).isEmpty)
        #expect(data.totalsByDay(catalog: catalog) == [friday: totals])
    }

    @Test func intensityLevels() {
        #expect(IntensityLevel.level(volumeKg: 0, hadStrength: false, maxVolumeKg: 100) == 0)
        #expect(IntensityLevel.level(volumeKg: 0, hadStrength: true, maxVolumeKg: 100) == 1)
        #expect(IntensityLevel.level(volumeKg: 50, hadStrength: true, maxVolumeKg: 100) == 2)
        #expect(IntensityLevel.level(volumeKg: 100, hadStrength: true, maxVolumeKg: 100) == 3)
    }
}

@Suite struct WeightStepsTests {
    private let today = DayKey(year: 2026, month: 11, day: 15)

    /// Sets of one exercise on a day `back` days ago: `reps` at `lb` pounds.
    private func session(_ back: Int, lb: Double?, reps: [Int], pause: Int = 0) -> [LoggedSet] {
        let day = today.adding(days: -back, calendar: utc)
        return reps.enumerated().map { i, r in
            LoggedSet(day: day, exerciseID: "x", weightKg: lb.map(WeightUnit.lb.toKg), reps: r, pauseSeconds: pause,
                      loggedAt: day.date(calendar: utc).addingTimeInterval(Double(i) * 120))
        }
    }

    private func steps(_ sets: [LoggedSet], tracking: Tracking = .weightReps, targetSets: Int = 3, reps: Int = 10) -> WeightSteps {
        WeightSteps(sets: sets, tracking: tracking, targetSets: targetSets, targetReps: reps, targetHold: nil,
                    today: today, calendar: utc)
    }

    @Test func aStepEndsWhenTheWeightChanges() {
        let sets = session(40, lb: 100, reps: [10, 10, 10]) + session(33, lb: 100, reps: [10, 10, 10])
            + session(26, lb: 105, reps: [10, 9, 8]) + session(19, lb: 105, reps: [10, 10, 9])
        let s = steps(sets)
        #expect(s.steps.count == 2)
        #expect(s.steps[0].sessions.count == 2)
        #expect(s.days(in: s.steps[0]) == 14)
        #expect(s.daysAtCurrent == 26)
        #expect(s.usualDays == 14)
        #expect(s.label(for: s.steps[1], unit: .lb) == "105 lb")
        #expect(s.level(of: s.steps[0]) == 0)
        #expect(s.level(of: s.steps[1]) == 1)
    }

    @Test func readyNeedsTwoSessionsWithEverySetAtTheTarget() {
        var sets = session(21, lb: 110, reps: [10, 10, 9]) + session(14, lb: 110, reps: [10, 10, 10])
        #expect(steps(sets).verdict == .building(clean: 1))
        sets += session(7, lb: 110, reps: [10, 10, 10])
        #expect(steps(sets).verdict == .ready)
        // Two sets when three are planned is not a full session.
        sets += session(3, lb: 110, reps: [10, 10])
        #expect(steps(sets).verdict == .building(clean: 0))
    }

    @Test func aLiftInTwoPresetsCountsTheShorterDayToo() {
        // Planned 5 × 10 today; the other day's preset has it at 4 × 10.
        let sets = session(7, lb: 110, reps: [10, 10, 10, 10, 10]) + session(3, lb: 110, reps: [10, 10, 10, 10])
        #expect(steps(sets, targetSets: 5).verdict == .ready)
        let short = session(7, lb: 110, reps: [10, 10, 10, 10, 10]) + session(3, lb: 110, reps: [10, 10, 10])
        #expect(steps(short, targetSets: 5).verdict == .building(clean: 0))
    }

    @Test func todaysUnfinishedSessionDoesNotTakeReadyAway() {
        var sets = session(14, lb: 110, reps: [10, 10, 10]) + session(7, lb: 110, reps: [10, 10, 10])
        sets += session(0, lb: 110, reps: [10])
        #expect(steps(sets).verdict == .ready)
        // Moving up today starts a new step.
        let moved = sets.dropLast() + session(0, lb: 115, reps: [8])
        let s = steps(Array(moved))
        #expect(s.steps.count == 2)
        #expect(s.verdict == .new)
        #expect(s.daysAtCurrent == 0)
    }

    @Test func warmUpsAndLighterSetsDoNotCount() {
        var sets = session(7, lb: 110, reps: [10, 10, 10])
        sets.append(LoggedSet(day: today.adding(days: -7, calendar: utc), exerciseID: "x",
                              weightKg: WeightUnit.lb.toKg(55), reps: 10, isWarmup: true))
        let s = steps(sets)
        #expect(s.steps[0].sessions[0].values == [10, 10, 10])
        #expect(s.steps[0].sessions[0].hitTarget)
    }

    @Test func stalledAfterSixWeeksWithNoMoreReps() {
        var sets: [LoggedSet] = []
        for back in stride(from: 49, through: 7, by: -7) { sets += session(back, lb: 60, reps: [10, 9, 8]) }
        #expect(steps(sets).verdict == .stalled)
        // Still adding reps: not stalled.
        sets += session(3, lb: 60, reps: [10, 10, 9])
        #expect(steps(sets).verdict == .building(clean: 0))
    }

    @Test func aPauseIsAHarderStepAtTheSameWeight() {
        let sets = session(21, lb: nil, reps: [15, 15, 15]) + session(14, lb: nil, reps: [12, 11, 10], pause: 2)
        let s = steps(sets, tracking: .reps, reps: 15)
        #expect(s.steps.count == 2)
        #expect(s.level(of: s.steps[1]) == 1)
        #expect(s.label(for: s.steps[0], unit: .lb) == "Bodyweight")
        #expect(s.label(for: s.steps[1], unit: .lb, short: true) == "BW · 2 s")
    }

    @Test func spans() {
        #expect(SpanFormat.exact(days: 33) == "4 wk 5 d")
        #expect(SpanFormat.exact(days: 28) == "4 wk")
        #expect(SpanFormat.exact(days: 5) == "5 d")
        #expect(SpanFormat.exact(days: 0) == "today")
        #expect(SpanFormat.rough(days: 21) == "3 wk")
        #expect(SpanFormat.rough(days: 24) == "3½ wk")
    }

    @Test func demoHasStepsAndALiftReadyToGoUp() {
        let data = AccrueData.demo(today: today, calendar: utc)
        let s = WeightSteps(sets: data.history(of: StarterIDs.pulldown), tracking: .weightReps, targetSets: 4,
                            targetReps: 10, targetHold: nil, today: today, calendar: utc)
        #expect(s.steps.count == 5)
        #expect(s.verdict == .ready)
        let curl = WeightSteps(sets: data.history(of: StarterIDs.hammerCurl), tracking: .weightReps, targetSets: 3,
                               targetReps: 12, targetHold: nil, today: today, calendar: utc)
        #expect(curl.verdict == .stalled)
    }
}

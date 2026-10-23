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

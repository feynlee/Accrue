import Foundation
import Testing
@testable import AccrueKit

struct QuickLogTests {
    @Test func readsPlainWorkoutWords() {
        #expect(QuickLog.parse("Pulls 100, six by ten") == QuickLog(name: "pulls", weight: 100, reps: 10, sets: 6))
        #expect(QuickLog.parse("3 sets of pull-ups, 8 each") == QuickLog(name: "pull ups", reps: 8, sets: 3))
        #expect(QuickLog.parse("squat 185 x 5 x 3") == QuickLog(name: "squat", weight: 185, reps: 5, sets: 3))
        #expect(QuickLog.parse("bench 70kg for 5") == QuickLog(name: "bench", weight: 70, unit: .kg, reps: 5))
        #expect(QuickLog.parse("bench 155 for 5") == QuickLog(name: "bench", weight: 155, reps: 5))
        #expect(QuickLog.parse("pull-ups 3x8") == QuickLog(name: "pull ups", reps: 8, sets: 3))
        #expect(QuickLog.parse("curl 30lb 12 reps") == QuickLog(name: "curl", weight: 30, unit: .lb, reps: 12))
        #expect(QuickLog.parse("plank 45 sec") == QuickLog(name: "plank", holdSeconds: 45))
        #expect(QuickLog.parse("ran 5k in 28:30") == QuickLog(name: "run", meters: 5000, seconds: 1710))
        #expect(QuickLog.parse("What should I do if the pulldown machine is taken?") == nil)
        #expect(QuickLog.parse("Plan next week") == nil)
    }

    @Test func findsTheExerciseOnTodaysPlanFirst() throws {
        let catalog = try Catalog.bundled()
        let data = AccrueData.starter()
        // A day whose plan has the pulldown (Pull).
        let start = DayKey(year: 2026, month: 10, day: 19)
        let day = try #require((0..<7).map { start.adding(days: $0) }.first { d in
            data.parts(on: d).contains { data.items(in: $0).first?.exerciseID == StarterIDs.pulldown }
        })
        let logger = QuickLogger(catalog: catalog, day: day)
        #expect(logger.exercise(named: "pulls", in: data)?.id == StarterIDs.pulldown)
        #expect(logger.exercise(named: "pull ups", in: data)?.id == StarterIDs.pullUp)
        #expect(logger.exercise(named: "bench", in: data) != nil)
    }

    @Test func logsEachSetAndSaysWhatItDid() throws {
        let catalog = try Catalog.bundled()
        var data = AccrueData.starter()
        let start = DayKey(year: 2026, month: 10, day: 19)
        let day = try #require((0..<7).map { start.adding(days: $0) }.first { d in
            data.parts(on: d).contains { data.items(in: $0).first?.exerciseID == StarterIDs.pulldown }
        })
        let logger = QuickLogger(catalog: catalog, day: day)
        let entry = try #require(QuickLog.parse("Pulls 100, six by ten"))
        let exercise = try #require(logger.exercise(named: entry.name, in: data))
        let sets = logger.log(entry, exercise: exercise, unit: .lb, into: &data)
        #expect(sets.count == 6)
        #expect(sets.allSatisfy { $0.reps == 10 && $0.partID != nil })
        #expect(abs((sets[0].weightKg ?? 0) - 100 / WeightUnit.poundsPerKilogram) < 0.001)
        #expect(logger.confirmation(sets, exercise: exercise, unit: .lb).hasSuffix("100 lb, 6 × 10."))
        #expect(logger.nextUp(after: exercise.id, in: data, unit: .lb)?.contains("is next") == true)
    }
}

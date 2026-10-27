import Foundation
import Testing
@testable import AccrueKit

struct AssistantTests {
    static let locale = Locale(identifier: "en_US")
    static let monday = DayKey(year: 2026, month: 10, day: 19)

    /// The starter week's day that has the pulldown first.
    func pullDay(_ data: AccrueData) throws -> DayKey {
        try #require((0..<7).map { Self.monday.adding(days: $0) }.first { d in
            data.parts(on: d).contains { data.items(in: $0).first?.exerciseID == StarterIDs.pulldown }
        })
    }

    func assistant(_ data: AccrueData, today: DayKey) throws -> Assistant {
        Assistant(catalog: try Catalog.bundled(), data: data, unit: .lb, today: today, locale: Self.locale)
    }

    func bench(_ data: inout AccrueData, on day: DayKey, lb: Double, reps: Int, sets: Int) {
        for n in 0..<sets {
            data.log(LoggedSet(day: day, exerciseID: StarterIDs.benchPress, weightKg: WeightUnit.lb.toKg(lb), reps: reps,
                               loggedAt: day.date().addingTimeInterval(3600 + Double(n))))
        }
    }

    @Test func saysTheDaysPlanWithLastTime() throws {
        var data = AccrueData.starter()
        let day = try pullDay(data)
        data.log(LoggedSet(day: day.adding(days: -7), exerciseID: StarterIDs.pulldown, weightKg: WeightUnit.lb.toKg(100), reps: 10))
        let plan = try assistant(data, today: day).plan(on: day)
        #expect(plan.hasPrefix("Today's plan is "))
        #expect(plan.contains("5 × 10 (last time 100 × 10 × 1)"))
        let rest = try #require((0..<7).map { Self.monday.adding(days: $0) }.first { data.parts(on: $0).isEmpty })
        #expect(try assistant(data, today: day).plan(on: rest).contains("is a rest day"))
    }

    @Test func saysWhatWasDoneAndTheWeek() throws {
        var data = AccrueData.starter()
        let today = Self.monday.adding(days: 2)
        bench(&data, on: today.adding(days: -1), lb: 155, reps: 8, sets: 3)
        let a = try assistant(data, today: today)
        #expect(a.log(on: today) == "Nothing is logged today.")
        let yesterday = a.log(on: today.adding(days: -1))
        #expect(yesterday.hasPrefix("Yesterday you did "))
        #expect(yesterday.contains("155 × 8 × 3"))
        #expect(yesterday.hasSuffix("3 working sets, 3,720 lb lifted."))
        #expect(a.lastWorkout() == yesterday)
        let week = a.week(of: today)
        #expect(week.hasPrefix("This week: 1 workout day (Tue), 3 working sets and 3,720 lb lifted."))
    }

    @Test func comparesProgressWithFourWeeksAgo() throws {
        var data = AccrueData.starter()
        let today = Self.monday.adding(days: 28)
        bench(&data, on: Self.monday, lb: 150, reps: 5, sets: 3)
        bench(&data, on: today, lb: 165, reps: 5, sets: 3)
        let a = try assistant(data, today: today)
        let progress = a.progress(of: StarterIDs.benchPress)
        #expect(progress.contains("last time, today, 165 × 5 × 3."))
        #expect(progress.contains("Estimated max 192.5 lb, up 10% from 4 weeks ago."))
        #expect(a.personalBest(of: StarterIDs.benchPress).contains("estimated max 192.5 lb, today (165 × 5 × 3)"))
        #expect(a.progress(of: StarterIDs.squat).hasSuffix("isn't logged yet."))
    }

    @Test func picksThePartToStartAndWhatIsNext() throws {
        var data = AccrueData.starter()
        let day = try pullDay(data)
        let first = try #require(data.partToStart(on: day))
        #expect(data.items(in: first).first?.exerciseID == StarterIDs.pulldown)
        let session = data.startSession(day: day, partID: first.id, title: "Pull")
        #expect(try assistant(data, today: day).nextUp().hasPrefix("Next is "))
        data.log(LoggedSet(day: day, exerciseID: StarterIDs.pulldown, partID: first.id, sessionID: session.id,
                           weightKg: 45, reps: 10))
        #expect(data.partToStart(on: day)?.id != first.id)
        #expect(try assistant(data, today: day).nextUp().contains("4 sets to go"))
    }

    @Test func swapsAddsAndUndoes() throws {
        var data = AccrueData.starter()
        let day = try pullDay(data)
        // In a preset: the preset changes.
        guard case .preset(let name)? = data.swap(StarterIDs.pulldown, for: StarterIDs.pullUp, on: day) else {
            Issue.record("expected a preset swap"); return
        }
        #expect(!name.isEmpty)
        // On its own: only that day changes.
        let part = data.add(PlannedExercise(exerciseID: StarterIDs.plank, sets: 3, reps: nil, holdSeconds: 45), on: day)
        #expect(data.add(PlannedExercise(exerciseID: StarterIDs.plank), on: day).id == part.id)
        #expect(data.swap(StarterIDs.plank, for: StarterIDs.farmersWalk, on: day) == .day)
        #expect(data.parts(on: day.adding(days: 7)).allSatisfy { data.items(in: $0).allSatisfy { $0.exerciseID != StarterIDs.farmersWalk } })
        #expect(data.remove(StarterIDs.farmersWalk, from: day) == .day)
        #expect(data.swap("nope", for: StarterIDs.plank, on: day) == nil)

        bench(&data, on: day, lb: 100, reps: 5, sets: 2)
        let newest = try #require(data.sets.max { $0.loggedAt < $1.loggedAt })
        #expect(data.undoLastSet()?.id == newest.id)
        #expect(data.sets.count == 1)
    }
}

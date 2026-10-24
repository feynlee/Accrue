import Foundation
import Testing
@testable import AccrueKit

@Suite struct TimedTests {
    let seven = TimedExercise.template(.sevenMinute)

    @Test func sevenMinuteIsTwelveMovesInSevenFifty() {
        #expect(seven.moves.count == 12)
        #expect(seven.totalSeconds() == 7 * 60 + 50)
        let list = seven.intervals()
        #expect(list.filter { $0.kind == .work }.count == 12)
        #expect(list.filter { $0.kind == .rest }.count == 11)
        #expect(list.first?.kind == .work && list.last?.kind == .work)
    }

    @Test func roundsGetABreakBetweenThem() {
        let hiit = TimedExercise.template(.hiit)
        let list = hiit.intervals()
        #expect(list.filter { $0.kind == .roundRest }.count == 2)
        #expect(list.map(\.seconds).reduce(0, +) == hiit.totalSeconds())
        // The break leads into round 2's first move.
        let i = list.firstIndex { $0.kind == .roundRest }!
        #expect(list[i + 1].kind == .work && list[i + 1].round == 2 && list[i + 1].move == 0)
    }

    @Test func everyTemplateMoveIsInTheCatalog() {
        let catalog = CatalogTests.catalog
        for style in TimedStyle.allCases {
            for id in TimedExercise.template(style).moves {
                #expect(catalog.exercise(id) != nil, "\(style) \(id)")
            }
        }
        for (area, ids) in TimedMoves.byArea {
            for id in ids {
                #expect(catalog.exercise(id) != nil, "\(id)")
                #expect(catalog.timedArea(of: id) == area)
            }
        }
    }

    @Test func timerFollowsThePlanWithNoTaps() {
        let timer = TimedTimer(rounds: 1)
        var p = timer.position(in: seven, at: 0)
        #expect(p.index == 0 && p.secondsLeft == 30 && p.interval?.kind == .work)
        p = timer.position(in: seven, at: 31)
        #expect(p.interval?.kind == .rest && p.interval?.move == 1 && p.secondsLeft == 9)
        p = timer.position(in: seven, at: 40)
        #expect(p.interval?.kind == .work && p.interval?.move == 1 && p.worksDone == 1)
        p = timer.position(in: seven, at: TimeInterval(seven.totalSeconds()))
        #expect(p.finished && p.worksDone == 12)
    }

    @Test func skipBackAndTenSeconds() {
        var timer = TimedTimer(rounds: 1)
        timer.skip(in: seven, at: 5)                       // into the first rest
        #expect(timer.position(in: seven, at: 5).interval?.kind == .rest)
        timer.skip(in: seven, at: 6)                       // into move 2
        #expect(timer.position(in: seven, at: 6).interval?.move == 1)
        timer.back(in: seven, at: 7)                       // 1 s in: back to move 1
        #expect(timer.position(in: seven, at: 7).interval?.move == 0)
        timer.back(in: seven, at: 17)                      // 10 s in: restart move 1
        let p = timer.position(in: seven, at: 17)
        #expect(p.interval?.move == 0 && p.secondsLeft == 30)
        timer.addTen(in: seven, at: 27)
        #expect(timer.position(in: seven, at: 27).secondsLeft == 30)
        #expect(timer.position(in: seven, at: 56).interval?.kind == .work)
        #expect(timer.position(in: seven, at: 58).interval?.kind == .rest)
    }

    @Test func addingARoundStartsTheMovesAgain() {
        var timer = TimedTimer(rounds: 1)
        let end = TimeInterval(seven.totalSeconds())
        #expect(timer.position(in: seven, at: end).finished)
        timer.addRound(in: seven, at: end)
        let p = timer.position(in: seven, at: end)
        #expect(!p.finished && p.interval?.round == 2 && p.interval?.move == 0 && p.secondsLeft == 30)
        #expect(p.workCount == 24)
    }

    @Test func oldFilesWithoutTimedStillLoad() throws {
        var data = AccrueData.starter()
        data.timed = []
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
        json.removeValue(forKey: "timed")
        // Old files had no timed parts either.
        json["routine"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WeekRoutine()))
        let old = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder().decode(AccrueData.self, from: old)
        #expect(loaded.timed.isEmpty)
        #expect(loaded.presets.count == data.presets.count)
    }

    @Test func starterWednesdayHasTheSevenMinute() throws {
        let data = AccrueData.starter()
        let part = try #require(data.routine[.wednesday].first)
        #expect(data.timedExercise(in: part)?.name == "7-minute classic")
        #expect(data.title(of: part, catalog: CatalogTests.catalog) == "7-minute classic")
        var copy = data
        copy.deleteTimed(part.timedID!)
        #expect(!copy.routine[.wednesday].contains { $0.timedID != nil })
    }
}

extension TimedTests {
    @Test func startingATimedPartStartsItsTimer() throws {
        var data = AccrueData.starter()
        let wednesday = DayKey.today().startOfWeek().adding(days: 2)
        let part = try #require(data.parts(on: wednesday).first)
        let session = data.startSession(day: wednesday, partID: part.id, title: "7-minute classic")
        #expect(session.timer?.rounds == 1)
        let plan = try #require(data.timedExercise(in: part))
        data.updateTimer(session.id) { $0.skip(in: plan, at: 3) }
        #expect(data.sessions.last?.timer?.index == 1)
    }
}

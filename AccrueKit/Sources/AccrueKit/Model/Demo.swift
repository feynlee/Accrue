import Foundation

extension AccrueData {
    /// The starter week with sixteen weeks of made-up history before `today`, for screenshots and
    /// previews. The app only uses it when launched with `-demoData YES`; it is never saved.
    ///
    /// Lifts go up one plate about every three weeks and have been at the latest weight for four,
    /// with the reps filling in toward the target inside each step, so the weight-steps chart
    /// has real steps to show.
    public static func demo(today: DayKey = .today(), calendar: Calendar = .current) -> AccrueData {
        var data = AccrueData.starter()
        let base: [String: Double] = [
            StarterIDs.benchPress: 60, StarterIDs.militaryPress: 40, StarterIDs.pushdown: 25,
            StarterIDs.pulldown: 45, StarterIDs.seatedRow: 50, StarterIDs.facePull: 20,
            StarterIDs.squat: 80, StarterIDs.romanianDeadlift: 70, StarterIDs.legPress: 120,
            StarterIDs.calfRaise: 60, StarterIDs.bentOverRow: 55, StarterIDs.hammerCurl: 14,
            StarterIDs.deadlift: 100, StarterIDs.farmersWalk: 24,
        ]
        // How far through its latest step each lift first hits every set: some are ready to go
        // up, some one session short, some still building.
        let cleanFrom: [String: Double] = [
            StarterIDs.pulldown: 0.7, StarterIDs.benchPress: 0.6, StarterIDs.squat: 0.85,
            StarterIDs.seatedRow: 0.85, StarterIDs.militaryPress: 1.1, StarterIDs.deadlift: 0.6,
        ]
        let liftDays = 112
        // Runs go back about five months, so the cardio trend lines have something to show.
        for back in stride(from: 140, to: liftDays, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            for part in data.parts(on: day, calendar: calendar)
            where data.items(in: part).contains(where: { $0.exerciseID == StarterIDs.run }) {
                data.log(run(day: day, partID: part.id, back: back, calendar: calendar))
            }
        }
        for back in stride(from: liftDays, through: 1, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            let elapsed = liftDays - back
            let week = elapsed / 7
            var clock = day.date(calendar: calendar).addingTimeInterval(6 * 3600)
            for part in data.parts(on: day, calendar: calendar) {
                for item in data.items(in: part) {
                    let id = item.exerciseID
                    if id == StarterIDs.run {
                        data.log(run(day: day, partID: part.id, back: back, calendar: calendar))
                        continue
                    }
                    if let hold = item.holdSeconds {
                        for _ in 0..<item.sets {
                            clock += 90
                            data.log(LoggedSet(day: day, exerciseID: id, partID: part.id,
                                               holdSeconds: hold + (week / 3) * 3, loggedAt: clock))
                        }
                        continue
                    }
                    // Steps of three weeks, the latest one four. The hammer curl never left its
                    // third weight, to show a stall.
                    let stalled = id == StarterIDs.hammerCurl
                    let step = min(week / 3, stalled ? 2 : 4)
                    let stepStart = step * 21
                    let stepDays = stalled ? liftDays - stepStart : (step == 4 ? 28 : 21)
                    let through = Double(elapsed - stepStart) / Double(stepDays)
                    // Whole 5 lb steps, so the numbers look like real plates in either unit.
                    let weight = base[id].map { kg -> Double in
                        let start = (kg * 0.95 * WeightUnit.poundsPerKilogram / 5).rounded() * 5
                        return WeightUnit.lb.toKg(start + Double(step) * (start >= 150 ? 10 : 5))
                    }
                    if let weight, id != StarterIDs.farmersWalk {
                        clock += 90
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, weightKg: WeightUnit.lb.toKg((WeightUnit.lb.fromKg(weight) * 0.5 / 5).rounded() * 5),
                                           reps: 10, isWarmup: true, loggedAt: clock))
                    }
                    // Reps still missing today, taken from the last sets first.
                    let missing: Int
                    if weight == nil {
                        // Bodyweight: the same level throughout, a rep more every few weeks.
                        missing = 0
                    } else if stalled {
                        missing = 2
                    } else {
                        let from = cleanFrom[id] ?? 0.9
                        missing = through >= from ? 0 : Int(((from - through) / from * 4).rounded(.up))
                    }
                    let bodyweightGain = weight == nil ? min(week, 15) / 4 - 2 : 0
                    for set in 0..<item.sets {
                        clock += TimeInterval(item.restSeconds + 40)
                        let fromEnd = item.sets - 1 - set
                        let short = max(0, min(2, missing - 2 * fromEnd))
                        let reps = item.reps.map { $0 - short + bodyweightGain - (weight == nil && fromEnd == 0 ? 1 : 0) }
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, weightKg: weight, reps: reps,
                                           distanceMeters: id == StarterIDs.farmersWalk ? 40 : nil,
                                           pauseSeconds: item.pauseSeconds, loggedAt: clock))
                    }
                }
            }
        }
        return data
    }

    /// One made-up run: a little longer and faster each week, with some day-to-day noise.
    private static func run(day: DayKey, partID: UUID, back: Int, calendar: Calendar) -> LoggedSet {
        let x = Double(back)
        let meters = (5300 - x * 12 + 180 * sin(x * 1.7)).rounded()
        let seconds = 30 * 60 + Int(90 * cos(x * 0.9)) + back * 2
        return LoggedSet(day: day, exerciseID: StarterIDs.run, partID: partID, distanceMeters: meters,
                         durationSeconds: seconds, loggedAt: day.date(calendar: calendar).addingTimeInterval(7 * 3600))
    }
}

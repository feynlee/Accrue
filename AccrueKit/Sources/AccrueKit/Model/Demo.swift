import Foundation

extension AccrueData {
    /// The starter week with five weeks of made-up history before `today`, for screenshots and
    /// previews. The app only uses it when launched with `-demoData YES`; it is never saved.
    public static func demo(today: DayKey = .today(), calendar: Calendar = .current) -> AccrueData {
        var data = AccrueData.starter()
        let base: [String: Double] = [
            StarterIDs.benchPress: 60, StarterIDs.militaryPress: 40, StarterIDs.pushdown: 25,
            StarterIDs.pulldown: 45, StarterIDs.seatedRow: 50, StarterIDs.facePull: 20,
            StarterIDs.squat: 80, StarterIDs.romanianDeadlift: 70, StarterIDs.legPress: 120,
            StarterIDs.calfRaise: 60, StarterIDs.bentOverRow: 55, StarterIDs.hammerCurl: 14,
            StarterIDs.deadlift: 100, StarterIDs.farmersWalk: 24,
        ]
        // Runs go back about five months, so the cardio trend lines have something to show.
        for back in stride(from: 140, to: 35, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            for part in data.parts(on: day, calendar: calendar)
            where data.items(in: part).contains(where: { $0.exerciseID == StarterIDs.run }) {
                data.log(run(day: day, partID: part.id, back: back, calendar: calendar))
            }
        }
        for back in stride(from: 35, through: 1, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            let week = Double(5 - back / 7)
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
                                               holdSeconds: hold + Int(week) * 3, loggedAt: clock))
                        }
                        continue
                    }
                    // Whole 5 lb steps, so the numbers look like real plates in either unit.
                    let weight = base[id].map { kg -> Double in
                        let lb = (kg * (1 + 0.025 * week) * WeightUnit.poundsPerKilogram / 5).rounded() * 5
                        return WeightUnit.lb.toKg(lb)
                    }
                    if let weight, id != StarterIDs.farmersWalk {
                        clock += 90
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, weightKg: WeightUnit.lb.toKg((WeightUnit.lb.fromKg(weight) * 0.5 / 5).rounded() * 5),
                                           reps: 10, isWarmup: true, loggedAt: clock))
                    }
                    for set in 0..<item.sets {
                        clock += TimeInterval(item.restSeconds + 40)
                        let reps = item.reps.map { $0 - (set == item.sets - 1 ? 1 : 0) }
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, weightKg: weight,
                                           reps: reps.map { $0 + (base[id] == nil ? Int(week) : 0) },
                                           distanceMeters: id == StarterIDs.farmersWalk ? 40 : nil, loggedAt: clock))
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

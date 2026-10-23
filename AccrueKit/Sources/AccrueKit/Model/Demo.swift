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
        for back in stride(from: 35, through: 1, by: -1) {
            let day = today.adding(days: -back, calendar: calendar)
            let week = Double(5 - back / 7)
            var clock = day.date(calendar: calendar).addingTimeInterval(6 * 3600)
            for part in data.parts(on: day, calendar: calendar) {
                for item in data.items(in: part) {
                    let id = item.exerciseID
                    if id == StarterIDs.run {
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, distanceMeters: 4800 + week * 100,
                                           durationSeconds: 30 * 60, loggedAt: clock))
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
                    let weight = base[id].map { ($0 * (1 + 0.025 * week) / 2.5).rounded() * 2.5 }
                    if let weight, id != StarterIDs.farmersWalk {
                        clock += 90
                        data.log(LoggedSet(day: day, exerciseID: id, partID: part.id, weightKg: (weight * 0.5).rounded(),
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
}

import Foundation

extension AccrueData {
    /// What a new install starts with: the Push / Pull / Legs week from the design mockups,
    /// so Train has something to show on day one. Every part can be edited or removed.
    public static func starter() -> AccrueData {
        func lift(_ id: String, _ sets: Int, _ reps: Int, pause: Int = 0, rest: Int = 120) -> PlannedExercise {
            PlannedExercise(exerciseID: id, sets: sets, reps: reps, pauseSeconds: pause, restSeconds: rest)
        }
        func hold(_ id: String, _ sets: Int, seconds: Int) -> PlannedExercise {
            PlannedExercise(exerciseID: id, sets: sets, reps: nil, holdSeconds: seconds, restSeconds: 60)
        }

        // Ids are openGym exercise ids (see Catalog/families/exercise-map.json).
        let push = Preset(name: "Push", items: [
            lift(StarterIDs.benchPress, 4, 8, rest: 150),
            lift(StarterIDs.militaryPress, 3, 8),
            lift(StarterIDs.chestDip, 3, 10),
            lift(StarterIDs.pushdown, 3, 12, rest: 90),
        ])
        let pull = Preset(name: "Pull", items: [
            lift(StarterIDs.pulldown, 5, 10),
            lift(StarterIDs.pullUp, 4, 8, pause: 2),
            lift(StarterIDs.seatedRow, 4, 10),
            lift(StarterIDs.facePull, 3, 15, rest: 60),
        ])
        let legs = Preset(name: "Legs", items: [
            lift(StarterIDs.squat, 4, 6, rest: 180),
            lift(StarterIDs.romanianDeadlift, 3, 8, rest: 150),
            lift(StarterIDs.legPress, 3, 10),
            lift(StarterIDs.calfRaise, 4, 12, rest: 60),
            hold(StarterIDs.plank, 3, seconds: 45),
        ])
        let pullB = Preset(name: "Pull B", items: [
            lift(StarterIDs.pulldown, 4, 10),
            lift(StarterIDs.bentOverRow, 4, 8),
            lift(StarterIDs.facePull, 3, 15, rest: 60),
            lift(StarterIDs.hammerCurl, 3, 12, rest: 60),
        ])
        let fullBody = Preset(name: "Full body", items: [
            lift(StarterIDs.deadlift, 3, 5, rest: 180),
            lift(StarterIDs.pushUp, 3, 15, rest: 60),
            lift(StarterIDs.bentOverRow, 3, 10),
            PlannedExercise(exerciseID: StarterIDs.farmersWalk, sets: 3, reps: nil, restSeconds: 90),
        ])
        let run = PlannedExercise(exerciseID: StarterIDs.run, sets: 1, reps: nil, restSeconds: 0, minutes: 30, targetZone: 2)

        let sevenMinute = TimedExercise.template(.sevenMinute)

        var routine = WeekRoutine()
        routine[.monday] = [.preset(push.id)]
        routine[.tuesday] = [.preset(pull.id)]
        routine[.wednesday] = [.timed(sevenMinute.id), .exercise(run)]
        routine[.thursday] = [.preset(legs.id)]
        routine[.friday] = [.preset(pullB.id)]
        routine[.saturday] = [.preset(fullBody.id)]

        return AccrueData(
            presets: [push, pull, legs, pullB, fullBody],
            routine: routine,
            favorites: [StarterIDs.pulldown, StarterIDs.pullUp, StarterIDs.benchPress, StarterIDs.pushUp, StarterIDs.run],
            timed: [sevenMinute]
        )
    }
}

public enum StarterIDs {
    public static let benchPress = "0025"
    public static let militaryPress = "1162"
    public static let chestDip = "0251"
    public static let pushdown = "0241"
    public static let pulldown = "0198"
    public static let pullUp = "0652"
    public static let seatedRow = "0861"
    public static let facePull = "5609"
    public static let squat = "0043"
    public static let romanianDeadlift = "0085"
    public static let legPress = "0739"
    public static let calfRaise = "3018"
    public static let plank = "0463"
    public static let bentOverRow = "0027"
    public static let hammerCurl = "0313"
    public static let deadlift = "0032"
    public static let pushUp = "0662"
    public static let farmersWalk = "2133"
    /// Outdoor and treadmill runs are separate exercises, so each has its own history and
    /// Apple Watch starts the right workout.
    public static let run = "s:outdoor-run"
    public static let treadmillRun = "s:treadmill-run"

    public static let all = [benchPress, militaryPress, chestDip, pushdown, pulldown, pullUp, seatedRow, facePull,
                             squat, romanianDeadlift, legPress, calfRaise, plank, bentOverRow, hammerCurl,
                             deadlift, pushUp, farmersWalk, run]
}

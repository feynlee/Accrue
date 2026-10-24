import Foundation

/// The four ways to start a timed exercise. They differ only in their starting moves and timing.
public enum TimedStyle: String, Codable, CaseIterable, Sendable {
    case sevenMinute, hiit, tabata, emom

    public var label: String {
        switch self {
        case .sevenMinute: "7-minute"
        case .hiit: "HIIT"
        case .tabata: "Tabata"
        case .emom: "EMOM"
        }
    }

    /// The small line under the template button.
    public var detail: String {
        switch self {
        case .sevenMinute: "12 · 30/10"
        case .hiit: "40/20 × 3"
        case .tabata: "20/10 × 8"
        case .emom: "every min"
        }
    }

    public var note: String {
        switch self {
        case .sevenMinute: "Classic HICT order: big muscle groups alternate, so one rests while the next works."
        case .hiit: "HIIT: hard 40 s, easy 20 s. Heart rate should reach Zone 4 by the end of each round."
        case .tabata: "Tabata: 8 intervals of 20 s all-out and 10 s rest. Ask more of yourself, not more time."
        case .emom: "EMOM: do the reps at the top of each minute and rest for what is left of it."
        }
    }
}

/// An exercise built from other exercises and run by a timer: 7-minute, HIIT, Tabata, EMOM.
/// It sits in the library like any exercise and goes on a day as its own part.
public struct TimedExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var style: TimedStyle
    public var workSeconds: Int
    public var restSeconds: Int
    public var rounds: Int
    /// The break between rounds.
    public var roundRestSeconds: Int
    /// Catalog exercise ids, in order.
    public var moves: [String]

    public init(id: UUID = UUID(), name: String, style: TimedStyle, workSeconds: Int, restSeconds: Int,
                rounds: Int = 1, roundRestSeconds: Int = 60, moves: [String]) {
        self.id = id
        self.name = name
        self.style = style
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.rounds = rounds
        self.roundRestSeconds = roundRestSeconds
        self.moves = moves
    }

    /// The whole thing, start to end, for `rounds` rounds.
    public func totalSeconds(rounds: Int? = nil) -> Int {
        let r = max(1, rounds ?? self.rounds), n = moves.count
        guard n > 0 else { return 0 }
        return r * (n * workSeconds + (n - 1) * restSeconds) + (r - 1) * roundRestSeconds
    }

    /// Every work and rest interval in order. Rest comes between moves; between rounds there is
    /// the round break instead.
    public func intervals(rounds: Int? = nil) -> [TimedInterval] {
        let r = max(1, rounds ?? self.rounds)
        var out: [TimedInterval] = []
        for round in 1...r {
            for move in moves.indices {
                out.append(TimedInterval(kind: .work, move: move, round: round, seconds: workSeconds))
                if move < moves.count - 1 {
                    if restSeconds > 0 { out.append(TimedInterval(kind: .rest, move: move + 1, round: round, seconds: restSeconds)) }
                } else if round < r, roundRestSeconds > 0 {
                    out.append(TimedInterval(kind: .roundRest, move: 0, round: round + 1, seconds: roundRestSeconds))
                }
            }
        }
        return out
    }

    /// A starting point for each style, with no-equipment moves from the catalog.
    public static func template(_ style: TimedStyle) -> TimedExercise {
        switch style {
        case .sevenMinute:
            TimedExercise(name: "7-minute classic", style: style, workSeconds: 30, restSeconds: 10, rounds: 1,
                          moves: TimedMoves.sevenMinute)
        case .hiit:
            TimedExercise(name: "HIIT 20", style: style, workSeconds: 40, restSeconds: 20, rounds: 3,
                          moves: [TimedMoves.burpee, TimedMoves.jumpSquat, TimedMoves.pushUp, TimedMoves.mountainClimber,
                                  TimedMoves.lunge, TimedMoves.bicycleCrunch])
        case .tabata:
            TimedExercise(name: "Tabata 4", style: style, workSeconds: 20, restSeconds: 10, rounds: 2,
                          moves: [TimedMoves.jumpSquat, TimedMoves.mountainClimber, TimedMoves.pushUp, TimedMoves.bicycleCrunch])
        case .emom:
            TimedExercise(name: "EMOM 12", style: style, workSeconds: 45, restSeconds: 15, rounds: 4,
                          moves: [TimedMoves.burpee, TimedMoves.gobletSquat, TimedMoves.pushUp])
        }
    }
}

public struct TimedInterval: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case work, rest, roundRest }

    public var kind: Kind
    /// The move this interval works, or (for a rest) the one coming up.
    public var move: Int
    public var round: Int
    public var seconds: Int
}

/// Catalog ids for the template moves (openGym ids, see Catalog/families/exercise-map.json).
public enum TimedMoves {
    public static let jumpingJack = "3094"
    public static let wallSit = "7557"
    public static let pushUp = "0662"
    public static let crunch = "0274"
    public static let stepUp = "3444"
    public static let squat = "1197"
    public static let tricepsDip = "0815"
    public static let plank = "0463"
    public static let highKnees = "3556"
    public static let lunge = "0612"
    public static let pushUpRotation = "0664"
    public static let sidePlank = "0715"
    public static let burpee = "1160"
    public static let jumpSquat = "0514"
    public static let mountainClimber = "0630"
    public static let bicycleCrunch = "6211"
    public static let gobletSquat = "0534"
    public static let skater = "3109"
    public static let gluteBridge = "3561"
    public static let pikePushUp = "2921"
    public static let inchworm = "1471"
    public static let deadBug = "0276"
    public static let hollowHold = "1246"

    public static let sevenMinute = [jumpingJack, wallSit, pushUp, crunch, stepUp, squat, tricepsDip, plank,
                                     highKnees, lunge, pushUpRotation, sidePlank]

    /// No-equipment moves to swap in, by area.
    public static let byArea: [TimedArea: [String]] = [
        .fullBody: [jumpingJack, highKnees, burpee, mountainClimber, skater],
        .legs: [wallSit, squat, lunge, stepUp, gluteBridge, jumpSquat, gobletSquat],
        .upperBody: [pushUp, tricepsDip, pushUpRotation, pikePushUp, inchworm],
        .core: [crunch, plank, sidePlank, deadBug, bicycleCrunch, hollowHold],
    ]
}

/// The four areas a timed exercise balances.
public enum TimedArea: String, CaseIterable, Sendable {
    case fullBody, legs, upperBody, core

    public var label: String {
        switch self {
        case .fullBody: "Full body"
        case .legs: "Legs"
        case .upperBody: "Upper body"
        case .core: "Core"
        }
    }
}

extension Catalog {
    /// Which area a move works: from the template lists first, then its main muscles' region.
    public func timedArea(of exerciseID: String) -> TimedArea {
        for area in TimedArea.allCases where TimedMoves.byArea[area]?.contains(exerciseID) == true { return area }
        guard let exercise = exercise(exerciseID) else { return .fullBody }
        switch region(for: exercise) {
        case "chest", "back", "shoulders", "arms", "forearms", "neck": return .upperBody
        case "core": return .core
        case "hips", "thighs", "lower legs", "feet": return .legs
        default: return .fullBody
        }
    }
}

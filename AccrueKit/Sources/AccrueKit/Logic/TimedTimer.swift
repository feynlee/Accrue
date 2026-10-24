import Foundation

/// Where a running timed exercise is. It counts in the workout's active seconds, so pausing the
/// workout pauses the timer, and with no taps it follows the plan from the start by itself.
public struct TimedTimer: Codable, Hashable, Sendable {
    /// Rounds planned so far (+ 1 round adds one).
    public var rounds: Int
    /// The interval the last tap put us in.
    public var index: Int
    /// Active seconds of the workout when that interval began.
    public var startedAt: TimeInterval
    /// Seconds added with +10 s to that interval.
    public var extra: Int

    public init(rounds: Int, index: Int = 0, startedAt: TimeInterval = 0, extra: Int = 0) {
        self.rounds = rounds
        self.index = index
        self.startedAt = startedAt
        self.extra = extra
    }

    /// What the screen shows at a moment.
    public struct Position: Hashable, Sendable {
        public var index: Int
        public var interval: TimedInterval?
        /// Seconds left in this interval, rounded up.
        public var secondsLeft: Int
        /// The length of this interval, with any +10 s.
        public var length: Int
        public var finished: Bool
        /// Work intervals done, out of `workCount`.
        public var worksDone: Int
        public var workCount: Int
    }

    /// Walks forward from the last tap to `active`.
    public func position(in plan: TimedExercise, at active: TimeInterval) -> Position {
        let list = plan.intervals(rounds: rounds)
        let works = list.filter { $0.kind == .work }.count
        var i = index, start = startedAt, extra = self.extra
        while i < list.count {
            let length = TimeInterval(list[i].seconds + extra)
            if active < start + length {
                let left = Int((start + length - active).rounded(.up))
                let done = list[..<i].filter { $0.kind == .work }.count
                return Position(index: i, interval: list[i], secondsLeft: max(1, left), length: list[i].seconds + extra,
                                finished: false, worksDone: done, workCount: works)
            }
            start += length
            extra = 0
            i += 1
        }
        return Position(index: list.count, interval: nil, secondsLeft: 0, length: 0, finished: true,
                        worksDone: works, workCount: works)
    }

    /// Jump to an interval, starting it now.
    private mutating func go(to i: Int, at active: TimeInterval) {
        index = i
        startedAt = active
        extra = 0
    }

    /// Skip › ends this interval now.
    public mutating func skip(in plan: TimedExercise, at active: TimeInterval) {
        let p = position(in: plan, at: active)
        go(to: min(p.index + 1, plan.intervals(rounds: rounds).count), at: active)
    }

    /// ‹ Back restarts the move a few seconds in; at its start, or in a rest, it goes to the move before.
    public mutating func back(in plan: TimedExercise, at active: TimeInterval) {
        let list = plan.intervals(rounds: rounds)
        let p = position(in: plan, at: active)
        let i = min(p.index, list.count - 1)
        guard i >= 0 else { return }
        let elapsed = p.finished ? 0 : p.length - p.secondsLeft
        if list[i].kind == .work, elapsed >= 3, !p.finished {
            go(to: i, at: active)
            return
        }
        let before = list[..<i].lastIndex { $0.kind == .work } ?? i
        go(to: before, at: active)
    }

    /// +10 s to the interval on screen.
    public mutating func addTen(in plan: TimedExercise, at active: TimeInterval) {
        let p = position(in: plan, at: active)
        guard !p.finished else { return }
        if p.index != index {
            // Fold the time that passed into a fresh start for this interval.
            startedAt = active - TimeInterval(p.length - p.secondsLeft)
            index = p.index
            extra = 0
        }
        extra += 10
    }

    /// + 1 round at the end: a round break, then the moves again, starting now.
    public mutating func addRound(in plan: TimedExercise, at active: TimeInterval) {
        let before = plan.intervals(rounds: rounds).count
        rounds += 1
        let list = plan.intervals(rounds: rounds)
        // The new list has the round break where the old one ended; start the new round's first move.
        let next = list[before...].firstIndex { $0.kind == .work } ?? before
        go(to: next, at: active)
    }
}

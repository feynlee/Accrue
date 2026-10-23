import Foundation

/// Accrue's logging rules, kept in one place so screens and tests agree.
public enum TrainingMath {
    /// A set lighter than this share of the day's top weight counts as a warm-up.
    public static let warmupShare = 0.6

    /// Estimated one-rep max (Epley). Reliable up to about 10 reps; nil past 12.
    public static func estimatedMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps <= 12 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// Sets that count toward Work and Strength: not flagged as warm-ups and, for weighted
    /// moves, not under 60% of the day's top weight. Added weight on a bodyweight move is not
    /// a reason to drop the bodyweight-only sets, so the weight rule needs a weighted tracking.
    public static func workingSets(_ sets: [LoggedSet], tracking: Tracking = .weightReps) -> [LoggedSet] {
        let flagged = sets.filter { !$0.isWarmup }
        guard tracking.usesWeight else { return flagged }
        let top = flagged.compactMap(\.weightKg).max() ?? 0
        guard top > 0 else { return flagged }
        return flagged.filter { ($0.weightKg ?? 0) >= top * warmupShare }
    }

    /// Total weight moved by working sets (weight × reps).
    public static func volume(_ sets: [LoggedSet], tracking: Tracking = .weightReps) -> Double {
        workingSets(sets, tracking: tracking).reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    public static func totalReps(_ sets: [LoggedSet], tracking: Tracking = .weightReps) -> Int {
        workingSets(sets, tracking: tracking).reduce(0) { $0 + ($1.reps ?? 0) }
    }

    /// The one number for "Strength", by how the exercise is tracked:
    /// Est. max for weighted moves, best set for bodyweight, longest hold for holds,
    /// longest session (seconds) for cardio.
    public static func strength(_ sets: [LoggedSet], tracking: Tracking) -> Double? {
        let working = workingSets(sets, tracking: tracking)
        switch tracking {
        case .weightReps:
            return working.compactMap { s in s.reps.flatMap { estimatedMax(weightKg: s.weightKg ?? 0, reps: $0) } }.max()
        case .reps:
            // Best set: the most reps in one working set at the current level.
            return working.compactMap { $0.reps }.max().map(Double.init)
        case .hold, .weightHold:
            return working.compactMap { $0.holdSeconds }.max().map(Double.init)
        case .weightDistance:
            return working.compactMap(\.weightKg).max()
        case .time, .timeHR, .distanceTimeHR:
            return working.compactMap { $0.durationSeconds }.max().map(Double.init)
        }
    }

    /// Percent change from `before` to `now`, or nil when there is nothing to compare.
    public static func change(from before: Double?, to now: Double?) -> Double? {
        guard let b = before, let n = now, b > 0 else { return nil }
        return (n - b) / b * 100
    }
}

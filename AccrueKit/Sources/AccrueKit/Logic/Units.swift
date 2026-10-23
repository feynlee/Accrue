import Foundation

/// The weight unit the user sees. Everything is stored in kilograms.
public enum WeightUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case kg
    case lb

    public static let poundsPerKilogram = 2.204_622_621_8

    public var id: String { rawValue }
    public var label: String { rawValue }

    /// One tap of the weight stepper.
    public var step: Double {
        switch self {
        case .kg: 2.5
        case .lb: 5
        }
    }

    public func fromKg(_ kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lb: kg * WeightUnit.poundsPerKilogram
        }
    }

    public func toKg(_ value: Double) -> Double {
        switch self {
        case .kg: value
        case .lb: value / WeightUnit.poundsPerKilogram
        }
    }

    /// "100", "102.5": at most one decimal, none when whole.
    public func format(kg: Double) -> String {
        Self.trim(fromKg(kg))
    }

    /// Rounds a stored weight to the nearest value the stepper can show, so 100 lb stays 100 lb.
    public func rounded(kg: Double) -> Double {
        let shown = (fromKg(kg) * 10).rounded() / 10
        return toKg(shown)
    }

    static func trim(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r)
    }
}

public enum DurationFormat {
    /// 75 -> "1:15", 3725 -> "1:02:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

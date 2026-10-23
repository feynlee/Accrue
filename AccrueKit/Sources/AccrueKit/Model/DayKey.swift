import Foundation

/// A calendar day, independent of time zone once made. Encodes as "2026-10-23".
public struct DayKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public static func today(calendar: Calendar = .current) -> DayKey {
        DayKey(Date(), calendar: calendar)
    }

    /// Noon on this day, so adding days never trips over a daylight-saving change.
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        DayKey(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? date(calendar: calendar), calendar: calendar)
    }

    public func weekday(calendar: Calendar = .current) -> Weekday {
        Weekday(calendarWeekday: calendar.component(.weekday, from: date(calendar: calendar)))
    }

    /// Monday of this day's week.
    public func startOfWeek(calendar: Calendar = .current) -> DayKey {
        adding(days: -(weekday(calendar: calendar).rawValue - 1), calendar: calendar)
    }

    public static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day \(text)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Monday-first weekday, as the Train strip shows it.
public enum Weekday: Int, Codable, Sendable, CaseIterable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }

    /// From `Calendar.component(.weekday:)`, where 1 is Sunday.
    public init(calendarWeekday: Int) {
        self = Weekday(rawValue: (calendarWeekday + 5) % 7 + 1) ?? .monday
    }

    public var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    public var short: String { String(name.prefix(3)) }
    public var letter: String { String(name.prefix(1)) }
}

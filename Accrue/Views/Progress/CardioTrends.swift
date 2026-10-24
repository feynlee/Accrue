import AccrueKit
import Charts
import SwiftUI

/// A number a cardio session can be tracked by. Each has a small trend line on the cardio card
/// and its own trend screen.
enum CardioStat: String, CaseIterable, Identifiable, Hashable {
    case distance, time, pace
    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: "Distance"
        case .time: "Time"
        case .pace: "Avg pace"
        }
    }

    var detail: String {
        switch self {
        case .distance: "Distance of each session."
        case .time: "Moving time of each session."
        case .pace: "Average pace of each session, any effort. Faster is drawn higher."
        }
    }

    /// Pace goes down as you get fitter; the line is drawn so up is always better.
    var higherIsBetter: Bool { self != .pace }

    /// Miles or km for distance, seconds for time, seconds per mile or km for pace.
    func value(_ s: DaySummary, unit: WeightUnit) -> Double? {
        let perUnit = unit == .lb ? 1609.344 : 1000
        switch self {
        case .distance:
            return s.distanceMeters.flatMap { $0 > 0 ? $0 / perUnit : nil }
        case .time:
            return s.durationSeconds.map(Double.init)
        case .pace:
            guard let m = s.distanceMeters, m > 0, let t = s.durationSeconds else { return nil }
            return Double(t) / (m / perUnit)
        }
    }

    func format(_ v: Double, unit: WeightUnit) -> String {
        switch self {
        case .distance: String(format: "%.1f %@", v, unit == .lb ? "mi" : "km")
        case .time: DurationFormat.clock(v)
        case .pace: String(format: "%d'%02d\"", Int(v) / 60, Int(v) % 60)
        }
    }

    /// "/mi" after a pace, nothing otherwise.
    func suffix(unit: WeightUnit) -> String {
        self == .pace ? (unit == .lb ? "/mi" : "/km") : ""
    }

    func delta(from b: Double, to a: Double, unit: WeightUnit) -> String {
        switch self {
        case .distance:
            return (a >= b ? "+" : "−") + format(abs(a - b), unit: unit)
        case .time:
            let min = Int((abs(a - b) / 60).rounded())
            return min == 0 ? "same" : (a >= b ? "+" : "−") + "\(min) min"
        case .pace:
            let s = Int(abs(a - b).rounded())
            return s == 0 ? "same" : "\(s) s " + (a < b ? "faster" : "slower")
        }
    }

    func improved(from b: Double, to a: Double) -> Bool {
        higherIsBetter ? a > b : a < b
    }
}

struct CardioTrendRoute: Hashable {
    let exerciseID: String
    let stat: CardioStat
    let day: DayKey
}

/// A small line of recent values. Up is always better, the latest value is a lime dot and the
/// compared session, when it is in the window, is a hollow dot.
struct TrendSparkline: View {
    @Environment(\.palette) private var palette
    let values: [Double]
    let higherIsBetter: Bool
    var markIndex: Int?

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let inset: CGFloat = 4
            func point(_ i: Int) -> CGPoint {
                let f = hi > lo ? (values[i] - lo) / (hi - lo) : 0.5
                let y = higherIsBetter ? 1 - f : f
                return CGPoint(x: inset + CGFloat(i) * (size.width - 2 * inset) / CGFloat(values.count - 1),
                               y: inset + CGFloat(y) * (size.height - 2 * inset))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            context.stroke(line, with: .color(palette.secondary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            if let m = markIndex, values.indices.contains(m), m != values.count - 1 {
                let p = point(m)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                               with: .color(palette.text.opacity(0.85)), lineWidth: 1.5)
            }
            let last = point(values.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)),
                         with: .color(palette.accentFill))
        }
        .accessibilityHidden(true)
    }
}

/// One cardio stat over time: pick the stat and the range; each session is a dot and the lime
/// line is the average of the last four.
struct CardioTrendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    let day: DayKey
    @State private var stat: CardioStat
    @State private var range = TrendRange.sixMonths

    init(route: CardioTrendRoute) {
        exerciseID = route.exerciseID
        day = route.day
        _stat = State(initialValue: route.stat)
    }

    enum TrendRange: Int, CaseIterable, Hashable {
        case threeMonths = 91, sixMonths = 182, oneYear = 365
        var short: String { self == .threeMonths ? "3M" : self == .sixMonths ? "6M" : "1Y" }
        var ago: String { self == .threeMonths ? "3 mo ago" : self == .sixMonths ? "6 mo ago" : "1 yr ago" }
    }

    private struct Point: Identifiable {
        let day: DayKey
        let value: Double
        var trend: Double = 0
        var id: DayKey { day }
    }

    var body: some View {
        let history = model.history(of: exerciseID)
        let start = day.adding(days: -range.rawValue)
        var points = history.days
            .filter { $0.day > start && $0.day <= day }
            .compactMap { s in stat.value(s, unit: unit).map { Point(day: s.day, value: $0) } }
        for i in points.indices {
            let recent = points[max(0, i - 3)...i]
            points[i].trend = recent.reduce(0) { $0 + $1.value } / Double(recent.count)
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.name(of: exerciseID)) · \(stat.title)")
                        .font(.display(34))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.detail)
                        .font(.inter(13))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, 4)

                HStack(spacing: 6) {
                    ForEach(CardioStat.allCases) { s in
                        OutlineChip(title: s.title, selected: s == stat, height: 32) { stat = s }
                    }
                }

                chartCard(points)

                if !points.isEmpty {
                    let values = points.map(\.value)
                    let best = stat.higherIsBetter ? values.max()! : values.min()!
                    HStack(spacing: 6) {
                        fact("BEST", stat.format(best, unit: unit))
                        fact("AVERAGE", stat.format(values.reduce(0, +) / Double(values.count), unit: unit))
                        fact("SESSIONS", "\(values.count)")
                    }
                    Text("EVERY SESSION")
                        .font(.inter(11, .bold))
                        .tracking(0.5)
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 4)
                        .padding(.horizontal, 4)
                    ForEach(points.reversed()) { p in
                        sessionRow(p, history: history, best: p.value == best)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chartCard(_ points: [Point]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if let last = points.last {
                        Text(stat.format(last.value, unit: unit) + stat.suffix(unit: unit))
                            .font(.number(36))
                            .foregroundStyle(palette.text)
                        if let first = points.first, points.count > 1 {
                            Text("\(stat.delta(from: first.value, to: last.value, unit: unit)) vs \(range.ago) (\(first.day.compareDate))")
                                .font(.inter(12, .bold))
                                .foregroundStyle(stat.improved(from: first.value, to: last.value) ? palette.accentText : palette.secondary)
                        }
                    } else {
                        Text("Nothing logged in this range.")
                            .font(.inter(14))
                            .foregroundStyle(palette.secondary)
                    }
                }
                Spacer()
                MiniToggle(options: TrendRange.allCases.map { ($0, $0.short) }, selection: $range)
                    .frame(width: 132)
            }
            if points.count > 1 {
                Chart {
                    ForEach(points) { p in
                        PointMark(x: .value("Day", p.day.date()), y: .value(stat.title, p.value))
                            .foregroundStyle(palette.cardio.opacity(0.8))
                            .symbolSize(28)
                        LineMark(x: .value("Day", p.day.date()), y: .value(stat.title, p.trend),
                                 series: .value("Line", "trend"))
                            .foregroundStyle(palette.accentFill)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: !stat.higherIsBetter))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(palette.raised)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(stat.format(v, unit: unit)).font(.inter(10)).foregroundStyle(palette.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.inter(10))
                            .foregroundStyle(palette.secondary)
                    }
                }
                .frame(height: 170)
                .accessibilityLabel("\(stat.title) over \(points.count) sessions")
                HStack(spacing: 14) {
                    legend(color: palette.cardio, bar: false, text: "Each session")
                    legend(color: palette.accentFill, bar: true, text: "Trend (4-session average)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary)
            Text(value).font(.number(20)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sessionRow(_ p: Point, history: ExerciseHistory, best: Bool) -> some View {
        let s = history.summary(on: p.day)
        let other = [s?.distanceMeters.map { DistanceFormat.format(meters: $0, unit: unit) },
                     s?.durationSeconds.map { DurationFormat.clock(TimeInterval($0)) }]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline) {
            Text(p.day.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.inter(13, .bold))
                .foregroundStyle(palette.text)
            Spacer()
            Text(other).font(.inter(12)).foregroundStyle(palette.secondary)
            Text(stat.format(p.value, unit: unit) + stat.suffix(unit: unit))
                .font(.inter(14, .bold))
                .foregroundStyle(best ? palette.accentText : palette.text)
                .frame(minWidth: 74, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legend(color: Color, bar: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            if bar {
                Capsule().fill(color).frame(width: 12, height: 3)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text).font(.inter(11)).foregroundStyle(palette.text.opacity(0.85))
        }
    }
}

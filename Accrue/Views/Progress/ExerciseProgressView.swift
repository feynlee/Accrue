import AccrueKit
import Charts
import SwiftUI

/// One exercise over time, as on the ADetail board: Est. max and Volume / week tiles that switch
/// the chart, then every session with its sets.
struct ExerciseProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    let day: DayKey
    let comparison: Comparison
    @State private var metric = StrengthMetric.strength
    @State private var showingInfo = false

    var body: some View {
        let history = model.history(of: exerciseID)
        let tracking = history.tracking
        let now = history.summary(on: day) ?? history.days.last
        let then = now.flatMap { history.compared(comparison, to: $0.day) }

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name(of: exerciseID))
                        .font(.display(34))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.text)
                    Text(subtitle(tracking: tracking, then: then))
                        .font(.inter(13))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, 4)

                if let now {
                    HStack(spacing: 8) {
                        tile(.strength, now: now, then: then, history: history)
                        tile(.volume, now: now, then: then, history: history)
                    }
                    chartCard(history: history)
                }

                Text("EVERY SESSION · \(tracking.usesHold ? "HOLDS" : tracking == .reps ? "REPS" : "WEIGHT × REPS")")
                    .font(.inter(11, .bold))
                    .tracking(0.5)
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                ForEach(Array(history.days.reversed().prefix(30)), id: \.day) { summary in
                    sessionRow(summary, tracking: tracking)
                }
                if history.days.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.inter(14))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How to read this")
            }
        }
        .sheet(isPresented: $showingInfo) {
            ProgressInfoSheet().presentationDetents([.medium, .large])
        }
    }

    private func subtitle(tracking: Tracking, then: DaySummary?) -> String {
        let kind = switch tracking {
        case .weightReps, .weightDistance, .weightHold: "Weighted"
        case .reps: "Bodyweight"
        case .hold: "Hold"
        case .time, .timeHR, .distanceTimeHR: "Cardio"
        }
        let muscle = model.exercise(exerciseID).map { model.catalog.muscles(for: $0) }?.primary.first
            .map { model.catalog.muscleLabel($0).lowercased() }
        let compared = then.map { "compared with \(comparison == .lastTime ? "last time" : comparison.label) (\($0.day.compareDate))" }
        return [kind, muscle, compared].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Tiles

    private func tile(_ which: StrengthMetric, now: DaySummary, then: DaySummary?, history: ExerciseHistory) -> some View {
        let tracking = history.tracking
        let on = metric == which
        let label: String
        let value: String
        let delta: String?
        let up: Bool
        if which == .volume && (tracking == .weightReps || tracking == .weightDistance) {
            // Volume / week: the week of `now` against the week of the compared session.
            let a = history.volume(inWeekOf: now.day)
            let b = then.map { history.volume(inWeekOf: $0.day) }
            label = "VOLUME / WEEK"
            value = "\(Int(unit.fromKg(a)).formatted()) \(unit.label)"
            delta = b.flatMap { TrainingMath.change(from: $0, to: a) }.map { String(format: "%+.0f%%", $0) }
            up = (b ?? .infinity) < a
        } else {
            let m = MetricValue(tracking: tracking, metric: which, now: now, then: then, unit: unit)
            label = m.label
            value = m.value
            delta = m.delta
            up = m.improved
        }
        return Button {
            metric = which
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.inter(11, .bold)).tracking(0.5).foregroundStyle(palette.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value).font(.number(28)).foregroundStyle(palette.text)
                        deltaText(delta, up: up)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(value).font(.number(28)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
                        deltaText(delta, up: up)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? palette.accentText : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func deltaText(_ delta: String?, up: Bool) -> some View {
        Text(delta.map { "\($0) vs \(comparison == .lastTime ? "last time" : comparison.label)" } ?? "")
            .font(.inter(12, .bold))
            .foregroundStyle(up ? palette.accentText : palette.secondary)
            .lineLimit(1)
    }

    // MARK: Chart

    @ViewBuilder
    private func chartCard(history: ExerciseHistory) -> some View {
        let tracking = history.tracking
        VStack(alignment: .leading, spacing: 6) {
            if metric == .strength {
                let recent = Array(history.days.suffix(12))
                Chart {
                    ForEach(recent, id: \.day) { d in
                        if let s = d.strength {
                            LineMark(x: .value("Day", d.day.date()), y: .value("Strength", shown(s, tracking)),
                                     series: .value("Line", "strength"))
                                .foregroundStyle(palette.accentFill)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                        }
                        if tracking.usesWeight, let w = d.topWeightKg {
                            PointMark(x: .value("Day", d.day.date()), y: .value("Weight", unit.fromKg(w)))
                                .foregroundStyle(palette.cardio)
                                .symbolSize(40)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(palette.raised)
                        AxisValueLabel().foregroundStyle(palette.secondary).font(.inter(10))
                    }
                }
                .frame(height: 130)
                HStack(spacing: 14) {
                    legend(color: palette.accentFill, bar: true, text: MetricValue.strengthName(tracking))
                    if tracking.usesWeight { legend(color: palette.cardio, bar: false, text: "Weight you used") }
                }
            } else {
                let weeks = history.weeklyVolume(weeks: 12, endingOn: day)
                let values: [Double] = weeks.map { w in
                    switch tracking {
                    case .weightReps, .weightDistance: unit.fromKg(w.volumeKg)
                    case .reps: Double(history.days.filter { $0.day.startOfWeek() == w.week }.reduce(0) { $0 + $1.totalReps })
                    default: Double(history.days.filter { $0.day.startOfWeek() == w.week }.reduce(0) { $0 + $1.totalHoldSeconds })
                    }
                }
                Chart {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                        BarMark(x: .value("Week", w.week.date(), unit: .weekOfYear), y: .value("Volume", values[i]))
                            .foregroundStyle(i == weeks.count - 1 ? palette.accentFill : palette.line)
                            .cornerRadius(3)
                            .annotation(position: .top) {
                                if i == 0 || i == weeks.count - 1, values[i] > 0 {
                                    Text(values[i] >= 1000 ? String(format: "%.1fk", values[i] / 1000) : "\(Int(values[i]))")
                                        .font(.inter(9))
                                        .foregroundStyle(palette.secondary)
                                }
                            }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 120)
                Text(tracking.usesWeight ? "Weight × reps, added up for every working set that week"
                     : tracking.usesHold ? "Every hold added up, per week" : "Every working rep added up, per week")
                    .font(.inter(11))
                    .foregroundStyle(palette.text.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func shown(_ strength: Double, _ tracking: Tracking) -> Double {
        tracking.usesWeight ? unit.fromKg(strength) : strength
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

    // MARK: Sessions

    private func sessionRow(_ summary: DaySummary, tracking: Tracking) -> some View {
        let sets = TrainingMath.workingSets(model.data.sets(of: exerciseID, on: summary.day), tracking: tracking)
        let best = sets.max { score($0, tracking) < score($1, tracking) }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.day.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.inter(13, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(summary.line(unit: unit, tracking: tracking)
                     + (tracking.usesWeight && summary.volumeKg > 0 ? " = \(Int(unit.fromKg(summary.volumeKg)).formatted()) \(unit.label)" : ""))
                    .font(.inter(12))
                    .foregroundStyle(palette.text.opacity(0.85))
            }
            FlowLayout(spacing: 4) {
                ForEach(sets) { set in
                    let top = set.id == best?.id
                    Text(chip(set, tracking: tracking))
                        .font(.inter(12, .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(top ? palette.accentText : palette.text)
                        .background(top ? palette.accentSoft : palette.raised, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func score(_ set: LoggedSet, _ tracking: Tracking) -> Double {
        TrainingMath.strength([set], tracking: tracking) ?? 0
    }

    private func chip(_ set: LoggedSet, tracking: Tracking) -> String {
        switch tracking {
        case .hold, .weightHold:
            let hold = DurationFormat.clock(TimeInterval(set.holdSeconds ?? 0))
            return set.weightKg.map { "\(unit.format(kg: $0)) × \(hold)" } ?? hold
        case .reps:
            let w = set.weightKg.map { "+\(unit.format(kg: $0)) · " } ?? ""
            return "\(w)\(set.reps ?? 0)" + (set.pauseSeconds > 0 ? " · \(set.pauseSeconds) s" : "")
        case .weightDistance:
            return "\(unit.format(kg: set.weightKg ?? 0)) × \(Int(set.distanceMeters ?? 0)) m"
        case .time, .timeHR, .distanceTimeHR:
            return DurationFormat.clock(TimeInterval(set.durationSeconds ?? 0))
        case .weightReps:
            return "\(unit.format(kg: set.weightKg ?? 0)) × \(set.reps ?? 0)" + (set.pauseSeconds > 0 ? " · \(set.pauseSeconds) s" : "")
        }
    }
}

extension MetricValue {
    static func strengthName(_ tracking: Tracking) -> String {
        switch tracking {
        case .weightReps: "Est. max"
        case .weightDistance: "Top weight"
        case .reps: "Best set"
        case .hold, .weightHold: "Longest hold"
        case .time, .timeHR, .distanceTimeHR: "Longest session"
        }
    }
}

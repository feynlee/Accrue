import AccrueKit
import SwiftUI

/// Est. max or Volume, the toggle on the selected-day panel and the exercise screen.
enum StrengthMetric: String, CaseIterable, Identifiable {
    case strength, volume
    var id: String { rawValue }
}

/// The number on the right of a Progress row, by how the exercise is tracked:
/// Est. max / Volume for weighted moves, Best set / Total reps for bodyweight,
/// Longest / Total time for holds.
struct MetricValue {
    var label: String
    var value: String
    var delta: String?
    var improved: Bool

    init(tracking: Tracking, metric: StrengthMetric, now: DaySummary, then: DaySummary?, unit: WeightUnit) {
        let strength = metric == .strength
        switch tracking {
        case .weightReps, .weightDistance:
            label = strength ? (tracking == .weightReps ? "EST. MAX" : "TOP WEIGHT") : "VOLUME"
            let a = strength ? (now.strength ?? 0) : now.volumeKg
            value = unit.format(kg: a) + " " + unit.label
            let b = then.map { strength ? ($0.strength ?? 0) : $0.volumeKg }
            if let b, let change = TrainingMath.change(from: b, to: a) {
                delta = abs(change) < 0.5 ? "same" : String(format: "%+.0f%%", change)
            }
            improved = (b ?? .infinity) < a
        case .reps:
            label = strength ? "BEST SET" : "TOTAL REPS"
            let a = strength ? Int(now.strength ?? 0) : now.totalReps
            value = "\(a) reps"
            let harder = (now.topWeightKg ?? 0) > (then?.topWeightKg ?? 0) && then != nil
            if harder {
                delta = "harder level"
            } else if let then {
                let b = strength ? Int(then.strength ?? 0) : then.totalReps
                delta = a == b ? "same" : String(format: "%+d reps", a - b)
            }
            improved = harder || (then.map { a > (strength ? Int($0.strength ?? 0) : $0.totalReps) } ?? false)
        case .hold, .weightHold:
            label = strength ? "LONGEST" : "TOTAL TIME"
            let a = strength ? Int(now.strength ?? 0) : now.totalHoldSeconds
            value = DurationFormat.clock(TimeInterval(a))
            if let then {
                let b = strength ? Int(then.strength ?? 0) : then.totalHoldSeconds
                delta = a == b ? "same" : String(format: "%+d s", a - b)
                improved = a > b
            } else {
                improved = false
            }
        case .time, .timeHR, .distanceTimeHR:
            label = "TIME"
            let a = now.durationSeconds ?? 0
            value = DurationFormat.clock(TimeInterval(a))
            if let b = then?.durationSeconds {
                delta = a == b ? "same" : String(format: "%+d min", (a - b) / 60)
            }
            improved = (then?.durationSeconds ?? .max) < a
        }
    }
}

extension DaySummary {
    /// Holds have no volume; the total time under tension stands in for it.
    var totalHoldSeconds: Int { (longestHoldSeconds ?? 0) * max(1, workingSets) }
}

/// Miles when weights are in pounds, kilometres otherwise.
enum DistanceFormat {
    static func format(meters: Double, unit: WeightUnit) -> String {
        unit == .lb ? String(format: "%.1f mi", meters / 1609.344) : String(format: "%.1f km", meters / 1000)
    }

    /// Pace per mile or per km, as 9'56".
    static func pace(seconds: Int, meters: Double, unit: WeightUnit) -> String {
        guard meters > 0 else { return "—" }
        let per = Double(seconds) / (unit == .lb ? meters / 1609.344 : meters / 1000)
        return String(format: "%d'%02d\"", Int(per) / 60, Int(per) % 60)
    }
}

extension DayKey {
    var shortDate: String { date().formatted(.dateTime.month(.abbreviated).day()) }

    /// "Oct 12", or "Oct 20, 2025" when it is not this year.
    var compareDate: String {
        year == DayKey.today().year ? shortDate : date().formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// White-selected two-option toggle on a dark track, as on the Progress boards.
struct MiniToggle<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let options: [(Value, String)]
    @Binding var selection: Value
    var height: CGFloat = 28

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.inter(height < 28 ? 11 : 12, .bold))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(on ? palette.background : palette.text.opacity(0.85))
                        .background(on ? palette.text : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// An outlined chip that turns lime when chosen ("4 wk ago", "Strength").
struct OutlineChip: View {
    @Environment(\.palette) private var palette
    let title: String
    let selected: Bool
    var height: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.inter(12, .bold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: height)
                .foregroundStyle(selected ? palette.accentText : palette.text.opacity(0.85))
                .overlay(Capsule().strokeBorder(selected ? palette.accentText : palette.line, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

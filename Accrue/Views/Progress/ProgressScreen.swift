import AccrueKit
import SwiftUI

/// First version of Progress: this week's strip, and the selected day's exercises with
/// Today, Last time and the change in strength vs 4 weeks ago. Charts and the calendar come next.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @State private var day = DayKey.today()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Progress")
                    .font(.display(34))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.text)
                thisWeek
                selectedDay
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private var thisWeek: some View {
        let monday = day.startOfWeek()
        let today = DayKey.today()
        let counts = (0..<7).map { model.data.sets(on: monday.adding(days: $0)).filter { !$0.isWarmup }.count }
        let top = max(1, counts.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This week").sectionLabel()
                Spacer()
                Text("\(counts.reduce(0, +)) working sets")
                    .font(.inter(12, .semibold))
                    .foregroundStyle(palette.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = monday.adding(days: i)
                    Button {
                        day = d
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(counts[i] > 0 ? palette.accentFill : palette.raised)
                                .frame(height: max(6, 70 * CGFloat(counts[i]) / CGFloat(top)))
                            Text(d.weekday().letter)
                                .font(.inter(11, .bold))
                                .foregroundStyle(d == day ? palette.accentText : (d == today ? palette.text : palette.secondary))
                        }
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .bottom)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d.weekday().name): \(counts[i]) working sets")
                }
            }
        }
        .padding(14)
        .card()
    }

    private var selectedDay: some View {
        let ids = model.data.sets(on: day).map(\.exerciseID).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return VStack(alignment: .leading, spacing: 8) {
            Text(day == DayKey.today() ? "Today" : day.date().formatted(.dateTime.weekday(.wide).month().day()))
                .sectionLabel()
            if ids.isEmpty {
                Text("Nothing logged on this day.")
                    .font(.inter(14))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .card(radius: 16)
            }
            ForEach(ids, id: \.self) { id in
                row(id)
            }
        }
    }

    private func row(_ exerciseID: String) -> some View {
        let history = model.history(of: exerciseID)
        let tracking = history.tracking
        let now = history.summary(on: day)
        let last = history.lastTime(before: day)
        let change = history.strengthChange(on: day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.name(of: exerciseID))
                    .font(.inter(15, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                if let s = now?.strength, tracking == .weightReps {
                    Text("Est. max \(unit.format(kg: s))")
                        .font(.inter(13, .bold))
                        .foregroundStyle(palette.text)
                }
            }
            if let now {
                Text("Today: \(now.line(unit: unit, tracking: tracking))")
                    .font(.inter(13))
                    .foregroundStyle(palette.text)
            }
            if let last {
                Text("Last time (\(last.day.date().formatted(.dateTime.month(.abbreviated).day()))): \(last.line(unit: unit, tracking: tracking))")
                    .font(.inter(13))
                    .foregroundStyle(palette.secondary)
            }
            if let change {
                Text(String(format: "%+.0f%% vs 4 wk ago", change))
                    .font(.inter(13, .bold))
                    .foregroundStyle(change >= 0 ? palette.accentText : palette.warmup)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }
}

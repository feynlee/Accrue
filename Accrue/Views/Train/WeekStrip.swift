import AccrueKit
import SwiftUI

/// Mon to Sun of the selected week, as on the board: each day shows its letter and its workout,
/// with no dates. A day with something logged shows what was done, in lime; every other day
/// shows its plan (faded once the day has passed), so a planned week never looks empty.
/// Swipe sideways for the previous or next week.
struct WeekStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Binding var selected: DayKey

    var body: some View {
        let today = DayKey.today()
        let monday = selected.startOfWeek()
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = monday.adding(days: offset)
                let isSelected = day == selected
                let summary = summary(for: day, today: today)
                Button {
                    selected = day
                } label: {
                    VStack(spacing: 1) {
                        Text(day.weekday().letter)
                            .font(.inter(11, .bold, relativeTo: .caption2))
                        ForEach(Array(summary.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.inter(11, .semibold, relativeTo: .caption2))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
                    .foregroundStyle(isSelected ? palette.onAccent : (summary.done ? palette.accentText : palette.text.opacity(summary.dim ? 0.5 : 0.85)))
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                    .background(isSelected ? palette.accentFill : palette.card,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        if day == today && !isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(palette.accentText.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(day.weekday().name)\(day == today ? ", today" : ""): \(summary.spoken)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { selected = selected.adding(days: 7) }
                if value.translation.width > 40 { selected = selected.adding(days: -7) }
            }
        )
    }

    private struct Summary {
        /// One or two short lines under the weekday letter.
        var lines: [String]
        var spoken: String
        /// Lime: something was logged that day.
        var done = false
        /// Faded: a rest day, or a past day whose plan was not logged.
        var dim = false
    }

    /// One name fills the line; two get a line each; more show the first and how many follow.
    private func lines(_ names: [String]) -> [String] {
        switch names.count {
        case 0: ["—"]
        case 1, 2: names
        default: [names[0], "+\(names.count - 1) more"]
        }
    }

    private func summary(for day: DayKey, today: DayKey) -> Summary {
        if day <= today {
            let done = model.doneTitles(on: day)
            if !done.isEmpty {
                return Summary(lines: lines(done), spoken: "done " + done.joined(separator: ", "), done: true)
            }
        }
        let planned = model.plannedTitles(on: day)
        if planned.isEmpty { return Summary(lines: ["—"], spoken: "rest", dim: true) }
        if day < today {
            return Summary(lines: lines(planned), spoken: "planned " + planned.joined(separator: ", ") + ", nothing logged", dim: true)
        }
        return Summary(lines: lines(planned), spoken: "planned " + planned.joined(separator: ", "))
    }
}

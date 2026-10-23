import AccrueKit
import SwiftUI

/// Mon to Sun of the selected week, as on the board: each day shows its letter and its workout,
/// with no dates. Past days show what was actually done; today and later show the plan.
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
                        Text(summary.text)
                            .font(.inter(11, .semibold, relativeTo: .caption2))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 2)
                    .foregroundStyle(isSelected ? palette.onAccent : (summary.done ? palette.accentText : palette.text.opacity(summary.dim ? 0.45 : 0.85)))
                    .frame(maxWidth: .infinity, minHeight: 48)
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
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { selected = selected.adding(days: 7) }
                if value.translation.width > 40 { selected = selected.adding(days: -7) }
            }
        )
    }

    private struct Summary {
        var text: String
        var spoken: String
        /// Lime: something was logged that day.
        var done = false
        /// Faded: a past day with nothing logged, or a rest day.
        var dim = false
    }

    private func summary(for day: DayKey, today: DayKey) -> Summary {
        let parts = model.data.parts(on: day)
        if day <= today {
            let names = model.doneTitles(on: day)
            if !names.isEmpty {
                let text = names.count == 1 ? names[0] : "\(names.count) parts"
                return Summary(text: text, spoken: "done " + names.joined(separator: ", "), done: true)
            }
            if day < today {
                return Summary(text: "—", spoken: parts.isEmpty ? "rest" : "nothing logged", dim: true)
            }
        }
        if parts.isEmpty { return Summary(text: "—", spoken: "rest", dim: true) }
        let names = model.plannedTitles(on: day)
        return Summary(text: names.count == 1 ? names[0] : "\(names.count) parts", spoken: "planned " + names.joined(separator: ", "))
    }
}

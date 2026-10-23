import AccrueKit
import SwiftUI

/// Mon to Sun of the selected week. Each day shows its letter, date and a dot when it has a plan.
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
                let planned = !model.data.parts(on: day).isEmpty
                let logged = !model.data.sets(on: day).isEmpty
                Button {
                    selected = day
                } label: {
                    VStack(spacing: 2) {
                        Text(day.weekday().letter)
                            .font(.inter(11, .bold, relativeTo: .caption2))
                            .foregroundStyle(isSelected ? palette.onAccent : palette.secondary)
                        Text("\(day.day)")
                            .font(.number(20))
                            .foregroundStyle(isSelected ? palette.onAccent : (day == today ? palette.accentText : palette.text))
                        Circle()
                            .fill(logged ? (isSelected ? palette.onAccent : palette.accentText) : (planned ? palette.line : .clear))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(isSelected ? palette.accentFill : palette.card,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(day, today: today, planned: planned, logged: logged))
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

    private func accessibilityLabel(_ day: DayKey, today: DayKey, planned: Bool, logged: Bool) -> String {
        var text = "\(day.weekday().name) \(day.day)"
        if day == today { text += ", today" }
        if logged { text += ", logged" } else if planned { text += ", planned" }
        return text
    }
}

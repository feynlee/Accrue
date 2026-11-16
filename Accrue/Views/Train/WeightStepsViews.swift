import AccrueKit
import SwiftUI

/// Which side of the Train card's top panel shows: your weight steps, or the exercise demo.
enum CardSide: String {
    case progress, demo
    static let key = "trainCardSide"
}

extension WeightSteps {
    /// "110 lb for 4 wk 5 d"; "115 lb · new today" on the first day at a weight.
    func title(unit: WeightUnit) -> String {
        guard let current else { return "" }
        let name = label(for: current, unit: unit)
        return daysAtCurrent <= 0 ? "\(name) · new today" : "\(name) for \(SpanFormat.exact(days: daysAtCurrent))"
    }
}

/// The small verdict beside the title: Ready (lime), Stalled (amber), or how far along.
struct VerdictChip: View {
    @Environment(\.palette) private var palette
    let verdict: WeightSteps.Verdict?
    /// The next weight, when there is one to suggest ("115").
    var next: String?

    var body: some View {
        switch verdict {
        case .ready:
            chip("Ready ↑" + (next.map { " \($0)" } ?? ""), ink: palette.onAccent, fill: palette.accentFill)
        case .stalled:
            chip("Stalled", ink: palette.warmup, fill: palette.warmup.opacity(0.18))
        case .building(let clean) where clean > 0:
            chip("\(clean) of \(WeightSteps.sessionsNeeded)", ink: palette.secondary, fill: palette.raised)
        case .new:
            chip("New weight", ink: palette.secondary, fill: palette.raised)
        default:
            EmptyView()
        }
    }

    private func chip(_ text: String, ink: Color, fill: Color) -> some View {
        Text(text)
            .font(.inter(12, .heavy))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .foregroundStyle(ink)
            .background(fill, in: Capsule())
            .fixedSize()
    }
}

/// The staircase: one flat step per weight, as long as the time spent there, newest on the right.
/// The current step is lime with a soft fill under it; a dashed step shows the next weight when
/// the lift is ready to go up.
struct StepsChart: View {
    @Environment(\.palette) private var palette
    let steps: WeightSteps
    let unit: WeightUnit
    /// One dot per session on each step (filled when every set hit the target).
    var dots = false
    /// At most this many of the latest steps.
    var maxSteps = 6
    /// The suggested next weight, drawn as a dashed step ("115").
    var ghost: String?

    var body: some View {
        Canvas { context, size in
            draw(&context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        steps.steps.suffix(maxSteps).map { step in
            "\(steps.label(for: step, unit: unit)) for \(SpanFormat.exact(days: steps.days(in: step)))"
        }.joined(separator: ", ")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let shown = Array(steps.steps.suffix(maxSteps))
        guard let first = shown.first, let current = shown.last else { return }
        let calendar = Calendar.current
        let roomy = size.height >= 86
        let left: CGFloat = 8
        let right: CGFloat = size.width - (ghost == nil ? 14 : 44)
        let top: CGFloat = roomy ? 28 : 16
        let bottom: CGFloat = size.height - 16
        guard right > left + 40, bottom > top + 8 else { return }

        let span = max(7, WeightSteps.days(from: first.start, to: steps.today, calendar: calendar))
        func x(_ day: DayKey) -> CGFloat {
            left + CGFloat(WeightSteps.days(from: first.start, to: day, calendar: calendar)) / CGFloat(span) * (right - left)
        }
        let levels = shown.map(steps.level(of:))
        let low = levels.min() ?? 0
        let count = (levels.max() ?? 0) - low + 1 + (ghost == nil ? 0 : 1)
        func y(_ level: Int) -> CGFloat {
            bottom - (CGFloat(level - low) + 0.55) / CGFloat(count) * (bottom - top)
        }
        let todayX = x(steps.today)

        // Month lines, with the month's name unless it would run into "Today".
        var month = calendar.dateComponents([.year, .month], from: first.start.date(calendar: calendar))
        month.day = 1
        month.hour = 12
        while let date = calendar.date(from: month) {
            let day = DayKey(date, calendar: calendar)
            if day > steps.today { break }
            if day > first.start {
                let mx = x(day)
                var line = Path()
                line.move(to: CGPoint(x: mx, y: top - 6))
                line.addLine(to: CGPoint(x: mx, y: bottom))
                context.stroke(line, with: .color(palette.line.opacity(0.6)), lineWidth: 1)
                if todayX - mx > 44 {
                    context.draw(Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.inter(10)).foregroundStyle(palette.secondary),
                                 at: CGPoint(x: mx + 3, y: size.height), anchor: .bottomLeading)
                }
            }
            month.month = (month.month ?? 1) + 1
        }
        context.draw(Text("Today").font(.inter(10, .bold)).foregroundStyle(palette.text),
                     at: CGPoint(x: min(todayX, size.width - 16), y: size.height), anchor: .bottom)

        for (i, step) in shown.enumerated() {
            let isCurrent = i == shown.count - 1
            let xa = x(step.start)
            let xb = isCurrent ? todayX : x(shown[i + 1].start)
            let sy = y(levels[i])
            let ink = isCurrent ? palette.accentText : palette.secondary
            if isCurrent {
                context.fill(Path(CGRect(x: xa, y: sy, width: max(2, xb - xa), height: bottom - sy)),
                             with: .color(palette.accentSoft))
            }
            if i > 0 {
                var riser = Path()
                riser.move(to: CGPoint(x: xa, y: y(levels[i - 1])))
                riser.addLine(to: CGPoint(x: xa, y: sy))
                context.stroke(riser, with: .color(ink.opacity(0.6)), lineWidth: 2)
            }
            var tread = Path()
            tread.move(to: CGPoint(x: xa, y: sy))
            tread.addLine(to: CGPoint(x: max(xb, xa + 2), y: sy))
            context.stroke(tread, with: .color(ink), style: StrokeStyle(lineWidth: isCurrent ? 3.5 : 2.5, lineCap: .round))

            if dots {
                for session in step.sessions {
                    let dot = CGRect(x: x(session.day) - 2.6, y: sy - 2.6, width: 5.2, height: 5.2)
                    if session.hitTarget {
                        context.fill(Path(ellipseIn: dot), with: .color(ink))
                    } else {
                        context.fill(Path(ellipseIn: dot), with: .color(palette.card))
                        context.stroke(Path(ellipseIn: dot), with: .color(ink), lineWidth: 1.3)
                    }
                }
            }

            // The weight above the step, and how long it lasted, where there is room for them.
            let width = xb - xa
            let mid = min(max((xa + xb) / 2, left + 14), size.width - 18)
            if width >= 20 || isCurrent {
                let name = Text(steps.label(for: step, unit: unit, short: true))
                    .font(.inter(isCurrent ? 12 : 11, .bold))
                    .foregroundStyle(isCurrent ? palette.text : palette.secondary)
                context.draw(name, at: CGPoint(x: mid, y: sy - (roomy ? 14 : 4)), anchor: .bottom)
            }
            if roomy, width >= 30 || isCurrent {
                let days = steps.days(in: step)
                let length = Text(isCurrent ? SpanFormat.exact(days: days) : SpanFormat.rough(days: days))
                    .font(.inter(9.5))
                    .foregroundStyle(palette.secondary)
                context.draw(length, at: CGPoint(x: mid, y: sy - 4), anchor: .bottom)
            }
        }

        if let ghost {
            let from = y(steps.level(of: current))
            let gy = y((levels.max() ?? 0) + 1)
            var path = Path()
            path.move(to: CGPoint(x: todayX, y: from))
            path.addLine(to: CGPoint(x: todayX, y: gy))
            path.addLine(to: CGPoint(x: size.width - 4, y: gy))
            context.stroke(path, with: .color(palette.accentText), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            context.draw(Text(ghost).font(.inter(11, .bold)).foregroundStyle(palette.accentText),
                         at: CGPoint(x: (todayX + size.width - 4) / 2, y: gy - 4), anchor: .bottom)
        }
    }
}

/// The Progress side of the Train card's top panel: how long you have been at this weight, the
/// steps that led here, and whether it is time to go up. The whole panel opens the details.
struct ProgressPanel: View {
    @Environment(\.palette) private var palette
    let steps: WeightSteps
    let unit: WeightUnit
    let next: String?
    /// "Pull B · 1 of 4"
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(steps.title(unit: unit))
                    .font(.inter(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                VerdictChip(verdict: steps.verdict, next: next)
            }
            .frame(minHeight: 24)
            StepsChart(steps: steps, unit: unit, ghost: steps.verdict == .ready ? (next ?? "next") : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Room for the Demo / Progress switch, which sits over this row.
            HStack {
                Spacer()
                Text(caption)
                    .font(.inter(11, .bold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(height: 34)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 12))
        .background(palette.sunken)
        .contentShape(Rectangle())
    }
}

/// Demo / Progress, bottom left of the card's top panel.
struct CardSideSwitch: View {
    @Environment(\.palette) private var palette
    @Binding var side: CardSide

    var body: some View {
        HStack(spacing: 0) {
            ForEach([CardSide.demo, .progress], id: \.self) { value in
                let on = value == side
                Button {
                    side = value
                } label: {
                    Text(value == .demo ? "Demo" : "Progress")
                        .font(.inter(12, .bold))
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .foregroundStyle(on ? palette.background : palette.text.opacity(0.8))
                        .background(on ? palette.text : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.background, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Top of the card shows")
    }
}

/// Pulled up from the Progress panel: the numbers behind the verdict, the full staircase, the
/// latest sessions at this weight, and one tap to move up.
struct WeightStepsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let item: PlannedExercise
    let day: DayKey
    /// Sets the card's weight stepper (kilograms) or its pause, then the sheet closes.
    let onUse: (_ weightKg: Double?, _ pauseSeconds: Int?) -> Void
    @State private var showingHistory = false

    var body: some View {
        let steps = model.weightSteps(for: item, on: day)
        let tracking = steps.tracking
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.name(of: item.exerciseID)) · target \(targetText(tracking))")
                                .sectionLabel()
                                .lineLimit(1)
                            Text(steps.title(unit: unit))
                                .font(.number(26))
                                .foregroundStyle(palette.text)
                        }
                        Spacer(minLength: 0)
                        VerdictChip(verdict: steps.verdict, next: nextLabel(steps))
                    }
                    if let note = note(steps) {
                        Text(note)
                            .font(.inter(13))
                            .foregroundStyle(palette.secondary)
                    }
                    stats(steps)
                    StepsChart(steps: steps, unit: unit, dots: true, maxSteps: 10,
                               ghost: steps.verdict == .ready ? (nextLabel(steps) ?? "next") : nil)
                        .frame(height: 170)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .card(radius: 16)
                    if steps.hasTarget {
                        HStack(spacing: 12) {
                            legend(filled: true, "Every set hit the target")
                            legend(filled: false, "Missed reps")
                        }
                    }
                    if let current = steps.current {
                        HStack {
                            Text("Recent sessions at \(steps.label(for: current, unit: unit))").sectionLabel()
                            Spacer()
                            Text(tracking.usesHold ? "each hold" : "reps per set")
                                .font(.inter(12))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.top, 2)
                        VStack(spacing: 6) {
                            ForEach(Array(current.sessions.suffix(4).reversed())) { session in
                                sessionRow(session, tracking: tracking)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(palette.background)
            .safeAreaInset(edge: .bottom) { buttons(steps) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingHistory) {
                ExerciseProgressView(exerciseID: item.exerciseID, day: day, comparison: .fourWeeks)
                    .background(palette.background)
            }
        }
    }

    private func targetText(_ tracking: Tracking) -> String {
        if tracking.usesHold { return "\(item.sets) × \(DurationFormat.clock(TimeInterval(item.holdSeconds ?? 30)))" }
        return "\(item.sets) × \(item.reps ?? 10)"
    }

    private func nextLabel(_ steps: WeightSteps) -> String? {
        guard steps.tracking.usesWeight, let kg = steps.current?.weightKg else { return nil }
        return unit.format(kg: unit.rounded(kg: kg + model.weightJumpKg(for: item.exerciseID, unit: unit)))
    }

    /// One plain sentence on why the chip says what it says.
    private func note(_ steps: WeightSteps) -> String? {
        let target = steps.tracking.usesHold ? DurationFormat.clock(TimeInterval(item.holdSeconds ?? 30)) : "\(item.reps ?? 10)"
        switch steps.verdict {
        case .ready:
            let days = steps.judgedSessions.suffix(WeightSteps.sessionsNeeded)
                .map { $0.day.date().formatted(.dateTime.month(.abbreviated).day()) }
            return "Every set hit \(target) on \(days.joined(separator: " and ")). Time to go up."
        case .stalled:
            return "Same weight for \(SpanFormat.exact(days: steps.daysAtCurrent)) and your total reps have not gone up in 4 weeks."
        case .building(let clean):
            return clean > 0
                ? "One session with every set at \(target). One more and it is time to go up."
                : "Go up after two sessions in a row with every set at \(target)."
        case .new:
            return "New today. Go up again after two sessions in a row with every set at \(target)."
        case nil:
            return nil
        }
    }

    private func stats(_ steps: WeightSteps) -> some View {
        HStack(spacing: 6) {
            if let current = steps.current {
                stat("\(current.sessions.count)", "sessions at \(steps.label(for: current, unit: unit, short: true))")
            }
            if steps.hasTarget {
                stat("\(steps.cleanStreak) of \(WeightSteps.sessionsNeeded)", "last sessions with every set at target")
            }
            if let usual = steps.usualDays {
                stat("~" + SpanFormat.rough(days: usual), "your usual time per weight")
            } else {
                stat("—", "your first weight so far")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.number(22))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.inter(11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(radius: 12)
    }

    private func legend(filled: Bool, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? palette.accentText : .clear)
                .overlay(Circle().strokeBorder(palette.accentText, lineWidth: 1.3))
                .frame(width: 8, height: 8)
            Text(text).font(.inter(12)).foregroundStyle(palette.secondary)
        }
    }

    private func sessionRow(_ session: StepSession, tracking: Tracking) -> some View {
        let values = session.values.map { tracking.usesHold ? DurationFormat.clock(TimeInterval($0)) : "\($0)" }
        let target = (tracking.usesHold ? item.holdSeconds : item.reps) ?? 0
        let result: String = if !steps(hasTarget: tracking) {
            ""
        } else if session.hitTarget {
            tracking.usesHold ? "all held ✓" : "all \(target) ✓"
        } else if tracking.usesHold {
            "\(session.values.filter { $0 >= target }.count) of \(item.sets)"
        } else {
            "\(session.total) of \(max(1, item.sets) * target)"
        }
        return HStack(spacing: 8) {
            Text(session.day.date().formatted(.dateTime.month(.abbreviated).day()))
                .font(.inter(13, .bold))
                .foregroundStyle(palette.text)
            Text(values.joined(separator: "  "))
                .font(.inter(13))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(result)
                .font(.inter(12, session.hitTarget ? .bold : .regular))
                .foregroundStyle(session.hitTarget ? palette.accentText : palette.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .card(radius: 12)
    }

    private func steps(hasTarget tracking: Tracking) -> Bool {
        tracking != .weightDistance && ((tracking.usesHold ? item.holdSeconds : item.reps) != nil)
    }

    @ViewBuilder
    private func buttons(_ steps: WeightSteps) -> some View {
        let ready = steps.verdict == .ready
        let jump = model.weightJumpKg(for: item.exerciseID, unit: unit)
        let weight = steps.current?.weightKg ?? 0
        let pause = steps.current?.pauseSeconds ?? 0
        HStack(spacing: 8) {
            if ready, steps.tracking.usesWeight {
                let next = unit.rounded(kg: weight + jump)
                Button("Use \(unit.format(kg: next)) \(unit.label) today") {
                    onUse(next, nil)
                    dismiss()
                }
                .buttonStyle(BigButtonStyle(filled: true))
            } else if ready, steps.tracking == .reps {
                // Bodyweight: add a little weight, or make each rep harder with a longer pause.
                Button("+ \(unit.format(kg: jump)) \(unit.label)") {
                    onUse(unit.rounded(kg: weight + jump), nil)
                    dismiss()
                }
                .buttonStyle(BigButtonStyle(filled: true))
                if let longer = [1, 2, 3, 5].first(where: { $0 > pause }) {
                    Button("\(longer) s pause") {
                        onUse(nil, longer)
                        dismiss()
                    }
                    .buttonStyle(BigButtonStyle(filled: true))
                }
            }
            Button("All history ›") { showingHistory = true }
                .buttonStyle(BigButtonStyle(filled: false))
                .frame(maxWidth: ready && (steps.tracking.usesWeight || steps.tracking == .reps) ? 140 : .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(palette.background)
    }
}

extension AppModel {
    /// The weight steps of one planned exercise, judged against its planned sets and reps.
    func weightSteps(for item: PlannedExercise, on day: DayKey) -> WeightSteps {
        WeightSteps(sets: data.history(of: item.exerciseID), tracking: tracking(of: item.exerciseID),
                    targetSets: item.sets, targetReps: item.reps, targetHold: item.holdSeconds, today: day)
    }

    /// The next plate up: one stepper step (5 lb, 2.5 kg), or two for barbell squats and
    /// deadlifts and the leg press, where the smallest jump is a plate each side.
    func weightJumpKg(for exerciseID: String, unit: WeightUnit) -> Double {
        let exercise = catalog.exercise(exerciseID)
        let family = exercise?.familyID ?? ""
        let big = (["squat", "deadlift"].contains(family) && exercise?.equipment == "barbell") || family == "leg-press"
        return unit.toKg(unit.step * (big ? 2 : 1))
    }
}

import AccrueKit
import AudioToolbox
import SwiftUI

extension TimedArea {
    /// Dot colours from the boards: lime, blue, amber, violet.
    var color: Color {
        switch self {
        case .fullBody: Color(hex: 0xC6F432)
        case .legs: Color(hex: 0x5BC8FF)
        case .upperBody: Color(hex: 0xFFB020)
        case .core: Color(hex: 0xC79BFF)
        }
    }
}

extension TimedExercise {
    /// "Timed exercise · 12 moves · 30 s on, 10 s rest · 7:50"
    var summaryLine: String {
        "Timed exercise · \(moves.count) moves · \(workSeconds) s on, \(restSeconds) s rest"
            + (rounds > 1 ? " · × \(rounds)" : "") + " · " + DurationFormat.clock(TimeInterval(totalSeconds()))
    }
}

/// The Train card for a timed exercise, built to the MTimer and MAsk boards: before it starts,
/// the moves; while it runs, a countdown ring, the move, what comes next, and Back / +10 s / Skip;
/// at the end, + 1 round or Finish. The timer moves you on, so there are no Log taps.
struct TimedCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let part: DayPart
    let plan: TimedExercise
    let day: DayKey
    /// The next part's title, for the Finish note.
    let nextTitle: String?
    let onFinishPart: () -> Void

    @State private var editing = false
    @State private var addingReps = false
    @State private var howToMove: String?

    private var session: WorkoutSession? {
        model.data.activeSession.flatMap { $0.partID == part.id && $0.day == day ? $0 : nil }
    }

    private var savedSession: WorkoutSession? {
        model.data.sessions(on: day).last { $0.partID == part.id && !$0.isActive }
    }

    var body: some View {
        Group {
            if let session, let timer = session.timer {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let p = timer.position(in: plan, at: session.activeSeconds(at: context.date))
                    running(session: session, timer: timer, position: p)
                }
            } else if let saved = savedSession {
                layout(demoMove: plan.moves.first, faded: false, segments: segments(done: plan.moves.count, current: nil),
                       position: nil, phase: nil) {
                    done(saved)
                }
            } else {
                layout(demoMove: plan.moves.first, faded: false, segments: segments(done: 0, current: nil),
                       position: nil, phase: nil) {
                    before
                }
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sheet(isPresented: $editing) {
            NavigationStack { TimedEditView(timedID: plan.id) }
        }
        .sheet(isPresented: $addingReps) {
            TimedRepsSheet(plan: plan, day: day, partID: part.id, session: savedSession)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: Binding(get: { howToMove.map(MoveID.init) }, set: { howToMove = $0?.id })) { move in
            HowToView(exerciseID: move.id, doneLabel: "Back to the timer")
        }
    }

    private struct MoveID: Identifiable { let id: String }

    // MARK: Running

    @ViewBuilder
    private func running(session: WorkoutSession, timer: TimedTimer, position p: TimedTimer.Position) -> some View {
        let interval = p.interval
        let isRest = interval.map { $0.kind != .work } ?? false
        let moveIndex = interval?.move ?? plan.moves.count - 1
        let done = p.finished ? plan.moves.count : moveIndex
        layout(demoMove: plan.moves[safe: moveIndex], faded: isRest,
               segments: segments(done: done, current: p.finished ? nil : moveIndex),
               position: positionLabel(p, timer: timer), phase: p.finished ? nil : (isRest ? "REST" : "WORK")) {
            countdown(p, timer: timer)
            HStack(spacing: 8) {
                timerButton("‹ Back", label: "Back to the previous move") { change(session) { $0.back(in: plan, at: $1) } }
                timerButton("+10 s", label: "Add 10 seconds") { change(session) { $0.addTen(in: plan, at: $1) } }
                timerButton("Skip ›", label: "Skip ahead") { change(session) { $0.skip(in: plan, at: $1) } }
            }
            .disabled(p.finished)
            Text("Beeps at 3, 2, 1 and a buzz at each change.")
                .font(.inter(11))
                .foregroundStyle(palette.secondary.opacity(0.8))
                .frame(maxWidth: .infinity)
        }
        .overlay {
            if p.finished { ask(session: session, timer: timer) }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: p.index)
        .onChange(of: p.secondsLeft) { _, left in
            if (1...3).contains(left), !session.isPaused { AudioServicesPlaySystemSound(1103) }
        }
        .onChange(of: p.finished, initial: true) { _, finished in
            // The last round ended: pause and ask, as the MAsk board does.
            if finished, !session.isPaused {
                let id = session.id
                model.update { $0.togglePause(id) }
            }
        }
    }

    private func countdown(_ p: TimedTimer.Position, timer: TimedTimer) -> some View {
        let interval = p.interval
        let isRest = interval.map { $0.kind != .work } ?? false
        let tint = isRest ? palette.cardio : palette.accentFill
        let move = plan.moves[safe: interval?.move ?? 0] ?? ""
        let area = model.catalog.timedArea(of: move)
        let n = plan.moves.count
        let phaseLine = p.finished ? "ALL \(p.workCount) DONE"
            : isRest ? (interval?.kind == .roundRest ? "ROUND BREAK · UP NEXT" : "REST · UP NEXT")
            : "WORK · \((interval?.move ?? 0) + 1) OF \(n)"
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(palette.line.opacity(0.6), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: p.length > 0 ? CGFloat(p.secondsLeft) / CGFloat(p.length) : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: p.secondsLeft)
                VStack(spacing: 0) {
                    Text("\(p.secondsLeft)")
                        .font(.display(44))
                        .monospacedDigit()
                        .foregroundStyle(palette.text)
                    Text("SEC").font(.inter(10, .bold)).foregroundStyle(palette.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement()
            .accessibilityLabel("\(p.secondsLeft) seconds left")
            VStack(alignment: .leading, spacing: 5) {
                Text(phaseLine)
                    .font(.inter(12, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(isRest ? palette.cardio : palette.accentText)
                Text(model.name(of: move))
                    .font(.inter(21, .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Circle().fill(area.color).frame(width: 7, height: 7)
                    Text(area.label)
                }
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                Text(nextLine(p, timer: timer))
                    .font(.inter(12))
                    .foregroundStyle(palette.text.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// While working, the next move; while resting (the move on screen is the next one), the one after.
    private func nextLine(_ p: TimedTimer.Position, timer: TimedTimer) -> String {
        guard let interval = p.interval else { return "" }
        let n = plan.moves.count
        if interval.kind == .work {
            if interval.move + 1 < n { return "Next: " + model.name(of: plan.moves[interval.move + 1]) }
            return interval.round < timer.rounds ? "Next: round \(interval.round + 1)" : "Next: done"
        }
        if interval.move + 1 < n { return "Then: " + model.name(of: plan.moves[interval.move + 1]) }
        return "Then: last move"
    }

    private func positionLabel(_ p: TimedTimer.Position, timer: TimedTimer) -> String {
        let n = plan.moves.count
        let move = p.finished ? n : (p.interval?.move ?? 0) + 1
        let round = p.interval?.round ?? timer.rounds
        return (timer.rounds > 1 ? "Round \(round) of \(timer.rounds) · " : "") + "\(move) of \(n)"
    }

    private func change(_ session: WorkoutSession, _ edit: @escaping (inout TimedTimer, TimeInterval) -> Void) {
        let id = session.id, active = session.activeSeconds(at: .now)
        model.update { $0.updateTimer(id) { edit(&$0, active) } }
    }

    private func timerButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.inter(14, .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(palette.text)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: End of the last round

    private func ask(session: WorkoutSession, timer: TimedTimer) -> some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0E0F12).opacity(0.55)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0E0F12))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: 0xFFB020), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(plan.style.label) finished").font(.inter(16, .heavy))
                        Text("Paused. Keep going, or finish and save it.")
                            .font(.inter(12))
                            .foregroundStyle(palette.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("+ 1 round") {
                        let id = session.id, active = session.activeSeconds(at: .now)
                        model.update { data in
                            data.updateTimer(id) { $0.addRound(in: plan, at: active) }
                            if data.sessions.first(where: { $0.id == id })?.isPaused == true { data.togglePause(id) }
                        }
                    }
                    .buttonStyle(AskButtonStyle(filled: false))
                    Button("Finish", action: onFinishPart)
                        .buttonStyle(AskButtonStyle(filled: true))
                }
                Text("Finish saves \(plan.name) as its own workout" + (nextTitle.map { ", then swipes to \($0)." } ?? "."))
                    .font(.inter(11))
                    .foregroundStyle(palette.secondary.opacity(0.85))
            }
            .padding(14)
            .foregroundStyle(palette.text)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 17, y: 14)
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Before and after

    private var before: some View {
        let counts = Dictionary(grouping: plan.moves) { model.catalog.timedArea(of: $0) }.mapValues(\.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name)
                    .font(.inter(19, .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer()
                Button("Edit") { editing = true }
                    .font(.inter(13, .bold))
                    .foregroundStyle(palette.accentText)
            }
            Text(plan.summaryLine)
                .font(.inter(13))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 4) {
                ForEach(TimedArea.allCases.filter { counts[$0] != nil }, id: \.self) { area in
                    HStack(spacing: 6) {
                        Circle().fill(area.color).frame(width: 7, height: 7)
                        Text("\(area.label) \(counts[area] ?? 0)")
                    }
                    .font(.inter(12, .bold))
                    .foregroundStyle(palette.text.opacity(0.85))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(palette.raised, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(plan.moves.prefix(4).enumerated()), id: \.offset) { i, move in
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.inter(11, .bold))
                            .foregroundStyle(palette.secondary.opacity(0.8))
                            .frame(width: 18, alignment: .leading)
                        Text(model.name(of: move))
                    }
                    .frame(minHeight: 22)
                }
                if plan.moves.count > 4 {
                    Text("and \(plan.moves.count - 4) more")
                        .font(.inter(12))
                        .foregroundStyle(palette.secondary.opacity(0.8))
                        .padding(.leading, 26)
                }
            }
            .font(.inter(13))
            .foregroundStyle(palette.text.opacity(0.85))
        }
    }

    private func done(_ saved: WorkoutSession) -> some View {
        let moves = saved.timer.map { $0.position(in: plan, at: saved.activeSeconds(at: .now)).worksDone } ?? plan.moves.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(plan.style.label) done")
                    .font(.inter(19, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("Saved")
                    .font(.inter(12, .bold))
                    .foregroundStyle(palette.accentText)
            }
            Text("\(DurationFormat.clock(saved.activeSeconds(at: .now))) · \(moves) moves")
                .font(.inter(13))
                .foregroundStyle(palette.secondary)
            Text("Counted reps? Add them so each move's history picks them up.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
            Button("Add reps") { addingReps = true }
                .font(.inter(14, .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(palette.text)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .buttonStyle(.plain)
        }
    }

    // MARK: Layout

    /// The light demo panel with the move playing, then the card's lower half.
    private func layout(demoMove: String?, faded: Bool, segments: [Color], position: String?, phase: String?,
                        @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            ZStack {
                palette.demo
                if let demoMove, let guide = model.exercise(demoMove).flatMap(model.catalog.howTo(for:)), !guide.keyframes.isEmpty {
                    AnimatedFigure(guide: guide)
                        .id(demoMove)
                        .padding(.top, 26)
                        .padding(.bottom, 30)
                        .opacity(faded ? 0.45 : 1)
                } else {
                    Image(systemName: "figure.highintensity.intervaltraining")
                        .font(.system(size: 76, weight: .ultraLight))
                        .foregroundStyle(palette.demoInk)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Text(position ?? "\(plan.name) · \(plan.moves.count) moves")
                    .font(.inter(11, .bold))
                    .foregroundStyle(palette.demoInk)
                    .padding(.leading, 12)
                    .padding(.top, 10)
            }
            .overlay(alignment: .topTrailing) {
                if let phase {
                    Text(phase)
                        .font(.inter(12, .heavy))
                        .tracking(0.7)
                        .foregroundStyle(Color(hex: 0x0E0F12))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(phase == "WORK" ? Color(hex: 0xC6F432) : Color(hex: 0x5BC8FF), in: Capsule())
                        .padding(.trailing, 10)
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 0) {
                    HStack(spacing: 2) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, color in
                            Capsule().fill(color).frame(height: 5)
                        }
                    }
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Button {
                        howToMove = demoMove
                    } label: {
                        Label("How to", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.inter(13, .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .foregroundStyle(palette.text)
                            .background(palette.background, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(demoMove == nil)
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
            .layoutPriority(-1)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        }
    }

    /// One bar per move: done, the one on now, still to come.
    private func segments(done: Int, current: Int?) -> [Color] {
        plan.moves.indices.map { i in
            i < done ? Color(hex: 0x8FB024) : i == current ? Color(hex: 0x0E0F12) : Color(hex: 0xC9CDD4)
        }
    }
}

/// The two big buttons on the end-of-round question: grey + 1 round, lime Finish.
struct AskButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(16, .heavy))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(filled ? palette.onAccent : palette.text)
            .background(filled ? palette.accentFill : palette.line, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// After a timed exercise: reps per move, so each move's history picks them up.
struct TimedRepsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let plan: TimedExercise
    let day: DayKey
    let partID: UUID
    let session: WorkoutSession?
    @State private var values: [String: Int] = [:]

    private var rounds: Int { session?.timer?.rounds ?? plan.rounds }

    var body: some View {
        let moves = plan.moves.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        NavigationStack {
            List {
                Section {
                    ForEach(moves, id: \.self) { move in
                        let hold = model.tracking(of: move).usesHold
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name(of: move)).font(.inter(15, .bold))
                                Text(hold ? "seconds held" : rounds > 1 ? "reps each round" : "reps")
                                    .font(.inter(12))
                                    .foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Stepper(value: binding(move), in: 0...300, step: hold ? 5 : 1) {
                                Text(values[move, default: 0] == 0 ? "–" : "\(values[move, default: 0])")
                                    .font(.number(24))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .fixedSize()
                        }
                        .listRowBackground(palette.card)
                    }
                } footer: {
                    Text("Moves left at – are not logged.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Add reps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.bold) }
            }
        }
    }

    private func binding(_ move: String) -> Binding<Int> {
        Binding(get: { values[move, default: 0] }, set: { values[move] = $0 })
    }

    private func save() {
        let entries = values.filter { $0.value > 0 }
        model.update { data in
            for (move, value) in entries {
                let hold = model.tracking(of: move).usesHold
                for _ in 0..<rounds {
                    data.log(LoggedSet(day: day, exerciseID: move, partID: partID, sessionID: session?.id,
                                       reps: hold ? nil : value, holdSeconds: hold ? value : nil))
                }
            }
        }
        dismiss()
    }
}

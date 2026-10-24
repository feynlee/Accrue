import AccrueKit
import SwiftUI

/// One exercise card on Train: a planned exercise inside one part of the day.
struct TrainCard: Identifiable, Hashable {
    let part: DayPart
    let partTitle: String
    let item: PlannedExercise
    /// Position inside its part, from 0.
    let index: Int
    let countInPart: Int
    /// Set when the part is a timed exercise; it then has this one card.
    var timed: TimedExercise? = nil

    var id: String { "\(part.id.uuidString)-\(item.id.uuidString)" }
}

/// Train: the week strip, the day's parts, and one swipeable card per exercise.
struct TrainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var day = DayKey.today()
    @State private var cardID: String?
    @State private var editingDay = false
    @State private var choosingOther = false
    @State private var finished: WorkoutSession?
    /// `-progressScreen howto` or `howtofix` opens the push-up how-to (used for screenshots).
    @State private var demoHowTo: Int? = ["howto": 2, "howtofix": 5][UserDefaults.standard.string(forKey: "progressScreen") ?? ""]
    /// `-progressScreen timededit` opens the first timed exercise's editor (screenshots).
    @State private var demoTimedEdit = UserDefaults.standard.string(forKey: "progressScreen") == "timededit"

    var body: some View {
        let parts = model.data.parts(on: day)
        let cards = cards(for: parts)
        let current = cards.first { $0.id == cardID } ?? cards.first

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                // The week hides during a workout, like the live board, to give the card the room.
                if model.data.activeSession == nil {
                    WeekStrip(selected: $day)
                }
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(day.weekday().name)
                            .font(.display(28))
                            .textCase(.uppercase)
                            .foregroundStyle(palette.text)
                        Text(day.date().formatted(.dateTime.month(.abbreviated).day()))
                            .font(.display(28))
                            .textCase(.uppercase)
                            .foregroundStyle(palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if day.startOfWeek() != DayKey.today().startOfWeek() {
                        Button("This week") { day = .today() }
                            .font(.inter(13, .bold))
                    }
                    Spacer()
                    Button("Edit day") { editingDay = true }
                        .font(.inter(13, .bold))
                        .padding(.vertical, 8)
                }
                .frame(minHeight: 36)
                if model.data.hasOverride(on: day) {
                    Text("Changed for this day only")
                        .font(.inter(12, .medium))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)

            if parts.isEmpty {
                restDay
            } else {
                partsRow(parts, cards: cards, current: current)
                    .padding(.bottom, 8)
                pager(cards)
                    .padding(.bottom, 8)
            }

            bottomBar(current: current)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .background(palette.background.ignoresSafeArea())
        .onChange(of: day) { cardID = nil }
        .onChange(of: cardioState, initial: true) { syncCardio() }
        .sheet(isPresented: $editingDay) {
            DayEditView(target: .date(day))
        }
        .sheet(isPresented: $choosingOther) {
            OtherWorkoutSheet(day: day)
        }
        .fullScreenCover(isPresented: Binding(get: { demoHowTo != nil }, set: { if !$0 { demoHowTo = nil } })) {
            HowToView(exerciseID: StarterIDs.pushUp, startStep: demoHowTo ?? 0)
        }
        .sheet(isPresented: $demoTimedEdit) {
            if let plan = model.data.timed.first {
                NavigationStack { TimedEditView(timedID: plan.id, startOpen: 2) }
            }
        }
        .sheet(item: $finished) { session in
            WorkoutSummaryView(session: session)
                .presentationDetents([.medium])
        }
    }

    /// What the cardio alert and GPS depend on: which workout, paused or not, and its goal.
    private var cardioState: [String] {
        guard let s = model.data.activeSession else { return [] }
        return [s.id.uuidString, "\(s.isPaused)", "\(s.goalSeconds ?? -1)", "\(s.goalMeters ?? -1)", "\(s.goalIsLastTime ?? false)"]
    }

    private func cards(for parts: [DayPart]) -> [TrainCard] {
        parts.flatMap { part in
            let title = model.data.title(of: part, catalog: model.catalog)
            if let plan = model.data.timedExercise(in: part) {
                return [TrainCard(part: part, partTitle: title, item: PlannedExercise(id: plan.id, exerciseID: "", sets: 1),
                                  index: 0, countInPart: 1, timed: plan)]
            }
            let items = model.data.items(in: part)
            return items.enumerated().map { index, item in
                TrainCard(part: part, partTitle: title, item: item, index: index, countInPart: items.count)
            }
        }
    }

    // MARK: Parts row

    private func partsRow(_ parts: [DayPart], cards: [TrainCard], current: TrainCard?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(parts) { part in
                        let on = current?.part.id == part.id
                        let live = model.data.activeSession?.partID == part.id
                        let done = !live && model.data.sessions(on: day).contains { $0.partID == part.id && !$0.isActive }
                        Button {
                            withAnimation { cardID = cards.first { $0.part.id == part.id }?.id }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: part))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(done || on ? palette.accentText : palette.secondary)
                                Text(model.data.title(of: part, catalog: model.catalog))
                                    .font(.inter(13, .heavy))
                                    .foregroundStyle(done && !on ? palette.secondary : palette.text)
                                let badge = done ? "✓" : live ? "● now" : tag(for: part)
                                if !badge.isEmpty {
                                    Text(badge)
                                        .font(.inter(11, .bold))
                                        .foregroundStyle(done ? palette.accentText : live ? palette.danger : palette.secondary)
                                }
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 14)
                            .frame(height: 40)
                            .overlay(alignment: .bottom) {
                                progressBars(for: part, current: on ? current : nil)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 5)
                            }
                            .background(on ? palette.raised : palette.sunken, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? palette.accentText : palette.raised, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .id(part.id)
                        .accessibilityLabel(model.data.title(of: part, catalog: model.catalog) + (done ? ", done and saved" : live ? ", recording" : ""))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Button {
                        editingDay = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(palette.text)
                            .overlay(Circle().strokeBorder(palette.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a preset or an exercise to this day")
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: current?.part.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    /// Only a preset gets a count ("3 lifts"); a single exercise needs no tag.
    private func tag(for part: DayPart) -> String {
        switch part.content {
        case .preset:
            let items = model.data.items(in: part)
            let lifts = items.filter { model.tracking(of: $0.exerciseID).isSetBased }.count
            return lifts == items.count ? "\(lifts) lifts" : "\(items.count)"
        case .exercise, .timed: return ""
        }
    }

    /// One bar per exercise in the part: lime when its sets are done, white for the card on screen,
    /// faint for the rest.
    private func progressBars(for part: DayPart, current: TrainCard?) -> some View {
        let items = model.data.items(in: part)
        return HStack(spacing: 2) {
            ForEach(items) { item in
                let logged = model.data.sets(of: item.exerciseID, on: day, partID: part.id).filter { !$0.isWarmup }.count
                let done = model.tracking(of: item.exerciseID).isSetBased ? logged >= max(1, item.sets) : logged > 0
                let isCurrent = current?.item.id == item.id
                Capsule()
                    .fill(done ? palette.accentFill : isCurrent ? palette.text : palette.secondary.opacity(0.35))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func icon(for part: DayPart) -> String {
        if part.timedID != nil { return "timer" }
        let items = model.data.items(in: part)
        return items.allSatisfy({ !model.tracking(of: $0.exerciseID).isSetBased }) ? "figure.run" : "dumbbell"
    }

    // MARK: Cards

    /// One full-width card at a time. The order is the day's plan, so Next (shown once an exercise
    /// is done) moves on; swiping still works for jumping around.
    private func pager(_ cards: [TrainCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 16) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                    let next = nextStop(after: i, in: cards)
                    Group {
                        if let plan = card.timed {
                            TimedCard(part: card.part, plan: plan, day: day, nextTitle: next?.title,
                                      onFinishPart: { finishPart(card, cards: cards) })
                        } else if model.isCardio(card.part) {
                            RunCard(card: card, day: day, nextTitle: next?.title,
                                    onFinishPart: { finishPart(card, cards: cards) })
                        } else {
                            ExerciseCard(card: card, day: day, nextTitle: next?.title,
                                         onNext: { if let id = next?.cardID { withAnimation { cardID = id } } },
                                         onFinishPart: { finishPart(card, cards: cards) })
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $cardID)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    /// Where Next goes: the next exercise in the part, or the first card of the next part.
    private func nextStop(after i: Int, in cards: [TrainCard]) -> (title: String, cardID: String)? {
        guard i + 1 < cards.count else { return nil }
        let card = cards[i], next = cards[i + 1]
        if next.part.id == card.part.id { return (model.name(of: next.item.exerciseID), next.id) }
        return (next.partTitle, next.id)
    }

    /// Finish on a part's last card: save its workout and move to the next part.
    private func finishPart(_ card: TrainCard, cards: [TrainCard]) {
        if let session = model.data.activeSession, session.partID == card.part.id {
            model.endWorkout(session.id)
            // Timed and cardio cards show their own "done"; a lifting part gets the summary.
            if card.timed == nil, !model.isCardio(card.part) { finished = model.data.sessions.first { $0.id == session.id } }
        }
        let partIDs = cards.map(\.part.id).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
        if let i = partIDs.firstIndex(of: card.part.id), i + 1 < partIDs.count {
            withAnimation { cardID = cards.first { $0.part.id == partIDs[i + 1] }?.id }
        }
    }

    // MARK: Cardio

    /// For a cardio workout: set its goal when it starts, keep the target alert in step with the
    /// clock, and follow GPS while an outdoor one is recording.
    private func syncCardio() {
        let tracker = model.runTracker
        guard let session = model.data.activeSession,
              let part = model.data.parts(on: session.day).first(where: { $0.id == session.partID }),
              case .exercise(let item) = part.content, !model.tracking(of: item.exerciseID).isSetBased else {
            tracker.stop()
            TargetAlerts.sync(nil, name: "")
            return
        }
        let id = session.id
        let name = model.name(of: item.exerciseID)
        if session.goalIsLastTime == nil {
            model.applyCardioGoal(id, exerciseID: item.exerciseID, plannedMinutes: item.minutes)
            TargetAlerts.requestPermission()
        }
        TargetAlerts.sync(model.data.activeSession, name: name)
        // Screenshots use made-up distance, not the simulator's GPS.
        guard model.exercise(item.exerciseID)?.isOutdoor == true, model.tracking(of: item.exerciseID).usesDistance,
              !UserDefaults.standard.bool(forKey: "demoData") else {
            tracker.stop()
            return
        }
        tracker.start(sessionID: id, from: session.distanceMeters ?? 0,
                      isPaused: { [model] in model.data.activeSession?.isPaused ?? true },
                      onDistance: { [model] meters in
                          let before = model.data.activeSession
                          model.update { $0.updateSession(id) { $0.distanceMeters = meters } }
                          if let before, let goal = before.goalMeters, (before.distanceMeters ?? 0) < goal, meters >= goal {
                              TargetAlerts.distanceReached(before, name: name)
                          }
                      })
    }

    // MARK: Rest day

    private var restDay: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(palette.secondary)
            Text("Rest day")
                .font(.display(32))
                .textCase(.uppercase)
                .foregroundStyle(palette.text)
            Text("Nothing planned. Add a preset or an exercise if you want to train.")
                .font(.inter(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 40)
            Button("Add to \(day.weekday().name)") { editingDay = true }
                .buttonStyle(.soft)
                .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Start / live bar

    @ViewBuilder
    private func bottomBar(current: TrainCard?) -> some View {
        if let session = model.data.activeSession {
            LiveBar(session: session) {
                let id = session.id
                let part = model.data.parts(on: session.day).first { $0.id == session.partID }
                model.endWorkout(id)
                if session.timer == nil, !(part.map(model.isCardio) ?? false) {
                    finished = model.data.sessions.first { $0.id == id }
                }
            }
        } else {
            HStack(spacing: 8) {
                if let current {
                    Button {
                        let part = current.part
                        let title = current.partTitle
                        model.update { $0.startSession(day: day, partID: part.id, title: title) }
                    } label: {
                        Label("Start \(current.partTitle)", systemImage: "play.fill")
                            .labelStyle(StartLabelStyle())
                    }
                    .buttonStyle(.outline)
                    .lineLimit(1)
                }
                Button {
                    choosingOther = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run").foregroundStyle(palette.accentText)
                        Text("Other")
                    }
                }
                .buttonStyle(.soft)
                .frame(maxWidth: current == nil ? .infinity : 118)
                .accessibilityHint("Start a different workout: run, walk, cycling and more")
            }
        }
    }
}

/// Small play icon before "Start Pull B", as on the board.
private struct StartLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 12, weight: .bold))
            configuration.title
        }
    }
}

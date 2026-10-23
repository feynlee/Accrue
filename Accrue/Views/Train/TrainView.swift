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
        .sheet(isPresented: $editingDay) {
            DayEditView(target: .date(day))
        }
        .sheet(isPresented: $choosingOther) {
            OtherWorkoutSheet(day: day)
        }
        .sheet(item: $finished) { session in
            WorkoutSummaryView(session: session)
                .presentationDetents([.medium])
        }
    }

    private func cards(for parts: [DayPart]) -> [TrainCard] {
        parts.flatMap { part in
            let items = model.data.items(in: part)
            let title = model.data.title(of: part, catalog: model.catalog)
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
        case .exercise: return ""
        }
    }

    private func icon(for part: DayPart) -> String {
        let items = model.data.items(in: part)
        return items.allSatisfy({ !model.tracking(of: $0.exerciseID).isSetBased }) ? "figure.run" : "dumbbell"
    }

    // MARK: Cards

    /// Cards are 48 pt narrower than the screen, so the next one peeks in from the right.
    private func pager(_ cards: [TrainCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                    let next = nextStop(after: i, in: cards)
                    ExerciseCard(card: card, day: day, nextTitle: next?.title,
                                 onNext: { if let id = next?.cardID { withAnimation { cardID = id } } },
                                 onFinishPart: { finishPart(card, cards: cards) })
                        .containerRelativeFrame(.horizontal) { width, _ in width - 48 }
                        .id(card.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $cardID)
        .scrollIndicators(.hidden)
        .contentMargins(.leading, 24, for: .scrollContent)
        .contentMargins(.trailing, 24, for: .scrollContent)
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
            model.update { $0.endSession(session.id) }
            finished = model.data.sessions.first { $0.id == session.id }
        }
        let partIDs = cards.map(\.part.id).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
        if let i = partIDs.firstIndex(of: card.part.id), i + 1 < partIDs.count {
            withAnimation { cardID = cards.first { $0.part.id == partIDs[i + 1] }?.id }
        }
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
                model.update { $0.endSession(id) }
                finished = model.data.sessions.first { $0.id == id }
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

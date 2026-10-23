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
            VStack(alignment: .leading, spacing: 12) {
                WeekStrip(selected: $day)
                HStack(alignment: .firstTextBaseline) {
                    Text(day.weekday().name)
                        .font(.display(36))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.text)
                    if day != DayKey.today() {
                        Button("Today") { day = .today() }
                            .font(.inter(13, .bold))
                    }
                    Spacer()
                    Button("Edit day") { editingDay = true }
                        .font(.inter(15, .bold))
                }
                if model.data.hasOverride(on: day) {
                    Text("Changed for this day only")
                        .font(.inter(12, .medium))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if parts.isEmpty {
                restDay
            } else {
                partsRow(parts, cards: cards, current: current)
                    .padding(.top, 12)
                pager(cards)
                    .padding(.top, 10)
            }

            bottomBar(current: current)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
                HStack(spacing: 8) {
                    ForEach(parts) { part in
                        let on = current?.part.id == part.id
                        let items = model.data.items(in: part)
                        Button {
                            withAnimation { cardID = cards.first { $0.part.id == part.id }?.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(model.data.title(of: part, catalog: model.catalog))
                                    .font(.inter(14, .bold))
                                Text(tag(for: part, count: items.count))
                                    .font(.inter(11, .semibold))
                                    .foregroundStyle(on ? palette.onAccent.opacity(0.7) : palette.secondary)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 38)
                            .foregroundStyle(on ? palette.onAccent : palette.text)
                            .background(on ? palette.accentFill : palette.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(part.id)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Button {
                        editingDay = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(palette.text)
                            .background(palette.card, in: Circle())
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

    private func tag(for part: DayPart, count: Int) -> String {
        switch part.content {
        case .preset: "\(count)"
        case .exercise(let item):
            model.tracking(of: item.exerciseID).isSetBased ? "\(item.sets) sets" : "\(item.minutes ?? 30) min"
        }
    }

    // MARK: Cards

    private func pager(_ cards: [TrainCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(cards) { card in
                    ExerciseCard(card: card, day: day) {
                        finishPart(card, cards: cards)
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
                    Button("Start \(current.partTitle)") {
                        let part = current.part
                        let title = current.partTitle
                        model.update { $0.startSession(day: day, partID: part.id, title: title) }
                    }
                    .buttonStyle(.outline)
                    .lineLimit(1)
                }
                Button("Other") { choosingOther = true }
                    .buttonStyle(.soft)
                    .frame(maxWidth: current == nil ? .infinity : 110)
                    .accessibilityHint("Start a different workout: run, walk, cycling and more")
            }
        }
    }
}

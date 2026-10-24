import AccrueKit
import SwiftUI

/// Edit a day's parts: reorder, remove, add a preset or one exercise.
/// From Train it asks "Today only" or "Every <weekday>"; from Plans it edits the routine.
struct DayEditView: View {
    enum Target: Hashable {
        case date(DayKey)
        case weekday(Weekday)
    }

    enum Scope: Hashable {
        case once, every
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let target: Target
    @State private var parts: [DayPart] = []
    @State private var scope = Scope.once
    @State private var adding = false
    @State private var loaded = false

    private var weekday: Weekday {
        switch target {
        case .date(let day): day.weekday()
        case .weekday(let w): w
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if case .date(let day) = target {
                    Section {
                        SegmentPicker(options: [(Scope.once, "This day only"), (Scope.every, "Every \(weekday.name)")],
                                      selection: $scope, filled: true)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } footer: {
                        Text(scope == .once
                             ? "Changes count for \(day.date().formatted(.dateTime.month(.wide).day())) only. Next \(weekday.name) follows the routine."
                             : "Changes save to your weekly routine.")
                    }
                }
                Section {
                    ForEach(parts) { part in
                        partRow(part)
                    }
                    .onMove { parts.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { parts.remove(atOffsets: $0) }
                    Button {
                        adding = true
                    } label: {
                        Label("Add a preset or exercise", systemImage: "plus")
                            .font(.inter(15, .bold))
                    }
                    .listRowBackground(palette.card)
                } header: {
                    Text(parts.isEmpty ? "Rest day" : "In this order")
                } footer: {
                    Text("Each part is its own workout: you start it, and it saves on its own.")
                }
                if case .date(let day) = target, model.data.hasOverride(on: day) {
                    Section {
                        Button("Go back to the routine") {
                            model.update { $0.clearOverride(on: day) }
                            dismiss()
                        }
                        .listRowBackground(palette.card)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(weekday.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.fontWeight(.bold)
                }
            }
            .sheet(isPresented: $adding) {
                AddPartSheet { parts.append($0) }
            }
            .onAppear(perform: load)
        }
    }

    private func partRow(_ part: DayPart) -> some View {
        let items = model.data.items(in: part)
        let isPreset = if case .preset = part.content { true } else { false }
        let timed = model.data.timedExercise(in: part)
        return HStack(spacing: 12) {
            Image(systemName: timed != nil ? "timer" : isPreset ? "list.bullet.rectangle" : "figure.strengthtraining.traditional")
                .foregroundStyle(palette.accentText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.data.title(of: part, catalog: model.catalog))
                    .font(.inter(15, .bold))
                Text(timed.map { "Timed · \($0.moves.count) moves · " + DurationFormat.clock(TimeInterval($0.totalSeconds())) }
                     ?? (isPreset
                         ? "Preset · " + items.map { model.name(of: $0.exerciseID) }.joined(separator: ", ")
                         : "Exercise · \(items.first.map(summary) ?? "")"))
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        }
        .listRowBackground(palette.card)
    }

    private func summary(_ item: PlannedExercise) -> String {
        let tracking = model.tracking(of: item.exerciseID)
        if !tracking.isSetBased { return "\(item.minutes ?? 30) min" }
        if let hold = item.holdSeconds { return "\(item.sets) × \(DurationFormat.clock(TimeInterval(hold)))" }
        return "\(item.sets) × \(item.reps ?? 10)"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .date(let day): parts = model.data.parts(on: day)
        case .weekday(let w): parts = model.data.routine[w]
        }
    }

    private func save() {
        let parts = parts
        switch target {
        case .date(let day):
            let scope: EditScope = scope == .once ? .thisDayOnly : .everyWeek
            model.update { $0.setParts(parts, on: day, scope: scope) }
        case .weekday(let w):
            model.update { $0.routine[w] = parts }
        }
        dismiss()
    }
}

/// Pick a preset, or one exercise, to add to a day.
struct AddPartSheet: View {
    enum Kind: Hashable { case presets, exercises, timed }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onAdd: (DayPart) -> Void
    @State private var kind = Kind.presets

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentPicker(options: [(Kind.presets, "Presets"), (Kind.exercises, "Exercises"), (Kind.timed, "Timed")],
                              selection: $kind, filled: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                if kind == .presets {
                    List {
                        if model.data.presets.isEmpty {
                            Text("No presets yet. Make one in Plans.")
                                .foregroundStyle(palette.secondary)
                                .listRowBackground(palette.card)
                        }
                        ForEach(model.data.presets) { preset in
                            Button {
                                onAdd(.preset(preset.id))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name).font(.inter(15, .bold)).foregroundStyle(palette.text)
                                    Text(preset.items.map { model.name(of: $0.exerciseID) }.joined(separator: ", "))
                                        .font(.inter(12))
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .listRowBackground(palette.card)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .navigationTitle("Add a preset")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                } else if kind == .timed {
                    List {
                        ForEach(model.data.timed) { plan in
                            Button {
                                onAdd(.timed(plan.id))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.name).font(.inter(15, .bold)).foregroundStyle(palette.text)
                                    Text(plan.summaryLine).font(.inter(12)).foregroundStyle(palette.secondary).lineLimit(1)
                                }
                            }
                            .listRowBackground(palette.card)
                        }
                        Section {
                            ForEach(TimedStyle.allCases, id: \.self) { style in
                                Button {
                                    let plan = TimedExercise.template(style)
                                    model.update { $0.upsert(plan) }
                                    onAdd(.timed(plan.id))
                                    dismiss()
                                } label: {
                                    Label("New \(style.label) · \(style.detail)", systemImage: "plus")
                                        .font(.inter(15, .bold))
                                }
                                .listRowBackground(palette.card)
                            }
                        } footer: {
                            Text("Change its moves and timing from the card's Edit, or in Plans › Exercises.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .navigationTitle("Add a timed exercise")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
                } else {
                    ExercisePicker(title: "Add an exercise") { id in
                        onAdd(.exercise(model.plannedDefaults(for: id)))
                        dismiss()
                    }
                }
            }
            .background(palette.background)
        }
    }
}

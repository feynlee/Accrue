import AccrueKit
import SwiftUI

/// Edit a preset: name, the weekdays it is on, and its exercises with targets.
struct PresetEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let presetID: UUID
    @State private var adding = false
    @State private var editingItem: PlannedExercise?
    @State private var confirmingDelete = false

    var body: some View {
        if let preset = model.data.preset(presetID) {
            content(preset)
        } else {
            Text("This preset was removed.")
                .foregroundStyle(palette.secondary)
        }
    }

    private func content(_ preset: Preset) -> some View {
        List {
            Section {
                TextField("Name", text: Binding(
                    get: { preset.name },
                    set: { name in change { $0.name = name } }
                ))
                .font(.display(30))
                .textCase(.uppercase)
                .listRowBackground(Color.clear)
            }
            Section("Scheduled on") {
                let scheduled = model.data.weekdays(using: presetID)
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases) { day in
                        let on = scheduled.contains(day)
                        Button {
                            model.update { $0.schedule(presetID, on: day, !on) }
                        } label: {
                            Text(day.letter)
                                .font(.inter(13, .bold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(on ? palette.onAccent : palette.secondary)
                                .background(on ? palette.accentFill : palette.raised,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.name + (on ? ", scheduled" : ""))
                    }
                }
                .listRowBackground(palette.card)
            }
            Section {
                ForEach(preset.items) { item in
                    Button {
                        editingItem = item
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name(of: item.exerciseID))
                                .font(.inter(15, .bold))
                                .foregroundStyle(palette.text)
                            HStack(spacing: 6) {
                                ForEach(chips(item), id: \.self) { chip in
                                    Text(chip)
                                        .font(.inter(12, .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(palette.text)
                                }
                            }
                        }
                    }
                    .listRowBackground(palette.card)
                }
                .onMove { from, to in change { $0.items.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in change { $0.items.remove(atOffsets: offsets) } }
                Button {
                    adding = true
                } label: {
                    Label("Add an exercise", systemImage: "plus").font(.inter(15, .bold))
                }
                .listRowBackground(palette.card)
            } header: {
                Text("Exercises")
            } footer: {
                Text("Changes here update every day that uses \(preset.name). To change one session only, use Edit day on Train.")
            }
            Section {
                Button("Duplicate") {
                    var copy = preset
                    copy.id = UUID()
                    copy.name = preset.name + " copy"
                    copy.items = preset.items.map { var i = $0; i.id = UUID(); return i }
                    model.update { $0.upsert(copy) }
                }
                Button("Delete preset", role: .destructive) { confirmingDelete = true }
            }
            .listRowBackground(palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $adding) {
            NavigationStack {
                ExercisePicker(title: "Add to \(preset.name)") { id in
                    let item = model.plannedDefaults(for: id)
                    change { $0.items.append(item) }
                    adding = false
                }
            }
        }
        .sheet(item: $editingItem) { item in
            PlannedExerciseEditor(item: item) { updated in
                change { p in
                    if let i = p.items.firstIndex(where: { $0.id == updated.id }) { p.items[i] = updated }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete \(preset.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.update { $0.deletePreset(presetID) }
                dismiss()
            }
        } message: {
            Text("It comes off every day it is on. Logged sets stay.")
        }
    }

    private func change(_ edit: (inout Preset) -> Void) {
        guard var preset = model.data.preset(presetID) else { return }
        edit(&preset)
        model.update { $0.upsert(preset) }
    }

    private func chips(_ item: PlannedExercise) -> [String] {
        let tracking = model.tracking(of: item.exerciseID)
        var chips: [String] = []
        if let w = item.weightKg, tracking.usesWeight || tracking == .reps {
            chips.append((tracking == .reps ? "+" : "") + "\(unit.format(kg: w)) \(unit.label)")
        }
        switch tracking {
        case .time, .timeHR, .distanceTimeHR:
            chips.append("\(item.minutes ?? 30) min")
        case .hold, .weightHold:
            chips.append("\(item.sets) × \(DurationFormat.clock(TimeInterval(item.holdSeconds ?? 30)))")
        default:
            chips.append("\(item.sets) × \(item.reps ?? 10)" + (item.pauseSeconds > 0 ? " · \(item.pauseSeconds) s pause" : ""))
        }
        if tracking.isSetBased, item.restSeconds > 0 { chips.append("rest \(DurationFormat.clock(TimeInterval(item.restSeconds)))") }
        return chips
    }
}

/// Sets, reps or hold, starting weight, pause and rest for one planned exercise.
struct PlannedExerciseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @State var item: PlannedExercise
    let onSave: (PlannedExercise) -> Void

    var body: some View {
        let tracking = model.tracking(of: item.exerciseID)
        NavigationStack {
            Form {
                if tracking.isSetBased {
                    Stepper("Sets: \(item.sets)", value: $item.sets, in: 1...20)
                    if tracking.usesHold {
                        Stepper("Hold: \(DurationFormat.clock(TimeInterval(item.holdSeconds ?? 30)))",
                                value: Binding(get: { item.holdSeconds ?? 30 }, set: { item.holdSeconds = $0 }),
                                in: 5...600, step: 5)
                    } else if tracking != .weightDistance {
                        Stepper("Reps: \(item.reps ?? 10)",
                                value: Binding(get: { item.reps ?? 10 }, set: { item.reps = $0 }), in: 1...100)
                        Picker("Pause at top", selection: $item.pauseSeconds) {
                            ForEach([0, 1, 2, 3, 5], id: \.self) { Text($0 == 0 ? "None" : "\($0) s").tag($0) }
                        }
                    }
                    if tracking.usesWeight || tracking == .reps {
                        let shown = item.weightKg.map { unit.format(kg: $0) } ?? "—"
                        Stepper("\(tracking == .reps ? "Added weight" : "Start weight"): \(shown) \(unit.label)") {
                            item.weightKg = unit.rounded(kg: (item.weightKg ?? 0) + unit.toKg(unit.step))
                        } onDecrement: {
                            let next = (item.weightKg ?? 0) - unit.toKg(unit.step)
                            item.weightKg = next <= 0 ? nil : unit.rounded(kg: next)
                        }
                        Text("Left empty, Train starts from what you did last time.")
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                    }
                    Stepper("Rest: \(DurationFormat.clock(TimeInterval(item.restSeconds)))",
                            value: $item.restSeconds, in: 0...600, step: 15)
                } else {
                    Stepper("Minutes: \(item.minutes ?? 30)",
                            value: Binding(get: { item.minutes ?? 30 }, set: { item.minutes = $0 }), in: 5...300, step: 5)
                }
            }
            .navigationTitle(model.name(of: item.exerciseID))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(item)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

import AccrueKit
import SwiftUI

/// How to do one exercise: muscles, setup, steps, cues, breathing, common mistakes.
/// Text comes from Accrue's own family research; only the name is openGym's.
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    @State private var addedTo: String?
    @State private var showingHowTo = false

    var body: some View {
        if let exercise = model.exercise(exerciseID) {
            content(exercise, family: model.catalog.family(for: exercise), subtype: model.catalog.subtype(for: exercise))
        } else {
            Text("This exercise is not in the catalog.")
                .foregroundStyle(palette.secondary)
        }
    }

    private func content(_ exercise: Exercise, family: Family?, subtype: Subtype?) -> some View {
        let muscles = model.catalog.muscles(for: exercise)
        let history = model.history(of: exercise.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.displayName)
                        .font(.display(36))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.text)
                    if let family {
                        Text(subtype.map { "\(family.name) · \($0.name)" } ?? family.name)
                            .font(.inter(13, .semibold))
                            .foregroundStyle(palette.secondary)
                        Text(family.pattern)
                            .font(.inter(15))
                            .foregroundStyle(palette.text)
                    }
                    if let subtype {
                        Text(subtype.change)
                            .font(.inter(14))
                            .foregroundStyle(palette.secondary)
                    }
                }

                if family != nil {
                    Button {
                        showingHowTo = true
                    } label: {
                        Label("Step by step", systemImage: "play.fill")
                    }
                    .buttonStyle(.soft)
                }

                if let last = history.days.last {
                    block("Your best and last") {
                        Text("Last (\(last.day.date().formatted(.dateTime.month(.abbreviated).day()))): \(last.line(unit: unit, tracking: history.tracking))")
                        if let best = history.days.compactMap(\.strength).max(), history.tracking == .weightReps {
                            Text("Est. max: \(unit.format(kg: best)) \(unit.label)")
                        }
                    }
                }

                if !muscles.primary.isEmpty {
                    block("Working muscles") {
                        FlowLayout(spacing: 6) {
                            ForEach(muscles.primary, id: \.self) { MuscleChip(label: model.catalog.muscleLabel($0), primary: true) }
                            ForEach(muscles.secondary, id: \.self) { MuscleChip(label: model.catalog.muscleLabel($0), primary: false) }
                        }
                    }
                }

                if let family {
                    if !family.setup.isEmpty {
                        block("Setup") { bullets(family.setup) }
                    }
                    if !family.steps.isEmpty {
                        block("Steps") {
                            ForEach(Array(family.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.number(20))
                                        .foregroundStyle(palette.accentText)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.phase).font(.inter(14, .bold))
                                        Text(step.text).font(.inter(14)).foregroundStyle(palette.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !family.cues.isEmpty {
                        block("Cues") {
                            ForEach(family.cues, id: \.cue) { cue in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(cue.joint.capitalized): \(cue.cue)").font(.inter(14, .bold))
                                    Text(cue.why).font(.inter(13)).foregroundStyle(palette.secondary)
                                }
                            }
                        }
                    }
                    block("Breathing") {
                        Text(family.breathing)
                        if let note = family.tempo?.note { Text("Tempo: \(note)").foregroundStyle(palette.secondary) }
                    }
                    if !family.mistakes.isEmpty {
                        block("Common mistakes") {
                            ForEach(family.mistakes) { mistake in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(mistake.name).font(.inter(14, .bold)).foregroundStyle(palette.warmup)
                                    Text(mistake.looks).font(.inter(13)).foregroundStyle(palette.secondary)
                                    Text("Fix: \(mistake.fix)").font(.inter(13, .semibold))
                                }
                            }
                        }
                    }
                    if !family.safety.isEmpty {
                        block("If something hurts") { bullets(family.safety) }
                    }
                    if !family.easier.isEmpty || !family.harder.isEmpty {
                        block("Easier and harder") {
                            if !family.easier.isEmpty { Text("Easier: " + family.easier.joined(separator: ", ")) }
                            if !family.harder.isEmpty { Text("Harder: " + family.harder.joined(separator: ", ")) }
                        }
                    }
                    Text("Research confidence: \(family.confidence). Form notes are Accrue's own, from published studies and coaching practice.")
                        .font(.inter(11))
                        .foregroundStyle(palette.secondary)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingHowTo) {
            HowToView(exerciseID: exercise.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(model.data.presets) { preset in
                        Button(preset.name) {
                            var p = preset
                            p.items.append(model.plannedDefaults(for: exercise.id))
                            model.update { $0.upsert(p) }
                            addedTo = preset.name
                        }
                    }
                } label: {
                    Label("Add to preset", systemImage: "plus.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.update { $0.toggleFavorite(exercise.id) }
                } label: {
                    Image(systemName: model.data.isFavorite(exercise.id) ? "star.fill" : "star")
                }
                .accessibilityLabel(model.data.isFavorite(exercise.id) ? "Remove from favorites" : "Add to favorites")
            }
        }
        .overlay(alignment: .bottom) {
            if let addedTo {
                Text("Added to \(addedTo)")
                    .font(.inter(14, .bold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(palette.onAccent)
                    .background(palette.accentFill, in: Capsule())
                    .padding(.bottom, 20)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        self.addedTo = nil
                    }
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            VStack(alignment: .leading, spacing: 10) { content() }
                .font(.inter(14))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card(radius: 16)
        }
    }

    private func bullets(_ lines: [String]) -> some View {
        ForEach(lines, id: \.self) { line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(palette.accentText).frame(width: 5, height: 5)
                Text(line)
            }
        }
    }
}

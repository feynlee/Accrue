import AccrueKit
import SwiftUI

/// The bar that replaces Start while a workout runs: Pause, time, heart rate, kcal, and an icon-only End.
struct LiveBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let session: WorkoutSession
    let onEnd: () -> Void
    @State private var confirmingEnd = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                let id = session.id
                model.update { $0.togglePause(id) }
            } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(palette.text)
                    .background(palette.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: -2) {
                        Text(DurationFormat.clock(session.activeSeconds(at: context.date)))
                            .font(.number(28))
                            .monospacedDigit()
                            .foregroundStyle(session.isPaused ? palette.warmup : palette.text)
                        Text(session.isPaused ? "PAUSED" : session.title.uppercased())
                            .font(.inter(10, .bold))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    metric("--", "BPM", icon: "heart.fill", color: palette.danger)
                    metric("--", "KCAL", icon: "flame.fill", color: palette.warmup)
                }
            }

            Button {
                confirmingEnd = true
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.white)
                    .background(palette.danger, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End workout")
        }
        .padding(8)
        .card(radius: 30)
        .confirmationDialog("End \(session.title)?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End and save", role: .destructive, action: onEnd)
        } message: {
            Text("Sets you logged stay in your history either way.")
        }
    }

    /// Heart rate and calories arrive with the Apple Health step; until then they show dashes.
    private func metric(_ value: String, _ label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: -2) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
                Text(value).font(.number(22)).foregroundStyle(palette.text)
            }
            Text(label).font(.inter(10, .bold)).foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) not available yet")
    }
}

/// Shown when a workout ends: total time against active time, and what was done.
struct WorkoutSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let session: WorkoutSession

    var body: some View {
        let sets = model.data.sets(in: session.id)
        let working = sets.filter { !$0.isWarmup }
        let volume = TrainingMath.volume(sets)
        let exercises = Set(sets.map(\.exerciseID)).count
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(session.title) done")
                    .font(.display(32))
                    .textCase(.uppercase)
                Spacer()
                Text("Saved")
                    .font(.inter(12, .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(palette.onAccent)
                    .background(palette.accentFill, in: Capsule())
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    stat(DurationFormat.clock(session.totalSeconds(at: .now)), "Total time")
                    stat(DurationFormat.clock(session.activeSeconds(at: .now)), "Active time")
                }
                GridRow {
                    stat("\(working.count)", "Working sets")
                    stat("\(exercises)", exercises == 1 ? "Exercise" : "Exercises")
                }
                if volume > 0 {
                    GridRow {
                        stat(unit.format(kg: volume), "Volume (\(unit.label))")
                    }
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
        }
        .padding(20)
        .foregroundStyle(palette.text)
        .background(palette.background.ignoresSafeArea())
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.number(30)).monospacedDigit()
            Text(label).font(.inter(12, .medium)).foregroundStyle(palette.secondary)
        }
    }
}

/// Today's sets of one exercise, opened from "Set 3 of 5".
struct SetsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    let day: DayKey
    let partID: UUID?

    var body: some View {
        let sets = model.data.sets(of: exerciseID, on: day, partID: partID)
        let tracking = model.tracking(of: exerciseID)
        NavigationStack {
            List {
                if sets.isEmpty {
                    Text("No sets yet. Each Log adds one here.")
                        .foregroundStyle(palette.secondary)
                }
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    HStack {
                        Text("\(index + 1)")
                            .font(.number(20))
                            .foregroundStyle(palette.secondary)
                            .frame(width: 28, alignment: .leading)
                        Text(describe(set, tracking: tracking))
                            .font(.inter(16, .semibold))
                        Spacer()
                        Button {
                            var changed = set
                            changed.isWarmup.toggle()
                            model.update { $0.updateSet(changed) }
                        } label: {
                            Text(set.isWarmup ? "Warm-up" : "Working")
                                .font(.inter(12, .bold))
                                .foregroundStyle(set.isWarmup ? palette.warmup : palette.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint("Switches between warm-up and working set")
                    }
                    .listRowBackground(palette.card)
                }
                .onDelete { offsets in
                    let ids = offsets.map { sets[$0].id }
                    model.update { data in ids.forEach { data.deleteSet($0) } }
                }
                if let last = model.history(of: exerciseID).lastTime(before: day) {
                    Section("Last time") {
                        Text(last.line(unit: unit, tracking: tracking))
                            .foregroundStyle(palette.secondary)
                            .listRowBackground(palette.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("\(model.name(of: exerciseID)) · today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func describe(_ set: LoggedSet, tracking: Tracking) -> String {
        var parts: [String] = []
        if let w = set.weightKg, w > 0 { parts.append("\(tracking == .reps ? "+" : "")\(unit.format(kg: w)) \(unit.label)") }
        if let r = set.reps { parts.append("\(r) reps") }
        if let h = set.holdSeconds { parts.append(DurationFormat.clock(TimeInterval(h))) }
        if let d = set.durationSeconds { parts.append(DurationFormat.clock(TimeInterval(d))) }
        if let m = set.distanceMeters { parts.append(m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m)) m") }
        if set.pauseSeconds > 0 { parts.append("\(set.pauseSeconds) s pause") }
        return parts.joined(separator: " × ")
    }
}

/// "Other": start a workout that is not on today's plan, such as a run or a walk.
struct OtherWorkoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let day: DayKey

    var body: some View {
        NavigationStack {
            ExercisePicker(title: "Other workout", suggestions: .cardio) { exerciseID in
                let item = model.plannedDefaults(for: exerciseID)
                let part = DayPart.exercise(item)
                let parts = model.data.parts(on: day) + [part]
                let title = model.name(of: exerciseID)
                model.update {
                    $0.setParts(parts, on: day, scope: .thisDayOnly)
                    $0.startSession(day: day, partID: part.id, title: title)
                }
                dismiss()
            }
        }
    }
}

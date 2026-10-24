import AccrueKit
import SwiftUI

/// The bar that replaces Start while a workout runs: Pause, time, heart rate, kcal, and an icon-only End.
struct LiveBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let session: WorkoutSession
    let onEnd: () -> Void
    @State private var confirmingEnd = false

    /// Working sets logged in this part against the sets planned for it; for a timed exercise,
    /// the moves done.
    private func progress(at now: Date) -> Double {
        guard let partID = session.partID,
              let part = model.data.parts(on: session.day).first(where: { $0.id == partID }) else { return 0 }
        if let plan = model.data.timedExercise(in: part), let timer = session.timer {
            let p = timer.position(in: plan, at: session.activeSeconds(at: now))
            return p.workCount == 0 ? 0 : Double(p.worksDone) / Double(p.workCount)
        }
        let items = model.data.items(in: part)
        let planned = items.reduce(0) { $0 + max(1, $1.sets) }
        let done = items.reduce(0) { total, item in
            total + min(max(1, item.sets), model.data.sets(of: item.exerciseID, on: session.day, partID: partID).filter { !$0.isWarmup }.count)
        }
        return planned == 0 ? 0 : Double(done) / Double(planned)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    let id = session.id
                    model.update { $0.togglePause(id) }
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(palette.onAccent)
                        .background(session.isPaused ? palette.accentFill : palette.warmup, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 0) {
                        column {
                            Text(session.isPaused ? "Paused" : DurationFormat.clock(session.activeSeconds(at: context.date)))
                                .font(.number(26))
                                .monospacedDigit()
                                .foregroundStyle(session.isPaused ? palette.warmup : palette.text)
                        } label: {
                            Text(session.title.uppercased())
                                .foregroundStyle(palette.secondary)
                        }
                        Rectangle().fill(palette.raised).frame(width: 1, height: 48)
                        column {
                            Text("--").font(.number(26)).foregroundStyle(palette.text)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill").foregroundStyle(palette.danger)
                                Text(session.isPaused ? "PAUSED" : "BPM").foregroundStyle(palette.secondary)
                            }
                        }
                        .opacity(session.isPaused ? 0.45 : 1)
                        .accessibilityLabel("Heart rate not available yet")
                        Rectangle().fill(palette.raised).frame(width: 1, height: 48)
                        column {
                            Text("--").font(.number(26)).foregroundStyle(palette.text)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill").foregroundStyle(palette.warmup)
                                Text("KCAL").foregroundStyle(palette.secondary)
                            }
                        }
                        .opacity(session.isPaused ? 0.45 : 1)
                        .accessibilityLabel("Calories not available yet")
                    }
                }

                Button {
                    confirmingEnd = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.white)
                        .background(palette.danger, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End workout")
            }
            .padding(.horizontal, 8)
            .frame(height: 72)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let done = progress(at: context.date)
                GeometryReader { proxy in
                    Rectangle().fill(palette.raised)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(palette.accentFill).frame(width: proxy.size.width * done)
                        }
                }
                .frame(height: 4)
                .accessibilityLabel("\(Int(done * 100)) percent of the plan done")
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .confirmationDialog("End \(session.title)?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End and save", role: .destructive, action: onEnd)
        } message: {
            Text("Sets you logged stay in your history either way.")
        }
    }

    private func column(@ViewBuilder value: () -> some View, @ViewBuilder label: () -> some View) -> some View {
        VStack(spacing: 3) {
            value()
            label()
                .font(.inter(10, .bold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

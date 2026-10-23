import AccrueKit
import SwiftUI

/// One full Train card: name, last time, set counter, steppers and Log.
/// Logging never starts a workout; only Start does.
struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb

    let card: TrainCard
    let day: DayKey
    let onFinishPart: () -> Void

    @State private var weightKg: Double = 20
    @State private var reps = 10
    @State private var holdSeconds = 30
    @State private var minutes = 30
    @State private var distanceKm = 5.0
    @State private var distanceM = 40.0
    @State private var isWarmup = false
    @State private var pauseSeconds = 0
    @State private var extraSets = 0
    @State private var restEnds: Date?
    @State private var holdStarted: Date?
    @State private var showingSets = false
    @State private var showingHowTo = false
    @State private var prepared = false

    private var exerciseID: String { card.item.exerciseID }
    private var tracking: Tracking { model.tracking(of: exerciseID) }
    private var todaySets: [LoggedSet] { model.data.sets(of: exerciseID, on: day, partID: card.part.id) }
    private var workingDone: Int { todaySets.filter { !$0.isWarmup }.count }
    private var targetSets: Int { max(1, card.item.sets) + extraSets }

    var body: some View {
        let history = model.history(of: exerciseID)
        VStack(spacing: 0) {
            topRow
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    demo
                    titleBlock(history: history)
                    if tracking.isSetBased {
                        setRow
                        if !tracking.usesHold && tracking != .weightDistance { pausePicker }
                        steppers
                    } else {
                        cardioSteppers
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            actionArea
                .padding(16)
        }
        .card(radius: 26)
        .onAppear { prepare(history: history) }
        .sheet(isPresented: $showingSets) {
            SetsSheet(exerciseID: exerciseID, day: day, partID: card.part.id)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingHowTo) {
            NavigationStack { ExerciseDetailView(exerciseID: exerciseID) }
        }
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack {
            Text("\(card.partTitle) · \(card.index + 1) of \(card.countInPart)")
                .sectionLabel()
            Spacer()
            Button {
                showingHowTo = true
            } label: {
                Label("How to", systemImage: "figure.strengthtraining.traditional")
                    .font(.inter(13, .bold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Stand-in for the animation: the working muscles until the rig is ported.
    private var demo: some View {
        let exercise = model.exercise(exerciseID)
        let muscles = exercise.map { model.catalog.muscles(for: $0) } ?? MuscleSet()
        let family = exercise.flatMap { model.catalog.family(for: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: tracking.isSetBased ? "figure.strengthtraining.traditional" : "figure.run")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                Spacer()
                if let family {
                    Text(family.name)
                        .font(.inter(12, .semibold))
                        .foregroundStyle(palette.secondary)
                }
            }
            if !muscles.primary.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(muscles.primary, id: \.self) { m in
                        MuscleChip(label: model.catalog.muscleLabel(m), primary: true)
                    }
                    ForEach(muscles.secondary.prefix(3), id: \.self) { m in
                        MuscleChip(label: model.catalog.muscleLabel(m), primary: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .card(radius: 18, color: palette.raised)
    }

    private func titleBlock(history: ExerciseHistory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.name(of: exerciseID))
                .font(.display(30, relativeTo: .title))
                .textCase(.uppercase)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if let last = history.lastTime(before: day) {
                HStack(spacing: 6) {
                    Text("Last: \(last.line(unit: unit, tracking: tracking))")
                        .foregroundStyle(palette.secondary)
                    if let change = history.strengthChange(on: day.adding(days: -1)) {
                        Text(String(format: "%+.0f%% vs 4 wk ago", change))
                            .foregroundStyle(change >= 0 ? palette.accentText : palette.warmup)
                            .fontWeight(.bold)
                    }
                }
                .font(.inter(13, .medium))
            } else {
                Text("First time. Pick a weight you can do with good form.")
                    .font(.inter(13))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var setRow: some View {
        HStack {
            Button {
                showingSets = true
            } label: {
                HStack(spacing: 8) {
                    Text("Set \(min(workingDone + 1, targetSets)) of \(targetSets)")
                        .font(.inter(15, .bold))
                        .foregroundStyle(palette.text)
                    HStack(spacing: 4) {
                        ForEach(0..<targetSets, id: \.self) { i in
                            Circle()
                                .fill(i < workingDone ? palette.accentFill : palette.line)
                                .frame(width: 7, height: 7)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set \(min(workingDone + 1, targetSets)) of \(targetSets). Show today's sets")
            Spacer()
            Toggle(isOn: $isWarmup) {
                Text("Warm-up")
                    .font(.inter(13, .bold))
                    .foregroundStyle(isWarmup ? palette.warmup : palette.secondary)
            }
            .toggleStyle(.switch)
            .tint(palette.warmup)
            .fixedSize()
        }
    }

    private var pausePicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pause at top").font(.inter(13, .bold)).foregroundStyle(palette.text)
                Text("seconds per rep").font(.inter(11)).foregroundStyle(palette.secondary)
            }
            Spacer()
            SegmentPicker(options: [(0, "None"), (1, "1"), (2, "2"), (3, "3"), (5, "5")],
                          selection: $pauseSeconds, filled: true)
                .frame(maxWidth: 210)
        }
    }

    @ViewBuilder
    private var steppers: some View {
        HStack(spacing: 10) {
            if tracking.usesWeight {
                ValueStepper(value: unit.format(kg: weightKg), unit: unit.label,
                             decrease: { weightKg = max(0, unit.rounded(kg: weightKg - unit.toKg(unit.step))) },
                             increase: { weightKg = unit.rounded(kg: weightKg + unit.toKg(unit.step)) })
            } else if tracking == .reps {
                ValueStepper(value: weightKg > 0 ? "+" + unit.format(kg: weightKg) : "BW",
                             unit: weightKg > 0 ? unit.label : "body",
                             decrease: { weightKg = max(0, unit.rounded(kg: weightKg - unit.toKg(unit.step))) },
                             increase: { weightKg = unit.rounded(kg: weightKg + unit.toKg(unit.step)) })
            }
            if tracking.usesHold {
                ValueStepper(value: DurationFormat.clock(TimeInterval(holdSeconds)), unit: "hold",
                             decrease: { holdSeconds = max(5, holdSeconds - 5) },
                             increase: { holdSeconds += 5 })
            } else if tracking == .weightDistance {
                ValueStepper(value: "\(Int(distanceM))", unit: "m",
                             decrease: { distanceM = max(10, distanceM - 10) },
                             increase: { distanceM += 10 })
            } else {
                ValueStepper(value: "\(reps)", unit: "reps",
                             decrease: { reps = max(1, reps - 1) },
                             increase: { reps += 1 })
            }
        }
    }

    private var cardioSteppers: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ValueStepper(value: "\(minutes)", unit: "min",
                             decrease: { minutes = max(1, minutes - 5) },
                             increase: { minutes += 5 })
                if tracking == .distanceTimeHR {
                    ValueStepper(value: String(format: "%.1f", distanceKm), unit: "km",
                                 decrease: { distanceKm = max(0, distanceKm - 0.5) },
                                 increase: { distanceKm += 0.5 })
                }
            }
            Text("Live heart rate, zones and route come with the Apple Health step. For now, log the time and distance when you're done.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionArea: some View {
        if let restEnds, restEnds > .now, tracking.isSetBased {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = restEnds.timeIntervalSince(context.date)
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Rest").font(.inter(12, .bold)).foregroundStyle(palette.secondary)
                        Text(DurationFormat.clock(max(0, left)))
                            .font(.number(30))
                            .monospacedDigit()
                            .foregroundStyle(palette.text)
                    }
                    Spacer()
                    Button("Skip rest") { self.restEnds = nil }
                        .buttonStyle(.soft)
                        .frame(maxWidth: 140)
                }
                .onChange(of: left <= 0) { _, done in if done { self.restEnds = nil } }
            }
        } else if tracking.isSetBased && workingDone >= targetSets {
            VStack(spacing: 8) {
                Text(card.index + 1 == card.countInPart ? "Last set done. Keep going, or finish \(card.partTitle)." : "All sets done.")
                    .font(.inter(13, .medium))
                    .foregroundStyle(palette.secondary)
                HStack(spacing: 8) {
                    Button("+ 1 set") { extraSets += 1 }
                        .buttonStyle(.soft)
                    if card.index + 1 == card.countInPart {
                        Button("Finish") { onFinishPart() }
                            .buttonStyle(.primary)
                    }
                }
            }
        } else if tracking.usesHold {
            holdButton
        } else {
            Button(logLabel) { logSet() }
                .buttonStyle(.primary)
        }
    }

    private var holdButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let holdStarted {
                Button("Stop · \(DurationFormat.clock(context.date.timeIntervalSince(holdStarted)))") {
                    holdSeconds = max(1, Int(Date().timeIntervalSince(holdStarted)))
                    self.holdStarted = nil
                    logSet()
                }
                .buttonStyle(.primary)
            } else {
                HStack(spacing: 8) {
                    Button("Start hold") { self.holdStarted = Date() }
                        .buttonStyle(.primary)
                    Button("Log \(DurationFormat.clock(TimeInterval(holdSeconds)))") { logSet() }
                        .buttonStyle(.soft)
                        .frame(maxWidth: 130)
                }
            }
        }
    }

    private var logLabel: String {
        switch tracking {
        case .weightReps:
            "Log set \(workingDone + 1) · \(unit.format(kg: weightKg)) × \(reps)"
        case .reps:
            weightKg > 0 ? "Log set \(workingDone + 1) · +\(unit.format(kg: weightKg)) × \(reps)" : "Log set \(workingDone + 1) · \(reps) reps"
        case .weightDistance:
            "Log set \(workingDone + 1) · \(unit.format(kg: weightKg)) × \(Int(distanceM)) m"
        case .hold, .weightHold:
            "Log hold"
        case .time, .timeHR:
            "Log \(minutes) min"
        case .distanceTimeHR:
            "Log \(minutes) min · \(String(format: "%.1f", distanceKm)) km"
        }
    }

    private func logSet() {
        let session = model.data.activeSession
        var set = LoggedSet(day: day, exerciseID: exerciseID, partID: card.part.id,
                            sessionID: session?.day == day ? session?.id : nil,
                            pauseSeconds: pauseSeconds, isWarmup: isWarmup)
        switch tracking {
        case .weightReps:
            set.weightKg = weightKg
            set.reps = reps
        case .reps:
            set.weightKg = weightKg > 0 ? weightKg : nil
            set.reps = reps
        case .hold:
            set.holdSeconds = holdSeconds
        case .weightHold:
            set.weightKg = weightKg
            set.holdSeconds = holdSeconds
        case .weightDistance:
            set.weightKg = weightKg
            set.distanceMeters = distanceM
        case .time, .timeHR:
            set.durationSeconds = minutes * 60
        case .distanceTimeHR:
            set.durationSeconds = minutes * 60
            set.distanceMeters = distanceKm * 1000
        }
        model.update { $0.log(set) }
        if isWarmup {
            isWarmup = false
        } else if tracking.isSetBased, card.item.restSeconds > 0, workingDone < targetSets {
            restEnds = Date().addingTimeInterval(TimeInterval(card.item.restSeconds))
        }
    }

    private func prepare(history: ExerciseHistory) {
        guard !prepared else { return }
        prepared = true
        let suggestion = SetSuggestion(plan: card.item, today: todaySets, lastTime: history.lastTime(before: day),
                                       tracking: tracking)
        weightKg = suggestion.weightKg ?? (tracking == .reps ? 0 : 20)
        reps = suggestion.reps ?? 10
        holdSeconds = suggestion.holdSeconds ?? 30
        pauseSeconds = card.item.pauseSeconds
        minutes = card.item.minutes ?? 30
        if let last = history.lastTime(before: day) {
            if let d = last.distanceMeters, tracking == .distanceTimeHR { distanceKm = (d / 100).rounded() / 10 }
            if let d = last.distanceMeters, tracking == .weightDistance { distanceM = d / Double(max(1, last.workingSets)) }
        }
    }
}

struct MuscleChip: View {
    @Environment(\.palette) private var palette
    let label: String
    let primary: Bool

    var body: some View {
        Text(label)
            .font(.inter(12, .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(primary ? palette.accentText : palette.secondary)
            .background(primary ? palette.accentSoft : palette.card, in: Capsule())
    }
}

/// − value + with large tap targets.
struct ValueStepper: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Less", action: decrease)
            VStack(spacing: -2) {
                Text(value)
                    .font(.number(30))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.inter(11, .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            stepButton("plus", label: "More", action: increase)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 68)
        .card(radius: 18, color: palette.raised)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 52)
                .foregroundStyle(palette.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(unit)")
    }
}

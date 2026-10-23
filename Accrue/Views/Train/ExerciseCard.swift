import AccrueKit
import SwiftUI

/// One full Train card, laid out like the MTrain board: the demo on top takes the space that is
/// left, and below it the name, the set chip with Warm-up, Pause at top, the two steppers and Log.
/// Logging never starts a workout; only Start does.
struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb

    let card: TrainCard
    let day: DayKey
    /// The next exercise in this part, or the next part on the last card. Nil at the end of the day.
    let nextTitle: String?
    let onNext: () -> Void
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
    private var isLastInPart: Bool { card.index + 1 == card.countInPart }
    private var partIsLive: Bool { model.data.activeSession?.partID == card.part.id }

    var body: some View {
        let history = model.history(of: exerciseID)
        VStack(spacing: 0) {
            demo
            VStack(alignment: .leading, spacing: 10) {
                nameRow(history: history)
                if tracking.isSetBased {
                    setRow
                    if tracking.usesHold {
                        holdNote(history: history)
                    } else if tracking != .weightDistance {
                        pausePicker
                    }
                    steppers
                } else {
                    cardioSteppers
                }
                actionArea
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    /// Stand-in for the animation until the rig is ported: a light panel, like the boards.
    private var demo: some View {
        ZStack {
            palette.demo
            Image(systemName: tracking.isSetBased ? "figure.strengthtraining.traditional" : "figure.run")
                .font(.system(size: 76, weight: .ultraLight))
                .foregroundStyle(palette.demoInk)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Text(card.countInPart > 1 ? "\(card.partTitle) · \(card.index + 1) of \(card.countInPart)" : "\(card.partTitle) · single exercise")
                .font(.inter(11, .bold))
                .foregroundStyle(palette.demoInk)
                .padding(.leading, 12)
                .padding(.top, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showingHowTo = true
            } label: {
                Label("How to", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.inter(13, .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(palette.text)
                    .background(palette.background, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
        .layoutPriority(-1)
    }

    private func nameRow(history: ExerciseHistory) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.name(of: exerciseID))
                .font(.inter(19, .bold, relativeTo: .title3))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let last = history.lastTime(before: day) {
                Text("Last: \(last.line(unit: unit, tracking: tracking))")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                Text("First time")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var setRow: some View {
        let finished = workingDone >= targetSets
        let word = tracking.usesHold ? "Hold" : "Set"
        let label = isWarmup ? "Warm-up set"
            : finished ? "All \(targetSets) \(tracking.usesHold ? "holds" : "sets")"
            : "\(word) \(workingDone + 1) of \(targetSets)"
        let tint = isWarmup ? palette.warmup : palette.text
        return HStack(alignment: .center, spacing: 8) {
            Button {
                showingSets = true
            } label: {
                HStack(spacing: 6) {
                    Text(label).font(.inter(13, .heavy))
                    if !todaySets.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(todaySets) { set in
                                Circle()
                                    .fill(set.isWarmup ? palette.warmup : palette.accentFill)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 28)
                .foregroundStyle(tint)
                .overlay(Capsule().strokeBorder(isWarmup ? palette.warmup : palette.secondary.opacity(0.55), lineWidth: 1.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(todaySets.count) logged. Show them")
            Spacer(minLength: 0)
            if !tracking.usesHold {
                Toggle(isOn: $isWarmup) {
                    Text("Warm-up")
                        .font(.inter(12, .bold))
                        .foregroundStyle(isWarmup ? palette.warmup : palette.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(palette.warmup)
                .fixedSize()
            }
        }
    }

    private func holdNote(history: ExerciseHistory) -> some View {
        let best = model.data.history(of: exerciseID).compactMap(\.holdSeconds).max()
        return Text("Hold · the timer counts up when you tap Start hold." + (best.map { " Best \(DurationFormat.clock(TimeInterval($0)))." } ?? ""))
            .font(.inter(12))
            .foregroundStyle(palette.secondary)
    }

    private var pausePicker: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Pause at top").font(.inter(12, .bold)).foregroundStyle(palette.text)
                Text("seconds per rep").font(.inter(10)).foregroundStyle(palette.secondary)
            }
            .fixedSize()
            HStack(spacing: 2) {
                ForEach([0, 1, 2, 3, 5], id: \.self) { value in
                    let on = value == pauseSeconds
                    Button {
                        pauseSeconds = value
                    } label: {
                        Text(value == 0 ? "None" : "\(value) s")
                            .font(.inter(13, .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(on ? palette.onAccent : palette.text)
                            .background(on ? palette.accentFill : .clear,
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(value == 0 ? "No pause" : "\(value) second pause")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .frame(height: 34)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var steppers: some View {
        HStack(spacing: 8) {
            if tracking.usesWeight {
                ValueStepper(value: unit.format(kg: weightKg), unit: unit.label,
                             decrease: { weightKg = max(0, unit.rounded(kg: weightKg - unit.toKg(unit.step))) },
                             increase: { weightKg = unit.rounded(kg: weightKg + unit.toKg(unit.step)) })
            } else {
                ValueStepper(value: weightKg > 0 ? "+" + unit.format(kg: weightKg) : "BW",
                             unit: "\(unit.label) added",
                             decrease: { weightKg = max(0, unit.rounded(kg: weightKg - unit.toKg(unit.step))) },
                             increase: { weightKg = unit.rounded(kg: weightKg + unit.toKg(unit.step)) })
            }
            if tracking.usesHold {
                ValueStepper(value: DurationFormat.clock(TimeInterval(holdSeconds)), unit: "seconds",
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
            HStack(spacing: 8) {
                ValueStepper(value: "\(minutes)", unit: "min",
                             decrease: { minutes = max(1, minutes - 5) },
                             increase: { minutes += 5 })
                if tracking == .distanceTimeHR {
                    ValueStepper(value: String(format: "%.1f", distanceKm), unit: "km",
                                 decrease: { distanceKm = max(0, distanceKm - 0.5) },
                                 increase: { distanceKm += 0.5 })
                }
            }
            Text("Live heart rate and zones come with the Apple Health step. For now, log the time and distance.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionArea: some View {
        if let restEnds, restEnds > .now, tracking.isSetBased, workingDone < targetSets {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = restEnds.timeIntervalSince(context.date)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Rest").font(.inter(12)).foregroundStyle(palette.secondary)
                        Text(DurationFormat.clock(max(0, left)))
                            .font(.number(24))
                            .monospacedDigit()
                            .foregroundStyle(palette.accentText)
                    }
                    Spacer()
                    Button {
                        if tracking.usesHold { self.restEnds = nil; holdStarted = Date() } else { logSet() }
                    } label: {
                        Text(tracking.usesHold ? "Hold \(workingDone + 1)" : "Log set \(workingDone + 1)")
                            .font(.inter(15, .heavy))
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .foregroundStyle(palette.onAccent)
                            .background(palette.accentFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .frame(height: 54)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onChange(of: left <= 0) { _, done in if done { self.restEnds = nil } }
            }
        } else if tracking.isSetBased && workingDone >= targetSets {
            if isLastInPart && partIsLive {
                HStack(spacing: 8) {
                    Button(tracking.usesHold ? "+ 1 hold" : "+ 1 set") { extraSets += 1 }
                        .buttonStyle(BigButtonStyle(filled: false))
                    Button("Finish \(card.partTitle)") { onFinishPart() }
                        .buttonStyle(BigButtonStyle(filled: true))
                }
            } else if let nextTitle {
                Button("Next: \(nextTitle) ›", action: onNext)
                    .buttonStyle(BigButtonStyle(filled: true))
            } else {
                Button("Day done") {}
                    .buttonStyle(BigButtonStyle(filled: false))
                    .disabled(true)
            }
        } else if tracking.usesHold {
            holdButton
        } else {
            Button(logLabel) { logSet() }
                .buttonStyle(BigButtonStyle(filled: true))
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
                .buttonStyle(BigButtonStyle(filled: true))
            } else {
                Button("Start hold \(workingDone + 1) · aim \(DurationFormat.clock(TimeInterval(holdSeconds)))") {
                    self.holdStarted = Date()
                }
                .buttonStyle(BigButtonStyle(filled: true))
            }
        }
    }

    private var logLabel: String {
        switch tracking {
        case .weightReps:
            "\(logPrefix) · \(unit.format(kg: weightKg)) × \(reps)\(pauseSuffix)"
        case .reps:
            "\(logPrefix) · \(weightKg > 0 ? "+" + unit.format(kg: weightKg) : "BW") × \(reps)\(pauseSuffix)"
        case .weightDistance:
            "\(logPrefix) · \(unit.format(kg: weightKg)) × \(Int(distanceM)) m"
        case .hold, .weightHold:
            "Log hold"
        case .time, .timeHR:
            "Log \(minutes) min"
        case .distanceTimeHR:
            "Log \(minutes) min · \(String(format: "%.1f", distanceKm)) km"
        }
    }

    private var logPrefix: String { isWarmup ? "Log warm-up" : "Log set \(workingDone + 1)" }
    private var pauseSuffix: String { pauseSeconds > 0 ? " · \(pauseSeconds) s" : "" }

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

/// − value + in a rounded box, with round buttons either side.
struct ValueStepper: View {
    @Environment(\.palette) private var palette
    let value: String
    let unit: String
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Less", action: decrease)
            VStack(spacing: 0) {
                Text(value)
                    .font(.number(34))
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.inter(11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            stepButton("plus", label: "More", action: increase)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 40, height: 40)
                .foregroundStyle(palette.text)
                .background(palette.line, in: Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(label) \(unit)")
    }
}

/// The 54 pt card buttons: lime Log / Next / Finish, or grey + 1 set.
struct BigButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    var filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(17, .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(filled ? palette.onAccent : palette.text.opacity(isEnabled ? 1 : 0.5))
            .background(filled ? palette.accentFill : palette.line,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

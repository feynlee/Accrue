import AccrueKit
import SwiftUI

/// The Train card for a cardio part, built to the MTrain / MRun run card: the target zone on top;
/// before it starts, where you run; while it runs, time, distance and pace against the goal; at
/// the goal (or Done early) it pauses and asks + 5 min or Finish.
/// Heart rate and the live zone come with the Apple Health step, so they show a dash for now.
struct RunCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @AppStorage(SettingsKey.maxHeartRate) private var maxHR = HeartZones.defaultMax
    @AppStorage(SettingsKey.runIndoor) private var indoorChoice = false

    let card: TrainCard
    let day: DayKey
    let nextTitle: String?
    let onFinishPart: () -> Void

    @State private var stopping = false
    @State private var addingDistance = false

    private var exerciseID: String { card.item.exerciseID }
    private var tracking: Tracking { model.tracking(of: exerciseID) }
    private var zone: Int { card.item.targetZone ?? 2 }
    private var minutes: Int { card.item.minutes ?? 30 }

    private var session: WorkoutSession? {
        model.data.activeSession.flatMap { $0.partID == card.part.id && $0.day == day ? $0 : nil }
    }

    private var saved: WorkoutSession? {
        model.data.sessions(on: day).last { $0.partID == card.part.id && !$0.isActive }
    }

    /// "Zone 2 run · 30 min"
    private var title: String {
        "Zone \(zone) \(model.name(of: exerciseID).lowercased()) · \(minutes) min"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let active = session.activeSeconds(at: context.date)
                    let goal = TimeInterval(session.goalSeconds ?? minutes * 60)
                    target
                    running(session, active: active, goal: goal)
                        .onChange(of: active >= goal, initial: true) { _, reached in
                            // The goal time is up: pause and ask, like the end of a part's last set.
                            if reached, !session.isPaused {
                                let id = session.id
                                model.update { $0.togglePause(id) }
                            }
                        }
                        .overlay {
                            if session.isPaused && (active >= goal || stopping) {
                                ask(session, active: active, goal: goal)
                            }
                        }
                }
            } else if let saved {
                target
                done(saved)
            } else {
                target
                before
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sheet(isPresented: $addingDistance) {
            if let saved { DistanceSheet(session: saved, exerciseID: exerciseID).presentationDetents([.height(300)]) }
        }
    }

    // MARK: Target zone

    private var target: some View {
        let zones = HeartZones(maxHR: maxHR)
        let range = zones.range(zone)
        let colors = [palette.cardio, palette.cardio, Color(hex: 0xFFB020), palette.danger, palette.danger]
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(card.partTitle) · cardio")
                .font(.inter(11, .bold))
                .foregroundStyle(palette.secondary.opacity(0.8))
            HStack(alignment: .firstTextBaseline) {
                Text("TARGET · ZONE \(zone)")
                    .font(.inter(12, .heavy))
                    .tracking(0.7)
                    .foregroundStyle(palette.cardio)
                Spacer()
                Text("\(range.lowerBound)–\(range.upperBound) bpm")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("—")
                    .font(.display(72))
                    .foregroundStyle(palette.text)
                Text("bpm").font(.inter(14, .bold)).foregroundStyle(palette.secondary)
                Spacer()
                Text("Heart rate comes with Apple Health")
                    .font(.inter(12, .bold))
                    .foregroundStyle(palette.secondary.opacity(0.8))
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { z in
                        Capsule().fill(colors[z - 1]).frame(height: 10).opacity(z == zone ? 1 : 0.35)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { z in
                        Text("Z\(z)")
                            .font(.inter(10, .bold))
                            .foregroundStyle(z == zone ? palette.cardio : palette.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(palette.sunken)
        .layoutPriority(-1)
    }

    // MARK: States

    private var before: some View {
        let last = model.history(of: exerciseID).lastTime(before: day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.inter(19, .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer()
                if let last {
                    Text("Last: " + (last.distanceMeters.map { "\(unit.formatDistance(meters: $0)) \(unit.distanceLabel)" }
                                     ?? DurationFormat.clock(TimeInterval(last.durationSeconds ?? 0))))
                        .font(.inter(12))
                        .foregroundStyle(palette.secondary)
                }
            }
            if tracking.usesDistance {
                SegmentPicker(options: [(false, "Outdoor"), (true, "Treadmill")], selection: $indoorChoice, filled: true)
                    .frame(height: 38)
                Text(indoorChoice
                     ? "No GPS on a treadmill: add the distance from its screen at the end."
                     : "GPS measures distance and pace, with the screen off too.")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
            }
            Text("Saves as its own workout, separate from the lifting.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }

    private func running(_ session: WorkoutSession, active: TimeInterval, goal: TimeInterval) -> some View {
        let meters = session.distanceMeters ?? 0
        let indoor = session.indoor == true
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                stat("TIME", DurationFormat.clock(active), "of " + DurationFormat.clock(goal))
                if tracking.usesDistance {
                    stat("DISTANCE", indoor ? "—" : unit.formatDistance(meters: meters), indoor ? "add at the end" : unit.distanceLabel)
                    stat("PACE", indoor ? "—" : unit.formatPace(seconds: active, meters: meters) ?? "—", "/" + unit.distanceLabel)
                } else {
                    stat("TO GO", DurationFormat.clock(max(0, goal - active)), "min:sec")
                }
            }
            VStack(spacing: 4) {
                HStack {
                    Text(model.runTracker.sessionID == session.id ? (model.runTracker.status ?? "GPS on") : indoor ? "Treadmill" : "Zone \(zone) target")
                    Spacer()
                    Text(DurationFormat.clock(max(0, goal - active)) + " to go")
                }
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                GeometryReader { proxy in
                    Capsule().fill(palette.raised)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.cardio).frame(width: proxy.size.width * min(1, active / max(1, goal)))
                        }
                }
                .frame(height: 6)
            }
            Button("Done early") {
                stopping = true
                if !session.isPaused {
                    let id = session.id
                    model.update { $0.togglePause(id) }
                }
            }
            .font(.inter(15, .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(palette.text)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func stat(_ key: String, _ value: String, _ unitLine: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary)
            Text(value).font(.number(26)).monospacedDigit().foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(unitLine).font(.inter(10)).foregroundStyle(palette.secondary.opacity(0.8)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func ask(_ session: WorkoutSession, active: TimeInterval, goal: TimeInterval) -> some View {
        let reached = active >= goal
        let name = model.name(of: exerciseID).lowercased()
        return ZStack(alignment: .bottom) {
            Color(hex: 0x0E0F12).opacity(0.55)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0E0F12))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: 0xFFB020), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(reached ? "\(DurationFormat.clock(goal)) \(name) done" : "Stop the \(name) here?")
                            .font(.inter(16, .heavy))
                        Text("Paused. Keep going, or finish and save it.")
                            .font(.inter(12))
                            .foregroundStyle(palette.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("+ 5 min") {
                        let id = session.id
                        stopping = false
                        model.update { data in
                            data.updateSession(id) { $0.goalSeconds = Int(max(goal, active)) + 300 }
                            if data.sessions.first(where: { $0.id == id })?.isPaused == true { data.togglePause(id) }
                        }
                    }
                    .buttonStyle(AskButtonStyle(filled: false))
                    Button("Finish") {
                        stopping = false
                        onFinishPart()
                    }
                    .buttonStyle(AskButtonStyle(filled: true))
                }
                Text("Finish saves \(card.partTitle) as its own workout" + (nextTitle.map { ", then swipes to \($0)." } ?? "."))
                    .font(.inter(11))
                    .foregroundStyle(palette.secondary.opacity(0.85))
            }
            .padding(14)
            .foregroundStyle(palette.text)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 17, y: 14)
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func done(_ saved: WorkoutSession) -> some View {
        let set = model.data.sets(in: saved.id).last
        let meters = set?.distanceMeters ?? saved.distanceMeters
        let seconds = TimeInterval(set?.durationSeconds ?? Int(saved.activeSeconds(at: .now)))
        var parts = [DurationFormat.clock(seconds)]
        if let meters, meters > 0 {
            parts.append("\(unit.formatDistance(meters: meters)) \(unit.distanceLabel)")
            if let pace = unit.formatPace(seconds: seconds, meters: meters) { parts.append("\(pace) /\(unit.distanceLabel)") }
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.name(of: exerciseID)) done")
                    .font(.inter(19, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("Saved").font(.inter(12, .bold)).foregroundStyle(palette.accentText)
            }
            Text(parts.joined(separator: " · "))
                .font(.inter(13))
                .foregroundStyle(palette.secondary)
            if tracking.usesDistance {
                Button((meters ?? 0) > 0 ? "Change distance" : "Add distance") { addingDistance = true }
                    .font(.inter(14, .bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(palette.text)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
    }
}

/// The distance of a finished run, typed in (treadmill) or corrected.
private struct DistanceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let session: WorkoutSession
    let exerciseID: String
    @State private var value = 0.0
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Distance").font(.display(28)).textCase(.uppercase).foregroundStyle(palette.text)
            ValueStepper(value: String(format: "%.2f", value), unit: unit.distanceLabel,
                         decrease: { value = max(0, ((value - 0.05) * 100).rounded() / 100) },
                         increase: { value = ((value + 0.05) * 100).rounded() / 100 })
            Button("Save") { save() }
                .buttonStyle(.primary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.background.ignoresSafeArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let meters = model.data.sets(in: session.id).last?.distanceMeters ?? session.distanceMeters ?? 0
            value = (meters / unit.metersPerDistance * 100).rounded() / 100
        }
    }

    private func save() {
        let meters = value * unit.metersPerDistance
        let id = session.id
        model.update { data in
            if var set = data.sets(in: id).last {
                set.distanceMeters = meters > 0 ? meters : nil
                data.updateSet(set)
            }
            data.updateSession(id) { $0.distanceMeters = meters }
        }
        dismiss()
    }
}

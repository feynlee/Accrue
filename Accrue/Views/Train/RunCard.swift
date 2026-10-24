import AccrueKit
import SwiftUI

/// The Train card for a cardio part. The exercise plays on top (the skin figure, no muscles);
/// below, time, distance and pace, live once it starts and last time's beside them, so you can
/// compare. The target is last time's mark unless you set your own: reaching it beeps and
/// notifies, and the clock keeps going until you stop it with the live bar.
struct RunCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @AppStorage(SettingsKey.maxHeartRate) private var maxHR = HeartZones.defaultMax

    let card: TrainCard
    let day: DayKey
    let nextTitle: String?
    let onFinishPart: () -> Void

    @State private var showingHowTo = false
    @State private var addingDistance = false
    @State private var settingTarget: CardioTarget.Metric?

    private var exerciseID: String { card.item.exerciseID }
    private var tracking: Tracking { model.tracking(of: exerciseID) }
    private var outdoor: Bool { model.exercise(exerciseID)?.isOutdoor == true }
    private var zone: Int { card.item.targetZone ?? 2 }

    private var session: WorkoutSession? {
        model.data.activeSession.flatMap { $0.partID == card.part.id && $0.day == day ? $0 : nil }
    }

    private var saved: WorkoutSession? {
        model.data.sessions(on: day).last { $0.partID == card.part.id && !$0.isActive }
    }

    var body: some View {
        let last = model.history(of: exerciseID).lastTime(before: day)
        VStack(spacing: 0) {
            demo
            Group {
                if let session {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        running(session, active: session.activeSeconds(at: context.date), last: last)
                    }
                } else if let saved {
                    done(saved, last: last)
                } else {
                    before(last: last)
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fullScreenCover(isPresented: $showingHowTo) {
            HowToView(exerciseID: exerciseID, doneLabel: "Back")
        }
        .sheet(isPresented: $addingDistance) {
            if let saved { DistanceSheet(session: saved, exerciseID: exerciseID).presentationDetents([.height(300)]) }
        }
        .sheet(item: $settingTarget) { metric in
            TargetSheet(metric: metric, start: targetValue(metric, last: last)) { setTarget(CardioTarget(metric: metric, value: $0), last: last) }
                .presentationDetents([.height(300)])
        }
    }

    // MARK: Demo

    /// The exercise playing on the light panel, as on the lifting cards, without muscles.
    private var demo: some View {
        ZStack {
            palette.demo
            if let guide = model.exercise(exerciseID).flatMap(model.catalog.howTo(for:)), !guide.keyframes.isEmpty {
                AnimatedFigure(guide: guide, showMuscles: false)
                    .padding(.top, 22)
                    .padding(.bottom, 4)
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 76, weight: .ultraLight))
                    .foregroundStyle(palette.demoInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Text("\(card.partTitle) · cardio")
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

    // MARK: States

    private func before(last: DaySummary?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nameRow
            targetRow(goal: nil, last: last)
            stats(time: last?.durationSeconds.map { TimeInterval($0) }, meters: last?.distanceMeters, last: nil,
                  heading: last == nil ? nil : "LAST TIME")
            Text(last == nil ? "First time: whatever you do today becomes the mark to beat." : note)
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func running(_ session: WorkoutSession, active: TimeInterval, last: DaySummary?) -> some View {
        let hit = session.reachedGoal(active: active)
        return VStack(alignment: .leading, spacing: 10) {
            nameRow
            targetRow(goal: session, last: last)
            stats(time: active, meters: outdoor ? session.distanceMeters ?? 0 : nil, last: last, heading: nil, hit: hit)
            progress(session, active: active, last: last, hit: hit)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sensoryFeedback(.success, trigger: hit) { !$0 && $1 }
    }

    private func done(_ saved: WorkoutSession, last: DaySummary?) -> some View {
        let set = model.data.sets(in: saved.id).last
        let meters = set?.distanceMeters ?? saved.distanceMeters
        let seconds = TimeInterval(set?.durationSeconds ?? Int(saved.activeSeconds(at: .now)))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.name(of: exerciseID)) done")
                    .font(.inter(19, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("Saved").font(.inter(12, .bold)).foregroundStyle(palette.accentText)
            }
            stats(time: seconds, meters: meters ?? (tracking.usesDistance ? 0 : nil), last: last, heading: nil)
            if tracking.usesDistance && !outdoor {
                Button((meters ?? 0) > 0 ? "Change distance" : "Add the treadmill's distance") { addingDistance = true }
                    .font(.inter(14, .bold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(palette.onAccent)
                    .background(palette.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Pieces

    /// "Outdoor run" and the heart-rate zone to stay in.
    private var nameRow: some View {
        let range = HeartZones(maxHR: maxHR).range(zone)
        return HStack(alignment: .firstTextBaseline) {
            Text(model.name(of: exerciseID))
                .font(.inter(19, .bold, relativeTo: .title3))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold))
                Text("Zone \(zone) · \(range.lowerBound)–\(range.upperBound)")
            }
            .font(.inter(12, .bold))
            .foregroundStyle(palette.cardio)
            .accessibilityLabel("Stay in heart rate zone \(zone), \(range.lowerBound) to \(range.upperBound) beats a minute")
        }
    }

    private var note: String {
        guard tracking.usesDistance else { return "Saves as its own workout, separate from the lifting." }
        return outdoor ? "GPS measures distance and pace, with the screen off too."
                       : "No GPS indoors: add the treadmill's distance when you stop."
    }

    /// TARGET · Last time 31:20 ▾ — one menu: last time's time or distance, or your own.
    private func targetRow(goal session: WorkoutSession?, last: DaySummary?) -> some View {
        let target = model.data.cardioTarget(for: exerciseID)
        return Menu {
            Button("Last time's time") { setTarget(CardioTarget(metric: .time), last: last) }
            if tracking.usesDistance && (outdoor || session == nil) {
                Button("Last time's distance") { setTarget(CardioTarget(metric: .distance), last: last) }
            }
            Divider()
            Button("Set a time…") { settingTarget = .time }
            if tracking.usesDistance && outdoor {
                Button("Set a distance…") { settingTarget = .distance }
            }
        } label: {
            HStack(spacing: 6) {
                Text("TARGET")
                    .font(.inter(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.secondary)
                Text(targetLabel(target, session: session, last: last))
                    .font(.inter(14, .bold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityHint("Change what to aim for. The workout keeps going when you reach it.")
    }

    private func targetLabel(_ target: CardioTarget, session: WorkoutSession?, last: DaySummary?) -> String {
        let seconds = session?.goalSeconds.map { Double($0) } ?? (session == nil && target.metric == .time
            ? target.goal(last: last, plannedMinutes: card.item.minutes) : nil)
        let meters = session?.goalMeters ?? (session == nil && target.metric == .distance
            ? target.goal(last: last, plannedMinutes: nil) : nil)
        let fromLast = session?.goalIsLastTime ?? target.usesLastTime(last: last)
        let value = seconds.map { DurationFormat.clock($0) }
            ?? meters.map { "\(unit.formatDistance(meters: $0)) \(unit.distanceLabel)" }
        guard let value else { return "Last time's distance (none yet)" }
        if fromLast { return "Last time · \(value)" }
        return target.value == nil && target.metric == .time ? "Plan · \(value)" : value
    }

    /// Time, distance and pace. Live values show last time's under them; before the start the
    /// tiles are last time's.
    private func stats(time: TimeInterval?, meters: Double?, last: DaySummary?, heading: String?,
                       hit: Bool = false) -> some View {
        let lastTime = last?.durationSeconds.map { TimeInterval($0) }
        let lastMeters = last?.distanceMeters
        let dash = "—"
        return VStack(alignment: .leading, spacing: 6) {
            if let heading {
                Text(heading).font(.inter(10, .heavy)).tracking(0.6).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 6) {
                tile("TIME", time.map { DurationFormat.clock($0) } ?? dash,
                     lastTime.map { "last " + DurationFormat.clock($0) }, hot: hit)
                if tracking.usesDistance {
                    tile("DISTANCE " + unit.distanceLabel.uppercased(),
                         meters.map { unit.formatDistance(meters: $0) } ?? dash,
                         lastMeters.map { "last " + unit.formatDistance(meters: $0) }, hot: hit)
                    let pace = time.flatMap { t in meters.flatMap { unit.formatPace(seconds: t, meters: $0) } }
                    let lastPace = lastTime.flatMap { t in lastMeters.flatMap { unit.formatPace(seconds: t, meters: $0) } }
                    tile("PACE /" + unit.distanceLabel, pace ?? dash, lastPace.map { "last " + $0 }, hot: hit)
                }
            }
        }
    }

    private func tile(_ key: String, _ value: String, _ lastLine: String?, hot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary).lineLimit(1)
            Text(value).font(.number(26)).monospacedDigit().foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(lastLine ?? " ").font(.inter(11)).foregroundStyle(palette.secondary.opacity(0.85)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hot ? palette.accentText : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    /// The bar toward the target; once it is reached the bar turns lime and says by how much.
    private func progress(_ session: WorkoutSession, active: TimeInterval, last: DaySummary?, hit: Bool) -> some View {
        let fromLast = session.goalIsLastTime == true
        let line: String
        if hit {
            let over = session.goalSeconds.map { "+" + DurationFormat.clock(active - TimeInterval($0)) }
                ?? session.goalMeters.map { "+" + unit.formatDistance(meters: (session.distanceMeters ?? 0) - $0) + " " + unit.distanceLabel }
                ?? ""
            line = (fromLast ? "Past last time" : "Target reached") + " · \(over). Keep going, or stop with ■."
        } else if let goal = session.goalSeconds {
            line = DurationFormat.clock(max(0, TimeInterval(goal) - active)) + (fromLast ? " to match last time" : " to your target")
        } else if let goal = session.goalMeters {
            line = unit.formatDistance(meters: max(0, goal - (session.distanceMeters ?? 0))) + " \(unit.distanceLabel)"
                + (fromLast ? " to match last time" : " to your target")
        } else {
            line = model.runTracker.status ?? note
        }
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                Capsule().fill(palette.raised)
                    .overlay(alignment: .leading) {
                        Capsule().fill(hit ? palette.accentFill : palette.cardio)
                            .frame(width: proxy.size.width * session.goalProgress(active: active))
                    }
            }
            .frame(height: 6)
            HStack(spacing: 6) {
                if hit {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accentText)
                }
                Text(line)
                    .foregroundStyle(hit ? palette.text : palette.secondary)
                Spacer(minLength: 0)
                if !hit, outdoor, let status = model.runTracker.status {
                    Text(status).foregroundStyle(palette.secondary)
                }
            }
            .font(.inter(12, hit ? .bold : .regular))
            .lineLimit(2)
        }
    }

    // MARK: Target

    private func targetValue(_ metric: CardioTarget.Metric, last: DaySummary?) -> Double {
        let target = model.data.cardioTarget(for: exerciseID)
        if target.metric == metric, let value = target.goal(last: last, plannedMinutes: card.item.minutes) { return value }
        return CardioTarget(metric: metric).goal(last: last, plannedMinutes: card.item.minutes ?? 30)
            ?? (metric == .time ? 1800 : 5 * unit.metersPerDistance)
    }

    private func setTarget(_ target: CardioTarget, last: DaySummary?) {
        let id = exerciseID
        model.update { $0.setCardioTarget(target, for: id) }
        if let session {
            model.applyCardioGoal(session.id, exerciseID: id, plannedMinutes: card.item.minutes, target: target)
        }
    }
}

extension CardioTarget.Metric: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Your own target: a time in minutes, or a distance.
private struct TargetSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let metric: CardioTarget.Metric
    let start: Double
    let onSave: (Double) -> Void
    @State private var value: Double?

    var body: some View {
        let current = value ?? initial
        VStack(spacing: 16) {
            Text(metric == .time ? "Target time" : "Target distance")
                .font(.display(28)).textCase(.uppercase).foregroundStyle(palette.text)
            if metric == .time {
                ValueStepper(value: "\(Int(current))", unit: "min",
                             decrease: { value = max(1, current - 1) }, increase: { value = current + 1 })
            } else {
                ValueStepper(value: String(format: "%.1f", current), unit: unit.distanceLabel,
                             decrease: { value = max(0.1, ((current - 0.1) * 10).rounded() / 10) },
                             increase: { value = ((current + 0.1) * 10).rounded() / 10 })
            }
            Text("You'll get a beep and a notification when you reach it. The workout keeps going.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
            Button("Set target") {
                onSave(metric == .time ? current * 60 : current * unit.metersPerDistance)
                dismiss()
            }
            .buttonStyle(.primary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.background.ignoresSafeArea())
    }

    private var initial: Double {
        metric == .time ? max(1, (start / 60).rounded()) : max(0.1, (start / unit.metersPerDistance * 10).rounded() / 10)
    }
}

/// The distance of a finished treadmill workout, from the machine's screen.
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

import AccrueKit
import SwiftUI

/// Progress, as on the AProgress board: a THIS WEEK card with a Strength / Cardio toggle and one
/// bar per day over last week's faint bar, then the selected day's panel with the Est. max /
/// Volume toggle, the "vs" chips and one row per exercise.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @State private var day = DayKey.today()
    /// `-progressScreen cardio` opens with Cardio selected (used for screenshots).
    @State private var cardio = UserDefaults.standard.string(forKey: "progressScreen") == "cardio"
    @State private var metric = StrengthMetric.strength
    @State private var comparison = Comparison.fourWeeks
    @State private var showingInfo = false
    /// `-progressScreen calendar`, `exercise` or `cardiotrend` opens one level in (used for screenshots).
    @State private var path: NavigationPath = {
        var path = NavigationPath()
        switch UserDefaults.standard.string(forKey: "progressScreen") {
        case "calendar": path.append(CalendarRoute())
        case "exercise": path.append(ProgressExerciseRoute(exerciseID: StarterIDs.pulldown, day: .today(), comparison: .threeMonths))
        case "cardiotrend": path.append(CardioTrendRoute(exerciseID: StarterIDs.run, stat: .pace, day: .today()))
        default: break
        }
        return path
    }()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 10) {
                    header
                    WeekBars(day: $day, cardio: $cardio)
                    DayPanel(day: day, cardio: cardio, metric: $metric, comparison: $comparison)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Progress")
            .onAppear(perform: pickStartDay)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProgressExerciseRoute.self) { route in
                ExerciseProgressView(exerciseID: route.exerciseID, day: route.day, comparison: route.comparison)
            }
            .navigationDestination(for: CardioTrendRoute.self) { route in
                CardioTrendView(route: route)
            }
            .navigationDestination(for: CalendarRoute.self) { _ in
                CalendarScreen(selected: $day)
            }
            .sheet(isPresented: $showingInfo) {
                ProgressInfoSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Open on today, or on the latest day this week with something logged (cardio when Cardio is on).
    private func pickStartDay() {
        let today = DayKey.today()
        let fits = { (d: DayKey) -> Bool in
            let totals = model.data.totals(on: d, catalog: model.catalog)
            return cardio ? totals.hasCardio : !totals.isEmpty
        }
        guard day == today, !fits(today) else { return }
        let monday = today.startOfWeek()
        var d = today
        while d > monday {
            d = d.adding(days: -1)
            if fits(d) { day = d; return }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Progress")
                .font(.display(30))
                .textCase(.uppercase)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink(value: CalendarRoute()) {
                circleIcon("calendar")
            }
            .accessibilityLabel("Calendar")
            Button {
                showingInfo = true
            } label: {
                circleIcon("info.circle")
            }
            .accessibilityLabel("How to read Progress")
        }
        .padding(.leading, 4)
        .padding(.top, 6)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 40, height: 40)
            .foregroundStyle(palette.accentText)
            .background(palette.card, in: Circle())
    }
}

struct ProgressExerciseRoute: Hashable {
    let exerciseID: String
    let day: DayKey
    let comparison: Comparison
}

struct CalendarRoute: Hashable {}

// MARK: This week

/// Seven columns: TODAY or the letter, the date, this day's bar over last week's faint bar,
/// the amount and the workout name. Swipe sideways for other weeks.
private struct WeekBars: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @Binding var day: DayKey
    @Binding var cardio: Bool

    var body: some View {
        let today = DayKey.today()
        let monday = day.startOfWeek()
        let days = (0..<7).map { monday.adding(days: $0) }
        let now = days.map { model.data.totals(on: $0, catalog: model.catalog) }
        let before = days.map { model.data.totals(on: $0.adding(days: -7), catalog: model.catalog) }
        let amount: (DayTotals) -> Double = { cardio ? Double($0.cardioSeconds) / 60 : $0.volumeKg }
        let top = max(1, (now + before).map(amount).max() ?? 1)
        let accent = cardio ? palette.cardio : palette.accentText

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(monday == today.startOfWeek() ? "THIS WEEK" : "WEEK") · \(monday.shortDate.uppercased()) – \(monday.adding(days: 6).shortDate.uppercased())")
                        .font(.inter(11, .bold))
                        .tracking(0.5)
                        .foregroundStyle(palette.secondary)
                    Text(summary(now, today: today))
                        .font(.inter(13, .bold))
                        .foregroundStyle(palette.text)
                }
                Spacer(minLength: 8)
                MiniToggle(options: [(false, "Strength"), (true, "Cardio")], selection: $cardio)
                    .frame(width: 158)
            }
            .padding(.horizontal, 6)

            HStack(spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    column(d, now: now[i], before: before[i], amount: amount, top: top, today: today, accent: accent)
                }
            }
            Text(cardio ? "Bars: minutes of cardio. Faint: last week. Tap a day. Heart-rate zones come with Apple Health."
                        : "Bars: \(unit == .lb ? "pounds" : "kilos") lifted. Faint bars: last week. Tap a day to see it below.")
                .font(.inter(11))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 6)
        }
        .padding(EdgeInsets(top: 10, leading: 6, bottom: 8, trailing: 6))
        .background(palette.sunken, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -40 { day = day.adding(days: 7) }
                if value.translation.width > 40 { day = day.adding(days: -7) }
            }
        )
    }

    private func column(_ d: DayKey, now: DayTotals, before: DayTotals, amount: (DayTotals) -> Double,
                        top: Double, today: DayKey, accent: Color) -> some View {
        let selected = d == day
        let isToday = d == today
        let future = d > today
        let value = amount(now)
        let lastWeek = amount(before)
        let tag = cardio ? (now.hasCardio ? cardioTag(now) : "")
            : (future ? model.plannedTitles(on: d).first ?? "" : (now.hasStrength ? model.doneTitles(on: d).first ?? "" : ""))
        return Button {
            day = d
        } label: {
            VStack(spacing: 3) {
                Text(isToday ? "TODAY" : d.weekday().letter)
                    .font(.inter(10, .bold))
                    .foregroundStyle(isToday ? palette.accentText : palette.secondary)
                    .frame(height: 12)
                Text("\(d.day)")
                    .font(.inter(12, .heavy))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isToday ? palette.onAccent : (future ? palette.secondary : palette.text))
                    .background(isToday ? palette.accentFill : .clear, in: Circle())
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(palette.raised)
                        .frame(width: 24, height: 50 * lastWeek / top)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(cardio ? palette.cardio : palette.accentFill)
                        .frame(width: 14, height: 50 * value / top)
                }
                .frame(width: 24, height: 50, alignment: .bottom)
                Text(future ? "" : label(value))
                    .font(.inter(11, .bold))
                    .foregroundStyle(palette.text)
                    .frame(height: 14)
                Text(tag)
                    .font(.inter(10, .semibold))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 12)
            }
            .padding(.top, 5)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(selected ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isToday ? "Today, " : "")\(d.weekday().name) \(d.day): \(future ? "planned" : label(value))")
    }

    private func label(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        if cardio { return "\(Int(value.rounded()))m" }
        let shown = unit.fromKg(value)
        return shown >= 1000 ? String(format: "%.1fk", shown / 1000) : "\(Int(shown))"
    }

    private func cardioTag(_ totals: DayTotals) -> String {
        totals.cardioExercises.first.map { model.name(of: $0) }?.components(separatedBy: " ").first ?? "Cardio"
    }

    private func summary(_ week: [DayTotals], today: DayKey) -> String {
        if cardio {
            let minutes = week.reduce(0) { $0 + $1.cardioSeconds } / 60
            let sessions = week.filter(\.hasCardio).count
            return "\(minutes) min · \(sessions) \(sessions == 1 ? "session" : "sessions")"
        }
        let volume = unit.fromKg(week.reduce(0) { $0 + $1.volumeKg })
        let done = week.filter(\.hasStrength).count
        let planned = week.filter { day in
            model.data.parts(on: day.day).contains { part in
                model.data.items(in: part).contains { model.tracking(of: $0.exerciseID).isSetBased }
            }
        }.count
        return "\(Int(volume).formatted()) \(unit.label) · \(done) of \(max(done, planned)) lifting days done"
    }
}

// MARK: Selected day

private struct DayPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let day: DayKey
    let cardio: Bool
    @Binding var metric: StrengthMetric
    @Binding var comparison: Comparison

    var body: some View {
        let today = DayKey.today()
        let future = day > today
        let totals = model.data.totals(on: day, catalog: model.catalog)
        let accent = cardio ? palette.cardio : palette.accentText

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(day == today ? "TODAY" : future ? "PLANNED" : "SELECTED DAY")
                        .font(.inter(11, .bold))
                        .tracking(0.5)
                        .foregroundStyle(accent)
                    Text(title(totals: totals, future: future))
                        .font(.inter(17, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle(totals: totals, future: future))
                        .font(.inter(12))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 6)
                if !cardio {
                    MiniToggle(options: [(StrengthMetric.strength, "Est. max"), (.volume, "Volume")],
                               selection: $metric, height: 26)
                        .frame(width: 140)
                }
            }
            .padding(.horizontal, 2)

            HStack(spacing: 5) {
                Text("vs").font(.inter(11, .semibold)).foregroundStyle(palette.text.opacity(0.85))
                ForEach(Comparison.allCases) { c in
                    OutlineChip(title: c.label, selected: c == comparison) { comparison = c }
                }
            }
            .padding(.horizontal, 2)

            if cardio {
                let ids = future ? [] : totals.cardioExercises
                if ids.isEmpty {
                    empty(future ? "Nothing done yet on \(day.weekday().name)." : "No cardio on \(day.weekday().name).")
                }
                ForEach(ids, id: \.self) { CardioCard(exerciseID: $0, day: day, comparison: comparison) }
            } else {
                let rows = strengthRows(totals: totals, future: future)
                if rows.isEmpty {
                    empty("No strength training on \(day.weekday().name).")
                }
                ForEach(rows, id: \.exerciseID) { row in
                    NavigationLink(value: ProgressExerciseRoute(exerciseID: row.exerciseID, day: row.reference, comparison: comparison)) {
                        StrengthRow(exerciseID: row.exerciseID, reference: row.reference, future: future,
                                    metric: metric, comparison: comparison)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(palette.sunken)
        .overlay(alignment: .top) {
            Rectangle().fill(accent).frame(height: 2).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Logged exercises on a past day; on a planned day, each planned strength exercise
    /// against its last session.
    private func strengthRows(totals: DayTotals, future: Bool) -> [(exerciseID: String, reference: DayKey)] {
        if !future { return totals.strengthExercises.map { ($0, day) } }
        var ids: [String] = []
        for part in model.data.parts(on: day) {
            for item in model.data.items(in: part) where model.tracking(of: item.exerciseID).isSetBased && !ids.contains(item.exerciseID) {
                ids.append(item.exerciseID)
            }
        }
        return ids.compactMap { id in model.history(of: id).days.last.map { (id, $0.day) } }
    }

    private func title(totals: DayTotals, future: Bool) -> String {
        let date = day.date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let name = cardio ? (totals.hasCardio ? totals.cardioExercises.first.map { model.name(of: $0) } : nil)
            : (future ? model.plannedTitles(on: day).first : model.doneTitles(on: day).first)
        return name.map { "\(date) · \($0)" } ?? date
    }

    private func subtitle(totals: DayTotals, future: Bool) -> String {
        if future {
            let planned = model.plannedTitles(on: day)
            return cardio || planned.isEmpty ? "Planned" : "Planned. Showing the last session of each exercise."
        }
        let lifted = totals.hasStrength ? "\(Int(unit.fromKg(totals.volumeKg)).formatted()) \(unit.label) lifted" : nil
        let minutes = totals.hasCardio ? "\(totals.cardioSeconds / 60) min cardio" : nil
        let parts = cardio ? [minutes, lifted.map { "also " + $0 }] : [lifted, minutes.map { "also " + $0 }]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "Nothing logged" : text
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.inter(14))
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Name, "Today:" line, "4 wk ago (Sep 25):" line, and the number on the right.
private struct StrengthRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    let reference: DayKey
    let future: Bool
    let metric: StrengthMetric
    let comparison: Comparison

    var body: some View {
        let history = model.history(of: exerciseID)
        let tracking = history.tracking
        let now = history.summary(on: reference)
        let then = history.compared(comparison, to: reference)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name(of: exerciseID))
                    .font(.inter(14, .bold))
                    .foregroundStyle(palette.text)
                if let now {
                    (Text(future ? "Last (\(reference.shortDate)): " : "Today: ").foregroundStyle(palette.secondary)
                     + Text(now.line(unit: unit, tracking: tracking)).foregroundStyle(palette.text))
                        .font(.inter(12))
                }
                Text(then.map { "\(comparison.label) (\($0.day.compareDate)): \($0.line(unit: unit, tracking: tracking))" }
                     ?? "\(comparison.label): nothing logged")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let now {
                let m = MetricValue(tracking: tracking, metric: metric, now: now, then: then, unit: unit)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(m.label)
                        .font(.inter(10, .bold))
                        .tracking(0.4)
                        .foregroundStyle(palette.secondary)
                    Text(m.value)
                        .font(.number(22))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(m.delta.map { "\($0) vs \(comparison == .lastTime ? "last time" : comparison.label)" } ?? "no earlier session")
                        .font(.inter(11, .bold))
                        .foregroundStyle(m.improved ? palette.accentText : palette.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .frame(width: 112, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// One cardio session: distance, time, pace and heart rate, then the comparison.
private struct CardioCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    let exerciseID: String
    let day: DayKey
    let comparison: Comparison

    var body: some View {
        let history = model.history(of: exerciseID)
        let now = history.summary(on: day)
        let then = history.compared(comparison, to: day)
        let seconds = now?.durationSeconds ?? 0
        let meters = now?.distanceMeters ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.name(of: exerciseID)).font(.inter(15, .bold)).foregroundStyle(palette.text)
                Spacer()
                Text(day.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.inter(12)).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 4) {
                basic("DISTANCE", meters > 0 ? DistanceFormat.format(meters: meters, unit: unit) : "—")
                basic("TIME", DurationFormat.clock(TimeInterval(seconds)))
                basic("AVG PACE", DistanceFormat.pace(seconds: seconds, meters: meters, unit: unit))
                basic("AVG HR", "—")
            }
            Text(thenLine(then))
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
            if let now {
                let recent = Array(history.days.filter { $0.day <= day }.suffix(12))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(CardioStat.allCases) { stat in
                        statTile(stat, now: now, then: then, recent: recent)
                    }
                    healthTile
                }
                Text("Lines: your last \(recent.count) sessions. Hollow dot: the one you compare with. Tap a tile for the full trend.")
                    .font(.inter(11))
                    .foregroundStyle(palette.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func thenLine(_ then: DaySummary?) -> String {
        guard let then else { return "\(comparison.label): nothing logged" }
        var parts: [String] = []
        if let m = then.distanceMeters { parts.append(DistanceFormat.format(meters: m, unit: unit)) }
        if let s = then.durationSeconds { parts.append(DurationFormat.clock(TimeInterval(s))) }
        return "\(comparison.label) (\(then.day.compareDate)): " + parts.joined(separator: " · ")
    }

    private func basic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary)
            Text(value).font(.number(20)).foregroundStyle(palette.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A stat with its change and the last sessions as a small line; tap for its trend screen.
    private func statTile(_ stat: CardioStat, now: DaySummary, then: DaySummary?, recent: [DaySummary]) -> some View {
        let a = stat.value(now, unit: unit)
        let b = then.flatMap { stat.value($0, unit: unit) }
        let line = recent.compactMap { s in stat.value(s, unit: unit).map { (s.day, $0) } }
        return NavigationLink(value: CardioTrendRoute(exerciseID: exerciseID, stat: stat, day: day)) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(stat.title.uppercased()).font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.secondary)
                }
                Text(a.map { stat.format($0, unit: unit) + stat.suffix(unit: unit) } ?? "—")
                    .font(.number(22))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(a.flatMap { a in b.map { stat.delta(from: $0, to: a, unit: unit) } } ?? " ")
                    .font(.inter(11, .bold))
                    .foregroundStyle(a.flatMap { a in b.map { stat.improved(from: $0, to: a) } } == true ? palette.accentText : palette.secondary)
                TrendSparkline(values: line.map(\.1), higherIsBetter: stat.higherIsBetter,
                               markIndex: then.flatMap { t in line.firstIndex { $0.0 == t.day } })
                    .frame(height: 30)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stat.title) trend")
    }

    /// The fourth cell: what Apple Health will add.
    private var healthTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ZONE 2 PACE · VO₂ MAX").font(.inter(10, .bold)).tracking(0.4).foregroundStyle(palette.secondary)
            Text("Come with Apple Health, with heart-rate zones.")
                .font(.inter(12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// The ⓘ sheet: what the numbers mean.
struct ProgressInfoSheet: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("How to read Progress")
                    .font(.display(28))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.text)
                item("Est. max", "The weight you could lift once, estimated from your best working set (Epley, up to 12 reps). It goes up when you add weight or reps.")
                item("Volume", "Weight × reps, added up over the working sets. Warm-ups, and sets under 60% of the day's top weight, are left out.")
                item("Bodyweight", "Best set is the most reps in one set. Adding weight or moving to a harder version shows as \"harder level\", not as a drop.")
                item("Holds", "Longest is your longest hold that day; total time adds up every hold.")
                item("vs chips", "Compare with the last session, or with the closest session on or before 4 weeks, 3 months or 1 year earlier.")
            }
            .padding(20)
        }
        .background(palette.background.ignoresSafeArea())
    }

    private func item(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.inter(15, .bold)).foregroundStyle(palette.text)
            Text(text).font(.inter(14)).foregroundStyle(palette.secondary)
        }
    }
}

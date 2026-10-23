import AccrueKit
import SwiftUI

/// "Every day", as on the ACal board: months you scroll back through, or the whole year as small
/// squares. Pinch, or the Month / Year toggle, switches between them. Tapping a day opens it on
/// Progress.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: DayKey
    @State private var zoom = Zoom.month
    @State private var filter = Filter.all
    @State private var scrollTarget: String?

    enum Zoom: Hashable { case month, year }
    enum Filter: CaseIterable { case all, strength, cardio
        var label: String { switch self { case .all: "All"; case .strength: "Strength"; case .cardio: "Cardio" } }
    }

    var body: some View {
        let today = DayKey.today()
        let totals = model.data.totalsByDay(catalog: model.catalog)
        let maxVolume = totals.values.map(\.volumeKg).max() ?? 0

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Every day")
                    .font(.display(34))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.text)
                Spacer()
                Text("pinch to zoom").font(.inter(12)).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    OutlineChip(title: f.label, selected: f == filter, height: 30) { filter = f }
                }
                Spacer()
                Text(summary(totals: totals, today: today))
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            weekdayHeader
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    if zoom == .month {
                        LazyVStack(spacing: 0) {
                            ForEach(months(today: today, totals: totals), id: \.self) { first in
                                month(first, today: today, totals: totals, maxVolume: maxVolume)
                                    .id(monthID(first))
                            }
                        }
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(weeks(today: today), id: \.self) { monday in
                                yearRow(monday, today: today, totals: totals, maxVolume: maxVolume)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            .simultaneousGesture(
                MagnifyGesture().onEnded { value in
                    if value.magnification < 0.8 { withAnimation { zoom = .year } }
                    if value.magnification > 1.25 { withAnimation { zoom = .month } }
                }
            )

            legend
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MiniToggle(options: [(Zoom.month, "Month"), (.year, "Year")], selection: $zoom, height: 30)
                    .frame(width: 160)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            if zoom == .year { Color.clear.frame(width: 64, height: 1) }
            ForEach(Weekday.allCases, id: \.self) { w in
                Text(w.letter)
                    .font(.inter(10, .bold))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(palette.accentFill).frame(width: 10, height: 10)
                Text("Strength, brighter = more volume")
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(zoom == .month ? palette.cardio : palette.warmup).frame(width: 16, height: 4)
                Text(zoom == .month ? "Cardio, longer bar = more minutes" : "Cardio days")
            }
            Spacer(minLength: 0)
        }
        .font(.inter(11))
        .foregroundStyle(palette.text.opacity(0.85))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .top) { Rectangle().fill(palette.card).frame(height: 1) }
    }

    // MARK: Months

    /// First days of this month and the ones before it: at least six, back to the first log.
    private func months(today: DayKey, totals: [DayKey: DayTotals]) -> [DayKey] {
        let earliest = totals.keys.min() ?? today
        var first = DayKey(year: today.year, month: today.month, day: 1)
        var result: [DayKey] = []
        while result.count < 6 || first > DayKey(year: earliest.year, month: earliest.month, day: 1) {
            result.append(first)
            first = DayKey(year: first.month == 1 ? first.year - 1 : first.year, month: first.month == 1 ? 12 : first.month - 1, day: 1)
            if result.count > 120 { break }
        }
        return result
    }

    private func monthID(_ first: DayKey) -> String { "\(first.year)-\(first.month)" }

    private func month(_ first: DayKey, today: DayKey, totals: [DayKey: DayTotals], maxVolume: Double) -> some View {
        let lead = first.weekday().rawValueMondayFirst
        let length = Calendar.current.range(of: .day, in: .month, for: first.date())?.count ?? 30
        let days = (0..<length).map { first.adding(days: $0) }
        let active = days.filter { shows(totals[$0]) }.count
        let isThisMonth = first.year == today.year && first.month == today.month
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(first.date().formatted(.dateTime.month(.wide)) + (first.year != today.year ? " \(first.year)" : "") + (isThisMonth ? " · this month" : ""))
                    .font(.inter(15, .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text("\(active) days").font(.inter(12)).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 56) }
                ForEach(days, id: \.self) { d in
                    cell(d, today: today, totals: totals[d], maxVolume: maxVolume)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private func cell(_ d: DayKey, today: DayKey, totals: DayTotals?, maxVolume: Double) -> some View {
        let future = d > today
        let strength = showsStrength(totals)
        let cardio = showsCardio(totals)
        let level = strength ? IntensityLevel.level(volumeKg: totals?.volumeKg ?? 0, hadStrength: true, maxVolumeKg: maxVolume) : 0
        let tag = (strength || cardio) ? (model.doneTitles(on: d).first ?? totals?.cardioExercises.first.map { model.name(of: $0) } ?? "") : ""
        let onBright = level == 3
        return Button {
            selected = d
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(d.day)")
                    .font(.inter(11, .semibold))
                    .foregroundStyle(onBright ? palette.onAccent : palette.text.opacity(future ? 0.5 : 0.85))
                Spacer(minLength: 0)
                Text(tag)
                    .font(.inter(10, .bold))
                    .foregroundStyle(onBright ? palette.onAccent : palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                GeometryReader { proxy in
                    if cardio {
                        Capsule().fill(palette.cardio)
                            .frame(width: proxy.size.width * min(1, Double(totals?.cardioSeconds ?? 0) / 2700))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .leading)
            .background(future ? Color.clear : strength ? strengthColor(level) : cardio ? palette.raised : palette.sunken,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(d == today ? palette.text : future ? palette.raised : .clear, lineWidth: d == today ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(d.date().formatted(.dateTime.weekday(.wide).month(.wide).day()) + (tag.isEmpty ? "" : ", \(tag)"))
    }

    // MARK: Year

    /// Mondays from this week back to the first week of last year.
    private func weeks(today: DayKey) -> [DayKey] {
        let stop = DayKey(year: today.year - 1, month: 1, day: 1).startOfWeek()
        var monday = today.startOfWeek()
        var result: [DayKey] = []
        while monday >= stop {
            result.append(monday)
            monday = monday.adding(days: -7)
        }
        return result
    }

    private func yearRow(_ monday: DayKey, today: DayKey, totals: [DayKey: DayTotals], maxVolume: Double) -> some View {
        let days = (0..<7).map { monday.adding(days: $0) }
        let firstOfMonth = days.first { $0.day == 1 }
        // The week that holds Dec 31 of last year gets the year as its label.
        let yearBreak = days.contains { $0.month == 12 && $0.day == 31 && $0.year == today.year - 1 }
        let label = yearBreak ? "Dec \(today.year - 1)"
            : firstOfMonth.map { $0.date().formatted(.dateTime.month(.abbreviated)) } ?? ""
        return HStack(spacing: 4) {
            Button {
                let target = firstOfMonth ?? days[0]
                withAnimation { zoom = .month }
                scrollTarget = "\(target.year)-\(target.month)"
            } label: {
                Text(label)
                    .font(.inter(11, .bold))
                    .foregroundStyle(yearBreak ? palette.text : palette.text.opacity(0.8))
                    .frame(width: 64, height: 14, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(label.isEmpty)
            ForEach(days, id: \.self) { d in
                let t = totals[d]
                let future = d > today
                RoundedRectangle(cornerRadius: 3)
                    .fill(future ? Color.clear : showsStrength(t)
                          ? strengthColor(IntensityLevel.level(volumeKg: t?.volumeKg ?? 0, hadStrength: true, maxVolumeKg: maxVolume))
                          : showsCardio(t) ? cardioColor(t) : palette.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(d == today ? palette.text : future ? palette.raised : .clear, lineWidth: d == today ? 1.5 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
            }
        }
        .padding(.top, yearBreak ? 14 : 0)
    }

    // MARK: Colours and filter

    private func strengthColor(_ level: Int) -> Color {
        palette.accentFill.opacity([0, 0.22, 0.48, 1][min(3, max(0, level))])
    }

    private func cardioColor(_ totals: DayTotals?) -> Color {
        let minutes = Double(totals?.cardioSeconds ?? 0) / 60
        return palette.warmup.opacity(minutes > 40 ? 0.85 : minutes > 20 ? 0.55 : 0.3)
    }

    private func showsStrength(_ t: DayTotals?) -> Bool { filter != .cardio && (t?.hasStrength ?? false) }
    private func showsCardio(_ t: DayTotals?) -> Bool { filter != .strength && (t?.hasCardio ?? false) }
    private func shows(_ t: DayTotals?) -> Bool { showsStrength(t) || showsCardio(t) }

    private func summary(totals: [DayKey: DayTotals], today: DayKey) -> String {
        if zoom == .month { return "scroll down for older months" }
        let count = totals.filter { $0.key.year == today.year && shows($0.value) }.count
        return "\(count) days in \(String(today.year)) · scroll for \(String(today.year - 1))"
    }
}

private extension Weekday {
    /// 0 for Monday through 6 for Sunday.
    var rawValueMondayFirst: Int { Weekday.allCases.firstIndex(of: self) ?? 0 }
}

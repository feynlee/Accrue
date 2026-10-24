import AccrueKit
import SwiftUI

/// Plans: the week, the presets, and every exercise.
struct PlansView: View {
    enum PlansSection: Hashable { case week, presets, exercises }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var section = PlansSection.week
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                HStack {
                    Text("Plans")
                        .font(.display(34))
                        .textCase(.uppercase)
                    Spacer()
                    if section == .presets {
                        Button {
                            let preset = Preset(name: "New preset")
                            model.update { $0.upsert(preset) }
                            path.append(PresetRoute(id: preset.id))
                        } label: {
                            Label("New", systemImage: "plus")
                                .font(.inter(13, .bold))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .background(palette.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(palette.text)
                SegmentPicker(options: [(PlansSection.week, "Week"), (PlansSection.presets, "Presets"), (PlansSection.exercises, "Exercises")],
                              selection: $section)
                switch section {
                case .week: WeekList()
                case .presets: PresetGrid()
                case .exercises: ExerciseLibrary()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PresetRoute.self) { PresetEditView(presetID: $0.id) }
            .navigationDestination(for: ExerciseRoute.self) { ExerciseDetailView(exerciseID: $0.id) }
            .navigationDestination(for: FamilyRoute.self) { FamilyMembersView(familyID: $0.id) }
            .navigationDestination(for: TimedRoute.self) { TimedEditView(timedID: $0.id) }
        }
    }
}

struct PresetRoute: Hashable { let id: UUID }
struct ExerciseRoute: Hashable { let id: String }
struct FamilyRoute: Hashable { let id: String }
struct TimedRoute: Hashable { let id: UUID }

/// Mon to Sun with each day's parts; tap a day to change the routine.
private struct WeekList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var editing: Weekday?

    var body: some View {
        let today = DayKey.today().weekday()
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let parts = model.data.routine[day]
                    Button {
                        editing = day
                    } label: {
                        HStack(spacing: 12) {
                            Text(day.short)
                                .font(.inter(12, .bold))
                                .foregroundStyle(day == today ? palette.accentText : palette.secondary)
                                .frame(width: 36, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(parts.isEmpty ? "Rest" : parts.map { model.data.title(of: $0, catalog: model.catalog) }.joined(separator: " + "))
                                    .font(.inter(15, .bold))
                                    .foregroundStyle(palette.text)
                                Text(detail(parts))
                                    .font(.inter(12))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.line)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 58)
                        .card(radius: 14)
                    }
                    .buttonStyle(.plain)
                }
                Text("To change a single day, use Edit day on Train.")
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { day in
            DayEditView(target: .weekday(day))
        }
    }

    private func detail(_ parts: [DayPart]) -> String {
        guard !parts.isEmpty else { return "Nothing planned" }
        return parts.flatMap { model.data.items(in: $0) }.map { model.name(of: $0.exerciseID) }.joined(separator: ", ")
    }
}

/// Every preset as a card, with the weekdays it is on.
private struct PresetGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(model.data.presets) { preset in
                    NavigationLink(value: PresetRoute(id: preset.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .font(.inter(16, .bold))
                                .foregroundStyle(palette.text)
                            Text(preset.items.map { model.name(of: $0.exerciseID) }.joined(separator: ", "))
                                .font(.inter(12))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text(days(preset))
                                .font(.inter(11, .bold))
                                .foregroundStyle(palette.accentText)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .card(radius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func days(_ preset: Preset) -> String {
        let days = model.data.weekdays(using: preset.id)
        if days.isEmpty { return "Not scheduled" }
        if days.count == 1 { return days[0].name + "s" }
        return days.map(\.short).joined(separator: ", ")
    }
}

import AccrueKit
import SwiftUI

/// Search all exercises; with no search, favorites grouped by body area, then every family.
struct ExerciseLibrary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    /// A timed exercise just made with "+ New timed exercise", opened for editing.
    @State private var newTimed: UUID?

    private static let regionOrder = ["chest", "back", "shoulders", "arms", "forearms", "core", "hips", "thighs",
                                      "lower legs", "feet", "neck", "cardio", "other"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
                TextField("Search \(model.catalog.exercises.count) exercises", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(palette.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .font(.inter(15))
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .card(radius: 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        browse
                    } else {
                        let hits = model.catalog.search(query)
                        if hits.isEmpty {
                            Text("Nothing matches \"\(query)\".")
                                .font(.inter(14))
                                .foregroundStyle(palette.secondary)
                        }
                        ForEach(hits) { link($0) }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationDestination(item: $newTimed) { TimedEditView(timedID: $0) }
    }

    @ViewBuilder
    private var browse: some View {
        timedSection
        let favorites = model.data.favorites.compactMap { model.exercise($0) }
        let grouped = Dictionary(grouping: favorites) { model.catalog.region(for: $0) }
        ForEach(Self.regionOrder.filter { grouped[$0] != nil }, id: \.self) { region in
            Text("Favorites · \(region)")
                .sectionLabel()
                .padding(.top, 8)
            ForEach(grouped[region] ?? []) { link($0) }
        }
        if favorites.isEmpty {
            Text("Star exercises to keep them here.")
                .font(.inter(13))
                .foregroundStyle(palette.secondary)
        }
        Text("All families")
            .sectionLabel()
            .padding(.top, 14)
        ForEach(model.catalog.families.values.sorted { $0.name < $1.name }) { family in
            NavigationLink(value: FamilyRoute(id: family.id)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(family.name).font(.inter(15, .semibold)).foregroundStyle(palette.text)
                        Text("\(family.kind.rawValue.capitalized) · \(model.catalog.members(of: family.id).count)")
                            .font(.inter(12))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.line)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .card(radius: 12)
            }
            .buttonStyle(.plain)
        }
    }

    /// Timed exercises sit in the library with the rest; a new one starts from the 7-minute.
    @ViewBuilder
    private var timedSection: some View {
        Text("Timed")
            .sectionLabel()
            .padding(.top, 8)
        ForEach(model.data.timed) { plan in
            NavigationLink(value: TimedRoute(id: plan.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.inter(15, .semibold)).foregroundStyle(palette.text)
                        Text("\(plan.style.label) · \(plan.moves.count) moves · " + DurationFormat.clock(TimeInterval(plan.totalSeconds())))
                            .font(.inter(12))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.line)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .card(radius: 12)
            }
            .buttonStyle(.plain)
        }
        Button {
            var plan = TimedExercise.template(.sevenMinute)
            plan.name = "My timed exercise"
            model.update { $0.upsert(plan) }
            newTimed = plan.id
        } label: {
            Text("+ New timed exercise")
                .font(.inter(14, .bold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    private func link(_ exercise: Exercise) -> some View {
        NavigationLink(value: ExerciseRoute(id: exercise.id)) {
            ExerciseRow(exercise: exercise)
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .card(radius: 12)
        }
        .buttonStyle(.plain)
    }
}

/// The exercises in one family.
struct FamilyMembersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let familyID: String

    var body: some View {
        let members = model.catalog.members(of: familyID).sorted { $0.name < $1.name }
        List {
            if let family = model.catalog.families[familyID] {
                Section {
                    Text(family.pattern)
                        .font(.inter(14))
                        .foregroundStyle(palette.secondary)
                        .listRowBackground(palette.card)
                }
            }
            Section("\(members.count) exercises") {
                ForEach(members) { exercise in
                    NavigationLink(value: ExerciseRoute(id: exercise.id)) {
                        ExerciseRow(exercise: exercise)
                    }
                    .listRowBackground(palette.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(model.catalog.families[familyID]?.name ?? "Family")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import AccrueKit
import SwiftUI

/// Search every exercise; with an empty search, show favorites (or cardio) first.
struct ExercisePicker: View {
    enum Suggestions {
        case favorites
        case cardio
    }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    var suggestions: Suggestions = .favorites
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(suggestedGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items) { row($0) }
                    }
                }
            } else {
                let hits = model.catalog.search(query)
                if hits.isEmpty {
                    Text("No exercise matches \"\(query)\".")
                        .foregroundStyle(palette.secondary)
                        .listRowBackground(palette.card)
                }
                ForEach(hits) { row($0) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search \(model.catalog.exercises.filter { !$0.hidden }.count) exercises")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private struct SuggestionGroup {
        let title: String
        let items: [Exercise]
    }

    private var suggestedGroups: [SuggestionGroup] {
        let favorites = model.data.favorites.compactMap { model.exercise($0) }
        switch suggestions {
        case .favorites:
            return favorites.isEmpty ? [] : [SuggestionGroup(title: "Favorites", items: favorites)]
        case .cardio:
            let cardio = favorites.filter { model.catalog.region(for: $0) == "cardio" }
            let common = ["s:outdoor-run", "s:treadmill-run", "s:outdoor-walk", "s:treadmill-walk", "s:hike", "s:road-cycling", "s:swim-freestyle", "s:stair-climber", "s:spin-bike", "s:tennis"]
                .compactMap { model.exercise($0) }
                .filter { ex in !cardio.contains { $0.id == ex.id } }
            return [SuggestionGroup(title: "Favorites", items: cardio), SuggestionGroup(title: "Common", items: common)].filter { !$0.items.isEmpty }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        Button {
            onPick(exercise.id)
        } label: {
            ExerciseRow(exercise: exercise)
        }
        .buttonStyle(.plain)
        .listRowBackground(palette.card)
    }
}

/// Name, family and how it is tracked.
struct ExerciseRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.inter(15, .semibold))
                    .foregroundStyle(palette.text)
                Text(subtitle)
                    .font(.inter(12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.data.isFavorite(exercise.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.accentText)
                    .accessibilityLabel("Favorite")
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let tracking = model.catalog.tracking(for: exercise)
        var parts: [String] = []
        if let family = model.catalog.family(for: exercise) { parts.append(family.name) }
        else if let group = exercise.group { parts.append(group) }
        parts.append(tracking.label)
        return parts.joined(separator: " · ")
    }
}

extension Tracking {
    var label: String {
        switch self {
        case .weightReps: "Weighted"
        case .reps: "Bodyweight"
        case .hold: "Hold"
        case .weightHold: "Weighted hold"
        case .weightDistance: "Weight × distance"
        case .time: "Time"
        case .distanceTimeHR: "Cardio · distance"
        case .timeHR: "Cardio · time"
        }
    }
}

/// Lays children out in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

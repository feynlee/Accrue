import AccrueKit
import AppIntents
import Foundation

// What Siri and Shortcuts can name: exercises from the catalog, and the user's workouts
// (presets and timed exercises), plus the small choices the actions take.

/// An exercise from the catalog. Siri suggests today's plan, favorites and recent ones first.
struct ExerciseEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Exercise" }
    static var defaultQuery: ExerciseQuery { ExerciseQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.displayName
    }
}

struct ExerciseQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        let model = await SiriModel.ready()
        return identifiers.compactMap(model.exercise).map(ExerciseEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        let model = await SiriModel.ready()
        let logger = QuickLogger(catalog: model.catalog, day: .today())
        var found: [Exercise] = []
        // The user's own words first ("pulls" is their pulldown), then the catalog's matches.
        if let mine = logger.exercise(named: string, in: model.data) { found.append(mine) }
        for exercise in model.catalog.search(string, limit: 20) where !found.contains(where: { $0.id == exercise.id }) {
            found.append(exercise)
        }
        return found.map(ExerciseEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        let model = await SiriModel.ready()
        let data = model.data
        var ids = data.parts(on: .today()).flatMap { data.items(in: $0).map(\.exerciseID) }
        ids += data.favorites
        ids += data.sets.sorted { $0.loggedAt > $1.loggedAt }.prefix(200).map(\.exerciseID)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.prefix(30).compactMap(model.exercise).map(ExerciseEntity.init)
    }
}

/// One of the user's workouts: a preset ("Push") or a timed exercise ("7-minute").
struct WorkoutEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Workout" }
    static var defaultQuery: WorkoutQuery { WorkoutQuery() }

    /// "preset:<uuid>" or "timed:<uuid>".
    let id: String
    let name: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    var part: DayPart.Content? {
        let pieces = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, let uuid = UUID(uuidString: pieces[1]) else { return nil }
        return pieces[0] == "timed" ? .timed(uuid) : .preset(uuid)
    }

    @MainActor
    static func all(in model: AppModel) -> [WorkoutEntity] {
        let presets = model.data.presets.map { preset in
            WorkoutEntity(id: "preset:\(preset.id.uuidString)", name: preset.name,
                          detail: preset.items.prefix(3).map { model.name(of: $0.exerciseID) }.joined(separator: ", "))
        }
        let timed = model.data.timed.map { timed in
            WorkoutEntity(id: "timed:\(timed.id.uuidString)", name: timed.name,
                          detail: "\(max(1, timed.totalSeconds() / 60)) minutes")
        }
        return presets + timed
    }
}

struct WorkoutQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [WorkoutEntity] {
        let all = WorkoutEntity.all(in: await SiriModel.ready())
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    @MainActor
    func entities(matching string: String) async throws -> [WorkoutEntity] {
        let query = string.lowercased()
        return WorkoutEntity.all(in: await SiriModel.ready()).filter { $0.name.lowercased().contains(query) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkoutEntity] {
        WorkoutEntity.all(in: await SiriModel.ready())
    }
}

enum WeekdayChoice: Int, AppEnum {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Weekday" }
    static var caseDisplayRepresentations: [WeekdayChoice: DisplayRepresentation] {
        [.monday: "Monday", .tuesday: "Tuesday", .wednesday: "Wednesday", .thursday: "Thursday",
         .friday: "Friday", .saturday: "Saturday", .sunday: "Sunday"]
    }

    var weekday: Weekday { Weekday(rawValue: rawValue) ?? .monday }

    /// The next date (today included) that falls on this weekday.
    var nextDay: DayKey {
        let today = DayKey.today()
        return (0..<7).map { today.adding(days: $0) }.first { $0.weekday() == weekday } ?? today
    }
}

enum ScopeChoice: String, AppEnum {
    case thisDayOnly, everyWeek

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Change" }
    static var caseDisplayRepresentations: [ScopeChoice: DisplayRepresentation] {
        [.thisDayOnly: "This day only", .everyWeek: "Every week"]
    }

    var scope: EditScope { self == .everyWeek ? .everyWeek : .thisDayOnly }
}

enum TabChoice: String, AppEnum {
    case train, plans, progress, you

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Screen" }
    static var caseDisplayRepresentations: [TabChoice: DisplayRepresentation] {
        [.train: "Train", .plans: "Plans", .progress: "Progress", .you: "You"]
    }

    var tab: AppTab { AppTab(rawValue: rawValue) ?? .train }
}

enum UnitChoice: String, AppEnum {
    case lb, kg

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Weight unit" }
    static var caseDisplayRepresentations: [UnitChoice: DisplayRepresentation] {
        [.lb: "Pounds", .kg: "Kilograms"]
    }
}

enum AppearanceChoice: String, AppEnum {
    case dark, light, system

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Theme" }
    static var caseDisplayRepresentations: [AppearanceChoice: DisplayRepresentation] {
        [.dark: "Dark", .light: "Light", .system: "Match iPhone"]
    }
}

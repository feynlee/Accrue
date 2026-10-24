import AccrueKit
import Foundation
import Observation

/// The app's state: the catalog (read-only) and the user's data, saved shortly after each change.
@Observable
@MainActor
final class AppModel {
    private(set) var catalog: Catalog = .empty
    private(set) var catalogLoaded = false
    private(set) var data: AccrueData
    private(set) var saveError: String?

    /// GPS for outdoor cardio; Train starts and stops it with the workout.
    let runTracker = RunTracker()

    @ObservationIgnored private let store: DataStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: DataStore) {
        self.store = store
        self.data = (try? store.load()) ?? .starter()
    }

    /// The standard on-device store, or memory if Application Support is not available.
    /// Launched with `-demoData YES` (screenshots), it uses made-up history in memory instead.
    static func live() -> AppModel {
        if UserDefaults.standard.bool(forKey: "demoData") {
            var data = AccrueData.demo()
            // `-demoLive YES` also starts today's first part with two sets logged (live screenshot).
            if UserDefaults.standard.bool(forKey: "demoLive"), let catalog = try? Catalog.bundled() {
                let today = DayKey.today()
                if let part = data.parts(on: today).first, let item = data.items(in: part).first {
                    let session = data.startSession(day: today, partID: part.id, title: data.title(of: part, catalog: catalog),
                                                    at: Date().addingTimeInterval(-754))
                    let last = data.history(of: item.exerciseID).last { !$0.isWarmup }
                    for _ in 0..<2 {
                        data.log(LoggedSet(day: today, exerciseID: item.exerciseID, partID: part.id, sessionID: session.id,
                                           weightKg: last?.weightKg, reps: last?.reps ?? item.reps))
                    }
                }
            }
            demoTimed(&data)
            demoRun(&data)
            return AppModel(store: MemoryStore(data))
        }
        let store: DataStore = (try? JSONFileStore.standard()) ?? MemoryStore()
        return AppModel(store: store)
    }

    /// `-progressScreen timed | timedrun | timedask | timededit` puts the 7-minute first on today
    /// (screenshots); `timedrun` starts it four moves in, `timedask` at its end.
    private static func demoTimed(_ data: inout AccrueData) {
        let screen = UserDefaults.standard.string(forKey: "progressScreen") ?? ""
        guard screen.hasPrefix("timed"), let plan = data.timed.first else { return }
        let today = DayKey.today()
        let part = DayPart.timed(plan.id)
        data.setParts([part] + data.parts(on: today).filter { $0.timedID == nil }, on: today, scope: .thisDayOnly)
        let back: TimeInterval? = screen == "timedrun" ? 132 : screen == "timedask" ? TimeInterval(plan.totalSeconds()) : nil
        if let back {
            data.startSession(day: today, partID: part.id, title: plan.name, at: Date().addingTimeInterval(-back))
        }
    }

    /// `-progressScreen run | runlive | runask` puts today's run first (screenshots); `runlive`
    /// starts it six minutes in, `runask` at its goal time.
    private static func demoRun(_ data: inout AccrueData) {
        let screen = UserDefaults.standard.string(forKey: "progressScreen") ?? ""
        guard screen.hasPrefix("run") else { return }
        let today = DayKey.today()
        let item = PlannedExercise(exerciseID: StarterIDs.run, sets: 1, reps: nil, restSeconds: 0, minutes: 30, targetZone: 2)
        let part = DayPart.exercise(item)
        data.setParts([part] + data.parts(on: today), on: today, scope: .thisDayOnly)
        let back: TimeInterval? = screen == "runlive" ? 372 : screen == "runask" ? 30 * 60 : nil
        if let back {
            let session = data.startSession(day: today, partID: part.id, title: "Run", at: Date().addingTimeInterval(-back))
            data.updateSession(session.id) {
                $0.indoor = false
                $0.distanceMeters = screen == "runlive" ? 1030 : 5120
            }
        }
    }

    static func preview() -> AppModel {
        let model = AppModel(store: MemoryStore(.starter()))
        model.catalog = (try? Catalog.bundled()) ?? .empty
        model.catalogLoaded = true
        return model
    }

    func loadCatalog() async {
        guard !catalogLoaded else { return }
        let loaded = await Task.detached(priority: .userInitiated) { try? Catalog.bundled() }.value
        catalog = loaded ?? .empty
        catalogLoaded = true
    }

    // MARK: Changes

    /// Every change to the user's data goes through here, so it is saved.
    func update(_ change: (inout AccrueData) -> Void) {
        change(&data)
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try store.save(data)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Ends a workout. A cardio part saves one set with its time and distance, so it shows in
    /// history and Progress like the lifts do.
    func endWorkout(_ id: UUID) {
        guard let session = data.sessions.first(where: { $0.id == id }) else { return }
        update { data in
            if data.sets(in: id).isEmpty, session.timer == nil,
               let part = data.parts(on: session.day).first(where: { $0.id == session.partID }),
               case .exercise(let item) = part.content, !tracking(of: item.exerciseID).isSetBased {
                let meters = session.distanceMeters ?? 0
                data.log(LoggedSet(day: session.day, exerciseID: item.exerciseID, partID: part.id, sessionID: id,
                                   distanceMeters: meters > 0 ? meters : nil,
                                   durationSeconds: Int(session.activeSeconds(at: Date()).rounded())))
            }
            data.endSession(id)
        }
        if runTracker.sessionID == id { runTracker.stop() }
    }

    /// Whether a part is one cardio exercise (it gets the run card, and no lifting summary).
    func isCardio(_ part: DayPart) -> Bool {
        if case .exercise(let item) = part.content { return !tracking(of: item.exerciseID).isSetBased }
        return false
    }

    // MARK: Lookups the screens share

    func exercise(_ id: String) -> Exercise? {
        catalog.exercise(id)
    }

    func name(of exerciseID: String) -> String {
        catalog.exercise(exerciseID)?.displayName ?? "Exercise"
    }

    func tracking(of exerciseID: String) -> Tracking {
        catalog.exercise(exerciseID).map { catalog.tracking(for: $0) } ?? .weightReps
    }

    func history(of exerciseID: String) -> ExerciseHistory {
        ExerciseHistory(exerciseID: exerciseID, tracking: tracking(of: exerciseID), sets: data.history(of: exerciseID))
    }

    /// A planned exercise with targets that fit how it is tracked.
    func plannedDefaults(for exerciseID: String) -> PlannedExercise {
        switch tracking(of: exerciseID) {
        case .hold, .weightHold:
            PlannedExercise(exerciseID: exerciseID, sets: 3, reps: nil, holdSeconds: 30, restSeconds: 60)
        case .time, .timeHR, .distanceTimeHR:
            PlannedExercise(exerciseID: exerciseID, sets: 1, reps: nil, restSeconds: 0, minutes: 30, targetZone: 2)
        case .weightDistance:
            PlannedExercise(exerciseID: exerciseID, sets: 3, reps: nil, restSeconds: 90)
        case .weightReps, .reps:
            PlannedExercise(exerciseID: exerciseID, sets: 3, reps: 10)
        }
    }

    /// What was done on a day, by name: parts with logged sets, then workouts started from Other.
    /// Used by the Train week strip and the calendar.
    func doneTitles(on day: DayKey) -> [String] {
        let parts = data.parts(on: day)
        // A part counts as done once it has sets, or (a timed exercise) a saved workout.
        let loggedParts = Set(data.sets(on: day).compactMap(\.partID))
            .union(data.sessions(on: day).filter { !$0.isActive }.compactMap(\.partID))
        var names: [String] = []
        for part in parts where loggedParts.contains(part.id) {
            names.append(data.title(of: part, catalog: catalog))
        }
        for session in data.sessions(on: day) where !names.contains(session.title) {
            if session.partID == nil || !parts.contains(where: { $0.id == session.partID }) { names.append(session.title) }
        }
        return names
    }

    /// The day's plan, by name.
    func plannedTitles(on day: DayKey) -> [String] {
        data.parts(on: day).map { data.title(of: $0, catalog: catalog) }
    }
}

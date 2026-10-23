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
            return AppModel(store: MemoryStore(data))
        }
        let store: DataStore = (try? JSONFileStore.standard()) ?? MemoryStore()
        return AppModel(store: store)
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
            PlannedExercise(exerciseID: exerciseID, sets: 1, reps: nil, restSeconds: 0, minutes: 30)
        case .weightDistance:
            PlannedExercise(exerciseID: exerciseID, sets: 3, reps: nil, restSeconds: 90)
        case .weightReps, .reps:
            PlannedExercise(exerciseID: exerciseID, sets: 3, reps: 10)
        }
    }
}

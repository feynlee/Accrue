import AccrueKit
import Foundation
@preconcurrency import HealthKit
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
    /// Apple Health and the Accrue Watch app.
    let health = HealthService()
    let strap = HeartRateStrap()
    let coach = CoachModel()

    @ObservationIgnored private let store: DataStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(store: DataStore) {
        self.store = store
        self.data = (try? store.load()) ?? .starter()
        coach.attach(to: self)
    }

    var weightUnit: WeightUnit {
        UserDefaults.standard.string(forKey: SettingsKey.weightUnit).flatMap(WeightUnit.init(rawValue:)) ?? .lb
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
            let model = AppModel(store: MemoryStore(data))
            model.strap.showDemo()
            let screen = UserDefaults.standard.string(forKey: "progressScreen") ?? ""
            if screen.hasPrefix("coach") { model.coach.showDemo(screen) }
            return model
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

    /// `-progressScreen run | runlive | runhit | runzone | treadmill | treadmilldone` puts a run first on
    /// today (screenshots): `runlive` six minutes in, `runhit` just past last time's mark,
    /// `runzone` aiming for 25 min in Zone 2, `treadmilldone` a finished treadmill run.
    private static func demoRun(_ data: inout AccrueData) {
        let screen = UserDefaults.standard.string(forKey: "progressScreen") ?? ""
        guard screen.hasPrefix("run") || screen.hasPrefix("treadmill") else { return }
        let today = DayKey.today()
        let exerciseID = screen.hasPrefix("treadmill") ? StarterIDs.treadmillRun : StarterIDs.run
        let item = PlannedExercise(exerciseID: exerciseID, sets: 1, reps: nil, restSeconds: 0, minutes: 30, targetZone: 2)
        let part = DayPart.exercise(item)
        data.setParts([part] + data.parts(on: today), on: today, scope: .thisDayOnly)
        let last = data.history(of: StarterIDs.run).last { $0.day < today }
        let lastSeconds = TimeInterval(last?.durationSeconds ?? 1800)
        let back: TimeInterval? = switch screen {
        case "runlive": 372
        case "runhit": lastSeconds + 42
        case "runzone": 1334
        case "treadmilldone": 1830
        default: nil
        }
        guard let back else { return }
        let session = data.startSession(day: today, partID: part.id, title: "Run", at: Date().addingTimeInterval(-back))
        data.updateSession(session.id) {
            $0.goalSeconds = Int(lastSeconds)
            $0.goalIsLastTime = true
            $0.distanceMeters = screen == "runlive" ? 1030 : screen == "runhit" ? 5260 : screen == "runzone" ? 3720 : nil
            // Made-up heart rate, as the Accrue Watch app would send it.
            if screen != "treadmilldone" {
                $0.heartRate = screen == "runhit" ? 129 : 126
                $0.heartRateAt = Date()
                $0.zoneSeconds = [back * 0.15, back * 0.82, back * 0.03, 0, 0]
            }
            if screen == "runzone" {
                $0.goalZone = 2
                $0.goalSeconds = 25 * 60
                $0.goalIsLastTime = false
            }
        }
        if screen == "treadmilldone" {
            data.log(LoggedSet(day: today, exerciseID: exerciseID, partID: part.id, sessionID: session.id, durationSeconds: 1830))
            data.endSession(session.id)
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
        let kcal = estimatedKcal(session, at: Date())
        update { data in
            if let kcal { data.updateSession(id) { $0.activeKcal = kcal } }
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
        if let ended = data.sessions.first(where: { $0.id == id }), usesHealth {
            health.save(ended, configuration: healthConfiguration(for: ended))
        }
    }

    // MARK: Apple Health and the watch

    /// Screenshots use made-up data and never ask for Health.
    var usesHealth: Bool { !UserDefaults.standard.bool(forKey: "demoData") }

    /// What Health should call a workout: the cardio exercise's activity, HIIT for a timed
    /// exercise, strength training for lifting.
    func healthConfiguration(for session: WorkoutSession) -> HKWorkoutConfiguration {
        let exercise = cardioExercise(of: session)
        return HealthService.configuration(activity: exercise.flatMap(catalog.healthKitActivity(for:)),
                                           outdoor: exercise?.location.map { $0 == "outdoor" },
                                           timed: session.timer != nil)
    }

    /// The one cardio exercise a workout records, if it is one.
    private func cardioExercise(of session: WorkoutSession) -> Exercise? {
        guard let part = data.parts(on: session.day).first(where: { $0.id == session.partID }),
              case .exercise(let item) = part.content, !tracking(of: item.exerciseID).isSetBased else { return nil }
        return catalog.exercise(item.exerciseID)
    }

    /// Active calories from body weight and the activity, when no watch measures them.
    func estimatedKcal(_ session: WorkoutSession, at now: Date) -> Double? {
        guard session.watchLinked != true else { return session.activeKcal }
        let kg = UserDefaults.standard.object(forKey: SettingsKey.bodyWeightKg) as? Double ?? CalorieEstimate.defaultBodyKg
        return CalorieEstimate.activeKcal(activity: cardioExercise(of: session).flatMap(catalog.healthKitActivity(for:)),
                                          timed: session.timer != nil, seconds: session.activeSeconds(at: now),
                                          meters: session.distanceMeters, bodyKg: kg)
    }

    /// Connects the paired heart-rate strap while a workout records without a watch.
    func syncStrap() {
        if let session = data.activeSession, session.watchLinked != true, strap.savedID != nil {
            strap.onReading = { [weak self] bpm in
                guard self?.data.activeSession?.watchLinked != true else { return }
                self?.recordHeartRate(bpm)
            }
            strap.connect()
        } else if strap.status != .searching {
            strap.disconnect()
        }
    }

    /// What the watch shows: the title, your zones, and the cardio goal.
    func watchSetup(for session: WorkoutSession) -> WorkoutLink.Setup {
        let part = data.parts(on: session.day).first { $0.id == session.partID }
        var zone: Int?
        if let part, case .exercise(let item) = part.content { zone = item.targetZone }
        return WorkoutLink.Setup(title: session.title, maxHR: maxHeartRate, targetZone: zone,
                                 goalSeconds: session.goalSeconds, goalZone: session.goalZone)
    }

    var maxHeartRate: Int {
        UserDefaults.standard.object(forKey: SettingsKey.maxHeartRate) as? Int ?? HeartZones.defaultMax
    }

    /// Heart rate, calories and distance from the watch.
    func applyWatchReading(_ reading: WorkoutLink.Reading) {
        guard let before = data.activeSession else { return }
        let zones = HeartZones(maxHR: maxHeartRate)
        update { $0.updateSession(before.id) { $0.apply(reading, zones: zones) } }
        guard let after = data.activeSession else { return }
        let crossed = !before.reachedGoal(active: 0) && after.reachedGoal(active: 0)
        let distanceCrossed = after.goalMeters.map { (before.distanceMeters ?? 0) < $0 && (after.distanceMeters ?? 0) >= $0 } ?? false
        if (after.goalZone != nil && crossed) || distanceCrossed {
            TargetAlerts.reachedNow(after, name: after.title)
        }
    }

    /// Sets a cardio workout's goal from the exercise's target and last time.
    func applyCardioGoal(_ sessionID: UUID, exerciseID: String, plannedMinutes: Int?, zone: Int?,
                         target: CardioTarget? = nil) {
        let target = target ?? data.cardioTarget(for: exerciseID)
        guard let day = data.sessions.first(where: { $0.id == sessionID })?.day else { return }
        let last = history(of: exerciseID).lastTime(before: day)
        update { $0.updateSession(sessionID) { $0.setGoal(target, last: last, plannedMinutes: plannedMinutes, zone: zone ?? 2) } }
    }

    /// A heart-rate reading for the workout that is recording (from a Bluetooth strap). It
    /// adds up time in each zone and notifies once a time-in-zone target is reached.
    func recordHeartRate(_ bpm: Int, at date: Date = Date()) {
        guard let before = data.activeSession else { return }
        let max = UserDefaults.standard.object(forKey: SettingsKey.maxHeartRate) as? Int ?? HeartZones.defaultMax
        update { $0.updateSession(before.id) { $0.recordHeartRate(bpm, at: date, zones: HeartZones(maxHR: max)) } }
        if let after = data.activeSession, after.goalZone != nil, !before.reachedGoal(active: 0), after.reachedGoal(active: 0) {
            TargetAlerts.reachedNow(after, name: after.title)
        }
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

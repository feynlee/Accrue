import AccrueKit
import AppIntents
import Foundation

// Everything you can do in Accrue, as App Intents: Siri runs them by voice, Shortcuts chains
// them, and Apple Intelligence can use them with your data. The answers come from
// AccrueKit's Assistant, so they say what the screens show.

@MainActor
enum SiriModel {
    /// The app's model with the catalog loaded (an intent can run before any screen is open).
    static func ready() async -> AppModel {
        let model = AppModel.shared
        await model.loadCatalog()
        return model
    }

    static func assistant(_ model: AppModel) -> Assistant {
        Assistant(catalog: model.catalog, data: model.data, unit: model.weightUnit)
    }

    /// Saves straight away: Siri may not keep the app running for the usual half second.
    static func change(_ model: AppModel, _ edit: (inout AccrueData) -> Void) {
        model.update(edit)
        model.saveNow()
    }

    static func day(_ date: Date?) -> DayKey {
        date.map { DayKey($0) } ?? .today()
    }
}

struct SiriError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// The answer, spoken by Siri and passed on as text in Shortcuts.
func answer(_ text: String) -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    .result(value: text, dialog: IntentDialog(stringLiteral: text))
}

// MARK: Your data

struct DayPlanIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Workout Plan" }
    static var description: IntentDescription { IntentDescription("Says what is planned for a day, with last time's numbers for each exercise.") }

    @Parameter(title: "Day", description: "Leave empty for today.")
    var date: Date?

    static var parameterSummary: some ParameterSummary { Summary("Get the plan for \(\.$date)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).plan(on: SiriModel.day(date)))
    }
}

struct DayLogIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Workout Log" }
    static var description: IntentDescription { IntentDescription("Says what you did on a day: each exercise, your sets and the total lifted.") }

    @Parameter(title: "Day", description: "Leave empty for today.")
    var date: Date?

    static var parameterSummary: some ParameterSummary { Summary("Get what I did on \(\.$date)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).log(on: SiriModel.day(date)))
    }
}

struct LastWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Last Workout" }
    static var description: IntentDescription { IntentDescription("Says what you did the last day you trained.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).lastWorkout())
    }
}

struct WeekSummaryIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Week Summary" }
    static var description: IntentDescription { IntentDescription("Says how a week went: workout days, working sets, weight lifted, cardio, and planned days left.") }

    @Parameter(title: "Week of", description: "Any day in the week. Leave empty for this week.")
    var date: Date?

    static var parameterSummary: some ParameterSummary { Summary("Get the week of \(\.$date)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).week(of: SiriModel.day(date)))
    }
}

struct ExerciseProgressIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Exercise Progress" }
    static var description: IntentDescription { IntentDescription("Says your last time on an exercise, your estimated max or best, and the change from 4 weeks ago.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    static var parameterSummary: some ParameterSummary { Summary("Get progress on \(\.$exercise)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).progress(of: exercise.id))
    }
}

struct PersonalBestIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Personal Best" }
    static var description: IntentDescription { IntentDescription("Says your best day on an exercise.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    static var parameterSummary: some ParameterSummary { Summary("Get my best \(\.$exercise)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).personalBest(of: exercise.id))
    }
}

struct WhatsNextIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Next Exercise" }
    static var description: IntentDescription { IntentDescription("During a workout, says the next exercise and how many sets are left. Otherwise, what to start today.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        return answer(SiriModel.assistant(model).nextUp())
    }
}

// MARK: Workouts

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Start Workout" }
    static var description: IntentDescription { IntentDescription("Starts today's next workout, or the workout or exercise you name, and opens Train.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Workout", description: "A preset or timed workout. Leave empty for today's next one.")
    var workout: WorkoutEntity?

    @Parameter(title: "Exercise", description: "Or one exercise, like a run.")
    var exercise: ExerciseEntity?

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$workout) \(\.$exercise)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        model.route = .tab(.train)
        if let active = model.data.activeSession { return answer("\(active.title) is already recording.") }
        let day = DayKey.today()
        var part: DayPart?
        if let content = workout?.part {
            part = model.data.parts(on: day).first { $0.content == content }
            if part == nil { SiriModel.change(model) { part = $0.add(DayPart(content), on: day) } }
        } else if let exercise {
            part = model.data.parts(on: day).first { model.data.items(in: $0).contains { $0.exerciseID == exercise.id } }
            if part == nil {
                let item = model.plannedDefaults(for: exercise.id)
                SiriModel.change(model) { part = $0.add(item, on: day) }
            }
        } else {
            part = model.data.partToStart(on: day)
        }
        guard let part else {
            throw SiriError(message: model.data.parts(on: day).isEmpty
                ? "Nothing is planned today. Say which workout or exercise to start."
                : "Everything planned for today is done.")
        }
        let title = model.data.title(of: part, catalog: model.catalog)
        SiriModel.change(model) { _ = $0.startSession(day: day, partID: part.id, title: title) }
        return answer("Started \(title).")
    }
}

struct PauseWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Pause Workout" }
    static var description: IntentDescription { IntentDescription("Pauses the workout that is recording.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let active = model.data.activeSession else { throw SiriError(message: "No workout is recording.") }
        guard !active.isPaused else { return answer("\(active.title) is already paused.") }
        SiriModel.change(model) { $0.togglePause(active.id) }
        return answer("Paused \(active.title).")
    }
}

struct ResumeWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Resume Workout" }
    static var description: IntentDescription { IntentDescription("Resumes the paused workout.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let active = model.data.activeSession else { throw SiriError(message: "No workout is recording.") }
        guard active.isPaused else { return answer("\(active.title) is already running.") }
        SiriModel.change(model) { $0.togglePause(active.id) }
        return answer("Resumed \(active.title).")
    }
}

struct EndWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "End Workout" }
    static var description: IntentDescription { IntentDescription("Ends and saves the workout that is recording, to Accrue and Apple Health.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let active = model.data.activeSession else { throw SiriError(message: "No workout is recording.") }
        model.endWorkout(active.id)
        model.saveNow()
        let minutes = Int((active.activeSeconds(at: Date()) / 60).rounded())
        let sets = model.data.sets(in: active.id).filter { !$0.isWarmup }.count
        var text = "Saved \(active.title), \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        if sets > 0 { text += " and \(sets) \(sets == 1 ? "set" : "sets")" }
        return answer(text + ".")
    }
}

// MARK: Logging

struct LogWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Log Workout" }
    static var description: IntentDescription {
        IntentDescription("Logs what you did, in your own words: \"bench 155 for 5\", \"pulls 100, six by ten\", \"ran 5k in 28:30\", \"plank 45 seconds\".")
    }

    @Parameter(title: "What you did", requestValueDialog: "What did you do?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let entry = QuickLog.parse(text) else {
            throw SiriError(message: "I couldn't read that. Try \"bench 155 for 5\" or \"ran 5k in 28:30\".")
        }
        let logger = QuickLogger(catalog: model.catalog, day: .today())
        guard let exercise = logger.exercise(named: entry.name, in: model.data) else {
            throw SiriError(message: "I couldn't find \"\(entry.name)\" in your exercises.")
        }
        return answer(logEntry(entry, exercise, model: model, logger: logger))
    }
}

struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource { "Log Sets" }
    static var description: IntentDescription { IntentDescription("Logs sets of an exercise with weight and reps, a hold, or a time and distance.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Weight")
    var weight: Measurement<UnitMass>?

    @Parameter(title: "Reps")
    var reps: Int?

    @Parameter(title: "Sets", default: 1)
    var sets: Int

    @Parameter(title: "Time", description: "A hold, or a cardio session's length.")
    var time: Measurement<UnitDuration>?

    @Parameter(title: "Distance")
    var distance: Measurement<UnitLength>?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$sets) sets of \(\.$exercise)") {
            \.$weight
            \.$reps
            \.$time
            \.$distance
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let found = model.exercise(exercise.id) else { throw SiriError(message: "That exercise isn't in Accrue.") }
        let unit = model.weightUnit
        let seconds = time.map { Int($0.converted(to: .seconds).value.rounded()) }
        let entry = QuickLog(name: exercise.name, weight: weight.map { unit.fromKg($0.converted(to: .kilograms).value) },
                             unit: unit, reps: reps, sets: max(1, sets), holdSeconds: seconds,
                             meters: distance?.converted(to: .meters).value, seconds: seconds)
        return answer(logEntry(entry, found, model: model, logger: QuickLogger(catalog: model.catalog, day: .today())))
    }
}

/// Logs the sets, saves, and says what was logged and what is next.
@MainActor
private func logEntry(_ entry: QuickLog, _ exercise: Exercise, model: AppModel, logger: QuickLogger) -> String {
    let unit = model.weightUnit
    var logged: [LoggedSet] = []
    SiriModel.change(model) { logged = logger.log(entry, exercise: exercise, unit: unit, into: &$0) }
    var text = logger.confirmation(logged, exercise: exercise, unit: unit)
    if let next = logger.nextUp(after: exercise.id, in: model.data, unit: unit) { text += " " + next }
    return text
}

struct UndoLastSetIntent: AppIntent {
    static var title: LocalizedStringResource { "Undo Last Set" }
    static var description: IntentDescription { IntentDescription("Deletes the set you logged last.") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        var removed: LoggedSet?
        SiriModel.change(model) { removed = $0.undoLastSet() }
        guard let removed else { throw SiriError(message: "There's nothing to undo.") }
        return answer("Deleted your last \(model.name(of: removed.exerciseID).lowercased()) set.")
    }
}

// MARK: Plans

struct AddExerciseIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Exercise to a Day" }
    static var description: IntentDescription { IntentDescription("Adds an exercise to a day's plan, for that day only or every week.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Day", description: "Leave empty for today.")
    var date: Date?

    @Parameter(title: "Change", default: .thisDayOnly)
    var scope: ScopeChoice

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$exercise) to \(\.$date), \(\.$scope)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        let day = SiriModel.day(date)
        let item = model.plannedDefaults(for: exercise.id)
        SiriModel.change(model) { $0.add(item, on: day, scope: scope.scope) }
        let when = SiriModel.assistant(model).dayName(day)
        return answer("Added \(exercise.name.lowercased()) to \(scope == .everyWeek ? "every \(day.weekday().name)" : when).")
    }
}

struct SwapExerciseIntent: AppIntent {
    static var title: LocalizedStringResource { "Swap Exercise" }
    static var description: IntentDescription { IntentDescription("Replaces an exercise on a day's plan with another, keeping its sets and reps.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Replacement")
    var replacement: ExerciseEntity

    @Parameter(title: "Day", description: "Leave empty for today.")
    var date: Date?

    @Parameter(title: "Change", default: .thisDayOnly)
    var scope: ScopeChoice

    static var parameterSummary: some ParameterSummary { Summary("Swap \(\.$exercise) for \(\.$replacement) on \(\.$date), \(\.$scope)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        let day = SiriModel.day(date)
        var result: AccrueData.SwapResult?
        SiriModel.change(model) { result = $0.swap(exercise.id, for: replacement.id, on: day, scope: scope.scope) }
        switch result {
        case .preset(let name)?:
            return answer("Swapped \(exercise.name.lowercased()) for \(replacement.name.lowercased()) in your \(name) preset, so it changes every day you do \(name).")
        case .day?:
            return answer("Swapped \(exercise.name.lowercased()) for \(replacement.name.lowercased()).")
        case nil:
            throw SiriError(message: "\(exercise.name) isn't on that day's plan.")
        }
    }
}

struct RemoveExerciseIntent: AppIntent {
    static var title: LocalizedStringResource { "Remove Exercise from a Day" }
    static var description: IntentDescription { IntentDescription("Takes an exercise off a day's plan.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Day", description: "Leave empty for today.")
    var date: Date?

    @Parameter(title: "Change", default: .thisDayOnly)
    var scope: ScopeChoice

    static var parameterSummary: some ParameterSummary { Summary("Remove \(\.$exercise) from \(\.$date), \(\.$scope)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        var result: AccrueData.SwapResult?
        SiriModel.change(model) { result = $0.remove(exercise.id, from: SiriModel.day(date), scope: scope.scope) }
        switch result {
        case .preset(let name)?: return answer("Removed \(exercise.name.lowercased()) from your \(name) preset.")
        case .day?: return answer("Removed \(exercise.name.lowercased()).")
        case nil: throw SiriError(message: "\(exercise.name) isn't on that day's plan.")
        }
    }
}

struct ScheduleWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Schedule Workout" }
    static var description: IntentDescription { IntentDescription("Puts a workout on a weekday of your weekly routine, or takes it off.") }

    @Parameter(title: "Workout")
    var workout: WorkoutEntity

    @Parameter(title: "Weekday")
    var weekday: WeekdayChoice

    @Parameter(title: "On the routine", default: true)
    var on: Bool

    static var parameterSummary: some ParameterSummary {
        When(\.$on, .equalTo, true) {
            Summary("Put \(\.$workout) on \(\.$weekday)") { \.$on }
        } otherwise: {
            Summary("Take \(\.$workout) off \(\.$weekday)") { \.$on }
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        guard let content = workout.part else { throw SiriError(message: "That workout isn't in Accrue.") }
        let day = weekday.weekday
        SiriModel.change(model) { data in
            switch content {
            case .preset(let id):
                data.schedule(id, on: day, on)
            default:
                var parts = data.routine[day]
                parts.removeAll { $0.content == content }
                if on { parts.append(DayPart(content)) }
                data.routine[day] = parts
            }
        }
        return answer(on ? "\(workout.name) is on every \(day.name) now." : "Took \(workout.name) off \(day.name)s.")
    }
}

struct FavoriteExerciseIntent: AppIntent {
    static var title: LocalizedStringResource { "Favorite Exercise" }
    static var description: IntentDescription { IntentDescription("Adds an exercise to your favorites, or removes it.") }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    @Parameter(title: "Favorite", default: true)
    var favorite: Bool

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$exercise) favorite to \(\.$favorite)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await SiriModel.ready()
        if model.data.isFavorite(exercise.id) != favorite {
            SiriModel.change(model) { $0.toggleFavorite(exercise.id) }
        }
        return answer(favorite ? "\(exercise.name) is in your favorites." : "Removed \(exercise.name) from your favorites.")
    }
}

// MARK: Settings

struct SetWeightUnitIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Weight Unit" }

    @Parameter(title: "Unit")
    var unit: UnitChoice

    static var parameterSummary: some ParameterSummary { Summary("Show weights in \(\.$unit)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        UserDefaults.standard.set(unit.rawValue, forKey: SettingsKey.weightUnit)
        return answer("Weights are in \(unit == .kg ? "kilograms" : "pounds") now.")
    }
}

struct SetBodyWeightIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Body Weight" }
    static var description: IntentDescription { IntentDescription("Sets the body weight Accrue uses to estimate calories without Apple Watch.") }

    @Parameter(title: "Body weight")
    var weight: Measurement<UnitMass>

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let kg = weight.converted(to: .kilograms).value
        guard (30...300).contains(kg) else { throw SiriError(message: "That body weight looks wrong.") }
        UserDefaults.standard.set(kg, forKey: SettingsKey.bodyWeightKg)
        let unit = AppModel.shared.weightUnit
        return answer("Body weight set to \(unit.format(kg: kg)) \(unit.label).")
    }
}

struct SetMaxHeartRateIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Max Heart Rate" }
    static var description: IntentDescription { IntentDescription("Sets the maximum heart rate your zones are based on.") }

    @Parameter(title: "Max heart rate", inclusiveRange: (120, 220))
    var bpm: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        UserDefaults.standard.set(bpm, forKey: SettingsKey.maxHeartRate)
        return answer("Max heart rate set to \(bpm).")
    }
}

struct SetThemeIntent: AppIntent {
    static var title: LocalizedStringResource { "Set Theme" }

    @Parameter(title: "Theme")
    var theme: AppearanceChoice

    static var parameterSummary: some ParameterSummary { Summary("Use the \(\.$theme) theme") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        UserDefaults.standard.set(theme.rawValue, forKey: SettingsKey.appearance)
        return answer("Theme changed.")
    }
}

// MARK: Opening the app

struct OpenScreenIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Accrue Screen" }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Screen")
    var screen: TabChoice

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$screen)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.route = .tab(screen.tab)
        return .result()
    }
}

struct ShowHowToIntent: AppIntent {
    static var title: LocalizedStringResource { "Show How To" }
    static var description: IntentDescription { IntentDescription("Opens the step-by-step how-to for an exercise, with its demo.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Exercise")
    var exercise: ExerciseEntity

    static var parameterSummary: some ParameterSummary { Summary("Show how to do \(\.$exercise)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = await SiriModel.ready()
        model.route = .howTo(exercise.id)
        return .result()
    }
}

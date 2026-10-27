import AppIntents

/// The phrases Siri knows without any setup (an app can offer ten). Every other action is in
/// the Shortcuts app, and Siri with Apple Intelligence can use all of them.
struct AccrueShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .lime }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DayPlanIntent(), phrases: [
            "What's my workout today in \(.applicationName)",
            "What's my \(.applicationName) plan",
            "What's on my \(.applicationName) plan today",
        ], shortTitle: "Today's Plan", systemImageName: "calendar")
        AppShortcut(intent: StartWorkoutIntent(), phrases: [
            "Start my workout in \(.applicationName)",
            "Start my \(.applicationName) workout",
            "Start \(\.$workout) in \(.applicationName)",
            "Start a \(\.$exercise) in \(.applicationName)",
        ], shortTitle: "Start Workout", systemImageName: "play.fill")
        AppShortcut(intent: LogWorkoutIntent(), phrases: [
            "Log a set in \(.applicationName)",
            "Log a workout in \(.applicationName)",
            "Log in \(.applicationName)",
        ], shortTitle: "Log Sets", systemImageName: "plus.circle")
        AppShortcut(intent: WhatsNextIntent(), phrases: [
            "What's next in \(.applicationName)",
            "What's my next exercise in \(.applicationName)",
        ], shortTitle: "What's Next", systemImageName: "forward.fill")
        AppShortcut(intent: PauseWorkoutIntent(), phrases: [
            "Pause my \(.applicationName) workout",
            "Pause \(.applicationName)",
        ], shortTitle: "Pause", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeWorkoutIntent(), phrases: [
            "Resume my \(.applicationName) workout",
            "Resume \(.applicationName)",
        ], shortTitle: "Resume", systemImageName: "play.circle")
        AppShortcut(intent: EndWorkoutIntent(), phrases: [
            "End my \(.applicationName) workout",
            "Finish my \(.applicationName) workout",
        ], shortTitle: "End Workout", systemImageName: "stop.fill")
        AppShortcut(intent: UndoLastSetIntent(), phrases: [
            "Undo my last set in \(.applicationName)",
            "Delete my last set in \(.applicationName)",
        ], shortTitle: "Undo Last Set", systemImageName: "arrow.uturn.backward")
        AppShortcut(intent: ExerciseProgressIntent(), phrases: [
            "How's my \(\.$exercise) in \(.applicationName)",
            "Show my \(\.$exercise) progress in \(.applicationName)",
            "How am I doing in \(.applicationName)",
        ], shortTitle: "Exercise Progress", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: WeekSummaryIntent(), phrases: [
            "How's my week in \(.applicationName)",
            "How was my week in \(.applicationName)",
        ], shortTitle: "Week Summary", systemImageName: "chart.bar")
    }
}

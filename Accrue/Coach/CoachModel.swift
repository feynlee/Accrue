import AccrueKit
import Foundation
import Observation

/// The coach conversation. Plain workout words ("pulls 100, six by ten") are logged straight
/// away, offline; everything else goes to the coach's model.
@Observable
@MainActor
final class CoachModel {
    struct Message: Identifiable, Equatable {
        enum From { case me, coach }
        var id = UUID()
        var from: From
        var text: String
        /// Sets this message logged, so they can be undone.
        var logged: [UUID] = []
    }

    private(set) var messages: [Message] = []
    private(set) var thinking = false
    @ObservationIgnored private weak var model: AppModel?

    func attach(to model: AppModel) {
        self.model = model
    }

    /// Made-up conversation for screenshots (the ACoach board).
    func showDemo() {
        messages = [
            Message(from: .me, text: "What should I do if the pulldown machine is taken?"),
            Message(from: .coach, text: "Do pull-ups first, then come back to it. Same total sets, so your Pull volume stays the same."),
            Message(from: .me, text: "Pulls 100, six by ten."),
            Message(from: .coach, text: "Logged: cable pulldown, 100 lb, 6 × 10. Seated row is next at 90 lb."),
        ]
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model else { return }
        messages.append(Message(from: .me, text: text))
        if let entry = QuickLog.parse(text), let reply = log(entry, in: model) {
            messages.append(reply)
            return
        }
        messages.append(Message(from: .coach, text: "I can log workouts already, like \"bench 155 x 5 x 3\" or \"ran 5k in 28:30\". Questions, swaps and plans come next."))
    }

    func undo(_ message: Message) {
        guard let model, !message.logged.isEmpty else { return }
        model.update { data in message.logged.forEach { data.deleteSet($0) } }
        if let i = messages.firstIndex(where: { $0.id == message.id }) {
            messages[i].logged = []
            messages[i].text = "Undone. Nothing was logged."
        }
    }

    private func log(_ entry: QuickLog, in model: AppModel) -> Message? {
        let coach = CoachLog(catalog: model.catalog, day: DayKey.today())
        guard let exercise = coach.exercise(named: entry.name, in: model.data) else { return nil }
        let unit = model.weightUnit
        var sets: [LoggedSet] = []
        model.update { data in sets = coach.log(entry, exercise: exercise, unit: unit, into: &data) }
        var text = coach.confirmation(sets, exercise: exercise, unit: unit)
        if let next = coach.nextUp(after: exercise.id, in: model.data, unit: unit) { text += " " + next }
        return Message(from: .coach, text: text, logged: sets.map(\.id))
    }
}

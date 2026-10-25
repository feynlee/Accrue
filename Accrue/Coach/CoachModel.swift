import AccrueKit
import Foundation
import Observation

/// The coach conversation. Warning signs get a fixed "see a professional" reply before anything
/// else. Plain workout words ("pulls 100, six by ten") are logged straight away, offline. Form
/// questions are answered from the exercise's how-to notes, and training and health questions
/// from sourced guidelines, with the source shown.
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
        /// The exercise whose how-to this answer comes from, for its "Open How to" button.
        var howTo: String?
        /// Health or safety information: shown with a "check with a professional" tag.
        var health = false
        /// Where the statements come from.
        var sources: [String] = []
    }

    private(set) var messages: [Message] = []
    private(set) var thinking = false
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let knowledge = (try? CoachKnowledge.bundled()) ?? .empty

    func attach(to model: AppModel) {
        self.model = model
    }

    /// Made-up conversation for screenshots (the ACoach board). `coachhealth` and `coachsafety`
    /// ask real questions once the catalog has loaded.
    func showDemo(_ screen: String) {
        let questions = [
            "coachhealth": ["How do I do a push-up properly?", "How long should I rest between sets?"],
            "coachsafety": ["I get a sharp pain in my shoulder on bench press"],
        ][screen]
        if let questions {
            Task {
                while model?.catalogLoaded != true { try? await Task.sleep(for: .milliseconds(100)) }
                questions.forEach(send)
            }
            return
        }
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
        messages.append(reply(to: text, in: model))
    }

    private func reply(to text: String, in model: AppModel) -> Message {
        if let warning = SafetyCheck.check(text) {
            // For a condition or pregnancy, add what the guidelines say about checking first.
            let facts = warning.level == .medical
                ? knowledge.guidelines(for: text, limit: 1).filter { ["pregnancy", "preparticipation"].contains($0.id) } : []
            let body = ([warning.reply] + facts.map(\.text)).joined(separator: "\n\n")
            return Message(from: .coach, text: body, health: true, sources: facts.map(\.source))
        }
        if let entry = QuickLog.parse(text), let reply = log(entry, in: model) {
            return reply
        }
        let coach = CoachLog(catalog: model.catalog, day: DayKey.today())
        if let form = coach.formAnswer(to: text, in: model.data) {
            return Message(from: .coach, text: form.text, howTo: form.exerciseID)
        }
        let facts = knowledge.guidelines(for: text)
        if !facts.isEmpty {
            return Message(from: .coach, text: CoachKnowledge.answer(facts), health: true,
                           sources: Array(Set(facts.map(\.source))).sorted())
        }
        return Message(from: .coach, text: "I can log workouts (\"bench 155 x 5 x 3\"), explain form (\"how do I squat?\") and answer training questions from published guidelines (\"how long should I rest?\"). Swaps and plans come next.")
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

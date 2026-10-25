import Foundation
import Testing
@testable import AccrueKit

struct KnowledgeTests {
    @Test func everyGuidelineHasASource() throws {
        let knowledge = try CoachKnowledge.bundled()
        #expect(knowledge.guidelines.count >= 20)
        #expect(Set(knowledge.guidelines.map(\.id)).count == knowledge.guidelines.count)
        for fact in knowledge.guidelines {
            #expect(!fact.text.isEmpty && !fact.source.isEmpty && !fact.tags.isEmpty, "\(fact.id)")
        }
    }

    @Test func findsTheGuidelineAQuestionIsAbout() throws {
        let knowledge = try CoachKnowledge.bundled()
        func first(_ q: String) -> String? { knowledge.guidelines(for: q).first?.id }
        #expect(first("How much cardio should I do a week?") == "who-aerobic")
        #expect(first("How long should I rest between sets?")?.hasSuffix("rest") == true)
        #expect(first("How much protein do I need?") == "protein")
        #expect(first("Should I stretch before lifting?") == "behm-stretching")
        #expect(first("How do I work out my max heart rate?") == "tanaka-hrmax")
        #expect(first("Is it normal to be sore the next day?") == "doms")
        #expect(first("How many sets a week for muscle growth?") == "schoenfeld-volume")
        #expect(knowledge.guidelines(for: "Pulls 100, six by ten").isEmpty)
        #expect(knowledge.guidelines(for: "thanks!").isEmpty)
    }

    @Test func answersFormQuestionsFromTheHowToNotes() throws {
        let catalog = try Catalog.bundled()
        let data = AccrueData.starter()
        let coach = CoachLog(catalog: catalog, day: DayKey(year: 2026, month: 10, day: 19))
        let pushUp = try #require(coach.formAnswer(to: "How do I do a push-up properly?", in: data))
        #expect(pushUp.exerciseID == StarterIDs.pushUp)
        #expect(pushUp.text.contains("• Set up:"))
        #expect(pushUp.text.contains("How to"))
        #expect(coach.formAnswer(to: "squat form tips", in: data) != nil)
        #expect(coach.formAnswer(to: "Pulls 100, six by ten", in: data) == nil)
        #expect(coach.formAnswer(to: "How do I sleep better?", in: data) == nil)
    }

    @Test func sendsWarningSignsToAProfessional() {
        #expect(SafetyCheck.check("I get chest pain when I run")?.level == .stopNow)
        #expect(SafetyCheck.check("felt dizzy and lightheaded after squats")?.level == .stopNow)
        #expect(SafetyCheck.check("sharp pain in my shoulder on bench")?.level == .injury)
        #expect(SafetyCheck.check("my fingers go numb on rows")?.level == .injury)
        #expect(SafetyCheck.check("I'm pregnant, can I still deadlift?")?.level == .medical)
        #expect(SafetyCheck.check("what creatine dose should I take")?.level == .dose)
        // Exercise words that look like warnings are not.
        #expect(SafetyCheck.check("chest press 3x10") == nil)
        #expect(SafetyCheck.check("medicine ball slams 3x12") == nil)
        #expect(SafetyCheck.check("rowing at 24 stroke rate") == nil)
        #expect(SafetyCheck.check("I pulled a 405 deadlift") == nil)
    }
}

import Foundation
import Testing
@testable import AccrueKit

@Suite struct CatalogTests {
    static let catalog: Catalog = {
        do { return try Catalog.bundled() } catch { fatalError("catalog did not load: \(error)") }
    }()

    @Test func loadsEveryFamilyAndExercise() {
        let c = Self.catalog
        #expect(c.families.count == 104)
        #expect(c.exercises.count > 5_600)
        #expect(c.muscles["chest"]?.label == "Chest")
    }

    @Test func everyExerciseFamilyExists() {
        let c = Self.catalog
        let missing = c.exercises.filter { ex in ex.familyID.map { c.families[$0] == nil } ?? false }
        #expect(missing.isEmpty, "\(missing.prefix(5).map(\.id))")
    }

    @Test func everyMuscleIdIsKnown() {
        let c = Self.catalog
        for family in c.families.values {
            for id in family.muscles.primary + family.muscles.secondary {
                #expect(c.muscles[id] != nil, "\(family.id): \(id)")
            }
        }
    }

    @Test func starterExercisesExist() {
        for id in StarterIDs.all {
            #expect(Self.catalog.exercise(id) != nil, "\(id)")
        }
    }

    @Test func trackingFollowsFamilyAndWeightedVersions() throws {
        let c = Self.catalog
        #expect(c.tracking(for: try #require(c.exercise(StarterIDs.benchPress))) == .weightReps)
        #expect(c.tracking(for: try #require(c.exercise(StarterIDs.pullUp))) == .reps)
        #expect(c.tracking(for: try #require(c.exercise("0841"))) == .weightReps) // weighted pull-up
        #expect(c.tracking(for: try #require(c.exercise(StarterIDs.plank))) == .hold)
        #expect(c.tracking(for: try #require(c.exercise(StarterIDs.run))) == .distanceTimeHR)
    }

    @Test func searchRanksExactNamesFirst() {
        let hits = Self.catalog.search("pull-up")
        #expect(hits.first?.name == "pull-up")
        #expect(Self.catalog.search("pullup").contains { $0.name == "pull-up" })
        #expect(Self.catalog.search("bench press barbell").first?.id == StarterIDs.benchPress)
    }

    @Test func searchSkipsCameraAngleDuplicates() {
        let hits = Self.catalog.search("barbell deadlift", limit: 200)
        #expect(!hits.contains { $0.name.contains("pov") || $0.name.contains("view") })
    }

    @Test func cardioSessionsAreExercises() throws {
        let hike = try #require(Self.catalog.exercise("s:hike"))
        #expect(hike.displayName == "Hike")
        #expect(Self.catalog.tracking(for: hike) == .distanceTimeHR)
        #expect(Self.catalog.region(for: hike) == "cardio")
    }

    @Test func subtypesMatchByName() throws {
        let c = Self.catalog
        let pushUp = try #require(c.families["push-up"])
        #expect(pushUp.subtype(matching: "knee push-up")?.id == "knee")
        #expect(pushUp.subtype(matching: "push-up") == nil)
    }

    @Test func keyframesKeepAnglesAndScapula() throws {
        let pushUp = try #require(Self.catalog.families["push-up"])
        let first = try #require(pushUp.motion.keyframes.first)
        #expect(first.phase != nil)
        #expect(first.pose.angles["t"] == nil)
        #expect(first.pose.angles["elbowFlex"] != nil)
        #expect(pushUp.motion.keyframes.contains { $0.pose.scapula != nil })
    }
}

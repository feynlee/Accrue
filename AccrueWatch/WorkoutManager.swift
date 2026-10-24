import AccrueKit
import Foundation
@preconcurrency import HealthKit
import Observation
import WatchKit

/// Runs the workout on Apple Watch: the HealthKit session that measures heart rate, calories and
/// distance and saves the workout to Health. It mirrors to the phone, which shows it on the run
/// or lifting card and can pause or end it.
@Observable
@MainActor
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    /// What the summary screen shows once a workout ends.
    struct Summary {
        var title: String
        var activity: HKWorkoutActivityType
        var elapsed: TimeInterval
        var activeKcal: Double
        var totalKcal: Double
        var meters: Double
        var averageHeartRate: Int?
    }

    private(set) var state: HKWorkoutSessionState = .notStarted
    private(set) var activity: HKWorkoutActivityType = .traditionalStrengthTraining
    private(set) var startDate: Date?
    private(set) var heartRate: Int?
    private(set) var averageHeartRate: Int?
    private(set) var activeKcal: Double = 0
    private(set) var basalKcal: Double = 0
    private(set) var meters: Double = 0
    /// Seconds spent in each zone, Z1 first.
    private(set) var zoneSeconds: [TimeInterval] = Array(repeating: 0, count: 5)
    private(set) var setup = WorkoutLink.Setup(title: "Workout", maxHR: HeartZones.defaultMax, targetZone: nil)
    private(set) var summary: Summary?
    private(set) var error: String?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var lastZone: Int?
    @ObservationIgnored private var lastReading: (zone: Int, at: Date)?
    @ObservationIgnored private var demoElapsed: TimeInterval?

    var isRunning: Bool { state == .running || state == .paused }
    var totalKcal: Double { activeKcal + basalKcal }

    /// Time so far, pauses left out.
    func elapsed(at date: Date) -> TimeInterval { demoElapsed ?? builder?.elapsedTime(at: date) ?? 0 }
    var zones: HeartZones { HeartZones(maxHR: setup.maxHR) }

    /// The phone asked for this workout (it calls `startWatchApp`).
    func start(_ configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        let energy: Set<HKQuantityType> = [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned)]
        let distances: Set<HKQuantityType> = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                                              HKQuantityType(.distanceSwimming)]
        do {
            try await store.requestAuthorization(toShare: energy.union(distances).union([HKQuantityType.workoutType()]),
                                                 read: energy.union(distances).union([HKQuantityType(.heartRate)]))
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            activity = configuration.activityType
            heartRate = nil
            averageHeartRate = nil
            activeKcal = 0
            basalKcal = 0
            meters = 0
            zoneSeconds = Array(repeating: 0, count: 5)
            lastReading = nil
            summary = nil
            let start = Date()
            startDate = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            try await session.startMirroringToCompanionDevice()
            error = nil
        } catch {
            self.error = "Couldn't start: \(error.localizedDescription)"
        }
    }

    /// A workout in progress for screenshots (`-demoWorkout run|strength|cycle`); nothing is measured or saved.
    func showDemo(_ kind: String, ended: Bool) {
        switch kind {
        case "strength":
            setup = WorkoutLink.Setup(title: "Push day", maxHR: 190, targetZone: nil)
            activity = .traditionalStrengthTraining
            heartRate = 112
            averageHeartRate = 104
            activeKcal = 186
            basalKcal = 61
            meters = 0
            demoElapsed = 41 * 60 + 7.38
            zoneSeconds = [900, 1080, 420, 60, 0]
        case "cycle":
            setup = WorkoutLink.Setup(title: "Outdoor ride", maxHR: 190, targetZone: 2)
            activity = .cycling
            heartRate = 131
            averageHeartRate = 127
            activeKcal = 342
            basalKcal = 48
            meters = 14_830
            demoElapsed = 32 * 60 + 44.12
            zoneSeconds = [120, 1500, 340, 0, 0]
        default:
            setup = WorkoutLink.Setup(title: "Outdoor run", maxHR: 190, targetZone: 2)
            activity = .running
            heartRate = 128
            averageHeartRate = 126
            activeKcal = 214
            basalKcal = 27
            meters = 3420
            demoElapsed = 18 * 60 + 13.42
            zoneSeconds = [95, 812, 186, 0, 0]
        }
        if ended {
            summary = currentSummary()
        } else {
            state = .running
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() { session?.end() }
    func dismissSummary() { summary = nil }

    private func currentSummary() -> Summary {
        Summary(title: setup.title, activity: activity, elapsed: elapsed(at: Date()), activeKcal: activeKcal,
                totalKcal: totalKcal, meters: meters, averageHeartRate: averageHeartRate)
    }

    private func send(_ message: WorkoutLink.Message) {
        guard let session else { return }
        let data = WorkoutLink.encode(message)
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    private func received(_ data: [Data]) {
        for item in data {
            switch WorkoutLink.decode(item) {
            case .setup(let setup)?: self.setup = setup
            case .command(.pause)?: pause()
            case .command(.resume)?: resume()
            case .command(.end)?: end()
            default: break
            }
        }
    }

    private func changed(to new: HKWorkoutSessionState, at date: Date) {
        state = new
        guard new == .ended, let builder else { return }
        summary = Summary(title: setup.title, activity: activity, elapsed: builder.elapsedTime(at: date),
                          activeKcal: activeKcal, totalKcal: totalKcal, meters: meters,
                          averageHeartRate: averageHeartRate)
        Task {
            try? await builder.endCollection(at: date)
            _ = try? await builder.finishWorkout()
            self.session = nil
            self.builder = nil
            self.state = .notStarted
            self.startDate = nil
        }
    }

    private func collected(_ reading: Collected) {
        if let bpm = reading.heartRate { heartRate = Int(bpm.rounded()) }
        if let average = reading.averageHeartRate { averageHeartRate = Int(average.rounded()) }
        if let kcal = reading.activeKcal { activeKcal = kcal }
        if let kcal = reading.basalKcal { basalKcal = kcal }
        if let distance = reading.meters { meters = distance }
        if let heartRate {
            let zone = zones.zone(for: heartRate)
            let now = Date()
            // Time in zone, as on the Heart Rate Zones page: each gap goes to the zone of the reading
            // before it, at most 15 s, and nothing while paused.
            if let last = lastReading, state == .running {
                zoneSeconds[last.zone - 1] += min(now.timeIntervalSince(last.at), 15)
            }
            lastReading = (zone, now)
            // A tap on the wrist when you drift out of the zone you're aiming for.
            if let target = setup.targetZone {
                if let lastZone, lastZone == target, zone != target {
                    WKInterfaceDevice.current().play(zone > target ? .directionDown : .directionUp)
                }
                lastZone = zone
            }
        }
        send(.reading(.init(heartRate: heartRate, activeKcal: activeKcal, meters: meters > 0 ? meters : nil, at: Date())))
    }
}

/// One round of numbers from the live builder.
private struct Collected: Sendable {
    var heartRate: Double?
    var averageHeartRate: Double?
    var activeKcal: Double?
    var basalKcal: Double?
    var meters: Double?
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.changed(to: toState, at: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let text = error.localizedDescription
        Task { @MainActor in self.error = text }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        let distance = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceSwimming)]
            .lazy.compactMap { workoutBuilder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }.first
        let reading = Collected(
            heartRate: heart?.mostRecentQuantity()?.doubleValue(for: bpmUnit),
            averageHeartRate: heart?.averageQuantity()?.doubleValue(for: bpmUnit),
            activeKcal: workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            basalKcal: workoutBuilder.statistics(for: HKQuantityType(.basalEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            meters: distance)
        Task { @MainActor in self.collected(reading) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

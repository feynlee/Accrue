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

    private(set) var state: HKWorkoutSessionState = .notStarted
    private(set) var startDate: Date?
    private(set) var heartRate: Int?
    private(set) var activeKcal: Double = 0
    private(set) var meters: Double = 0
    private(set) var setup = WorkoutLink.Setup(title: "Workout", maxHR: HeartZones.defaultMax, targetZone: nil)
    private(set) var error: String?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var lastZone: Int?

    var isRunning: Bool { state == .running || state == .paused }

    /// Time so far, pauses left out.
    func elapsed(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? 0 }
    var zones: HeartZones { HeartZones(maxHR: setup.maxHR) }

    /// The phone asked for this workout (it calls `startWatchApp`).
    func start(_ configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        do {
            try await store.requestAuthorization(toShare: [HKQuantityType.workoutType(),
                                                           HKQuantityType(.activeEnergyBurned),
                                                           HKQuantityType(.distanceWalkingRunning),
                                                           HKQuantityType(.distanceCycling)],
                                                 read: [HKQuantityType(.heartRate),
                                                        HKQuantityType(.activeEnergyBurned),
                                                        HKQuantityType(.distanceWalkingRunning),
                                                        HKQuantityType(.distanceCycling)])
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            heartRate = nil
            activeKcal = 0
            meters = 0
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

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() { session?.end() }

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
        Task {
            try? await builder.endCollection(at: date)
            _ = try? await builder.finishWorkout()
            self.session = nil
            self.builder = nil
            self.state = .notStarted
            self.startDate = nil
        }
    }

    private func collected(heartRate bpm: Double?, kcal: Double?, meters distance: Double?) {
        if let bpm { heartRate = Int(bpm.rounded()) }
        if let kcal { activeKcal = kcal }
        if let distance { meters = distance }
        // A tap on the wrist when you drift out of the zone you're aiming for.
        if let target = setup.targetZone, let heartRate {
            let zone = zones.zone(for: heartRate)
            if let lastZone, lastZone == target, zone != target {
                WKInterfaceDevice.current().play(zone > target ? .directionDown : .directionUp)
            }
            lastZone = zone
        }
        send(.reading(.init(heartRate: heartRate, activeKcal: activeKcal, meters: meters > 0 ? meters : nil, at: Date())))
    }
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
        let bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let distance = (workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))
            ?? workoutBuilder.statistics(for: HKQuantityType(.distanceCycling)))?
            .sumQuantity()?.doubleValue(for: .meter())
        Task { @MainActor in self.collected(heartRate: bpm, kcal: kcal, meters: distance) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

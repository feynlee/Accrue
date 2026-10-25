import AccrueKit
import Foundation
@preconcurrency import HealthKit
import Observation

/// Apple Health and the Accrue Watch app. Starting a workout on Train starts it on the watch,
/// which measures heart rate and calories, mirrors them here, and saves the workout to Health.
/// Without a watch, the phone saves the workout to Health itself when it ends.
@Observable
@MainActor
final class HealthService: NSObject {
    /// The workout the watch is running for us, if any.
    private(set) var linkedSessionID: UUID?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var mirrored: HKWorkoutSession?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var requestedFor: UUID?
    @ObservationIgnored private var lastPaused: Bool?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Listens for the watch's mirrored workouts. Called once at launch.
    func attach(to model: AppModel) {
        self.model = model
        guard Self.isAvailable else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            let box = Box(session)
            Task { @MainActor in self?.mirroringStarted(box.value) }
        }
    }

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
                                       HKQuantityType(.distanceWalkingRunning), HKQuantityType(.vo2Max),
                                       HKQuantityType(.bodyMass), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Following the workout on Train

    /// Called whenever the recording workout starts, pauses, resumes or ends.
    func sync(_ session: WorkoutSession?, configuration: HKWorkoutConfiguration?) {
        guard Self.isAvailable else { return }
        guard let session, session.isActive else {
            // Ended on the phone: end it on the watch too (the watch saves it to Health).
            if linkedSessionID != nil { send(.command(.end)) }
            linkedSessionID = nil
            requestedFor = nil
            lastPaused = nil
            mirrored = nil
            return
        }
        if requestedFor != session.id, let configuration {
            requestedFor = session.id
            Task {
                await requestAuthorization()
                // Opens the Accrue Watch app and starts the workout there; fails quietly with no watch.
                store.startWatchApp(with: configuration) { _, _ in }
            }
        }
        if linkedSessionID == session.id, lastPaused != session.isPaused {
            send(.command(session.isPaused ? .pause : .resume))
        }
        lastPaused = session.isPaused
    }

    private func mirroringStarted(_ session: HKWorkoutSession) {
        guard let model, let active = model.data.activeSession else {
            // Nothing recording on the phone any more: stop the watch.
            mirrored = session
            send(.command(.end))
            return
        }
        mirrored = session
        session.delegate = self
        linkedSessionID = active.id
        lastPaused = active.isPaused
        model.update { $0.updateSession(active.id) { $0.watchLinked = true } }
        send(.setup(model.watchSetup(for: active)))
    }

    private func send(_ message: WorkoutLink.Message) {
        guard let mirrored else { return }
        let data = WorkoutLink.encode(message)
        Task { try? await mirrored.sendToRemoteWorkoutSession(data: data) }
    }

    private func received(_ data: [Data]) {
        for item in data {
            if case .reading(let reading)? = WorkoutLink.decode(item) { model?.applyWatchReading(reading) }
        }
    }

    /// Paused, resumed or ended on the watch.
    private func remoteChanged(to state: HKWorkoutSessionState) {
        guard let model, let active = model.data.activeSession, active.id == linkedSessionID else { return }
        switch state {
        case .paused where !active.isPaused, .running where active.isPaused:
            lastPaused = !active.isPaused
            model.update { $0.togglePause(active.id) }
        case .ended, .stopped:
            linkedSessionID = nil
            model.endWorkout(active.id)
        default:
            break
        }
    }

    // MARK: Saving without a watch

    /// Saves a finished workout to Health from the phone, when no watch recorded it.
    func save(_ session: WorkoutSession, configuration: HKWorkoutConfiguration) {
        guard Self.isAvailable, session.watchLinked != true, let end = session.endedAt else { return }
        let meters = session.distanceMeters ?? 0
        let distanceType = configuration.activityType == .cycling ? HKQuantityType(.distanceCycling) : HKQuantityType(.distanceWalkingRunning)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        Task {
            await requestAuthorization()
            do {
                try await builder.beginCollection(at: session.startedAt)
                var samples: [HKSample] = []
                if meters > 0 {
                    samples.append(HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                                                    start: session.startedAt, end: end))
                }
                if let kcal = session.activeKcal, kcal > 0 {
                    samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                                    start: session.startedAt, end: end))
                }
                if !samples.isEmpty { try await builder.addSamples(samples) }
                try await builder.endCollection(at: end)
                _ = try await builder.finishWorkout()
            } catch {
                // Health declined (no permission): the workout stays in Accrue.
            }
        }
    }

    /// Health's activity for a Train part: the cardio exercise's own, HIIT for a timed exercise,
    /// strength training for lifting.
    static func configuration(activity: String?, outdoor: Bool?, timed: Bool) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = timed ? .highIntensityIntervalTraining
            : activity.flatMap { activityTypes[$0] } ?? .traditionalStrengthTraining
        configuration.locationType = outdoor == true ? .outdoor : outdoor == false || activity == nil ? .indoor : .unknown
        if configuration.activityType == .swimming {
            configuration.swimmingLocationType = outdoor == true ? .openWater : .pool
            configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
        }
        return configuration
    }

    private static let activityTypes: [String: HKWorkoutActivityType] = [
        "running": .running, "walking": .walking, "hiking": .hiking, "cycling": .cycling,
        "crossCountrySkiing": .crossCountrySkiing, "snowSports": .snowSports, "rowing": .rowing,
        "paddleSports": .paddleSports, "swimming": .swimming, "waterFitness": .waterFitness,
        "stairClimbing": .stairClimbing, "stairs": .stairs, "climbing": .climbing, "elliptical": .elliptical,
        "highIntensityIntervalTraining": .highIntensityIntervalTraining, "jumpRope": .jumpRope,
        "crossTraining": .crossTraining, "boxing": .boxing, "kickboxing": .kickboxing, "cardioDance": .cardioDance,
        "socialDance": .socialDance, "stepTraining": .stepTraining, "skatingSports": .skatingSports,
        "tennis": .tennis, "badminton": .badminton, "squash": .squash, "pickleball": .pickleball,
        "basketball": .basketball, "soccer": .soccer,
    ]
}

extension HealthService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.remoteChanged(to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data) }
    }
}

/// Carries a HealthKit object across to the main actor.
private struct Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

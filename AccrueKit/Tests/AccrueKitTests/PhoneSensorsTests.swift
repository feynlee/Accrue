import Testing
@testable import AccrueKit

struct PhoneSensorsTests {
    @Test func readsOneAndTwoByteHeartRates() {
        #expect(HeartRateMeasurement.bpm(from: [0x00, 72]) == 72)
        #expect(HeartRateMeasurement.bpm(from: [0x16, 140, 0x40, 0x03]) == 140)  // contact + RR bits
        #expect(HeartRateMeasurement.bpm(from: [0x01, 0x2C, 0x01]) == 300)
        #expect(HeartRateMeasurement.bpm(from: [0x00, 0]) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x01, 72]) == nil)
        #expect(HeartRateMeasurement.bpm(from: []) == nil)
    }

    @Test func estimatesActiveCalories() {
        // 30 min at 10 km/h (167 m/min): ACSM gives ~10.5 METs, so ~356 kcal for 75 kg.
        let run = CalorieEstimate.activeKcal(activity: "running", timed: false, seconds: 1800, meters: 5000, bodyKg: 75)
        #expect(run > 330 && run < 380)
        // A treadmill run with no distance yet falls back to 9.8 METs.
        let treadmill = CalorieEstimate.activeKcal(activity: "running", timed: false, seconds: 3600, meters: nil, bodyKg: 70)
        #expect(abs(treadmill - 8.8 * 70) < 0.001)
        // An hour of lifting: 4 active METs.
        #expect(abs(CalorieEstimate.activeKcal(activity: nil, timed: false, seconds: 3600, meters: nil, bodyKg: 80) - 320) < 0.001)
        #expect(CalorieEstimate.activeKcal(activity: "running", timed: false, seconds: 0, meters: nil, bodyKg: 80) == 0)
        // A timed circuit counts as HIIT.
        #expect(abs(CalorieEstimate.activeKcal(activity: nil, timed: true, seconds: 420, meters: nil, bodyKg: 75) - 7 * 75 * 420 / 3600) < 0.001)
    }
}

import AccrueKit
@preconcurrency import HealthKit
import SwiftUI
import WatchKit

/// The workout on the wrist, laid out like Apple's Workout app: controls to the left, the metrics
/// for this kind of workout in the middle (Heart Rate Zones one scroll down), Now Playing to the
/// right, and a summary when it ends. Workouts start from Train on the phone.
struct WorkoutView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var page = UserDefaults.standard.string(forKey: "demoPage") == "controls" ? "controls" : "metrics"
    @State private var metricsPage = UserDefaults.standard.string(forKey: "demoPage") == "zones" ? "zones" : "metrics"

    static let lime = Color(red: 0xC6 / 255, green: 0xF4 / 255, blue: 0x32 / 255)
    static let timeYellow = Color(red: 1, green: 0.9, blue: 0)
    static let zoneColors: [Color] = [
        Color(red: 0x5B / 255, green: 0xC8 / 255, blue: 1), Color(red: 0x5B / 255, green: 0xC8 / 255, blue: 1),
        Color(red: 1, green: 0xB0 / 255, blue: 0x20 / 255),
        Color(red: 1, green: 0x5A / 255, blue: 0x5F / 255), Color(red: 1, green: 0x5A / 255, blue: 0x5F / 255),
    ]

    var body: some View {
        if workout.isRunning {
            TabView(selection: $page) {
                WorkoutControls().tag("controls")
                TabView(selection: $metricsPage) {
                    WorkoutMetrics().tag("metrics")
                    HeartRateZones().tag("zones")
                }
                .tabViewStyle(.verticalPage)
                .tag("metrics")
                NowPlayingView().tag("nowPlaying")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: workout.state) { _, state in
                // Back to the numbers after Pause or Resume, as the Workout app does.
                if state == .running || state == .paused { withAnimation { page = "metrics" } }
            }
        } else if let summary = workout.summary {
            WorkoutSummary(summary: summary)
        } else {
            VStack(spacing: 8) {
                Text("ACCRUE")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.lime)
                Text(workout.error ?? "Start a workout from Train on your iPhone. It runs here and saves to Health.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

// MARK: - What each kind of workout shows

/// The metrics the Workout app shows by default for each kind of workout.
enum WorkoutMetric: Hashable {
    case activeKcal, totalKcal, heartRate, distance, averagePace, averageSpeed

    static func metrics(for activity: HKWorkoutActivityType) -> [WorkoutMetric] {
        switch activity {
        case .running, .walking, .hiking, .crossCountrySkiing:
            [.activeKcal, .heartRate, .distance, .averagePace]
        case .cycling, .handCycling, .wheelchairRunPace, .wheelchairWalkPace, .skatingSports:
            [.activeKcal, .heartRate, .distance, .averageSpeed]
        case .swimming, .paddleSports:
            [.activeKcal, .distance, .heartRate]
        default:
            [.activeKcal, .totalKcal, .heartRate]
        }
    }
}

extension HKWorkoutActivityType {
    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairs: "figure.stairs"
        case .stairClimbing: "figure.stair.stepper"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "figure.strengthtraining.traditional"
        case .jumpRope: "figure.jumprope"
        case .crossTraining: "figure.cross.training"
        default: "figure.mixed.cardio"
        }
    }
}

/// Miles where the watch is set to US units, kilometres elsewhere; pool swims in yards or metres.
struct DistanceFormat {
    var activity: HKWorkoutActivityType
    private var us: Bool { Locale.current.measurementSystem == .us }

    var unit: String {
        activity == .swimming ? (us ? "YD" : "M") : (us ? "MI" : "KM")
    }

    func value(_ meters: Double) -> String {
        if activity == .swimming { return "\(Int((us ? meters / 0.9144 : meters).rounded()))" }
        return String(format: "%.2f", meters / (us ? 1609.344 : 1000))
    }

    /// 8'31" per mile or kilometre.
    func pace(seconds: TimeInterval, meters: Double) -> String {
        guard meters > 20 else { return "--'--\"" }
        let perUnit = Int((seconds / (meters / (us ? 1609.344 : 1000))).rounded())
        return perUnit >= 60 * 60 ? "--'--\"" : String(format: "%d'%02d\"", perUnit / 60, perUnit % 60)
    }

    func speed(seconds: TimeInterval, meters: Double) -> String {
        guard seconds > 0 else { return "0.0" }
        return String(format: "%.1f", meters / (us ? 1609.344 : 1000) / (seconds / 3600))
    }

    var speedUnit: String { us ? "MPH" : "KM/H" }
    var paceUnit: String { us ? "/MI" : "/KM" }
}

/// 18:13.42 under an hour, 1:02:15 after. Hundredths only while the wrist is raised.
func workoutClock(_ time: TimeInterval, hundredths: Bool) -> String {
    let seconds = Int(time)
    if seconds >= 3600 {
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    let base = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    return hundredths ? base + String(format: ".%02d", Int((time - Double(seconds)) * 100)) : base
}

// MARK: - Metrics

struct WorkoutMetrics: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.periodic(from: .now, by: dimmed ? 1 : 1 / 30)) { context in
            let elapsed = workout.elapsed(at: context.date)
            let format = DistanceFormat(activity: workout.activity)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: workout.activity.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                    if workout.state == .paused {
                        Text("PAUSED").font(.system(size: 13, weight: .semibold)).foregroundStyle(WorkoutView.timeYellow)
                    }
                }
                Text(workoutClock(elapsed, hundredths: !dimmed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WorkoutView.timeYellow)
                    .opacity(workout.state == .paused ? 0.6 : 1)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                let metrics = WorkoutMetric.metrics(for: workout.activity)
                ForEach(metrics, id: \.self) { metric in
                    row(metric, elapsed: elapsed, format: format)
                        .environment(\.metricSize, metrics.count > 3 ? 26 : 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func row(_ metric: WorkoutMetric, elapsed: TimeInterval, format: DistanceFormat) -> some View {
        switch metric {
        case .activeKcal:
            MetricRow(value: "\(Int(workout.activeKcal))", unit: "ACTIVE\nKCAL")
        case .totalKcal:
            MetricRow(value: "\(Int(workout.totalKcal))", unit: "TOTAL\nKCAL")
        case .heartRate:
            MetricRow(value: workout.heartRate.map { "\($0)" } ?? "--", unit: "BPM", icon: "heart.fill")
        case .distance:
            MetricRow(value: format.value(workout.meters), unit: format.unit)
        case .averagePace:
            MetricRow(value: format.pace(seconds: elapsed, meters: workout.meters), unit: "AVG\n" + format.paceUnit)
        case .averageSpeed:
            MetricRow(value: format.speed(seconds: elapsed, meters: workout.meters), unit: "AVG\n" + format.speedUnit)
        }
    }
}

/// A big number with its unit stacked small beside it, as in the Workout app.
struct MetricRow: View {
    @Environment(\.metricSize) private var size
    var value: String
    var unit: String
    var icon: String?

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .medium, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 0) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.red)
                }
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineSpacing(-2)
                    .fixedSize()
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Heart Rate Zones

struct HeartRateZones: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TimelineView(.periodic(from: .now, by: dimmed ? 1 : 1 / 30)) { context in
            let zone = workout.heartRate.map { workout.zones.zone(for: $0) }
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutClock(workout.elapsed(at: context.date), hundredths: !dimmed))
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WorkoutView.timeYellow)
                Text(zone.map { "ZONE \($0)" } ?? "ZONE --")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(zone.map { WorkoutView.zoneColors[$0 - 1] } ?? .secondary)
                MetricRow(value: workout.heartRate.map { "\($0)" } ?? "--", unit: "BPM", icon: "heart.fill")
                gauge(zone: zone)
                if let zone {
                    let range = workout.zones.range(zone)
                    HStack {
                        Text(workoutClock(workout.zoneSeconds[zone - 1], hundredths: false))
                            .foregroundStyle(WorkoutView.zoneColors[zone - 1])
                        Text("IN ZONE").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(range.lowerBound)–\(range.upperBound)").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 6)
        }
    }

    /// Z1…Z5 with the current zone raised and numbered; the zone you aim for is outlined.
    private func gauge(zone: Int?) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(1...5, id: \.self) { z in
                let current = z == zone
                RoundedRectangle(cornerRadius: 4)
                    .fill(WorkoutView.zoneColors[z - 1].opacity(current ? 1 : 0.35))
                    .frame(height: current ? 22 : 10)
                    .overlay {
                        if current {
                            Text("\(z)").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(z == workout.setup.targetZone && !current ? Color.white : .clear, lineWidth: 1.5))
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

struct WorkoutControls: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        let paused = workout.state == .paused
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                control("Lock", symbol: "drop.fill", tint: .cyan) {
                    WKInterfaceDevice.current().enableWaterLock()
                }
                Color.clear.frame(width: 1, height: 1)
            }
            GridRow {
                control("End", symbol: "xmark", tint: .red) { workout.end() }
                control(paused ? "Resume" : "Pause", symbol: paused ? "arrow.clockwise" : "pause.fill",
                        tint: paused ? .green : .yellow) {
                    paused ? workout.resume() : workout.pause()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func control(_ label: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            Text(label).font(.system(size: 13, weight: .medium))
        }
    }
}

// MARK: - Summary

struct WorkoutSummary: View {
    @Environment(WorkoutManager.self) private var workout
    var summary: WorkoutManager.Summary

    private static let pink = Color(red: 0.98, green: 0.07, blue: 0.31)
    private static let blue = Color(red: 0.35, green: 0.78, blue: 0.98)

    var body: some View {
        let format = DistanceFormat(activity: summary.activity)
        let metrics = WorkoutMetric.metrics(for: summary.activity)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: summary.activity.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 34, height: 34)
                        .background(Color.green.opacity(0.2), in: Circle())
                    Text(summary.title).font(.headline).lineLimit(2)
                }
                item("Workout Time", workoutClock(summary.elapsed, hundredths: false), WorkoutView.timeYellow)
                if metrics.contains(.distance) {
                    item("Distance", format.value(summary.meters) + format.unit, Self.blue)
                }
                item("Active Kilocalories", "\(Int(summary.activeKcal))KCAL", Self.pink)
                item("Total Kilocalories", "\(Int(summary.totalKcal))KCAL", Self.pink)
                if let bpm = summary.averageHeartRate {
                    item("Avg. Heart Rate", "\(bpm)BPM", .red)
                }
                if metrics.contains(.averagePace) {
                    item("Avg. Pace", format.pace(seconds: summary.elapsed, meters: summary.meters) + format.paceUnit, Self.blue)
                }
                if metrics.contains(.averageSpeed) {
                    item("Avg. Speed", format.speed(seconds: summary.elapsed, meters: summary.meters) + format.speedUnit, Self.blue)
                }
                Button("Done") { workout.dismissSummary() }
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    private func item(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
            Divider()
        }
    }
}

extension EnvironmentValues {
    /// Number size on the metrics page: a little smaller when four metrics share the screen.
    @Entry var metricSize: CGFloat = 30
}

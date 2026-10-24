import AccrueKit
@preconcurrency import HealthKit
import SwiftUI

/// The watch face of a workout: time, heart rate and its zone, calories and distance, with
/// Pause and End. Workouts start from Train on the phone.
struct WorkoutView: View {
    @Environment(WorkoutManager.self) private var workout

    private static let lime = Color(red: 0xC6 / 255, green: 0xF4 / 255, blue: 0x32 / 255)
    private static let zoneColors: [Color] = [
        Color(red: 0x5B / 255, green: 0xC8 / 255, blue: 1), Color(red: 0x5B / 255, green: 0xC8 / 255, blue: 1),
        Color(red: 1, green: 0xB0 / 255, blue: 0x20 / 255),
        Color(red: 1, green: 0x5A / 255, blue: 0x5F / 255), Color(red: 1, green: 0x5A / 255, blue: 0x5F / 255),
    ]

    var body: some View {
        if workout.isRunning {
            TabView {
                metrics
                controls
            }
            .tabViewStyle(.verticalPage)
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

    private var metrics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let zone = workout.heartRate.map { workout.zones.zone(for: $0) }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.setup.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Self.lime)
                    .lineLimit(1)
                Text(clock(workout.elapsed(at: context.date)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(workout.state == .paused ? .yellow : .primary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(workout.heartRate.map { "\($0)" } ?? "--")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
                    if let zone {
                        Text("Z\(zone)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Self.zoneColors[zone - 1])
                    }
                }
                band(zone: zone)
                HStack {
                    Text("\(Int(workout.activeKcal)) kcal")
                    Spacer()
                    if workout.meters > 0 {
                        Text(String(format: "%.2f km", workout.meters / 1000))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    /// Z1…Z5 with the target zone bright and the current one outlined.
    private func band(zone: Int?) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { z in
                Capsule()
                    .fill(Self.zoneColors[z - 1].opacity(z == workout.setup.targetZone || workout.setup.targetZone == nil ? 1 : 0.35))
                    .frame(height: 6)
                    .overlay(Capsule().strokeBorder(z == zone ? Color.white : .clear, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                workout.state == .paused ? workout.resume() : workout.pause()
            } label: {
                Label(workout.state == .paused ? "Resume" : "Pause",
                      systemImage: workout.state == .paused ? "play.fill" : "pause.fill")
            }
            .tint(.yellow)
            Button(role: .destructive) {
                workout.end()
            } label: {
                Label("End", systemImage: "stop.fill")
            }
        }
        .padding(.horizontal)
    }

    private func clock(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

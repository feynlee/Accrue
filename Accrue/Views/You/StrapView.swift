import AccrueKit
import SwiftUI

/// Pairs a Bluetooth heart-rate strap or armband, for heart rate and zones without Apple Watch.
struct StrapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    /// "Polar H10 A1B2C3D4" → "Polar H10": the serial adds nothing in a list.
    static func shortName(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard let last = words.last, words.count > 1, last.count >= 6, last.allSatisfy(\.isHexDigit) else { return name }
        return words.dropLast().joined(separator: " ")
    }

    var body: some View {
        let strap = model.strap
        Form {
            if let name = strap.savedName {
                Section("Paired") {
                    HStack {
                        Image(systemName: "heart.fill").foregroundStyle(palette.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.inter(16, .semibold)).foregroundStyle(palette.text)
                            Text(status(strap)).font(.inter(13)).foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        if let bpm = strap.bpm {
                            Text("\(bpm)").font(.number(28)).monospacedDigit().foregroundStyle(palette.text)
                            Text("BPM").font(.inter(11, .bold)).foregroundStyle(palette.secondary)
                        }
                    }
                    Button("Forget this strap", role: .destructive) { strap.forget() }
                }
                .listRowBackground(palette.card)
            }
            Section {
                if strap.status == .searching {
                    HStack {
                        ProgressView()
                        Text("Looking for straps…").foregroundStyle(palette.secondary)
                    }
                    ForEach(strap.found) { device in
                        Button {
                            strap.pair(device)
                        } label: {
                            LabeledContent(device.name, value: device.id == strap.savedID ? "Paired" : "Pair")
                        }
                    }
                } else if strap.status == .bluetoothOff {
                    Text("Bluetooth is off or not allowed for Accrue. Turn it on in Settings.")
                        .foregroundStyle(palette.secondary)
                } else {
                    Button(strap.savedName == nil ? "Find a strap" : "Pair a different strap") { strap.startSearching() }
                }
            } header: {
                Text(strap.savedName == nil ? "Pair" : "Change")
            } footer: {
                Text("Wear the strap so it wakes up. Any strap or armband that shows heart rate in other apps works: Polar, Garmin, Wahoo, Coros and more. During a workout without Apple Watch, Accrue connects to it and shows your heart rate and zones.")
                    .font(.inter(13))
            }
            .listRowBackground(palette.card)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Heart rate strap")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { strap.stopSearching() }
    }

    private func status(_ strap: HeartRateStrap) -> String {
        switch strap.status {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .bluetoothOff: "Bluetooth is off"
        case .off, .searching: "Connects during workouts"
        }
    }
}

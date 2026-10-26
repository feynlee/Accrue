import AccrueKit
import SwiftUI

/// You: appearance, units, and credits.
struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.dark
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb
    @AppStorage(SettingsKey.maxHeartRate) private var maxHR = HeartZones.defaultMax
    @AppStorage(SettingsKey.bodyWeightKg) private var bodyKg = CalorieEstimate.defaultBodyKg
    /// `-progressScreen strap` opens the strap screen (screenshots).
    @State private var showingStrap = UserDefaults.standard.string(forKey: "progressScreen") == "strap"
    /// `-progressScreen siri` opens Siri & Shortcuts (screenshots).
    @State private var showingSiri = UserDefaults.standard.string(forKey: "progressScreen") == "siri"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You")
                        .font(.display(34))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.text)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.card)
                }
                Section("Units") {
                    Picker("Weight", selection: $unit) {
                        ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.card)
                }
                Section {
                    Stepper(value: $maxHR, in: 120...220) {
                        LabeledContent("Max heart rate", value: "\(maxHR) bpm")
                    }
                    let z2 = HeartZones(maxHR: maxHR).range(2)
                    Text("Sets the cardio zones. Zone 2 is \(z2.lowerBound)–\(z2.upperBound) bpm. A rough guess is 220 minus your age.")
                        .font(.inter(13))
                        .foregroundStyle(palette.secondary)
                    NavigationLink {
                        StrapView()
                    } label: {
                        LabeledContent("Heart rate strap", value: model.strap.savedName.map(StrapView.shortName) ?? "None")
                    }
                    Stepper(value: Binding(get: { unit.fromKg(bodyKg).rounded() },
                                           set: { bodyKg = unit.toKg($0) }), in: unit.fromKg(30)...unit.fromKg(250)) {
                        LabeledContent("Body weight", value: "\(Int(unit.fromKg(bodyKg).rounded())) \(unit.label)")
                    }
                    Text("Without Apple Watch, calories are estimated from your body weight and the workout.")
                        .font(.inter(13))
                        .foregroundStyle(palette.secondary)
                } header: {
                    Text("Heart")
                }
                .listRowBackground(palette.card)
                Section {
                    NavigationLink {
                        SiriView()
                    } label: {
                        Label("Siri & Shortcuts", systemImage: "waveform")
                    }
                } footer: {
                    Text("Ask Siri about your plan and progress, or start, log and end workouts hands-free.")
                        .font(.inter(13))
                }
                .listRowBackground(palette.card)
                Section("Your log") {
                    LabeledContent("Logged sets", value: "\(model.data.sets.count)")
                    LabeledContent("Workouts", value: "\(model.data.sessions.count)")
                    LabeledContent("Presets", value: "\(model.data.presets.count)")
                    if let error = model.saveError {
                        Text("Could not save: \(error)").foregroundStyle(palette.danger)
                    }
                }
                .listRowBackground(palette.card)
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("Exercise names come from openGym (MIT). How-to text, cues and mistakes are Accrue's own research. Barlow Condensed and Inter are under the SIL Open Font License.")
                        .font(.inter(13))
                        .foregroundStyle(palette.secondary)
                }
                .listRowBackground(palette.card)
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingStrap) { StrapView() }
            .navigationDestination(isPresented: $showingSiri) { SiriView() }
        }
    }
}

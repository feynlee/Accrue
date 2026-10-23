import AccrueKit
import SwiftUI

/// You: appearance, units, and credits.
struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.appearance) private var appearance = Appearance.dark
    @AppStorage(SettingsKey.weightUnit) private var unit = WeightUnit.lb

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("You")
        }
    }
}
